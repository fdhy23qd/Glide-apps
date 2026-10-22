#include "archiver.h"
#include "glidetr.h"

#include <QCollator>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QSet>
#include <QStringDecoder>
#include <QThread>
#include <QUrl>
#include <QVariantMap>

#include <archive.h>
#include <archive_entry.h>
#include <sys/stat.h>

namespace {

constexpr int Block = 1 << 16;

QString errorOf(archive *a)
{
    const char *s = archive_error_string(a);
    return s ? QString::fromUtf8(s) : glideTr(QStringLiteral("ошибка libarchive"));
}

bool passphraseError(const QString &msg)
{
    return msg.contains(QLatin1String("assphrase"), Qt::CaseInsensitive)
        || msg.contains(QLatin1String("password"), Qt::CaseInsensitive);
}

// libarchive не умеет расшифровывать 7z и RAR — об этом говорит прямо
bool unsupportedEncryption(const QString &msg)
{
    return msg.contains(QLatin1String("encrypt"), Qt::CaseInsensitive)
        && (msg.contains(QLatin1String("not supported"), Qt::CaseInsensitive)
            || msg.contains(QLatin1String("unavailable"), Qt::CaseInsensitive)
            || msg.contains(QLatin1String("unsupported"), Qt::CaseInsensitive));
}

// путь внутри архива → «a/b/c» без «./», ведущих и хвостовых «/»; null — небезопасный (с «..»)
QString cleanPath(QString p)
{
    p.replace(QLatin1Char('\\'), QLatin1Char('/'));
    QStringList out;
    for (const QString &part : p.split(QLatin1Char('/'), Qt::SkipEmptyParts)) {
        if (part == QLatin1String("."))
            continue;
        if (part == QLatin1String(".."))
            return QString();
        out << part;
    }
    return out.join(QLatin1Char('/'));
}

bool validUtf8(const char *s)
{
    if (!s)
        return true;
    QStringDecoder dec(QStringDecoder::Utf8);
    (void)dec.decode(QByteArrayView(s));
    return !dec.hasError();
}

bool hasCyrillic(const QString &s)
{
    for (QChar ch : s)
        if (ch.unicode() >= 0x0400 && ch.unicode() <= 0x04ff)
            return true;
    return false;
}

// zip без флага UTF-8 libarchive читает как CP437: русские имена превращаются в «ÄΓτ±Γ»
bool looksCp437(const QString &s)
{
    bool high = false;
    for (QChar ch : s)
        if (ch.unicode() >= 0x80)
            high = true;
    return high && !hasCyrillic(s);
}

QString rawEntryName(archive_entry *e)
{
    if (const char *u = archive_entry_pathname_utf8(e))
        return QString::fromUtf8(u);
    if (const char *m = archive_entry_pathname(e))
        return QString::fromLocal8Bit(m);
    return QString();
}

struct Reader {
    archive *a = nullptr;
    bool raw = false;     // одиночный сжатый файл (file.txt.gz): формат raw, одна запись
    ~Reader() { if (a) archive_read_free(a); }
};

archive *newReader(const QString &password, const QString &charset, bool raw)
{
    archive *a = archive_read_new();
    archive_read_support_filter_all(a);
    if (raw)
        archive_read_support_format_raw(a);
    else
        archive_read_support_format_all(a);
    if (!charset.isEmpty())
        archive_read_set_options(a, ("zip:hdrcharset=" + charset).toUtf8().constData());
    if (!password.isEmpty())
        archive_read_add_passphrase(a, password.toUtf8().constData());
    return a;
}

QString openReader(Reader &r, const QString &path, const QString &password, const QString &charset)
{
    const QByteArray file = QFile::encodeName(path);
    r.a = newReader(password, charset, false);
    if (archive_read_open_filename(r.a, file.constData(), Block) == ARCHIVE_OK)
        return QString();
    const QString err = errorOf(r.a);
    archive_read_free(r.a);
    // не архив — может быть просто сжатый файл: raw, но только если есть фильтр сжатия
    r.a = newReader(password, charset, true);
    r.raw = true;
    if (archive_read_open_filename(r.a, file.constData(), Block) == ARCHIVE_OK
        && archive_filter_count(r.a) > 1 && archive_filter_code(r.a, 0) != ARCHIVE_FILTER_NONE)
        return QString();
    archive_read_free(r.a);
    r.a = nullptr;
    return err.contains(QLatin1String("Unrecognized"), Qt::CaseInsensitive)
        ? glideTr(QStringLiteral("Это не архив или формат не поддерживается")) : err;
}

QString entryName(const Reader &r, archive_entry *e, const QString &archivePath)
{
    if (r.raw) {   // у raw имени нет («data»): имя архива без последнего расширения
        QString n = QFileInfo(archivePath).fileName();
        const int dot = n.lastIndexOf(QLatin1Char('.'));
        if (dot > 0)
            n.truncate(dot);
        const QString l = QFileInfo(archivePath).suffix().toLower();
        if (l == QLatin1String("tgz") || l == QLatin1String("txz") || l == QLatin1String("tzst") || l == QLatin1String("tbz2"))
            n += QLatin1String(".tar");
        return n;
    }
    return cleanPath(rawEntryName(e));
}

QString formatName(archive *a, bool raw)
{
    QString base;
    switch (archive_format(a) & ARCHIVE_FORMAT_BASE_MASK) {
    case ARCHIVE_FORMAT_ZIP: base = "ZIP"; break;
    case ARCHIVE_FORMAT_7ZIP: base = "7z"; break;
    case ARCHIVE_FORMAT_RAR: base = "RAR"; break;
    case ARCHIVE_FORMAT_RAR_V5: base = "RAR5"; break;
    case ARCHIVE_FORMAT_TAR: base = "TAR"; break;
    case ARCHIVE_FORMAT_ISO9660: base = "ISO"; break;
    case ARCHIVE_FORMAT_CPIO: base = "CPIO"; break;
    case ARCHIVE_FORMAT_AR: base = "AR"; break;
    case ARCHIVE_FORMAT_CAB: base = "CAB"; break;
    case ARCHIVE_FORMAT_LHA: base = "LHA"; break;
    case ARCHIVE_FORMAT_XAR: base = "XAR"; break;
    default: base = raw ? QString() : QString::fromUtf8(archive_format_name(a)); break;
    }
    QStringList filters;
    for (int i = 0; i < archive_filter_count(a); ++i)
        if (archive_filter_code(a, i) != ARCHIVE_FILTER_NONE)
            filters << QString::fromUtf8(archive_filter_name(a, i));
    if (raw)
        return filters.join(QLatin1Char('+'));
    return filters.isEmpty() ? base : base + QLatin1String(" + ") + filters.join(QLatin1Char('+'));
}

QString uniquePath(const QString &path)
{
    struct stat st;
    if (lstat(QFile::encodeName(path).constData(), &st) != 0)
        return path;
    const QFileInfo fi(path);
    QString stem = fi.fileName(), ext;
    // «архив.tar.gz» → «архив (2).tar.gz»
    static const QStringList doubles{".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tar.lz4"};
    for (const QString &d : doubles)
        if (stem.endsWith(d, Qt::CaseInsensitive)) { ext = stem.right(d.size()); stem.chop(d.size()); break; }
    if (ext.isEmpty()) {
        const int dot = stem.lastIndexOf(QLatin1Char('.'));
        if (dot > 0 && !fi.isDir()) { ext = stem.mid(dot); stem.truncate(dot); }
    }
    for (int i = 2;; ++i) {
        const QString p = fi.absolutePath() + QLatin1Char('/') + stem + QStringLiteral(" (%1)").arg(i) + ext;
        if (lstat(QFile::encodeName(p).constData(), &st) != 0)
            return p;
    }
}

} // namespace

