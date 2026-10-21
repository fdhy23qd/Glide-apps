#include "glidesettings.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

GlideSettings::GlideSettings(QObject *parent) : QObject(parent)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/glide-shell";
    m_path = dir + "/config.json";
    load();
    // qp-config.py пишет через временный файл и rename — следим за папкой, а не за самим файлом
    if (QDir(dir).exists())
        m_watcher.addPath(dir);
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(150);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_debounce, qOverload<>(&QTimer::start));
    connect(&m_debounce, &QTimer::timeout, this, &GlideSettings::load);
}

void GlideSettings::load()
{
    QFile f(m_path);
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject panel = QJsonDocument::fromJson(f.readAll()).object().value("panel").toObject();

    const QColor accent(panel.value("accent").toString());
    const QString tone = panel.value("themeTone").toString();
    const qreal radius = panel.value("themeRadius").toDouble(1);
    const qreal font = panel.value("themeFont").toDouble(1);

    const QColor newAccent = accent.isValid() ? accent : QColor(0x7b, 0x61, 0xff);
    const QString newTone = tone.isEmpty() ? QStringLiteral("glide") : tone;
    const qreal newRadius = radius > 0 ? radius : 1;
    const qreal newFont = font > 0 ? font : 1;
    if (newAccent == m_accent && newTone == m_tone && newRadius == m_radius && newFont == m_font)
        return;
    m_accent = newAccent;
    m_tone = newTone;
    m_radius = newRadius;
    m_font = newFont;
    emit changed();
}
