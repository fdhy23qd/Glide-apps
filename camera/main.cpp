#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/qqmlextensionplugin.h>

#include "glidetr.h"
#include "testhook.h"

Q_IMPORT_QML_PLUGIN(Glide_UiPlugin)

// glide-camera — фото и видео с веб-камеры
int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("glide-camera");
    app.setApplicationDisplayName(glideTr("Камера"));
    app.setOrganizationName("Glide");
    app.setDesktopFileName("glide-camera");

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("GlideCamera", "Main");
    Glide::runTestScript(engine);
    return app.exec();
}