// ---------------------------------------------------------------- 7z как запасной путь
// libarchive не расшифровывает 7z и RAR. Если стоит 7-Zip — такие архивы читаем им. Пароль идёт в stdin
// (7z спрашивает его сам), а не в аргументы: командную строку видят все процессы.

static qint64 finishListing(QVariantList &list, const QList<qint64> &sizes);

static QString sevenZip()
{
    static const QString exe = [] {
        for (const char *n : {"7z", "7zz", "7za"})
            if (QString p = QStandardPaths::findExecutable(QString::fromLatin1(n)); !p.isEmpty())
                return p;
        return QString();
    }();
    return exe;
}

static QString run7z(QProcess &p, const QStringList &args, const QString &password, std::atomic<bool> *cancel,
                     std::function<void(qreal)> progress, QByteArray *out)
{
    p.setProgram(sevenZip());
    p.setArguments(args);
    p.setProcessChannelMode(QProcess::SeparateChannels);
    p.start();
    if (!p.waitForStarted(5000))
        return glideTr(QStringLiteral("7z не запустился"));
    p.write(password.toUtf8() + "\n");   // на вопрос «Enter password» (и пустой — если не спросит)
    p.closeWriteChannel();
    static const QRegularExpression percent(QStringLiteral("(\\d+)%"));
    QByteArray buf;
    while (!p.waitForFinished(100)) {
        if (cancel && *cancel) {
            p.kill();
            p.waitForFinished(2000);
            return QStringLiteral("cancelled");
        }
        const QByteArray chunk = p.readAllStandardOutput();
        buf += chunk;
        if (progress && !chunk.isEmpty()) {
            auto it = percent.globalMatch(QString::fromUtf8(chunk));
            int last = -1;
            while (it.hasNext())
                last = it.next().captured(1).toInt();
            if (last >= 0)
                progress(last / 100.0);
        }
    }
    buf += p.readAllStandardOutput();
    if (out)
        *out = buf;
    const QString err = QString::fromUtf8(p.readAllStandardError());
    if (p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
        if (err.contains(QLatin1String("Wrong password"), Qt::CaseInsensitive)
            || err.contains(QLatin1String("encrypted"), Qt::CaseInsensitive)
            || err.contains(QLatin1String("Data Error in encrypted"), Qt::CaseInsensitive))
            return password.isEmpty() ? QStringLiteral("password") : QStringLiteral("wrong-password");
        const QString line = err.trimmed().section(QLatin1Char('\n'), -1).trimmed();
        return line.isEmpty() ? glideTr(QStringLiteral("7z: код %1")).arg(p.exitCode()) : QStringLiteral("7z: ") + line;
    }
    return QString();
}

