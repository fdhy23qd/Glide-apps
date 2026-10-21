#pragma once

// Сценарий проверки интерфейса без мыши и клавиатуры: GLIDE_TEST="мс команда; мс команда; …"
//   300 key:Right      300 key:Ctrl+C      500 move:400,300     600 click:400,300   650 dclick:400,300
//   700 press:x,y  750 drag:x,y  800 release:x,y   (перетаскивание левой кнопкой)
//   700 wheel:400,300,120   (120 — щелчок колеса вверх; tpad:x,y,dx,dy — прокрутка тачпадом)
//   900 shot:/путь/кадр.png     1200 quit
// События идут через QPA (как от настоящего устройства: Shortcut и обработчики видят их обычно).
// Без переменной окружения ничего не делает. Удобно с QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software.

#include <QGuiApplication>
#include <QKeySequence>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QWheelEvent>
#include <qpa/qwindowsysteminterface.h>

namespace Glide {

inline void runTestScript(QQmlApplicationEngine &engine)
{
    const QString script = qEnvironmentVariable("GLIDE_TEST");
    if (script.isEmpty())
        return;
    if (qEnvironmentVariableIsSet("GLIDE_TEST_LOG")) {   // что из событий доходит до окна
        struct Log : QObject {
            bool eventFilter(QObject *o, QEvent *e) override {
                if (e->type() == QEvent::Wheel) {
                    auto *we = static_cast<QWheelEvent *>(e);
                    qWarning() << "wheel →" << o << we->phase() << we->pixelDelta() << we->angleDelta() << we->isAccepted();
                }
                return false;
            }
        };
        qApp->installEventFilter(new Log);
    }
    auto window = [&engine]() -> QQuickWindow * {
        const auto roots = engine.rootObjects();
        return roots.isEmpty() ? nullptr : qobject_cast<QQuickWindow *>(roots.first());
    };
    for (const QString &step : script.split(';', Qt::SkipEmptyParts)) {
        const QString s = step.trimmed();
        const int sp = s.indexOf(' ');
        const int ms = s.left(sp).toInt();
        const QString cmd = s.mid(sp + 1).trimmed();
        QTimer::singleShot(ms, &engine, [window, cmd] {
            QQuickWindow *w = window();
            if (!w)
                return;
            const QString name = cmd.section(':', 0, 0);
            const QString arg = cmd.section(':', 1);
            const QStringList n = arg.split(',');
            auto pt = [&n](int i) { return QPointF(n.value(i).toDouble(), n.value(i + 1).toDouble()); };
            using WSI = QWindowSystemInterface;
            if (name == "key") {
                const QKeyCombination k = QKeySequence::fromString(arg)[0];
                const QString text = k.keyboardModifiers() & ~Qt::ShiftModifier ? QString()
                                   : arg.size() == 1 ? arg : QString();
                WSI::handleKeyEvent<WSI::SynchronousDelivery>(w, QEvent::KeyPress, k.key(), k.keyboardModifiers(), text);
                WSI::handleKeyEvent<WSI::SynchronousDelivery>(w, QEvent::KeyRelease, k.key(), k.keyboardModifiers(), text);
            } else if (name == "move") {
                WSI::handleMouseEvent<WSI::SynchronousDelivery>(w, pt(0), w->mapToGlobal(pt(0)), Qt::NoButton, Qt::NoButton, QEvent::MouseMove);
            } else if (name == "click" || name == "dclick") {
                for (int i = 0; i < (name == "dclick" ? 2 : 1); ++i) {
                    WSI::handleMouseEvent<WSI::SynchronousDelivery>(w, pt(0), w->mapToGlobal(pt(0)), Qt::LeftButton, Qt::LeftButton, QEvent::MouseButtonPress);
                    WSI::handleMouseEvent<WSI::SynchronousDelivery>(w, pt(0), w->mapToGlobal(pt(0)), Qt::NoButton, Qt::LeftButton, QEvent::MouseButtonRelease);
                }
            } else if (name == "press" || name == "drag" || name == "release") {   // перетаскивание левой кнопкой
                const QEvent::Type t = name == "press" ? QEvent::MouseButtonPress : name == "drag" ? QEvent::MouseMove : QEvent::MouseButtonRelease;
                const Qt::MouseButtons state = name == "release" ? Qt::NoButton : Qt::LeftButton;
                WSI::handleMouseEvent<WSI::SynchronousDelivery>(w, pt(0), w->mapToGlobal(pt(0)), state,
                                                                name == "drag" ? Qt::NoButton : Qt::LeftButton, t);
            } else if (name == "wheel") {
                const int d = n.value(2).toInt();
                QWheelEvent e(pt(0), w->mapToGlobal(pt(0)), QPoint(), QPoint(0, d), Qt::NoButton, Qt::NoModifier,
                              Qt::NoScrollPhase, false);
                QGuiApplication::sendEvent(w, &e);
            } else if (name == "tpad") {
                const QPoint px(n.value(2).toInt(), n.value(3).toInt());
                // тачпад: колесо — прямо в окно (очередь QPA после ScrollBegin перестаёт отдавать события из таймера)
                // QtWayland шлёт ScrollBegin уже с первым сдвигом — так и здесь
                for (Qt::ScrollPhase ph : {Qt::ScrollBegin, Qt::ScrollEnd}) {
                    const QPoint d = ph == Qt::ScrollBegin ? px : QPoint();
                    QWheelEvent e(pt(0), w->mapToGlobal(pt(0)), d, d * 2, Qt::NoButton, Qt::NoModifier, ph, false);
                    QGuiApplication::sendEvent(w, &e);
                }
            } else if (name == "shot") {
                w->grabWindow().save(arg);
            } else if (name == "quit") {
                QCoreApplication::quit();
            }
        });
    }
}

} // namespace Glide
