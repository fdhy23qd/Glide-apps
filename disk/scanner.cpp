#include "scanner.h"
#include "glidetr.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMetaObject>
#include <QSet>
#include <QStorageInfo>
#include <QThread>
#include <QUrl>
#include <algorithm>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

constexpr qint64 kSmall = 1024 * 1024;   // мельче — только суммой в папке

const char *const kKinds[] = {"video", "image", "audio", "archive", "doc", "other"};

int kindIndex(const QString &name)
{
    static const QHash<QString, int> kinds = [] {
        QHash<QString, int> h;
        auto add = [&h](int k, std::initializer_list<const char *> ext) { for (auto e : ext) h.insert(e, k); };
        add(0, {"mp4", "mkv", "webm", "avi", "mov", "m4v", "wmv", "flv", "ts", "mpg", "mpeg"});
        add(1, {"jpg", "jpeg", "png", "gif", "webp", "heic", "avif", "jxl", "svg", "bmp", "tif", "tiff", "raw",
                "cr2", "nef", "arw", "dng", "psd", "kra", "xcf"});
        add(2, {"mp3", "flac", "ogg", "opus", "wav", "m4a", "aac", "wma", "alac"});
        add(3, {"zip", "7z", "rar", "tar", "gz", "xz", "zst", "bz2", "tgz", "iso", "img", "deb", "rpm", "appimage",
                "pkg", "dmg", "qcow2", "vdi", "vmdk"});
        add(4, {"pdf", "doc", "docx", "odt", "xls", "xlsx", "ods", "ppt", "pptx", "odp", "txt", "md", "epub", "djvu", "fb2"});
        return h;
    }();
    const int dot = name.lastIndexOf('.');
    return dot > 0 ? kinds.value(name.mid(dot + 1).toLower(), 5) : 5;
}

// чем занята папка больше всего — её цвет на карте
QString dominant(const Scanner::Node *n)
{
    int best = 5;
    for (int k = 0; k < 6; ++k) if (n->byKind[k] > n->byKind[best]) best = k;
    return QString::fromLatin1(kKinds[best]);
}

struct Walk {
    dev_t dev;
    std::atomic<qint64> &files, &bytes;
    std::atomic<bool> &cancel;
    QMutex &lock;
    QString &cur;
    QList<QPair<QString, qint64>> &partial;
    Scanner::Node *top = nullptr;   // корень обхода: его папки показываются, как только досчитаны
    QSet<QPair<quint64, quint64>> seen;   // жёсткие ссылки: (устройство, inode)
    int tick = 0;

    // папка по открытому дескриптору: файлы — сразу, вложенные папки — рекурсией
    void dir(int fd, Scanner::Node *node, const QString &path)
    {
        if (++tick % 64 == 0) { QMutexLocker l(&lock); cur = path; }
        DIR *d = fdopendir(fd);
        if (!d) { close(fd); node->denied = true; return; }
        while (dirent *e = readdir(d)) {
            if (cancel.load()) break;
            const char *n = e->d_name;
            if (n[0] == '.' && (n[1] == 0 || (n[1] == '.' && n[2] == 0)))
                continue;
            struct stat st;
            if (fstatat(dirfd(d), n, &st, AT_SYMLINK_NOFOLLOW) != 0)
                continue;
            const qint64 used = qint64(st.st_blocks) * 512;
            if (S_ISDIR(st.st_mode)) {
                if (st.st_dev != dev)   // точка монтирования другого диска — не входим
                    continue;
                auto kid = std::make_unique<Scanner::Node>();
                kid->name = QString::fromUtf8(n);
                kid->dir = true;
                kid->parent = node;
                kid->size = used;
                const int sub = openat(dirfd(d), n, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
                if (sub >= 0) dir(sub, kid.get(), path + '/' + kid->name);
                else kid->denied = true;
                if (node == top) { QMutexLocker l(&lock); partial.append({kid->name, kid->size}); }
                node->size += kid->size;
                node->files += kid->files;
                for (int k = 0; k < 6; ++k) node->byKind[k] += kid->byKind[k];
                if (kid->denied) node->denied = true;
                node->kids.push_back(std::move(kid));
            } else {
                if (st.st_nlink > 1) {
                    const QPair<quint64, quint64> key{quint64(st.st_dev), quint64(st.st_ino)};
                    if (seen.contains(key)) continue;
                    seen.insert(key);
                }
                files.fetch_add(1);
                bytes.fetch_add(used);
                const int kind = kindIndex(QString::fromUtf8(n));
                node->byKind[kind] += used;
                node->files++;
                node->size += used;
                if (used < kSmall) {
                    node->smallSize += used;
                    node->smallCount++;
                } else {
                    auto kid = std::make_unique<Scanner::Node>();
                    kid->name = QString::fromUtf8(n);
                    kid->size = used;
                    kid->files = 1;
                    kid->byKind[kind] = used;
                    kid->parent = node;
                    node->kids.push_back(std::move(kid));
                }
            }
        }
        closedir(d);
    }
};


}