static QString list7z(const QString &path, const QString &password, Archive::Listing *out)
{
    if (sevenZip().isEmpty())
        return QStringLiteral("unsupported-encryption");
    QProcess p;
    QByteArray text;
    // -slt — подробно «ключ = значение», -ba — без шапки, -sccUTF-8 — имена в UTF-8
    if (QString err = run7z(p, {"l", "-slt", "-ba", "-sccUTF-8", "--", path}, password, nullptr, {}, &text); !err.isEmpty())
        return err;
    QVariantList list;
    QList<qint64> sizes;
    QHash<QString, int> index;
    bool encrypted = false;
    auto addDir = [&](const QString &d) {
        if (d.isEmpty() || index.contains(d))
            return;
        index.insert(d, list.size());
        list << QVariantMap{{"path", d}, {"dir", true}, {"size", 0}, {"mtime", 0}, {"enc", false}};
        sizes << 0;
    };
    const QStringList blocks = QString::fromUtf8(text).split(QRegularExpression(QStringLiteral("\\n\\s*\\n")), Qt::SkipEmptyParts);
    for (const QString &b : blocks) {
        QHash<QString, QString> kv;
        for (const QString &line : b.split(QLatin1Char('\n'))) {
            const int eq = line.indexOf(QLatin1String(" = "));
            if (eq > 0)
                kv.insert(line.left(eq).trimmed(), line.mid(eq + 3).trimmed());
        }
        const QString name = cleanPath(kv.value("Path"));
        if (name.isEmpty())
            continue;
        const bool dir = kv.value("Folder") == QLatin1String("+") || kv.value("Attributes").startsWith(QLatin1Char('D'));
        const bool enc = kv.value("Encrypted") == QLatin1String("+");
        encrypted |= enc;
        const QStringList parts = name.split(QLatin1Char('/'));
        for (int i = 1; i < parts.size(); ++i)
            addDir(parts.mid(0, i).join(QLatin1Char('/')));
        if (dir) {
            addDir(name);
            continue;
        }
        const qint64 size = kv.value("Size").toLongLong();
        const QDateTime mt = QDateTime::fromString(kv.value("Modified").left(19), QStringLiteral("yyyy-MM-dd HH:mm:ss"));
        index.insert(name, list.size());
        list << QVariantMap{{"path", name}, {"dir", false}, {"size", size}, {"mtime", mt.isValid() ? mt.toMSecsSinceEpoch() : 0},
                            {"enc", enc}, {"link", false}};
        sizes << size;
    }
    out->total = finishListing(list, sizes);
    out->entries = list;
    out->charset = QStringLiteral("7z");
    out->encrypted = encrypted;
    out->format = QFileInfo(path).suffix().toLower() == QLatin1String("rar") ? QStringLiteral("RAR (7-Zip)") : QStringLiteral("7z (7-Zip)");
    return QString();
}

// выбранное — во временную папку внутри dest с полными путями, потом переносим без пути до выбранного
static QString extract7z(const QString &path, const QString &password, const QStringList &paths, const QString &root,
                         QString *written, std::atomic<bool> *cancel, std::function<void(qreal)> progress)
{
    if (sevenZip().isEmpty())
        return QStringLiteral("unsupported-encryption");
    QTemporaryDir tmp(root + QStringLiteral("/.glide-archive-XXXXXX"));
    if (!tmp.isValid())
        return glideTr(QStringLiteral("Не удалось создать временную папку в %1")).arg(root);
    QStringList args{"x", "-y", "-bsp1", "-bso0", "-sccUTF-8", "-o" + tmp.path(), "--", path};
    for (const QString &s : paths)
        args << cleanPath(s);
    QProcess p;
    if (QString err = run7z(p, args, password, cancel, progress, nullptr); !err.isEmpty())
        return err;
    QStringList tops;
    auto moveOut = [&](const QString &from, const QString &name) -> QString {
        const QString to = uniquePath(root + QLatin1Char('/') + name);
        if (!QFile::rename(from, to))
            return glideTr(QStringLiteral("Не удалось перенести %1")).arg(name);
        tops << to;
        return QString();
    };
    if (paths.isEmpty()) {
        for (const QString &n : QDir(tmp.path()).entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot))
            if (QString err = moveOut(tmp.path() + QLatin1Char('/') + n, n); !err.isEmpty())
                return err;
    } else {
        for (const QString &s : paths) {
            const QString c = cleanPath(s);
            if (QFileInfo::exists(tmp.path() + QLatin1Char('/') + c))
                if (QString err = moveOut(tmp.path() + QLatin1Char('/') + c, c.section(QLatin1Char('/'), -1)); !err.isEmpty())
                    return err;
        }
    }
    if (progress)
        progress(1);
    if (written)
        *written = tops.size() == 1 ? tops.first() : root;
    return QString();
}

// ---------------------------------------------------------------- список

// размеры папок, число вложенных, имя и родитель у каждой записи; сортировка; возвращает сумму размеров
static qint64 finishListing(QVariantList &list, const QList<qint64> &sizes)
{
    qint64 total = 0;
    QHash<QString, qint64> dirSize;
    QHash<QString, int> dirCount;
    for (int i = 0; i < list.size(); ++i) {
        const QString p = list[i].toMap().value("path").toString();
        const int slash = p.lastIndexOf(QLatin1Char('/'));
        const QString parent = slash < 0 ? QString() : p.left(slash);
        dirCount[parent] += 1;
        if (list[i].toMap().value("dir").toBool())
            continue;
        total += sizes[i];
        QString d = parent;
        while (!d.isEmpty()) {
            dirSize[d] += sizes[i];
            const int s = d.lastIndexOf(QLatin1Char('/'));
            d = s < 0 ? QString() : d.left(s);
        }
    }
    for (QVariant &v : list) {
        QVariantMap m = v.toMap();
        const QString p = m.value("path").toString();
        const int slash = p.lastIndexOf(QLatin1Char('/'));
        m.insert("name", slash < 0 ? p : p.mid(slash + 1));
        m.insert("parent", slash < 0 ? QString() : p.left(slash));
        if (m.value("dir").toBool()) {
            m.insert("size", dirSize.value(p));
            m.insert("count", dirCount.value(p));
        }
        v = m;
    }
    // папки сверху, дальше по имени «по-человечески» (файл2 < файл10)
    QCollator col;
    col.setNumericMode(true);
    col.setCaseSensitivity(Qt::CaseInsensitive);
    std::stable_sort(list.begin(), list.end(), [&](const QVariant &a, const QVariant &b) {
        const QVariantMap x = a.toMap(), y = b.toMap();
        if (x.value("dir").toBool() != y.value("dir").toBool())
            return x.value("dir").toBool();
        return col.compare(x.value("name").toString(), y.value("name").toString()) < 0;
    });
    return total;
}

