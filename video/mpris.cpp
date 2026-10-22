#include "mpris.h"
#include "glidetr.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QStringList>
#include <QUrl>
#include <cstdlib>
#include <unistd.h>

namespace {
const char *kPath = "/org/mpris/MediaPlayer2";
const char *kPlayer = "org.mpris.MediaPlayer2.Player";
} // namespace

// org.mpris.MediaPlayer2 — само приложение
class MprisRoot : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ yes)
    Q_PROPERTY(bool CanRaise READ yes)
    Q_PROPERTY(bool HasTrackList READ no)
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry)
    Q_PROPERTY(QStringList SupportedUriSchemes READ schemes)
    Q_PROPERTY(QStringList SupportedMimeTypes READ mimes)
public:
    explicit MprisRoot(Mpris *m) : QDBusAbstractAdaptor(m), m_m(m) {}
    bool yes() const { return true; }
    bool no() const { return false; }
    QString identity() const { return glideTr(QStringLiteral("Glide Видео")); }
    QString desktopEntry() const { return QStringLiteral("glide-video"); }
    QStringList schemes() const { return {"file"}; }
    QStringList mimes() const { return {"video/mp4", "video/x-matroska", "video/webm", "audio/mpeg"}; }
public slots:
    void Raise() { emit m_m->raiseRequested(); }
    void Quit() { emit m_m->quitRequested(); }
private:
    Mpris *m_m;
};

// org.mpris.MediaPlayer2.Player — воспроизведение
class MprisPlayer : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ status)
    Q_PROPERTY(double Rate READ rate WRITE setRate)
    Q_PROPERTY(double MinimumRate READ minRate)
    Q_PROPERTY(double MaximumRate READ maxRate)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(bool CanGoNext READ canNext)
    Q_PROPERTY(bool CanGoPrevious READ canPrev)
    Q_PROPERTY(bool CanPlay READ hasMedia)
    Q_PROPERTY(bool CanPause READ hasMedia)
    Q_PROPERTY(bool CanSeek READ hasMedia)
    Q_PROPERTY(bool CanControl READ yes)
public:
    explicit MprisPlayer(Mpris *m) : QDBusAbstractAdaptor(m), m_m(m) {}
    QString status() const { return m_m->status(); }
    double rate() const { return m_m->rate(); }
    void setRate(double r) { emit m_m->rateRequested(r); }
    double minRate() const { return 0.25; }
    double maxRate() const { return 4.0; }
    QVariantMap metadata() const { return m_m->metadata(); }
    double volume() const { return m_m->volume(); }
    void setVolume(double v) { m_m->requestVolume(v); }
    qlonglong position() const { return m_m->position() * 1000; }   // мкс
    bool canNext() const { return m_m->canNext(); }
    bool canPrev() const { return m_m->canPrevious(); }
    bool hasMedia() const { return !m_m->url().isEmpty(); }
    bool yes() const { return true; }
public slots:
    void Next() { emit m_m->nextRequested(); }
    void Previous() { emit m_m->previousRequested(); }
    void Pause() { emit m_m->pauseRequested(); }
    void PlayPause() { emit m_m->toggleRequested(); }
    void Stop() { emit m_m->stopRequested(); }
    void Play() { emit m_m->playRequested(); }
    void Seek(qlonglong offsetUs) { emit m_m->seekRequested(std::max<qint64>(0, m_m->position() + offsetUs / 1000)); }
    void SetPosition(const QDBusObjectPath &track, qlonglong us)
    {
        if (track == m_m->trackId())   // по спецификации: позиция для другого трека — игнорировать
            emit m_m->seekRequested(us / 1000);
    }
    void OpenUri(const QString &) {}
signals:
    void Seeked(qlonglong positionUs);
private:
    Mpris *m_m;
};

Mpris::Mpris(QObject *parent) : QObject(parent)
{
    new MprisRoot(this);
    new MprisPlayer(this);
    QDBusConnection bus = QDBusConnection::sessionBus();
    m_service = QStringLiteral("org.mpris.MediaPlayer2.glide_video.instance%1").arg(::getpid());
    bus.registerObject(kPath, this, QDBusConnection::ExportAdaptors);
    bus.registerService(m_service);
}

Mpris::~Mpris()
{
    QDBusConnection::sessionBus().unregisterService(m_service);
}

QDBusObjectPath Mpris::trackId() const
{
    return QDBusObjectPath(QStringLiteral("/org/glide/video/track/%1").arg(m_track));
}

QVariantMap Mpris::metadata() const
{
    QVariantMap m{{"mpris:trackid", QVariant::fromValue(trackId())}, {"xesam:title", m_title}};
    if (!m_url.isEmpty())
        m["xesam:url"] = m_url;
    if (m_length > 0)
        m["mpris:length"] = qlonglong(m_length * 1000);
    return m;
}

void Mpris::setPosition(qint64 p)
{
    // большой скачок (перемотка) — сообщаем Seeked, обычный ход времени клиенты считают сами
    const qint64 expected = m_position;
    m_position = p;
    if (std::abs(p - expected) > 1500) {
        QDBusMessage sig = QDBusMessage::createSignal(kPath, kPlayer, "Seeked");
        sig << qlonglong(p * 1000);
        QDBusConnection::sessionBus().send(sig);
    }
}

void Mpris::notify(const char *property)
{
    QVariant value;
    const QString name = QString::fromLatin1(property);
    if (name == "Metadata") value = metadata();
    else if (name == "PlaybackStatus") value = m_status;
    else if (name == "CanGoNext") value = m_canNext;
    else if (name == "CanGoPrevious") value = m_canPrev;
    else if (name == "Volume") value = m_volume;
    else if (name == "Rate") value = m_rate;
    QDBusMessage sig = QDBusMessage::createSignal(kPath, "org.freedesktop.DBus.Properties", "PropertiesChanged");
    sig << QString::fromLatin1(kPlayer) << QVariantMap{{name, value}} << QStringList();
    QDBusConnection::sessionBus().send(sig);
}

#include "mpris.moc"
