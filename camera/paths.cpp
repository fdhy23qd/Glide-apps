#include "paths.h"
#include "glidetr.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>

namespace {

QString unique(const QString &folder, const QString &stem, const QString &ext)
{
    QDir().mkpath(folder);
    QString p = QStringLiteral("%1/%2.%3").arg(folder, stem, ext);
    for (int n = 2; QFileInfo::exists(p); ++n)
        p = QStringLiteral("%1/%2 (%3).%4").arg(folder, stem).arg(n).arg(ext);
    return p;
}

QString stamp() { return QDateTime::currentDateTime().toString("yyyy-MM-dd HH-mm-ss"); }

}

bool Paths::cameraOff() const { return qEnvironmentVariable("GLIDE_CAMERA_OFF") == "1"; }

QString Paths::photoFolder() const
{
    return QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + '/' + glideTr(QStringLiteral("Камера"));
}

QString Paths::videoFolder() const
{
    return QStandardPaths::writableLocation(QStandardPaths::MoviesLocation) + '/' + glideTr(QStringLiteral("Камера"));
}

QString Paths::newPhoto() const { return unique(photoFolder(), glideTr(QStringLiteral("Фото ")) + stamp(), "jpg"); }
QString Paths::newVideo() const { return unique(videoFolder(), glideTr(QStringLiteral("Видео ")) + stamp(), "mp4"); }

QString Paths::latest() const
{
    QFileInfo best;
    for (const QString &folder : {photoFolder(), videoFolder()}) {
        const QFileInfoList files = QDir(folder).entryInfoList({"*.jpg", "*.mp4"}, QDir::Files, QDir::Time);
        if (!files.isEmpty() && (!best.exists() || files.first().lastModified() > best.lastModified()))
            best = files.first();
    }
    return best.exists() ? best.absoluteFilePath() : QString();
}