// один проход по заголовкам; *badNames — имена похожи на не-UTF-8 (повторить с CP866)
static QString listOnce(const QString &path, const QString &password, const QString &charset,
                        Archive::Listing *out, bool *badNamesOut)
{
    {
        Reader r;
        if (QString err = openReader(r, path, password, charset); !err.isEmpty())
            return err;
        QHash<QString, int> index;
        QVariantList list;
        QList<qint64> sizes;
        bool encrypted = false, verified = false, badNames = false;
        auto addDir = [&](const QString &p) {
            if (p.isEmpty() || index.contains(p))
                return;
            index.insert(p, list.size());
            list << QVariantMap{{"path", p}, {"dir", true}, {"size", 0}, {"mtime", 0}, {"enc", false}};
            sizes << 0;
        };
        archive_entry *e;
        int rc;
        while ((rc = archive_read_next_header(r.a, &e)) == ARCHIVE_OK || rc == ARCHIVE_WARN) {
            const QString name = entryName(r, e, path);
            if (!r.raw && (!validUtf8(archive_entry_pathname(e)) || looksCp437(name)))
                badNames = true;
            if (name.isEmpty())
                continue;
            const bool dir = archive_entry_filetype(e) == AE_IFDIR;
            const bool enc = archive_entry_is_encrypted(e);
            encrypted |= enc;
            // пароль проверяем сразу, на первом зашифрованном файле: иначе ошибка всплывёт посреди распаковки
            if (enc && !password.isEmpty() && !verified && !dir && archive_entry_size(e) > 0) {
                char buf[16];
                if (archive_read_data(r.a, buf, sizeof buf) < 0) {
                    const QString msg = errorOf(r.a);
                    if (unsupportedEncryption(msg))   // 7z/RAR с шифрованием: только через 7-Zip
                        return list7z(path, password, out);
                    return passphraseError(msg) ? QStringLiteral("wrong-password") : msg;
                }
                verified = true;
            }
            // родительские папки: в zip их часто нет отдельными записями
            const QStringList parts = name.split(QLatin1Char('/'));
            for (int i = 1; i < parts.size(); ++i)
                addDir(parts.mid(0, i).join(QLatin1Char('/')));
            if (dir) {
                addDir(name);
                continue;
            }
            const qint64 size = archive_entry_size_is_set(e) ? archive_entry_size(e) : -1;
            QVariantMap m{{"path", name}, {"dir", false}, {"size", size},
                          {"mtime", qint64(archive_entry_mtime(e)) * 1000}, {"enc", enc},
                          {"link", archive_entry_filetype(e) == AE_IFLNK}};
            if (index.contains(name)) {   // в tar запись может встретиться дважды — берём последнюю
                list[index[name]] = m;
                sizes[index[name]] = qMax<qint64>(0, size);
            } else {
                index.insert(name, list.size());
                list << m;
                sizes << qMax<qint64>(0, size);
            }
        }
        if (rc != ARCHIVE_EOF) {
            const QString msg = errorOf(r.a);
            if (passphraseError(msg))
                return password.isEmpty() ? QStringLiteral("password") : QStringLiteral("wrong-password");
            if (unsupportedEncryption(msg))
                return QStringLiteral("unsupported-encryption");
            if (list.isEmpty())
                return msg;
            // повреждённый хвост: показываем то, что прочиталось
            qWarning("glide-archive: %s", qPrintable(msg));
        }
        *badNamesOut = badNames && (archive_format(r.a) & ARCHIVE_FORMAT_BASE_MASK) == ARCHIVE_FORMAT_ZIP;

        const qint64 total = finishListing(list, sizes);
        out->entries = list;
        out->format = formatName(r.a, r.raw);
        out->charset = charset;
        out->total = total;
        out->encrypted = encrypted;
        return QString();
    }
    return QString();
}

QString Archive::listSync(const QString &path, const QString &password, Listing *out)
{
    bool badNames = false;
    if (QString err = listOnce(path, password, QString(), out, &badNames); !err.isEmpty() || !badNames) {
        if (err == QLatin1String("unsupported-encryption"))   // зашифрованный заголовок 7z
            return list7z(path, password, out);
        return err;
    }
    // имена не в UTF-8 у zip — почти всегда CP866 (архиватор Windows с русскими именами);
    // берём CP866, только если с ней появились русские буквы
    Listing cp;
    bool dummy;
    if (!listOnce(path, password, QStringLiteral("CP866"), &cp, &dummy).isEmpty())
        return QString();
    for (const QVariant &v : cp.entries)
        if (hasCyrillic(v.toMap().value("path").toString())) {
            *out = cp;
            break;
        }
    return QString();
}

// ---------------------------------------------------------------- распаковка

