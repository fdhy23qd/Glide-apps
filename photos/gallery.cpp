#include "gallery.h"

#include <QClipboard>
#include <QCollator>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QImageReader>
#include <QSet>
#include <QUrl>
#include <algorithm>

namespace {

const QSet<QString> &suffixes()
{
    static const QSet<QString> set = [] {
        QSet<QString> s;
        for (const QByteArray &f : QImageReader::supportedImageFormats())
            s.insert(QString::fromLatin1(f).toLower());
        s.remove("pdf");   // плагин QtPdf: страницы — дело просмотрщика PDF
        s.insert("jpe");
        return s;
    }();
    return set;
}

QString toLocal(const QString &pathOrUrl)
{
    if (pathOrUrl.startsWith("file:"))
        return QUrl(pathOrUrl).toLocalFile();
    return pathOrUrl;
}

} // namespace

Gallery::Gallery(QObject *parent) : QObject(parent)
{
    m_rescan.setSingleShot(true);
    m_rescan.setInterval(300);   // копирование пачки файлов — один пересчёт
    connect(&m_rescan, &QTimer::timeout, this, [this] { rescan(path()); });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Gallery::scheduleRescan);
}

bool Gallery::isImage(const QString &path)
{
    return suffixes().contains(QFileInfo(path).suffix().toLower());
}

bool Gallery::open(const QString &pathOrUrl)
{
    const QFileInfo fi(toLocal(pathOrUrl));
    if (!fi.exists()) {
        emit error(QStringLiteral("Файл не найден: %1").arg(fi.fileName()));
        return false;
    }
    if (!fi.isDir() && !isImage(fi.fileName())) {
        emit error(QStringLiteral("Формат «%1» не поддерживается").arg(fi.suffix()));
        return false;
    }
    const QString folder = fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath();
    if (!m_folder.isEmpty())
        m_watcher.removePath(m_folder);
    m_folder = folder;
    m_index = -1;
    m_watcher.addPath(m_folder);
    rescan(fi.isDir() ? QString() : fi.absoluteFilePath());
    if (m_index < 0)
        emit error(QStringLiteral("В папке нет картинок"));
    return m_index >= 0;
}

void Gallery::rescan(const QString &keep)
{
    QDir dir(m_folder);
    QStringList names = dir.entryList(QDir::Files | QDir::Readable | QDir::Hidden, QDir::NoSort);
    names.erase(std::remove_if(names.begin(), names.end(),
                               [](const QString &n) { return !isImage(n) || n.startsWith('.'); }),
                names.end());
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(names.begin(), names.end(), [&](const QString &a, const QString &b) { return collator.compare(a, b) < 0; });

    const QString keepName = keep.isEmpty() ? QString() : QFileInfo(keep).fileName();
    const int oldIndex = m_index;
    const QString oldPath = path();
    m_files = names;
    ++m_revision;
    int i = keepName.isEmpty() ? (m_files.isEmpty() ? -1 : 0) : int(m_files.indexOf(keepName));
    if (i < 0 && !m_files.isEmpty())   // текущий удалили со стороны — встаём на соседний
        i = std::clamp(oldIndex, 0, int(m_files.size()) - 1);
    m_index = i;
    emit listChanged();
    if (path() != oldPath || m_index != oldIndex)
        emit currentChanged();
}

void Gallery::setIndex(int i)
{
    if (m_files.isEmpty())
        return;
    i = std::clamp(i, 0, int(m_files.size()) - 1);
    if (i == m_index)
        return;
    m_index = i;
    emit currentChanged();
}

QString Gallery::path() const
{
    if (m_index < 0 || m_index >= m_files.size())
        return {};
    return m_folder + '/' + m_files.at(m_index);
}

QString Gallery::urlAt(int i) const
{
    if (i < 0 || i >= m_files.size())
        return {};
    // ?v=время изменения: замена файла на месте («Заменить оригинал») — новый адрес для кэша картинок Qt
    const QString p = m_folder + '/' + m_files.at(i);
    QUrl url = QUrl::fromLocalFile(p);
    url.setQuery(QStringLiteral("v=%1").arg(QFileInfo(p).lastModified().toMSecsSinceEpoch()));
    return url.toString();
}

