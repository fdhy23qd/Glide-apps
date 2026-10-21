#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

// Настройки темы из Glide Shell (~/.config/glide-shell/config.json, раздел "panel"): акцент, тон,
// масштаб скруглений и шрифта. Меняются в настройках оболочки — приложения подхватывают сразу.
class GlideSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QColor accent READ accent NOTIFY changed)
    Q_PROPERTY(QString tone READ tone NOTIFY changed)
    Q_PROPERTY(qreal radius READ radius NOTIFY changed)
    Q_PROPERTY(qreal font READ font NOTIFY changed)

public:
    explicit GlideSettings(QObject *parent = nullptr);

    QColor accent() const { return m_accent; }
    QString tone() const { return m_tone; }
    qreal radius() const { return m_radius; }
    qreal font() const { return m_font; }

signals:
    void changed();

private:
    void load();

    QString m_path;
    QColor m_accent{0x7b, 0x61, 0xff};
    QString m_tone{QStringLiteral("glide")};
    qreal m_radius = 1;
    qreal m_font = 1;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};
