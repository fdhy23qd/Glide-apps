#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// MPRIS2 (org.mpris.MediaPlayer2.glide_video.instancePID): медиаклавиши (playerctl в niri), остров
// Glide Shell и любые другие пульты видят плеер. QML задаёт состояние, команды приходят сигналами.
class Mpris : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString title READ title WRITE setTitle NOTIFY metadataChanged)
    Q_PROPERTY(QString url READ url WRITE setUrl NOTIFY metadataChanged)
    Q_PROPERTY(qint64 length READ length WRITE setLength NOTIFY metadataChanged)   // мс
    Q_PROPERTY(qint64 position READ position WRITE setPosition)                    // мс, MPRIS опрашивает сам
    Q_PROPERTY(QString status READ status WRITE setStatus NOTIFY statusChanged)    // Playing | Paused | Stopped
    Q_PROPERTY(bool canNext READ canNext WRITE setCanNext NOTIFY navChanged)
    Q_PROPERTY(bool canPrevious READ canPrevious WRITE setCanPrevious NOTIFY navChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(double rate READ rate WRITE setRate NOTIFY rateChanged)

public:
    explicit Mpris(QObject *parent = nullptr);
    ~Mpris() override;

    QString title() const { return m_title; }
    void setTitle(const QString &t) { if (t != m_title) { m_title = t; ++m_track; emit metadataChanged(); notify("Metadata"); } }
    QString url() const { return m_url; }
    void setUrl(const QString &u) { if (u != m_url) { m_url = u; emit metadataChanged(); notify("Metadata"); } }
    qint64 length() const { return m_length; }
    void setLength(qint64 l) { if (l != m_length) { m_length = l; emit metadataChanged(); notify("Metadata"); } }
    qint64 position() const { return m_position; }
    void setPosition(qint64 p);
    QString status() const { return m_status; }
    void setStatus(const QString &s) { if (s != m_status) { m_status = s; emit statusChanged(); notify("PlaybackStatus"); } }
    bool canNext() const { return m_canNext; }
    void setCanNext(bool b) { if (b != m_canNext) { m_canNext = b; emit navChanged(); notify("CanGoNext"); } }
    bool canPrevious() const { return m_canPrev; }
    void setCanPrevious(bool b) { if (b != m_canPrev) { m_canPrev = b; emit navChanged(); notify("CanGoPrevious"); } }
    double volume() const { return m_volume; }
    void setVolume(double v) { if (v != m_volume) { m_volume = v; emit volumeChanged(); notify("Volume"); } }
    double rate() const { return m_rate; }
    void setRate(double r) { if (r != m_rate) { m_rate = r; emit rateChanged(); notify("Rate"); } }

    QVariantMap metadata() const;
    QDBusObjectPath trackId() const;

    // вызывается адаптером (D-Bus) — уходит в QML
    void requestVolume(double v) { emit volumeRequested(v); }

signals:
    void metadataChanged();
    void statusChanged();
    void navChanged();
    void volumeChanged();
    void rateChanged();

    void playRequested();
    void pauseRequested();
    void toggleRequested();
    void stopRequested();
    void nextRequested();
    void previousRequested();
    void seekRequested(qint64 ms);         // абсолютная позиция
    void volumeRequested(double volume);
    void rateRequested(double rate);
    void raiseRequested();
    void quitRequested();

private:
    void notify(const char *property);

    QString m_service;
    QString m_title, m_url, m_status{QStringLiteral("Stopped")};
    qint64 m_length = 0, m_position = 0;
    bool m_canNext = false, m_canPrev = false;
    double m_volume = 1, m_rate = 1;
    int m_track = 0;
};
