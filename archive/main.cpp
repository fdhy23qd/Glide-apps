#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/qqmlextensionplugin.h>

#include "archiver.h"
#include "glidetr.h"
#include "testhook.h"

Q_IMPORT_QML_PLUGIN(Glide_UiPlugin)

// glide-archive                        — пустое окно: открыть архив или перетащить файлы
// glide-archive архив.zip              — показать содержимое
// glide-archive --extract-here архив   — распаковать рядом и закрыться (окно — только с прогрессом)
// glide-archive --create файлы…        — упаковать: сразу окно создания архива
int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("glide-archive");
    app.setApplicationDisplayName(glideTr("Архивы"));
    app.setOrganizationName("Glide");
    app.setDesktopFileName("glide-archive");

    QString mode;
    QStringList files;
    for (const QString &a : app.arguments().mid(1)) {
        if (a == "--extract-here" || a == "--create")
            mode = a.mid(2);
        else if (!a.startsWith('-'))
            files << a;
    }
    Archive::cleanOpened();

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{"startFiles", files}, {"startMode", mode}});
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("GlideArchive", "Main");
    Glide::runTestScript(engine);
    return app.exec();
}
