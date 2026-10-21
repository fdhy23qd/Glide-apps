#pragma once

#include <QImage>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QSize>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Скриншот и его разметка. Снимает сам niri (родной выбор области/окна): action screenshot… --path,
// готовность — событие ScreenshotCaptured в `niri msg --json event-stream`. Итог рисует QPainter по
// тому же списку фигур, что показывает QML, — превью и файл совпадают.
//
// Фигура (QVariantMap): type — arrow | line | rect | ellipse | pen | marker | text | step | pixel;
// color, width (пиксели картинки); x1 y1 x2 y2; points — [x, y, x, y…] для pen/marker; text, size; n — номер шага.
class Shot : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString path READ path NOTIFY loaded)
    Q_PROPERTY(QUrl url READ url NOTIFY loaded)
    Q_PROPERTY(QSize size READ size NOTIFY loaded)
    Q_PROPERTY(bool ready READ ready NOTIFY loaded)
    Q_PROPERTY(bool capturing READ capturing NOTIFY capturingChanged)
    Q_PROPERTY(bool fresh READ fresh NOTIFY loaded)            // снимок сделан нами (Сохранить — поверх него)
    Q_PROPERTY(QUrl pixelUrl READ pixelUrl NOTIFY pixelChanged) // вся картинка «размытая» (пикселями)
    Q_PROPERTY(QString folder READ folder CONSTANT)            // куда niri кладёт скриншоты

public:
    explicit Shot(QObject *parent = nullptr);
    ~Shot() override;

    QString path() const { return m_path; }
    QUrl url() const;
    QSize size() const { return m_image.size(); }
    bool ready() const { return !m_image.isNull(); }
    bool capturing() const { return m_events != nullptr; }
    bool fresh() const { return m_fresh; }
    QUrl pixelUrl() const { return m_pixelFile.isEmpty() ? QUrl() : QUrl::fromLocalFile(m_pixelFile); }
    QString folder() const { return m_folder; }

    Q_INVOKABLE void capture(const QString &mode);   // region | screen | window
    Q_INVOKABLE bool load(const QString &pathOrUrl);
    Q_INVOKABLE void preparePixels();                  // для инструмента «размыть» — по требованию
    Q_INVOKABLE QString savePath() const;               // куда «Сохранить»
    Q_INVOKABLE bool save(const QVariantList &items, const QVariantMap &crop, const QString &target);
    Q_INVOKABLE bool copy(const QVariantList &items, const QVariantMap &crop);
    Q_INVOKABLE QString localPath(const QString &url) const;
    Q_INVOKABLE void showInFolder(const QString &file) const;

    QImage render(const QVariantList &items, const QVariantMap &crop) const;
    static int pixelBlock(QSize s) { return std::max(8, std::max(s.width(), s.height()) / 120); }

signals:
    void loaded();
    void capturingChanged();
    void pixelChanged();
    void failed(const QString &message);
    void captureGaveUp();   // долго нет снимка (в niri нажали Esc) — окно так и не показали

private:
    void stopEvents();

    QString m_path;
    QImage m_image;
    QImage m_pixels;
    QString m_pixelFile;
    QString m_folder;
    QString m_target;
    bool m_fresh = false;
    QPointer<QProcess> m_events;
    QTimer m_giveUp;
};
