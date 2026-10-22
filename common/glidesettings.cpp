#include "glidesettings.h"
#include "glidetr.h"

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonObject>
#include <QStyleHints>
#include <QTime>

GlideSettings::GlideSettings(QObject *parent) : QObject(parent)
{
    m_path = glideConfigPath();
    const QString dir = QFileInfo(m_path).path();
    load();
    // qp-config.py пишет через временный файл и rename — следим за папкой, а не за самим файлом
    if (QDir(dir).exists())
        m_watcher.addPath(dir);
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(150);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_debounce, qOverload<>(&QTimer::start));
    connect(&m_debounce, &QTimer::timeout, this, &GlideSettings::load);
    // тема «авто»: системная схема (её ставит оболочка при «Тема и акцент — приложениям»), без неё — по часам
    connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, this, &GlideSettings::load);
    m_dayTimer.setInterval(60000);
    connect(&m_dayTimer, &QTimer::timeout, this, &GlideSettings::load);
    m_dayTimer.start();
}

void GlideSettings::load()
{
    const QJsonObject panel = glidePanel();

    const QColor accent(panel.value("accent").toString());
    const QString tone = panel.value("themeTone").toString();
    const qreal radius = panel.value("themeRadius").toDouble(1);
    const qreal font = panel.value("themeFont").toDouble(1);
    const QString mode = qEnvironmentVariable("GLIDE_THEME", panel.value("themeMode").toString());

    const QColor newAccent = accent.isValid() ? accent : QColor(0x7b, 0x61, 0xff);
    const QString newTone = tone.isEmpty() ? QStringLiteral("glide") : tone;
    const qreal newRadius = radius > 0 ? radius : 1;
    const qreal newFont = font > 0 ? font : 1;
    bool newLight = mode == "light";
    if (mode == "auto") {
        const auto scheme = QGuiApplication::styleHints()->colorScheme();
        if (scheme != Qt::ColorScheme::Unknown) {
            newLight = scheme == Qt::ColorScheme::Light;
        } else {
            const int h = QTime::currentTime().hour();
            newLight = h >= 7 && h < 21;
        }
    }
    const QString newLang = glideLang(panel);
    const bool langChanged = newLang != m_lang;
    if (newAccent == m_accent && newTone == m_tone && newRadius == m_radius && newFont == m_font
        && newLight == m_light && !langChanged)
        return;
    if (langChanged)
        m_dict = glideDict(newLang);
    m_accent = newAccent;
    m_tone = newTone;
    m_radius = newRadius;
    m_font = newFont;
    m_light = newLight;
    m_lang = newLang;
    emit changed();
}