Scanner::Scanner(QObject *parent) : QObject(parent)
{
    m_progress.setInterval(120);
    connect(&m_progress, &QTimer::timeout, this, &Scanner::progressChanged);
}

Scanner::~Scanner()
{
    m_cancel = true;
    if (m_thread) { m_thread->wait(); delete m_thread; }
}

QString Scanner::progressPath() const
{
    QMutexLocker l(&m_pathLock);
    return m_curPath;
}

QVariantList Scanner::partial() const
{
    QList<QPair<QString, qint64>> copy;
    { QMutexLocker l(&m_pathLock); copy = m_partial; }
    std::sort(copy.begin(), copy.end(), [](const auto &a, const auto &b) { return a.second > b.second; });
    QVariantList out;
    for (const auto &p : copy.mid(0, 8)) out.append(QVariantMap{{"name", p.first}, {"size", p.second}});
    return out;
}

QString Scanner::home() const { return QDir::homePath(); }

void Scanner::scan(const QString &pathIn)
{
    if (m_scanning) return;
    const QString path = QFileInfo(pathIn.startsWith("file:") ? QUrl(pathIn).toLocalFile() : pathIn).absoluteFilePath();
    struct stat st;
    const int fd = ::open(QFile::encodeName(path).constData(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0 || fstat(fd, &st) != 0) {
        if (fd >= 0) close(fd);
        emit error(glideTr(QStringLiteral("Нет доступа к папке %1")).arg(path));
        return;
    }
    m_files = 0; m_bytes = 0; m_cancel = false;
    { QMutexLocker l(&m_pathLock); m_curPath = path; m_partial.clear(); }
    m_scanning = true;
    emit scanningChanged();
    m_progress.start();
    m_thread = QThread::create([this, fd, path, dev = st.st_dev] {
        auto tree = std::make_unique<Node>();
        tree->name = path;
        tree->dir = true;
        Walk w{dev, m_files, m_bytes, m_cancel, m_pathLock, m_curPath, m_partial, tree.get(), {}};
        w.dir(fd, tree.get(), path);
        Node *raw = tree.release();
        QMetaObject::invokeMethod(this, [this, raw, path] { finish(std::unique_ptr<Node>(raw), path); }, Qt::QueuedConnection);
    });
    m_thread->start();
}

void Scanner::finish(std::unique_ptr<Node> tree, const QString &path)
{
    if (m_thread) { m_thread->wait(); delete m_thread; m_thread = nullptr; }
    m_progress.stop();
    const bool cancelled = m_cancel.load();
    m_scanning = false;
    if (!cancelled) {
        m_root = std::move(tree);
        m_rootPath = path;
        m_undo = {};
        emit undoChanged();
        ++m_revision;
        emit treeChanged();
    }
    emit progressChanged();
    emit scanningChanged();
}

void Scanner::cancel() { m_cancel = true; }

Scanner::Node *Scanner::find(const QString &path) const
{
    if (!m_root) return nullptr;
    if (path == m_rootPath) return m_root.get();
    if (!path.startsWith(m_rootPath + '/')) return nullptr;
    Node *n = m_root.get();
    for (const QString &part : path.mid(m_rootPath.size() + 1).split('/', Qt::SkipEmptyParts)) {
        auto it = std::find_if(n->kids.begin(), n->kids.end(), [&](const auto &k) { return k->name == part; });
        if (it == n->kids.end()) return nullptr;
        n = it->get();
    }
    return n;
}

QVariantList Scanner::children(const QString &path) const
{
    QVariantList out;
    const Node *n = find(path);
    if (!n) return out;
    std::vector<const Node *> kids;
    kids.reserve(n->kids.size());
    for (const auto &k : n->kids) kids.push_back(k.get());
    std::sort(kids.begin(), kids.end(), [](const Node *a, const Node *b) { return a->size > b->size; });
    bool smallDone = n->smallCount == 0;
    auto small = [&] {
        out.append(QVariantMap{{"name", glideTr(QStringLiteral("Мелкие файлы: %1")).arg(n->smallCount)}, {"path", ""},
                               {"size", n->smallSize}, {"files", n->smallCount}, {"dir", false}, {"kind", "small"}, {"small", true}});
        smallDone = true;
    };
    for (const Node *k : kids) {
        if (!smallDone && n->smallSize > k->size) small();
        out.append(QVariantMap{{"name", k->name}, {"path", path + '/' + k->name}, {"size", k->size}, {"files", k->files},
                               {"dir", k->dir}, {"kind", dominant(k)},
                               {"small", false}, {"denied", k->denied}});
    }
    if (!smallDone) small();
    return out;
}

QVariantMap Scanner::info(const QString &path) const
{
    const Node *n = find(path);
    if (!n) return {};
    QVariantList kinds;
    for (int k = 0; k < 6; ++k)
        if (n->byKind[k] > 0) kinds.append(QVariantMap{{"kind", QString::fromLatin1(kKinds[k])}, {"size", n->byKind[k]}});
    std::sort(kinds.begin(), kinds.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("size").toLongLong() > b.toMap().value("size").toLongLong();
    });
    return {{"size", n->size}, {"files", n->files}, {"denied", n->denied}, {"kinds", kinds}};
}