QString Archive::extractSync(const QString &path, const QString &password, const QString &charset,
                             const QStringList &paths, const QString &dest, QString *written, QStringList *skipped,
                             std::atomic<bool> *cancel, std::function<void(qreal)> progress)
{
    if (!QDir().mkpath(dest))
        return glideTr(QStringLiteral("Не удалось создать папку %1")).arg(dest);
    // настоящий путь папки: SECURE_SYMLINKS не пустит запись через ссылку, в том числе в самом пути
    const QString root = QFileInfo(dest).canonicalFilePath();
    if (root.isEmpty())
        return glideTr(QStringLiteral("Нет папки %1")).arg(dest);

    // выбранное распаковывается без пути до него: «a/b/c.txt» из папки «a/b» → «dest/c.txt»
    struct Sel { QString path; int strip; };
    QList<Sel> sels;
    for (const QString &p : paths) {
        const QString c = cleanPath(p);
        if (c.isEmpty())
            continue;
        const int slash = c.lastIndexOf(QLatin1Char('/'));
        sels << Sel{c, slash < 0 ? 0 : slash + 1};
    }

    if (charset == QLatin1String("7z"))
        return extract7z(path, password, paths, root, written, cancel, progress);
    auto selected = [&sels](const QString &name) -> QString {   // путь в dest; пусто — не выбрано
        if (sels.isEmpty())
            return name;
        for (const Sel &s : sels)
            if (name == s.path || name.startsWith(s.path + QLatin1Char('/')))
                return name.mid(s.strip);
        return QString();
    };

    // zip, 7z, rar: сначала пробегаем заголовки (это быстро — оглавление в конце или в начале файла).
    // Нужен ли пароль и не придётся ли звать 7-Zip — выясняем до того, как что-то записано.
    {
        Reader r;
        if (QString err = openReader(r, path, password, charset); !err.isEmpty())
            return err;
        archive_entry *e;
        int base = 0;
        bool encrypted = false;
        while (archive_read_next_header(r.a, &e) == ARCHIVE_OK) {
            base = archive_format(r.a) & ARCHIVE_FORMAT_BASE_MASK;
            if (base != ARCHIVE_FORMAT_ZIP && base != ARCHIVE_FORMAT_7ZIP && base != ARCHIVE_FORMAT_RAR
                && base != ARCHIVE_FORMAT_RAR_V5)
                break;
            const QString name = entryName(r, e, path);
            if (archive_entry_is_encrypted(e) && !name.isEmpty() && !selected(name).isEmpty()) {
                encrypted = true;
                break;
            }
        }
        if (encrypted && password.isEmpty())
            return QStringLiteral("password");
        if (encrypted && base != ARCHIVE_FORMAT_ZIP && !sevenZip().isEmpty())
            return extract7z(path, password, paths, root, written, cancel, progress);
    }

    Reader r;
    if (QString err = openReader(r, path, password, charset); !err.isEmpty())
        return err;
    archive *w = archive_write_disk_new();
    archive_write_disk_set_options(w, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_SECURE_NODOTDOT
                                          | ARCHIVE_EXTRACT_SECURE_SYMLINKS);
    archive_write_disk_set_standard_lookup(w);
    struct Closer { archive *w; ~Closer() { archive_write_free(w); } } closer{w};

    const qint64 fileSize = qMax<qint64>(1, QFileInfo(path).size());
    QHash<QString, QString> renamed;   // путь в архиве → куда записали (для жёстких ссылок)
    QStringList tops;                  // что появилось прямо в dest
    QString current;                   // файл, который пишется сейчас (удалить при отмене)
    qreal lastProgress = -1;
    auto fail = [&](const QString &msg) {
        if (!current.isEmpty())
            QFile::remove(current);
        return msg;
    };

    archive_entry *e;
    int rc;
    while ((rc = archive_read_next_header(r.a, &e)) == ARCHIVE_OK || rc == ARCHIVE_WARN) {
        if (cancel && *cancel)
            return QStringLiteral("cancelled");
        const QString name = entryName(r, e, path);
        if (name.isEmpty()) {   // «..» в пути — мимо
            if (skipped && !rawEntryName(e).isEmpty())
                *skipped << rawEntryName(e);
            continue;
        }
        const QString rel = selected(name);
        if (rel.isEmpty())
            continue;
        const bool dir = archive_entry_filetype(e) == AE_IFDIR;
        if (archive_entry_is_encrypted(e) && password.isEmpty())
            return QStringLiteral("password");

        // куда: если какую-то из папок выше пришлось переименовать — внутрь переименованной
        QString target = root + QLatin1Char('/') + rel;
        for (int s = rel.lastIndexOf(QLatin1Char('/')); s > 0; s = rel.lastIndexOf(QLatin1Char('/'), s - 1)) {
            if (const auto it = renamed.constFind(rel.left(s)); it != renamed.constEnd()) {
                target = *it + rel.mid(s);
                break;
            }
        }
        const QString planned = target;
        struct stat st;
        // файл с таким именем уже есть — не затираем, а кладём рядом «имя (2)»; папки сливаем
        if (lstat(QFile::encodeName(target).constData(), &st) == 0 && (!dir || !S_ISDIR(st.st_mode)))
            target = uniquePath(target);
        if (target != planned)
            renamed.insert(rel, target);
        else if (planned != root + QLatin1Char('/') + rel)
            renamed.insert(rel, planned);
        archive_entry_update_pathname_utf8(e, target.toUtf8().constData());

        if (const char *hl = archive_entry_hardlink_utf8(e)) {
            const QString h = cleanPath(QString::fromUtf8(hl));
            const QString hrel = h.isEmpty() ? QString() : selected(h);
            if (hrel.isEmpty())
                continue;   // ссылка на то, что не распаковываем
            archive_entry_update_hardlink_utf8(e, renamed.value(hrel, root + QLatin1Char('/') + hrel).toUtf8().constData());
        }

        const QString top = rel.section(QLatin1Char('/'), 0, 0);
        const QString topTarget = renamed.value(top, root + QLatin1Char('/') + top);
        if (!tops.contains(topTarget))
            tops << topTarget;

        if (archive_write_header(w, e) < ARCHIVE_WARN) {
            // запись через ссылку наружу и т.п. — пропускаем её одну, а не всю распаковку
            qWarning("glide-archive: пропуск %s: %s", qPrintable(rel), qPrintable(errorOf(w)));
            if (skipped)
                *skipped << rel;
            continue;
        }
        current = dir ? QString() : target;
        const void *buf;
        size_t len;
        la_int64_t off;
        int dr;
        while ((dr = archive_read_data_block(r.a, &buf, &len, &off)) == ARCHIVE_OK) {
            if (archive_write_data_block(w, buf, len, off) < ARCHIVE_OK)
                return fail(QStringLiteral("%1: %2").arg(rel, errorOf(w)));
            if (cancel && *cancel)
                return fail(QStringLiteral("cancelled"));
            if (progress) {
                const qreal p = qMin<qreal>(1, qreal(archive_filter_bytes(r.a, -1)) / fileSize);
                if (p - lastProgress >= 0.005) { lastProgress = p; progress(p); }
            }
        }
        if (dr != ARCHIVE_EOF) {
            const QString msg = errorOf(r.a);
            if (archive_entry_is_encrypted(e) && passphraseError(msg))
                return fail(QStringLiteral("wrong-password"));
            if (unsupportedEncryption(msg))
                return fail(QStringLiteral("unsupported-encryption"));
            return fail(QStringLiteral("%1: %2").arg(rel, msg));
        }
        if (archive_write_finish_entry(w) < ARCHIVE_WARN)
            return fail(QStringLiteral("%1: %2").arg(rel, errorOf(w)));
        current.clear();
    }
    if (rc != ARCHIVE_EOF) {
        const QString msg = errorOf(r.a);
        if (passphraseError(msg))
            return password.isEmpty() ? QStringLiteral("password") : QStringLiteral("wrong-password");
        if (unsupportedEncryption(msg))
            return QStringLiteral("unsupported-encryption");
        return msg;
    }
    archive_write_close(w);   // время изменения папок ставится в конце
    if (progress)
        progress(1);
    if (written)
        *written = tops.size() == 1 ? tops.first() : root;
    return QString();
}

