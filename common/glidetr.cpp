#include "glidetr.h"

#include <QFile>
#include <QJsonDocument>
#include <QStandardPaths>

QString glideConfigPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/glide-shell/config.json";
}

QJsonObject glidePanel()
{
    QFile f(glideConfigPath());
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object().value("panel").toObject();
}

// Язык — как у Glide Shell: "ru" / "en" из настроек, "auto" — по $LANG (ru* — русский, иначе английский).
// GLIDE_LANG — для проверок, перекрывает всё.
QString glideLang(const QJsonObject &panel)
{
    QString l = qEnvironmentVariable("GLIDE_LANG");
    if (l.isEmpty())
        l = panel.value("lang").toString();
    if (l == "ru" || l == "en")
        return l;
    QString sys = qEnvironmentVariable("LC_ALL");
    if (sys.isEmpty()) sys = qEnvironmentVariable("LC_MESSAGES");
    if (sys.isEmpty()) sys = qEnvironmentVariable("LANG");
    if (sys.isEmpty()) sys = QStringLiteral("ru");
    return sys.startsWith("ru") ? QStringLiteral("ru") : QStringLiteral("en");
}

QVariantMap glideDict(const QString &lang)
{
    if (lang == "ru")
        return {};
    QFile f(QStringLiteral(":/glide-i18n/%1.json").arg(lang));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object().toVariantMap();
}

QString glideTr(const QString &ru)
{
    static const QVariantMap dict = glideDict(glideLang(glidePanel()));
    const auto it = dict.constFind(ru);
    return it == dict.cend() ? ru : it->toString();
}
