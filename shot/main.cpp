#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/qqmlextensionplugin.h>

#include "testhook.h"

Q_IMPORT_QML_PLUGIN(Glide_UiPlugin)

// glide-shot                      — пустое окно: выбрать, что снять
// glide-shot --capture region     — сразу снять (region | window | screen) и открыть в редакторе
// glide-shot файл.png             — разметить готовую картинку
int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("glide-shot");
    app.setApplicationDisplayName("Скриншоты");
    app.setOrganizationName("Glide");
    app.setDesktopFileName("glide-shot");

    QString start, capture;
    const QStringList args = app.arguments().mid(1);
    for (int i = 0; i < args.size(); ++i) {
        if (args[i] == "--capture")
            capture = i + 1 < args.size() ? args[++i] : QStringLiteral("region");
        else if (args[i].startsWith("--capture="))
            capture = args[i].mid(10);
        else if (!args[i].startsWith('-'))
            start = args[i];
    }

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{"startPath", start}, {"startCapture", capture}});
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("GlideShot", "Main");
    Glide::runTestScript(engine);
    return app.exec();
}