// ---------------------------------------------------------------- создание

QString Archive::createSync(const QStringList &sources, const QString &out, const QString &format,
                            const QString &password, std::atomic<bool> *cancel, std::function<void(qreal)> progress)
{
    if (sources.isEmpty())
        return glideTr(QStringLiteral("Нечего упаковывать"));
    const QString part = out + QStringLiteral(".part");
    const QString outAbs = QFileInfo(out).absoluteFilePath();

    struct Item { QString abs, rel; qint64 size; };
    QList<Item> items;
    qint64 total = 0;
    QSet<QString> names;
    for (const QString &s : sources) {
        const QFileInfo fi(s);
        if (!fi.exists() && !fi.isSymLink())
            return glideTr(QStringLiteral("Нет файла %1")).arg(s);
        QString top = fi.fileName();
        // два источника с одинаковым именем из разных папок
        for (int i = 2; names.contains(top); ++i)
            top = fi.completeBaseName() + QStringLiteral(" (%1)").arg(i) + (fi.suffix().isEmpty() ? QString() : "." + fi.suffix());
        names.insert(top);
        items << Item{fi.absoluteFilePath(), top, fi.isFile() && !fi.isSymLink() ? fi.size() : 0};
        total += items.last().size;
        if (fi.isDir() && !fi.isSymLink()) {
            QDirIterator it(fi.absoluteFilePath(), QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot,
                            QDirIterator::Subdirectories);
            QList<Item> sub;
            while (it.hasNext()) {
                const QString p = it.next();
                const QFileInfo f = it.fileInfo();
                if (p == outAbs || p == part)
                    continue;
                sub << Item{p, top + p.mid(fi.absoluteFilePath().size()), f.isFile() && !f.isSymLink() ? f.size() : 0};
                total += sub.last().size;
            }
            std::sort(sub.begin(), sub.end(), [](const Item &a, const Item &b) { return a.rel < b.rel; });
            items << sub;
        }
    }

    archive *w = archive_write_new();
    struct Closer { archive *w; ~Closer() { archive_write_free(w); } } closer{w};
    int rc = ARCHIVE_OK;
    if (format == QLatin1String("zip")) {
        rc = archive_write_set_format_zip(w);
        archive_write_set_options(w, "zip:hdrcharset=UTF-8");
        if (!password.isEmpty()) {
            // AES-256: открывают 7-Zip, WinRAR, проводник Windows 11, ark; старый «ZipCrypto» — небезопасен
            if (archive_write_set_options(w, "zip:encryption=aes256") != ARCHIVE_OK
                || archive_write_set_passphrase(w, password.toUtf8().constData()) != ARCHIVE_OK)
                return errorOf(w);
        }
    } else if (format == QLatin1String("7z")) {
        rc = archive_write_set_format_7zip(w);
        archive_write_set_options(w, "7zip:compression=lzma2");
    } else if (format.startsWith(QLatin1String("tar"))) {
        rc = archive_write_set_format_pax_restricted(w);
        if (format == QLatin1String("tar.zst")) rc = qMin(rc, archive_write_add_filter_zstd(w));
        else if (format == QLatin1String("tar.xz")) rc = qMin(rc, archive_write_add_filter_xz(w));
        else if (format == QLatin1String("tar.gz")) rc = qMin(rc, archive_write_add_filter_gzip(w));
        else if (format != QLatin1String("tar")) return glideTr(QStringLiteral("Неизвестный формат: %1")).arg(format);
    } else {
        return glideTr(QStringLiteral("Неизвестный формат: %1")).arg(format);
    }
    if (rc != ARCHIVE_OK)
        return errorOf(w);
    if (!password.isEmpty() && format != QLatin1String("zip"))
        return glideTr(QStringLiteral("Пароль можно поставить только на zip"));

    QFile::remove(part);
    if (archive_write_open_filename(w, QFile::encodeName(part).constData()) != ARCHIVE_OK)
        return errorOf(w);
    auto fail = [&](const QString &msg) {
        archive_write_close(w);
        QFile::remove(part);
        return msg;
    };

    archive *disk = archive_read_disk_new();
    archive_read_disk_set_standard_lookup(disk);
    archive_read_disk_set_symlink_physical(disk);   // ссылки — ссылками, не их содержимым
    struct DiskCloser { archive *d; ~DiskCloser() { archive_read_free(d); } } diskCloser{disk};

    qint64 done = 0;
    qreal lastProgress = -1;
    QByteArray buf(Block, Qt::Uninitialized);
    for (const Item &it : items) {
        if (cancel && *cancel)
            return fail(QStringLiteral("cancelled"));
        archive_entry *e = archive_entry_new();
        struct EntryFree { archive_entry *e; ~EntryFree() { archive_entry_free(e); } } ef{e};
        const QByteArray src = QFile::encodeName(it.abs);
        archive_entry_copy_sourcepath(e, src.constData());
        if (archive_read_disk_entry_from_file(disk, e, -1, nullptr) < ARCHIVE_WARN)
            return fail(QStringLiteral("%1: %2").arg(it.rel, errorOf(disk)));
        archive_entry_update_pathname_utf8(e, it.rel.toUtf8().constData());
        const int type = archive_entry_filetype(e);
        if (type != AE_IFREG && type != AE_IFDIR && type != AE_IFLNK)
            continue;   // сокеты, устройства, fifo — в архив не кладём
        if (archive_write_header(w, e) < ARCHIVE_WARN)
            return fail(QStringLiteral("%1: %2").arg(it.rel, errorOf(w)));
        if (type == AE_IFREG && archive_entry_size(e) > 0) {
            QFile f(it.abs);
            if (!f.open(QIODevice::ReadOnly))
                return fail(QStringLiteral("%1: %2").arg(it.rel, f.errorString()));
            qint64 n;
            while ((n = f.read(buf.data(), buf.size())) > 0) {
                if (archive_write_data(w, buf.constData(), size_t(n)) < 0)
                    return fail(QStringLiteral("%1: %2").arg(it.rel, errorOf(w)));
                done += n;
                if (cancel && *cancel)
                    return fail(QStringLiteral("cancelled"));
                if (progress && total > 0) {
                    const qreal p = qreal(done) / total * 0.98;   // остаток — запись хвоста (7z сжимает в конце)
                    if (p - lastProgress >= 0.005) { lastProgress = p; progress(p); }
                }
            }
        }
    }
    if (archive_write_close(w) != ARCHIVE_OK) {
        const QString msg = errorOf(w);
        QFile::remove(part);
        return msg;
    }
    QFile::remove(out);   // «Сохранить как» уже спросил про замену
    if (!QFile::rename(part, out)) {
        QFile::remove(part);
        return glideTr(QStringLiteral("Не удалось записать %1")).arg(out);
    }
    if (progress)
        progress(1);
    return QString();
}

