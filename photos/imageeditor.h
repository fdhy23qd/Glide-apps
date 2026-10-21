#pragma once

#include <QDateTime>
#include <QImage>
#include <QMutex>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>
#include <atomic>

// Правка фото: поворот → отражение → обрезка → размер → кодирование (JPEG, PNG, WebP, BMP, TIFF — Qt;
// AVIF, JPEG XL — ffmpeg). Работает в фоновом потоке; исходник декодируется один раз и кэшируется.
//
// Параметры (QVariantMap): path, rotate (0/90/180/270), flipH, flipV, crop {x,y,w,h} — доли 0…1 в уже
// повёрнутом и отражённом изображении (пусто — без обрезки), longSide (0 — исходный), format (same | jpg |
// png | webp | avif | jxl | bmp | tiff), quality (1…100), mode (copy | replace).
class ImageEditor : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(qint64 estimate READ estimate NOTIFY estimated)   // байт, -1 — неизвестно
    Q_PROPERTY(QSize outputSize READ outputSize NOTIFY estimated)

public:
    explicit ImageEditor(QObject *parent = nullptr);
    ~ImageEditor() override;

    bool busy() const { return m_saving; }
    qint64 estimate() const { return m_estimate; }
    QSize outputSize() const { return m_outSize; }

    Q_INVOKABLE void requestEstimate(const QVariantMap &opts);   // последняя заявка вытесняет прежние
    Q_INVOKABLE void save(const QVariantMap &opts);
    Q_INVOKABLE QString outputExt(const QVariantMap &opts) const;
    Q_INVOKABLE void forget();   // выйти из правки — отпустить кэш исходника

    static bool writable(const QString &ext);

signals:
    void busyChanged();
    void estimated();
    // replaced: оригинал ушёл в корзину (inTrash) и на его месте — новый файл
    void saved(const QString &file, const QString &original, const QString &inTrash);
    void failed(const QString &error);

private:
    QImage base(const QString &path, QString *err);   // повёрнутый по EXIF исходник, из кэша
    void runEstimate(QVariantMap opts, int ticket);

    QMutex m_cacheLock;
    QString m_cachePath;
    QDateTime m_cacheTime;
    QImage m_cache;

    std::atomic<int> m_ticket{0};
    std::atomic<bool> m_estimating{false};
    QVariantMap m_pending;
    bool m_hasPending = false;
    QMutex m_pendingLock;

    bool m_saving = false;
    qint64 m_estimate = -1;
    QSize m_outSize;
};
