#include "playlist.h"
#include "glidetr.h"

#include <QCollator>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QStringDecoder>
#include <QUrl>
#include <algorithm>

namespace {

const QSet<QString> kMedia = {
    "mp4", "m4v", "mkv", "webm", "mov", "avi", "wmv", "flv", "ts", "m2ts", "mts", "mpg", "mpeg", "3gp", "ogv",
    "mp3", "flac", "ogg", "oga", "opus", "m4a", "aac", "wav", "wma",
};

constexpr int kMaxResume = 300;

} // namespace

Playlist::Playlist(QObject *parent) : QObject(parent)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + "/glide-apps";
    m_resumeFile = dir + "/video-resume.json";
    QFile f(m_resumeFile);
    if (f.open(QIODevice::ReadOnly))
        m_resume = QJsonDocument::fromJson(f.readAll()).object();
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(2000);
    connect(&m_saveTimer, &QTimer::timeout, this, &Playlist::flush);
}

Playlist::~Playlist()
{
    if (m_saveTimer.isActive())
        flush();
}

bool Playlist::isMedia(const QString &name)
{
    return kMedia.contains(QFileInfo(name).suffix().toLower());
}

bool Playlist::open(const QString &pathOrUrl)
{
    const QString local = pathOrUrl.startsWith("file:") ? QUrl(pathOrUrl).toLocalFile() : pathOrUrl;
    const QFileInfo fi(local);
    if (!fi.exists()) {
        emit error(glideTr(QStringLiteral("Файл не найден: %1")).arg(fi.fileName()));
        return false;
    }
    if (fi.isFile() && !isMedia(fi.fileName())) {
        emit error(glideTr(QStringLiteral("Формат «%1» не поддерживается")).arg(fi.suffix()));
        return false;
    }
    m_folder = fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath();
    QStringList names = QDir(m_folder).entryList(QDir::Files | QDir::Readable, QDir::NoSort);
    names.erase(std::remove_if(names.begin(), names.end(), [](const QString &n) { return !isMedia(n); }), names.end());
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(names.begin(), names.end(), [&](const QString &a, const QString &b) { return collator.compare(a, b) < 0; });
    m_files = names;
    m_index = fi.isDir() ? (m_files.isEmpty() ? -1 : 0) : int(m_files.indexOf(fi.fileName()));
    emit listChanged();
    emit currentChanged();
    if (m_index < 0)
        emit error(glideTr(QStringLiteral("В папке нет видео")));
    return m_index >= 0;
}

void Playlist::setIndex(int i)
{
    if (m_files.isEmpty())
        return;
    i = std::clamp(i, 0, int(m_files.size()) - 1);
    if (i == m_index)
        return;
    m_index = i;
    emit currentChanged();
}

QString Playlist::path() const
{
    return m_index >= 0 && m_index < m_files.size() ? m_folder + '/' + m_files.at(m_index) : QString();
}

QString Playlist::url() const
{
    const QString p = path();
    return p.isEmpty() ? QString() : QUrl::fromLocalFile(p).toString();
}

QString Playlist::name() const
{
    return m_index >= 0 && m_index < m_files.size() ? m_files.at(m_index) : QString();
}

qint64 Playlist::resumePosition(const QString &path) const
{
    const QJsonObject e = m_resume.value(path).toObject();
    return qint64(e.value("pos").toDouble());
}

void Playlist::savePosition(const QString &path, qint64 positionMs, qint64 durationMs)
{
    if (path.isEmpty() || durationMs <= 0)
        return;
    // короткие ролики и почти досмотренные — не запоминаем; первые 10 с — тоже
    const bool keep = durationMs > 90000 && positionMs > 10000 && positionMs < durationMs - 15000;
    if (!keep) {
        if (m_resume.contains(path)) {
            m_resume.remove(path);
            m_saveTimer.start();
        }
        return;
    }
    m_resume.insert(path, QJsonObject{{"pos", double(positionMs)}, {"dur", double(durationMs)},
                                      {"t", double(QDateTime::currentSecsSinceEpoch())}});
    if (m_resume.size() > kMaxResume) {   // самое давнее — вон
        QString oldest;
        double t = 1e18;
        for (auto it = m_resume.begin(); it != m_resume.end(); ++it)
            if (it->toObject().value("t").toDouble() < t) { t = it->toObject().value("t").toDouble(); oldest = it.key(); }
        m_resume.remove(oldest);
    }
    m_saveTimer.start();
}

void Playlist::flush()
{
    QDir().mkpath(QFileInfo(m_resumeFile).absolutePath());
    QSaveFile f(m_resumeFile);   // атомарно: временный файл и rename
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(m_resume).toJson(QJsonDocument::Compact));
    f.commit();
}

void Playlist::showInFolder(const QString &path) const
{
    QDBusMessage msg = QDBusMessage::createMethodCall("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                                                      "org.freedesktop.FileManager1", "ShowItems");
    msg << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    QDBusConnection::sessionBus().asyncCall(msg);
}

QVariantList Playlist::subtitleFiles(const QString &path) const
{
    const QFileInfo fi(path);
    const QString base = fi.completeBaseName();
    QVariantList out;
    const QStringList names = QDir(fi.absolutePath()).entryList({"*.srt", "*.vtt", "*.SRT", "*.VTT"}, QDir::Files, QDir::Name);
    for (const QString &n : names) {
        if (!n.startsWith(base))
            continue;
        // «фильм.ru.srt» → «ru», «фильм.srt» → имя файла
        QString label = n.mid(base.size()).section('.', 1, -2);
        out.append(QVariantMap{{"file", fi.absolutePath() + '/' + n}, {"label", label.isEmpty() ? n : label}});
    }
    return out;
}

QVariantList Playlist::loadSubtitles(const QString &file) const
{
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly) || f.size() > 8 * 1024 * 1024)
        return {};
    QByteArray raw = f.readAll();
    QString text = QString::fromUtf8(raw);
    if (text.contains(QChar::ReplacementCharacter))   // не UTF-8 — чаще всего старые русские srt в cp1251
        if (auto dec = QStringDecoder("windows-1251"); dec.isValid())
            text = dec(raw);
    text.replace("\r\n", "\n").replace('\r', '\n');
    static const QRegularExpression timeRe(
        R"((?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{3})\s*-->\s*(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{3}))");
    static const QRegularExpression tags(R"(<[^>]*>|\{\\[^}]*\})");
    auto ms = [](const QRegularExpressionMatch &m, int i) {
        return ((m.captured(i).toLongLong() * 60 + m.captured(i + 1).toLongLong()) * 60 + m.captured(i + 2).toLongLong()) * 1000
               + m.captured(i + 3).toLongLong();
    };
    QVariantList out;
    for (const QString &block : text.split(QRegularExpression("\n\\s*\n"), Qt::SkipEmptyParts)) {
        QStringList lines = block.split('\n');
        int i = 0;
        while (i < lines.size() && !lines[i].contains("-->")) ++i;
        if (i >= lines.size()) continue;
        const auto m = timeRe.match(lines[i]);
        if (!m.hasMatch()) continue;
        QString t = lines.mid(i + 1).join('\n').remove(tags).trimmed();
        if (!t.isEmpty())
            out.append(QVariantMap{{"s", ms(m, 1)}, {"e", ms(m, 5)}, {"t", t}});
    }
    return out;
}