QVariantMap Gallery::info() const
{
    return infoAt(m_index);
}

QVariantMap Gallery::infoAt(int i) const
{
    if (i < 0 || i >= m_files.size())
        return {};
    const QString p = m_folder + '/' + m_files.at(i);
    const QFileInfo fi(p);
    const QDateTime mtime = fi.lastModified();
    auto it = m_infoCache.constFind(p);
    if (it != m_infoCache.cend() && it->value("modified").toDateTime() == mtime)
        return *it;

    // только заголовок: размер, формат, поворот EXIF, анимация — без декодирования пикселей
    QImageReader reader(p);
    reader.setAutoTransform(true);
    QSize size = reader.size();
    const QImageIOHandler::Transformations tr = reader.transformation();
    if (tr & QImageIOHandler::TransformationRotate90)
        size.transpose();
    const QString suffix = fi.suffix().toLower();
    QVariantMap m{
        {"name", fi.fileName()},
        {"path", p},
        {"width", size.width()},
        {"height", size.height()},
        {"bytes", fi.size()},
        {"modified", mtime},
        {"format", QString::fromLatin1(reader.format()).toUpper()},
        {"animated", reader.supportsAnimation() && reader.imageCount() != 1},
        {"vector", suffix == "svg" || suffix == "svgz"},
    };
    if (m_infoCache.size() > 512)
        m_infoCache.clear();
    m_infoCache.insert(p, m);
    return m;
}

bool Gallery::trash()
{
    const QString p = path();
    if (p.isEmpty())
        return false;
    QString inTrash;
    if (!QFile::moveToTrash(p, &inTrash)) {
        emit error(QStringLiteral("Не удалось переместить в корзину"));
        return false;
    }
    m_trashed.append({p, inTrash, {}});
    emit undoChanged();
    const int at = m_index;
    m_watcher.blockSignals(true);   // список правим сами, без пересчёта по событию папки
    m_files.removeAt(at);
    m_watcher.blockSignals(false);
    ++m_revision;
    m_index = m_files.isEmpty() ? -1 : std::min(at, int(m_files.size()) - 1);
    emit listChanged();
    emit currentChanged();
    return true;
}

bool Gallery::undoTrash()
{
    if (m_trashed.isEmpty())
        return false;
    const Trashed t = m_trashed.takeLast();
    emit undoChanged();
    // отмена замены: правленый файл — тоже в корзину (не удаляем насовсем), оригинал — на место
    if (!t.replacement.isEmpty() && QFileInfo::exists(t.replacement))
        QFile::moveToTrash(t.replacement);
    if (QFileInfo::exists(t.original) || !QFile::rename(t.inTrash, t.original)) {
        emit error(QStringLiteral("Не удалось вернуть файл из корзины"));
        return false;
    }
    // описание в Trash/info больше не нужно: иначе корзина покажет «призрак»
    const QFileInfo trashed(t.inTrash);
    QFile::remove(trashed.dir().absolutePath() + "/../info/" + trashed.fileName() + ".trashinfo");
    if (QFileInfo(t.original).absolutePath() == m_folder)
        rescan(t.original);
    return true;
}

void Gallery::recordReplace(const QString &original, const QString &inTrash, const QString &replacement)
{
    m_trashed.append({original, inTrash, replacement});
    emit undoChanged();
}

bool Gallery::copyImage() const
{
    QImageReader reader(path());
    reader.setAutoTransform(true);
    const QImage img = reader.read();
    if (img.isNull())
        return false;
    QGuiApplication::clipboard()->setImage(img);
    return true;
}

void Gallery::copyPath() const
{
    QGuiApplication::clipboard()->setText(path());
}

void Gallery::showInFolder() const
{
    // файловый менеджер (Nautilus) выделит файл; без него — просто откроется папка
    QDBusMessage msg = QDBusMessage::createMethodCall("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                                                      "org.freedesktop.FileManager1", "ShowItems");
    msg << QStringList{QUrl::fromLocalFile(path()).toString()} << QString();
    QDBusConnection::sessionBus().asyncCall(msg);
}
