#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Простой редактор на FFmpeg: сведения о файле (ffprobe), экспорт фрагмента/в другой формат/размер/
// качество (ffmpeg с прогрессом), кадр в PNG. Без перекодирования (копия потоков), когда это возможно.
//
// Параметры экспорта (QVariantMap): input, start и end (мс, 0 — без обрезки), format (same | mp4 | mkv |
// webm | gif | webp | mp3 | m4a | opus | flac | wav), quality (copy | high | medium | small), height (0 —
// исходный; это короткая сторона: «720p» и для вертикального видео), mute, rotate (0/90/180/270).
class Converter : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantMap info READ info NOTIFY infoChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(qreal speed READ speed NOTIFY progressChanged)
    Q_PROPERTY(int eta READ eta NOTIFY progressChanged)
    Q_PROPERTY(QString output READ output NOTIFY runningChanged)
    Q_PROPERTY(QString hardware READ hardware NOTIFY hardwareChanged)

public:
    explicit Converter(QObject *parent = nullptr);
    ~Converter() override;

    QVariantMap info() const { return m_info; }
    bool running() const { return m_proc != nullptr; }
    qreal progress() const { return m_progress; }
    qreal speed() const { return m_speed; }
    int eta() const { return m_eta; }
    QString output() const { return m_output; }
    QString hardware() const { return m_hardware; }

    Q_INVOKABLE void probe(const QString &path);
    Q_INVOKABLE bool canCopy(const QVariantMap &opts) const;
    Q_INVOKABLE QString outputName(const QVariantMap &opts) const;   // имя файла, который получится
    Q_INVOKABLE void start(const QVariantMap &opts);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void snapshot(const QString &path, qint64 ms);
    Q_INVOKABLE void detectHardware();   // один раз: пробное кодирование VA-API (~0,2 с)

    static QStringList buildArgs(const QVariantMap &opts, const QVariantMap &info, bool hw, const QString &out);

signals:
    void infoChanged();
    void runningChanged();
    void progressChanged();
    void hardwareChanged();
    void finished(bool ok, const QString &output, const QString &error);
    void snapshotSaved(const QString &file);
    void failed(const QString &error);

private:
    QString outputPath(const QVariantMap &opts) const;
    void launch(bool hw);
    void onProgressOutput();
    void onFinished(int code, QProcess::ExitStatus status);
    static void prepareChild(QProcess *p);

    QVariantMap m_info;
    QString m_probing;
    QPointer<QProcess> m_proc;
    QVariantMap m_opts;
    QString m_output;
    QString m_stderr;
    bool m_hwRun = false;
    bool m_cancelled = false;
    qreal m_progress = 0;
    qreal m_speed = 0;
    int m_eta = -1;
    qint64 m_segmentUs = 0;
    QElapsedTimer m_clock;
    QString m_hardware;
    bool m_hwChecked = false;
};
