#include "inhibitor.h"
#include "glidetr.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

namespace {
QDBusMessage call(const char *method)
{
    return QDBusMessage::createMethodCall("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver",
                                          "org.freedesktop.ScreenSaver", method);
}
} // namespace

void Inhibitor::setActive(bool on)
{
    m_want = on;
    if (on && m_cookie == 0) {
        QDBusMessage msg = call("Inhibit");
        msg << QStringLiteral("glide-video") << glideTr(QStringLiteral("Идёт видео"));
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
            w->deleteLater();
            QDBusPendingReply<uint> r = *w;
            if (r.isError())
                return;
            m_cookie = r.value();
            if (!m_want)   // пока ждали ответа, видео уже остановили
                setActive(false);
            else
                emit activeChanged();
        });
    } else if (!on && m_cookie != 0) {
        QDBusMessage msg = call("UnInhibit");
        msg << m_cookie;
        QDBusConnection::sessionBus().asyncCall(msg);
        m_cookie = 0;
        emit activeChanged();
    }
}

Inhibitor::~Inhibitor()
{
    if (m_cookie == 0)
        return;
    // при выходе — синхронно: асинхронный вызов не успел бы уйти до закрытия соединения
    QDBusMessage msg = call("UnInhibit");
    msg << m_cookie;
    QDBusConnection::sessionBus().call(msg, QDBus::Block, 300);
}