// ---------------------------------------------------------------- объект для QML

Archive::Archive(QObject *parent) : QObject(parent) {}

Archive::~Archive()
{
    if (m_thread) {
        m_cancel = true;
        m_thread->wait();
        delete m_thread;
    }
}

void Archive::setBusy(bool b)
{
    if (m_busy == b)
        return;
    m_busy = b;
    emit busyChanged();
}

void Archive::setProgress(qreal p)
{
    if (qFuzzyCompare(m_progress + 1, p + 1))
        return;
    m_progress = p;
    emit progressChanged();
}

void Archive::run(std::function<void()> job)
{
    m_cancel = false;
    setProgress(0);
    setBusy(true);
    m_thread = QThread::create(std::move(job));
    m_thread->start();
}

// в начале каждого ответа из потока: поток уже выходит (ответ — его последнее действие), ждать — микросекунды.
// «Занят» снимаем до сигналов, чтобы обработчик мог сразу начать следующее (открыть созданный архив).
void Archive::done()
{
    if (m_thread) {
        m_thread->wait();
        delete m_thread;
        m_thread = nullptr;
    }
    setBusy(false);
}

QString Archive::localPath(const QString &url) const
{
    if (url.startsWith(QLatin1String("file:")))
        return QUrl(url).toLocalFile();
    return url;
}

bool Archive::isArchive(const QString &pathOrUrl) const
{
    static const QStringList exts{"zip", "7z", "rar", "tar", "tgz", "gz", "xz", "txz", "zst", "tzst", "bz2", "tbz",
                                  "tbz2", "lz4", "lzma", "tlz", "iso", "cab", "cpio", "jar", "apk", "cbz", "cbr",
                                  "cb7", "xpi", "deb", "rpm", "ar", "lha", "lzh", "xar", "war", "epub"};
    const QFileInfo fi(localPath(pathOrUrl));
    return fi.isFile() && exts.contains(fi.suffix().toLower());
}

void Archive::open(const QString &pathOrUrl, const QString &password)
{
    if (m_busy)
        return;
    const QString p = QFileInfo(localPath(pathOrUrl)).absoluteFilePath();
    run([this, p, password] {
        Listing l;
        const QString err = listSync(p, password, &l);
        QMetaObject::invokeMethod(this, [this, p, password, err, l] {
            done();
            if (err == QLatin1String("password") || err == QLatin1String("wrong-password")) {
                m_path = p;
                m_password.clear();
                m_entries.clear();
                m_format.clear();
                m_total = 0;
                m_needsPassword = true;
                emit opened();
                emit passwordRequired(err == QLatin1String("wrong-password"), false);
                return;
            }
            if (!err.isEmpty()) {
                emit failed(err == QLatin1String("unsupported-encryption")
                                ? glideTr(QStringLiteral("Зашифрованные 7z и RAR пока не открываются"))
                                : err);
                return;
            }
            m_path = p;
            m_password = password;
            m_charset = l.charset;
            m_entries = l.entries;
            m_format = l.format;
            m_total = l.total;
            m_encrypted = l.encrypted;
            m_needsPassword = false;
            emit opened();
        }, Qt::QueuedConnection);
    });
}

void Archive::setPassword(const QString &password)
{
    m_password = password;
}

QString Archive::defaultDestination() const
{
    const QFileInfo fi(m_path);
    // одна запись верхнего уровня — прямо рядом с архивом (если имя свободно), иначе — папка по имени архива
    QSet<QString> tops;
    for (const QVariant &v : m_entries)
        tops.insert(v.toMap().value("path").toString().section(QLatin1Char('/'), 0, 0));
    if (tops.size() == 1 && !QFileInfo::exists(fi.absolutePath() + QLatin1Char('/') + *tops.begin()))
        return fi.absolutePath();
    QString name = fi.fileName();
    static const QStringList doubles{".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tar.lz4", ".tar.lzma"};
    bool chopped = false;
    for (const QString &d : doubles)
        if (name.endsWith(d, Qt::CaseInsensitive)) { name.chop(d.size()); chopped = true; break; }
    if (!chopped && name.lastIndexOf(QLatin1Char('.')) > 0)
        name.truncate(name.lastIndexOf(QLatin1Char('.')));
    return uniquePath(fi.absolutePath() + QLatin1Char('/') + name);
}

