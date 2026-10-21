#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include <atomic>
#include <functional>

class QThread;

// Архивы через libarchive: чтение zip, 7z, rar (в т.ч. RAR5), tar.* (gz, xz, zst, bz2, lz4), iso и др.;
// создание zip (с паролем AES-256), 7z, tar.zst, tar.xz, tar.gz. Вся работа — в фоновом потоке.
// Распаковка безопасна: пути с «..», абсолютные и через ссылки за пределы папки отбрасываются.
class Archive : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString path READ path NOTIFY opened)
    Q_PROPERTY(QString format READ format NOTIFY opened)
    Q_PROPERTY(QVariantList entries READ entries NOTIFY opened)   // [{path, size, dir, mtime}]
    Q_PROPERTY(qint64 totalSize READ totalSize NOTIFY opened)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(bool needsPassword READ needsPassword NOTIFY opened)
    Q_PROPERTY(bool encrypted READ encrypted NOTIFY opened)

public:
    explicit Archive(QObject *parent = nullptr);
    ~Archive() override;

    QString path() const { return m_path; }
    QString format() const { return m_format; }
    QVariantList entries() const { return m_entries; }
    qint64 totalSize() const { return m_total; }
    bool busy() const { return m_busy; }
    qreal progress() const { return m_progress; }
    bool needsPassword() const { return m_needsPassword; }
    bool encrypted() const { return m_encrypted; }

    Q_INVOKABLE void open(const QString &pathOrUrl, const QString &password = QString());
    // paths — что распаковать (пусто — всё; папка — со всем содержимым); dest — куда
    Q_INVOKABLE void extract(const QStringList &paths, const QString &dest);
    // открыть файл из архива программой по умолчанию: распаковать во временную папку → entryReady(файл)
    Q_INVOKABLE void openEntry(const QString &path);
    Q_INVOKABLE QString defaultDestination() const;   // рядом с архивом, папка по его имени
    // format: zip | 7z | tar.zst | tar.xz | tar.gz
    Q_INVOKABLE void create(const QStringList &sources, const QString &out, const QString &format,
                            const QString &password = QString());
    Q_INVOKABLE QString suggestName(const QStringList &sources, const QString &format) const;
    Q_INVOKABLE void setPassword(const QString &password);
    Q_INVOKABLE void cancel() { m_cancel = true; }
    Q_INVOKABLE QString localPath(const QString &url) const;
    Q_INVOKABLE bool isArchive(const QString &pathOrUrl) const;
    Q_INVOKABLE void showInFolder(const QString &file) const;
    // для окна создания: {count, files, dirs, size, folder, names[]} — что пакуем
    Q_INVOKABLE QVariantMap sourcesInfo(const QStringList &sources) const;
    Q_INVOKABLE QString homePath(const QString &path) const;   // /home/u/x → ~/x

    static void cleanOpened();

    // синхронные версии — для самотеста
    struct Listing {
        QVariantList entries;
        QString format, charset;      // charset — кодировка имён (CP866 у старых zip из Windows)
        qint64 total = 0;
        bool encrypted = false;       // есть зашифрованные записи
    };
    // ошибка — непустая строка; "password" — нужен пароль, "wrong-password" — не подошёл
    static QString listSync(const QString &path, const QString &password, Listing *out);
    // возвращает ошибку; *written — что получилось в dest (одна запись — её путь, иначе сама dest);
    // *skipped — небезопасные записи, которые не распакованы («..», через ссылку наружу)
    static QString extractSync(const QString &path, const QString &password, const QString &charset,
                               const QStringList &paths, const QString &dest, QString *written = nullptr,
                               QStringList *skipped = nullptr,
                               std::atomic<bool> *cancel = nullptr, std::function<void(qreal)> progress = {});
    static QString createSync(const QStringList &sources, const QString &out, const QString &format,
                              const QString &password, std::atomic<bool> *cancel = nullptr,
                              std::function<void(qreal)> progress = {});

signals:
    void opened();
    void busyChanged();
    void progressChanged();
    void failed(const QString &message);
    // wrong — пароль не подошёл; forExtract — спросили при распаковке (повторить её после ввода)
    void passwordRequired(bool wrong, bool forExtract);
    void extracted(const QString &dest, int skipped);
    void created(const QString &file);
    void entryReady(const QString &file);

private:
    void setBusy(bool b);
    void run(std::function<void()> job);
    void setProgress(qreal p);
    void done();
    QThread *m_thread = nullptr;

    QString m_path, m_format, m_password, m_charset;
    QVariantList m_entries;
    qint64 m_total = 0;
    bool m_busy = false;
    bool m_needsPassword = false;
    bool m_encrypted = false;
    qreal m_progress = 0;
    std::atomic<bool> m_cancel{false};
};
