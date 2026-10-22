#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Настройки из Glide Shell (~/.config/glide-shell/config.json, раздел "panel"): акцент, тон, масштаб скруглений
// и шрифта, светлая/тёмная тема, язык. Меняются в настройках оболочки — приложения подхватывают сразу.
class GlideSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QColor accent READ accent NOTIFY changed)
    Q_PROPERTY(QString tone READ tone NOTIFY changed)
    Q_PROPERTY(qreal radius READ radius NOTIFY changed)
    Q_PROPERTY(qreal font READ font NOTIFY changed)
    Q_PROPERTY(bool light READ light NOTIFY changed)
    Q_PROPERTY(QString lang READ lang NOTIFY changed)
    Q_PROPERTY(QVariantMap dict READ dict NOTIFY changed)

public:
    explicit GlideSettings(QObject *parent = nullptr);

    QColor accent() const { return m_accent; }
    QString tone() const { return m_tone; }
    qreal radius() const { return m_radius; }
    qreal font() const { return m_font; }
    bool light() const { return m_light; }
    QString lang() const { return m_lang; }
    QVariantMap dict() const { return m_dict; }

signals:
    void changed();

private:
    void load();

    QString m_path;
    QColor m_accent{0x7b, 0x61, 0xff};
    QString m_tone{QStringLiteral("glide")};
    qreal m_radius = 1;
    qreal m_font = 1;
    bool m_light = false;
    QString m_lang;   // пусто до первой загрузки — словарь грузится при первом load()
    QVariantMap m_dict;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QTimer m_dayTimer;
};