void Archive::extract(const QStringList &paths, const QString &dest)
{
    if (m_busy || m_path.isEmpty())
        return;
    const QString target = dest.isEmpty() ? defaultDestination() : localPath(dest);
    const QString p = m_path, pw = m_password, cs = m_charset;
    run([this, p, pw, cs, paths, target] {
        QString written;
        QStringList skipped;
        const QString err = extractSync(p, pw, cs, paths, target, &written, &skipped, &m_cancel,
                                        [this](qreal v) { QMetaObject::invokeMethod(this, [this, v] { setProgress(v); }, Qt::QueuedConnection); });
        QMetaObject::invokeMethod(this, [this, err, written, skipped] {
            done();
            if (err.isEmpty())
                emit extracted(written, skipped.size());
            else if (err == QLatin1String("password") || err == QLatin1String("wrong-password"))
                emit passwordRequired(err == QLatin1String("wrong-password"), true);
            else if (err == QLatin1String("cancelled"))
                emit failed(glideTr(QStringLiteral("Распаковка отменена")));
            else if (err == QLatin1String("unsupported-encryption"))
                emit failed(glideTr(QStringLiteral("Зашифрованные 7z и RAR пока не распаковываются")));
            else
                emit failed(err);
        }, Qt::QueuedConnection);
    });
}

void Archive::openEntry(const QString &entry)
{
    if (m_busy || m_path.isEmpty())
        return;
    // своя папка на каждое открытие: файл могли открыть дважды, а программа ещё держит первый.
    // Кэш чистится при запуске (cleanOpened) — открытые в прошлый раз файлы уже не нужны.
    const QString base = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/opened");
    QDir().mkpath(base);
    QTemporaryDir tmp(base + QStringLiteral("/XXXXXX"));
    tmp.setAutoRemove(false);
    const QString dir = tmp.path();
    const QString p = m_path, pw = m_password, cs = m_charset;
    run([this, p, pw, cs, entry, dir] {
        QString written;
        const QString err = extractSync(p, pw, cs, {entry}, dir, &written, nullptr, &m_cancel, {});
        QMetaObject::invokeMethod(this, [this, err, written] {
            done();
            if (err.isEmpty())
                emit entryReady(written);
            else if (err == QLatin1String("password") || err == QLatin1String("wrong-password"))
                emit passwordRequired(err == QLatin1String("wrong-password"), true);
            else if (err != QLatin1String("cancelled"))
                emit failed(err);
        }, Qt::QueuedConnection);
    });
}

void Archive::cleanOpened()
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/opened");
    const QDateTime old = QDateTime::currentDateTime().addDays(-1);
    for (const QFileInfo &fi : QDir(base).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot))
        if (fi.lastModified() < old)   // сутки — с запасом: вдруг файл ещё открыт в другой программе
            QDir(fi.absoluteFilePath()).removeRecursively();
}

QString Archive::suggestName(const QStringList &sources, const QString &format) const
{
    if (sources.isEmpty())
        return QString();
    const QFileInfo first(localPath(sources.first()));
    QString base = sources.size() == 1 ? first.fileName() : first.absoluteDir().dirName();
    if (base.isEmpty())
        base = glideTr(QStringLiteral("Архив"));
    return uniquePath(first.absolutePath() + QLatin1Char('/') + base + QLatin1Char('.') + format);
}

void Archive::create(const QStringList &sources, const QString &out, const QString &format, const QString &password)
{
    if (m_busy)
        return;
    QStringList src;
    for (const QString &s : sources)
        src << localPath(s);
    const QString target = uniquePath(localPath(out));   // своё окно не спрашивает о замене — не затираем
    run([this, src, target, format, password] {
        const QString err = createSync(src, target, format, password, &m_cancel,
                                       [this](qreal v) { QMetaObject::invokeMethod(this, [this, v] { setProgress(v); }, Qt::QueuedConnection); });
        QMetaObject::invokeMethod(this, [this, err, target] {
            done();
            if (err.isEmpty())
                emit created(target);
            else
                emit failed(err == QLatin1String("cancelled") ? glideTr(QStringLiteral("Создание отменено")) : err);
        }, Qt::QueuedConnection);
    });
}

void Archive::showInFolder(const QString &file) const
{
    QDBusMessage msg = QDBusMessage::createMethodCall("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                                                      "org.freedesktop.FileManager1", "ShowItems");
    msg << QStringList{QUrl::fromLocalFile(file).toString()} << QString();
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

QVariantMap Archive::sourcesInfo(const QStringList &sources) const
{
    qint64 size = 0;
    int files = 0, dirs = 0, seen = 0;
    QStringList names, paths;
    for (const QString &s : sources) {
        const QFileInfo fi(localPath(s));
        if (!fi.exists())
            continue;
        paths << fi.absoluteFilePath();
        names << fi.fileName();
        if (fi.isDir() && !fi.isSymLink()) {
            ++dirs;
            QDirIterator it(fi.absoluteFilePath(), QDir::Files | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot,
                            QDirIterator::Subdirectories);
            while (it.hasNext() && ++seen < 200000) {   // огромные деревья не считаем до конца
                it.next();
                if (!it.fileInfo().isSymLink())
                    size += it.fileInfo().size();
                ++files;
            }
        } else {
            ++files;
            size += fi.isSymLink() ? 0 : fi.size();
        }
    }
    return {{"count", paths.size()}, {"files", files}, {"dirs", dirs}, {"size", size}, {"names", names},
            {"paths", paths}, {"folder", paths.isEmpty() ? QDir::homePath() : QFileInfo(paths.first()).absolutePath()}};
}

QString Archive::homePath(const QString &path) const
{
    const QString home = QDir::homePath();
    if (path == home)
        return QStringLiteral("~");
    return path.startsWith(home + QLatin1Char('/')) ? QLatin1Char('~') + path.mid(home.size()) : path;
}
