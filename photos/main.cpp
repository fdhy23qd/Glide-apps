#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/qqmlextensionplugin.h>

#include "testhook.h"
#include "glidetr.h"

Q_IMPORT_QML_PLUGIN(Glide_UiPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("glide-photos");
    app.setApplicationDisplayName(glideTr("Фото"));
    app.setOrganizationName("Glide");
    app.setDesktopFileName("glide-photos");   // app_id окна — док и niri находят значок

    QString start;
    const QStringList args = app.arguments().mid(1);
    for (const QString &a : args)
        if (!a.startsWith('-')) { start = a; break; }

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{"startPath", start}});
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("GlidePhotos", "Main");
    Glide::runTestScript(engine);   // только с GLIDE_TEST — проверка интерфейса
    return app.exec();
}
