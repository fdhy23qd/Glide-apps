#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/qqmlextensionplugin.h>

#include "glidetr.h"
#include "testhook.h"

Q_IMPORT_QML_PLUGIN(Glide_UiPlugin)

// glide-disk          — диски и домашняя папка: выбрать, что проверить
// glide-disk папка    — сразу проверить эту папку
int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("glide-disk");
    app.setApplicationDisplayName(glideTr("Диск"));
    app.setOrganizationName("Glide");
    app.setDesktopFileName("glide-disk");

    QString start;
    for (const QString &a : app.arguments().mid(1))
        if (!a.startsWith('-')) start = a;

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{"startPath", start}});
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("GlideDisk", "Main");
    Glide::runTestScript(engine);
    return app.exec();
}