QVariantList Scanner::volumes() const
{
    static const QSet<QByteArray> skip{"tmpfs", "devtmpfs", "overlay", "squashfs", "efivarfs", "ramfs", "fuse.portal",
                                       "fuse.gvfsd-fuse", "nsfs", "autofs"};
    QVariantList out;
    QSet<QByteArray> devices;
    for (const QStorageInfo &v : QStorageInfo::mountedVolumes()) {
        if (!v.isValid() || !v.isReady() || skip.contains(v.fileSystemType()) || v.bytesTotal() <= 0)
            continue;
        if (v.rootPath().startsWith("/boot") || v.rootPath().startsWith("/run") || v.rootPath().startsWith("/var/lib"))
            continue;
        if (devices.contains(v.device())) continue;   // btrfs: один диск смонтирован в нескольких местах
        devices.insert(v.device());
        const QString label = v.rootPath() == "/" ? glideTr(QStringLiteral("Система")) : v.name().isEmpty() ? v.rootPath() : v.name();
        out.append(QVariantMap{{"name", label}, {"path", v.rootPath()}, {"total", v.bytesTotal()},
                               {"used", v.bytesTotal() - v.bytesFree()}, {"fs", QString::fromUtf8(v.fileSystemType())}});
    }
    return out;
}

bool Scanner::trash(const QString &path)
{
    Node *n = find(path);
    if (!n || n == m_root.get()) return false;
    QString inTrash;
    if (!QFile::moveToTrash(path, &inTrash)) {
        emit error(glideTr(QStringLiteral("Не удалось переместить в корзину")));
        return false;
    }
    Node *parent = n->parent;
    auto it = std::find_if(parent->kids.begin(), parent->kids.end(), [n](const auto &k) { return k.get() == n; });
    std::unique_ptr<Node> taken = std::move(*it);
    parent->kids.erase(it);
    for (Node *p = parent; p; p = p->parent) {
        p->size -= taken->size;
        p->files -= taken->files;
        for (int k = 0; k < 6; ++k) p->byKind[k] -= taken->byKind[k];
    }
    m_undo = {std::move(taken), path, inTrash};
    emit undoChanged();
    ++m_revision;
    emit treeChanged();
    return true;
}

bool Scanner::undoTrash()
{
    if (!m_undo.node) return false;
    if (!QFile::rename(m_undo.inTrash, m_undo.original)) {
        emit error(glideTr(QStringLiteral("Не удалось вернуть из корзины")));
        return false;
    }
    // папка-родитель могла уйти в корзину следом — тогда просто без восстановления в дереве
    Node *parent = find(QFileInfo(m_undo.original).absolutePath());
    if (parent) {
        for (Node *p = parent; p; p = p->parent) {
            p->size += m_undo.node->size;
            p->files += m_undo.node->files;
            for (int k = 0; k < 6; ++k) p->byKind[k] += m_undo.node->byKind[k];
        }
        m_undo.node->parent = parent;
        parent->kids.push_back(std::move(m_undo.node));
    }
    m_undo = {};
    emit undoChanged();
    ++m_revision;
    emit treeChanged();
    return true;
}

void Scanner::open(const QString &path) const { QDesktopServices::openUrl(QUrl::fromLocalFile(path)); }

void Scanner::showInFolder(const QString &path) const
{
    QDBusMessage msg = QDBusMessage::createMethodCall("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                                                      "org.freedesktop.FileManager1", "ShowItems");
    msg << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    QDBusConnection::sessionBus().asyncCall(msg);
}
