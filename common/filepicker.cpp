#include "filepicker.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QRandomGenerator>

namespace {

// фильтры портала: a(sa(us)) — [(«Изображения», [(0, "*.jpg"), …])]; 0 — шаблон, 1 — MIME
struct Pattern { uint kind; QString value; };
struct Filter { QString name; QList<Pattern> patterns; };

QDBusArgument &operator<<(QDBusArgument &a, const Pattern &p)
{
    a.beginStructure(); a << p.kind << p.value; a.endStructure(); return a;
}
const QDBusArgument &operator>>(const QDBusArgument &a, Pattern &p)
{
    a.beginStructure(); a >> p.kind >> p.value; a.endStructure(); return a;
}
QDBusArgument &operator<<(QDBusArgument &a, const Filter &f)
{
    a.beginStructure(); a << f.name << f.patterns; a.endStructure(); return a;
}
const QDBusArgument &operator>>(const QDBusArgument &a, Filter &f)
{
    a.beginStructure(); a >> f.name >> f.patterns; a.endStructure(); return a;
}

} // namespace

Q_DECLARE_METATYPE(Pattern)
Q_DECLARE_METATYPE(Filter)

namespace {
void registerTypes()
{
    static const bool once = [] {
        qDBusRegisterMetaType<Pattern>();
        qDBusRegisterMetaType<QList<Pattern>>();
        qDBusRegisterMetaType<Filter>();
        qDBusRegisterMetaType<QList<Filter>>();
        return true;
    }();
    Q_UNUSED(once);
}
} // namespace

FilePicker::FilePicker(QObject *parent) : QObject(parent) {}

void FilePicker::open(const QString &title, const QString &filterName, const QStringList &patterns, const QString &folder,
                      bool multiple)
{
    QVariantMap options{{"modal", true}, {"multiple", multiple}};
    if (!patterns.isEmpty()) {
        registerTypes();
        Filter f{filterName, {}};
        for (const QString &p : patterns)
            f.patterns.append({0, p});
        options.insert("filters", QVariant::fromValue(QList<Filter>{f}));
        options.insert("current_filter", QVariant::fromValue(f));
    }
    if (!folder.isEmpty())
        options.insert("current_folder", QByteArray(folder.toUtf8() + '\0'));
    request("OpenFile", title, options);
}

void FilePicker::openFolder(const QString &title, const QString &folder)
{
    QVariantMap options{{"modal", true}, {"directory", true}};
    if (!folder.isEmpty())
        options.insert("current_folder", QByteArray(folder.toUtf8() + '\0'));
    request("OpenFile", title, options);
}

void FilePicker::save(const QString &title, const QString &currentName, const QString &folder)
{
    QVariantMap options{{"modal", true}, {"current_name", currentName}};
    if (!folder.isEmpty())
        options.insert("current_folder", QByteArray(folder.toUtf8() + '\0'));
    request("SaveFile", title, options);
}

void FilePicker::request(const char *method, const QString &title, QVariantMap options)
{
    if (busy())
        return;
    QDBusConnection bus = QDBusConnection::sessionBus();
    const QString token = QStringLiteral("glide%1").arg(QRandomGenerator::global()->generate());
    QString sender = bus.baseService().mid(1);
    sender.replace('.', '_');
    m_request = QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2").arg(sender, token);
    // подписываемся на ответ заранее: портал может ответить раньше, чем вернётся вызов
    bus.connect("org.freedesktop.portal.Desktop", m_request, "org.freedesktop.portal.Request", "Response",
                this, SLOT(onResponse(uint, QVariantMap)));
    emit busyChanged();
    options.insert("handle_token", token);
    QDBusMessage msg = QDBusMessage::createMethodCall("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                                                      "org.freedesktop.portal.FileChooser", QString::fromLatin1(method));
    msg << QString() << title << options;
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (w->isError()) {   // портала нет
            qWarning("glide: портал выбора файлов недоступен: %s", qPrintable(w->error().message()));
            onResponse(2, {});
        }
    });
}

void FilePicker::onResponse(uint response, const QVariantMap &results)
{
    if (m_request.isEmpty())
        return;
    QDBusConnection::sessionBus().disconnect("org.freedesktop.portal.Desktop", m_request,
                                             "org.freedesktop.portal.Request", "Response",
                                             this, SLOT(onResponse(uint, QVariantMap)));
    m_request.clear();
    emit busyChanged();
    if (response == 0)   // 0 — выбрали, 1 — отмена, 2 — ошибка
        emit picked(results.value("uris").toStringList());
}
