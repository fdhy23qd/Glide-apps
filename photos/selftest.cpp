// Самотест правки фото: build/photos/glide-photos-selftest ПУСТАЯ_ПАПКА
// Картинка 400×200: левая половина красная, правая синяя, зелёная метка 40×40 в левом верхнем углу —
// по цветам пикселей результата видно, верно ли повёрнуто, отражено и обрезано (и в каком порядке).
#include "gallery.h"
#include "imageeditor.h"

#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QImageReader>
#include <QPainter>
#include <QProcess>
#include <QTimer>
#include <cstdio>

static int failed = 0;
static void report(const char *name, const QString &problem)
{
    std::printf("%-44s %s  %s\n", name, problem.isEmpty() ? "OK  " : "FAIL", qPrintable(problem));
    if (!problem.isEmpty()) ++failed;
}

static QString colorAt(const QImage &img, double fx, double fy)
{
    const QColor c = img.pixelColor(std::min(img.width() - 1, int(fx * img.width())), std::min(img.height() - 1, int(fy * img.height())));
    if (c.alpha() < 128) return "transparent";
    if (c.red() > 200 && c.green() > 200 && c.blue() > 200) return "white";
    if (c.green() > 150 && c.red() < 100) return "green";
    if (c.red() > 150 && c.blue() < 100) return "red";
    if (c.blue() > 150 && c.red() < 100) return "blue";
    return c.name();
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    const QString dir = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QDir::tempPath() + "/glide-photos-selftest";
    QDir().mkpath(dir);

    QImage src(400, 200, QImage::Format_RGB32);
    {
        QPainter p(&src);
        p.fillRect(0, 0, 200, 200, Qt::red);
        p.fillRect(200, 0, 200, 200, Qt::blue);
        p.fillRect(0, 0, 40, 40, Qt::green);
    }
    const QString png = dir + "/test.png";
    src.save(png);

    ImageEditor ed;
    auto save = [&](QVariantMap o) -> QString {
        QEventLoop loop;
        QString out, err;
        auto c1 = QObject::connect(&ed, &ImageEditor::saved, &loop, [&](const QString &f) { out = f; loop.quit(); });
        auto c2 = QObject::connect(&ed, &ImageEditor::failed, &loop, [&](const QString &e) { err = e; loop.quit(); });
        if (!o.contains("path")) o["path"] = png;
        if (!o.contains("mode")) o["mode"] = "copy";
        if (!o.contains("quality")) o["quality"] = 90;
        if (!o.contains("format")) o["format"] = "png";
        ed.save(o);
        QTimer::singleShot(60000, &loop, &QEventLoop::quit);
        loop.exec();
        QObject::disconnect(c1); QObject::disconnect(c2);
        if (!err.isEmpty()) std::printf("   ошибка: %s\n", qPrintable(err));
        return out;
    };
    auto check = [&](const char *name, QVariantMap o, QSize want, QList<std::tuple<double, double, QString>> px) {
        const QString f = save(o);
        const QImage img(f);
        QString problem;
        if (img.isNull()) problem = "не записан";
        else if (img.size() != want) problem = QStringLiteral("размер %1×%2, ждали %3×%4").arg(img.width()).arg(img.height()).arg(want.width()).arg(want.height());
        for (auto &[x, y, c] : px)
            if (problem.isEmpty() && colorAt(img, x, y) != c)
                problem = QStringLiteral("(%1,%2) = %3, ждали %4").arg(x).arg(y).arg(colorAt(img, x, y), c);
        report(name, problem);
        QFile::remove(f);
    };

    check("без изменений → PNG", {}, {400, 200}, {{0.02, 0.05, "green"}, {0.25, 0.5, "red"}, {0.75, 0.5, "blue"}});
    check("поворот 90° вправо", {{"rotate", 90}}, {200, 400}, {{0.95, 0.02, "green"}, {0.5, 0.25, "red"}, {0.5, 0.75, "blue"}});
    check("поворот 270°", {{"rotate", 270}}, {200, 400}, {{0.02, 0.98, "green"}, {0.5, 0.75, "red"}});
    check("отражение по горизонтали", {{"flipH", true}}, {400, 200}, {{0.98, 0.05, "green"}, {0.25, 0.5, "blue"}});
    check("отражение по вертикали", {{"flipV", true}}, {400, 200}, {{0.02, 0.95, "green"}});
    check("обрезка правой половины", {{"crop", QVariantMap{{"x", 0.5}, {"y", 0}, {"w", 0.5}, {"h", 1}}}}, {200, 200}, {{0.1, 0.1, "blue"}, {0.9, 0.9, "blue"}});
    check("поворот, потом обрезка верхней половины", {{"rotate", 90}, {"crop", QVariantMap{{"x", 0}, {"y", 0}, {"w", 1}, {"h", 0.5}}}},
          {200, 200}, {{0.5, 0.5, "red"}, {0.95, 0.02, "green"}});
    check("отражение, потом обрезка левой половины", {{"flipH", true}, {"crop", QVariantMap{{"x", 0}, {"y", 0}, {"w", 0.5}, {"h", 1}}}},
          {200, 200}, {{0.5, 0.5, "blue"}});
    check("длинная сторона 100", {{"longSide", 100}}, {100, 50}, {{0.25, 0.5, "red"}});
    check("JPEG", {{"format", "jpg"}}, {400, 200}, {{0.25, 0.5, "red"}});
    check("WebP", {{"format", "webp"}}, {400, 200}, {{0.75, 0.5, "blue"}});

    // AVIF и JPEG XL — Qt их не читает (без kimageformats): проверяем ffprobe
    for (const char *fmt : {"avif", "jxl"}) {
        const QString f = save({{"format", fmt}});
        QProcess p;
        p.start("ffprobe", {"-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name,width,height", "-of", "csv=p=0", f});
        p.waitForFinished(10000);
        const QString out = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
        report(fmt == QString("avif") ? "AVIF (ffmpeg)" : "JPEG XL (ffmpeg)",
               out.endsWith("400,200") ? QString() : "ffprobe: " + out);
        QFile::remove(f);
    }

    // прозрачное → JPEG: на белом, а не на чёрном
    {
        QImage t(100, 100, QImage::Format_ARGB32);
        t.fill(Qt::transparent);
        const QString tp = dir + "/alpha.png";
        t.save(tp);
        const QString f = save({{"path", tp}, {"format", "jpg"}});
        report("прозрачный PNG → JPEG на белом", colorAt(QImage(f), 0.5, 0.5) == "white" ? QString() : colorAt(QImage(f), 0.5, 0.5));
        QFile::remove(f);
        QFile::remove(tp);
    }
    // «как есть» для GIF → PNG (Qt не пишет GIF)
    {
        const QString gp = dir + "/still.gif";
        QProcess::execute("ffmpeg", {"-v", "error", "-y", "-i", png, gp});
        const QString f = save({{"path", gp}, {"format", "same"}});
        report("GIF «как есть» → PNG", f.endsWith(".png") ? QString() : f);
        QFile::remove(f);
        QFile::remove(gp);
    }
    // имя копии не затирает существующее
    {
        const QString a = save({}), b = save({});
        report("две копии — разные имена", a != b && QFileInfo::exists(a) && QFileInfo::exists(b) ? QString() : a + " / " + b);
        QFile::remove(a);
        QFile::remove(b);
    }
    // оценка размера
    {
        QEventLoop loop;
        QObject::connect(&ed, &ImageEditor::estimated, &loop, &QEventLoop::quit);
        ed.requestEstimate({{"path", png}, {"format", "jpg"}, {"quality", 80}, {"longSide", 200}});
        QTimer::singleShot(10000, &loop, &QEventLoop::quit);
        loop.exec();
        report("оценка размера (JPEG, 200 px)", ed.estimate() > 0 && ed.outputSize() == QSize(200, 100)
               ? QString() : QStringLiteral("%1 байт, %2×%3").arg(ed.estimate()).arg(ed.outputSize().width()).arg(ed.outputSize().height()));
    }
    // заменить оригинал → отменить
    {
        const QString orig = dir + "/replace.png";
        src.save(orig);
        Gallery g;
        g.open(orig);
        QEventLoop loop;
        QString file, original, inTrash;
        auto c = QObject::connect(&ed, &ImageEditor::saved, &loop, [&](const QString &f, const QString &o, const QString &t) { file = f; original = o; inTrash = t; loop.quit(); });
        ed.save({{"path", orig}, {"mode", "replace"}, {"format", "same"}, {"quality", 90}, {"rotate", 90}});
        QTimer::singleShot(20000, &loop, &QEventLoop::quit);
        loop.exec();
        QObject::disconnect(c);
        QString problem;
        if (file != orig) problem = "новый файл не на месте оригинала: " + file;
        else if (QImage(orig).size() != QSize(200, 400)) problem = "на месте оригинала — не правленый";
        else if (!QFileInfo::exists(inTrash)) problem = "оригинала нет в корзине";
        g.recordReplace(original, inTrash, file);
        if (problem.isEmpty() && !g.undoTrash()) problem = "отмена не удалась";
        if (problem.isEmpty() && QImage(orig).size() != QSize(400, 200)) problem = "после отмены на месте не оригинал";
        if (problem.isEmpty() && QFileInfo::exists(inTrash)) problem = "оригинал остался и в корзине";
        report("заменить оригинал → Ctrl+Z", problem);
        QFile::remove(orig);
    }
    QFile::remove(png);
    std::printf("\nпровалено: %d\n", failed);
    return failed ? 1 : 0;
}
