#pragma once

#include <QJsonObject>
#include <QObject>
#include <QVariantList>
#include <QStringList>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

// Видео и аудио папки (естественная сортировка, как в файловом менеджере), текущий файл и
// запомненные позиции: «продолжить с места, где остановились» (~/.local/state/glide-apps/video-resume.json).
class Playlist : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ count NOTIFY listChanged)
    Q_PROPERTY(int index READ index WRITE setIndex NOTIFY currentChanged)
    Q_PROPERTY(QString path READ path NOTIFY currentChanged)
    Q_PROPERTY(QString url READ url NOTIFY currentChanged)
    Q_PROPERTY(QString name READ name NOTIFY currentChanged)
    Q_PROPERTY(QString folder READ folder NOTIFY listChanged)

public:
    explicit Playlist(QObject *parent = nullptr);
    ~Playlist() override;

    int count() const { return int(m_files.size()); }
    int index() const { return m_index; }
    void setIndex(int i);
    QString path() const;
    QString url() const;
    QString name() const;
    QString folder() const { return m_folder; }

    Q_INVOKABLE bool open(const QString &pathOrUrl);
    Q_INVOKABLE void next() { setIndex(m_index + 1); }
    Q_INVOKABLE void prev() { setIndex(m_index - 1); }

    // позиция для продолжения (мс; 0 — с начала): только если остановились не в самом начале/конце
    Q_INVOKABLE qint64 resumePosition(const QString &path) const;
    Q_INVOKABLE void savePosition(const QString &path, qint64 positionMs, qint64 durationMs);
    Q_INVOKABLE void showInFolder(const QString &path) const;

    // внешние субтитры рядом с видео: «имя*.srt|vtt» → [{file, label}]; разбор → [{s, e, t}] (мс, текст)
    Q_INVOKABLE QVariantList subtitleFiles(const QString &path) const;
    Q_INVOKABLE QVariantList loadSubtitles(const QString &file) const;

    static bool isMedia(const QString &name);

signals:
    void listChanged();
    void currentChanged();
    void error(const QString &message);

private:
    void flush();

    QString m_folder;
    QStringList m_files;
    int m_index = -1;
    QJsonObject m_resume;
    QString m_resumeFile;
    QTimer m_saveTimer;
};
