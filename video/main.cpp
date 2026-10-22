#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/qqmlextensionplugin.h>

#include "testhook.h"
#include "glidetr.h"

Q_IMPORT_QML_PLUGIN(Glide_UiPlugin)

int main(int argc, char *argv[])
{
    // Qt Multimedia при первом плеере перебирает все аппаратные декодеры (vdpau, cuda, vaapi, qsv, vulkan) —
    // ~1,2 с, и выбирает CUDA: будит дискретную NVIDIA. Только VA-API встроенной графики Intel
    // (без драйвера — отказ за миллисекунды, декодирует процессор).
    if (qEnvironmentVariableIsEmpty("QT_FFMPEG_DECODING_HW_DEVICE_TYPES"))
        qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "vaapi");
    if (qEnvironmentVariableIsEmpty("QT_FFMPEG_ENCODING_HW_DEVICE_TYPES"))   // кодирует ffmpeg, не Qt
        qputenv("QT_FFMPEG_ENCODING_HW_DEVICE_TYPES", "vaapi");

    QGuiApplication app(argc, argv);
    app.setApplicationName("glide-video");
    app.setApplicationDisplayName(glideTr("Видео"));
    app.setOrganizationName("Glide");
    app.setDesktopFileName("glide-video");   // app_id окна — док и niri находят значок

    QString start;
    const QStringList args = app.arguments().mid(1);
    for (const QString &a : args)
        if (!a.startsWith('-')) { start = a; break; }

    QQmlApplicationEngine engine;
    engine.setInitialProperties({{"startPath", start}});
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("GlideVideo", "Main");
    Glide::runTestScript(engine);   // только с GLIDE_TEST — проверка интерфейса
    return app.exec();
}
