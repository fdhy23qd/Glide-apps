#include "library.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>

namespace {
constexpr int kMax = 300;
}

Library::Library(QObject *parent) : QObject(parent)
{
    m_file = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + "/glide-apps/pdf-positions.json";
    QFile f(m_file);
    if (f.open(QIODevice::ReadOnly))
        m_data = QJsonDocument::fromJson(f.readAll()).object();
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(1500);
    connect(&m_saveTimer, &QTimer::timeout, this, &Library::flush);
}

Library::~Library()
{
    if (m_saveTimer.isActive())
        flush();
}

QVariantMap Library::position(const QString &path) const
{
    return m_data.value(path).toObject().toVariantMap();
}

void Library::savePosition(const QString &path, const QVariantMap &pos)
{
    if (path.isEmpty())
        return;
    QJsonObject o = QJsonObject::fromVariantMap(pos);
    o.insert("t", double(QDateTime::currentSecsSinceEpoch()));
    m_data.insert(path, o);
    if (m_data.size() > kMax) {   // самое давнее — вон
        QString oldest;
        double t = 1e18;
        for (auto it = m_data.begin(); it != m_data.end(); ++it)
            if (it->toObject().value("t").toDouble() < t) { t = it->toObject().value("t").toDouble(); oldest = it.key(); }
        m_data.remove(oldest);
    }
    m_saveTimer.start();
}

void Library::flush()
{
    QDir().mkpath(QFileInfo(m_file).absolutePath());
    QSaveFile f(m_file);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(m_data).toJson(QJsonDocument::Compact));
    f.commit();
}

QString Library::localPath(const QString &pathOrUrl) const
{
    const QString p = pathOrUrl.startsWith("file:") ? QUrl(pathOrUrl).toLocalFile() : pathOrUrl;
    return p.isEmpty() ? QString() : QFileInfo(p).absoluteFilePath();
}

QUrl Library::fileUrl(const QString &path) const
{
    return QUrl::fromLocalFile(path);
}

QVariantMap Library::fileInfo(const QString &path) const
{
    const QFileInfo fi(path);
    return {{"name", fi.fileName()}, {"bytes", fi.size()}, {"modified", fi.lastModified()},
            {"folder", fi.absolutePath()}, {"exists", fi.exists()}};
}

void Library::showInFolder(const QString &path) const
{
    QDBusMessage msg = QDBusMessage::createMethodCall("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                                                      "org.freedesktop.FileManager1", "ShowItems");
    msg << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    QDBusConnection::sessionBus().asyncCall(msg);
}
