#pragma once

#include <QJsonObject>
#include <QString>
#include <QVariantMap>

// Перевод — общий для QML (через GlideSettings.dict и Tr.qml) и C++: ключ — русская строка, словарь —
// common/i18n/<язык>.json в ресурсах. Нет перевода — остаётся русская строка.
QString glideConfigPath();                    // ~/.config/glide-shell/config.json
QJsonObject glidePanel();                     // его раздел "panel"
QString glideLang(const QJsonObject &panel);  // "ru" | "en"
QVariantMap glideDict(const QString &lang);
QString glideTr(const QString &ru);           // язык — на момент запуска
