// Самотест отрисовки разметки: build/shot/glide-shot-selftest ПАПКА
// Серая картинка 400×300 с цветными полосами (для размытия) → каждая фигура → цвета в нужных местах.
#include "shot.h"

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QImageReader>
#include <QPainter>
#include <cstdio>

static int failed = 0;
static void report(const char *name, const QString &problem)
{
    std::printf("%-40s %s  %s\n", name, problem.isEmpty() ? "OK  " : "FAIL", qPrintable(problem));
    if (!problem.isEmpty()) ++failed;
}
static bool near(QColor a, QColor b, int tol = 40)
{
    return std::abs(a.red() - b.red()) <= tol && std::abs(a.green() - b.green()) <= tol && std::abs(a.blue() - b.blue()) <= tol;
}
static QVariantMap item(const char *type, const char *color, double w, double x1, double y1, double x2, double y2)
{
    return {{"type", type}, {"color", color}, {"width", w}, {"x1", x1}, {"y1", y1}, {"x2", x2}, {"y2", y2}};
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    const QString dir = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QDir::tempPath();
    QDir().mkpath(dir);
    QImage src(400, 300, QImage::Format_RGB32);
    src.fill(QColor(128, 128, 128));
    {
        QPainter p(&src);
        for (int x = 0; x < 120; x += 4)   // узкие полосы слева сверху — их «размоем»
            p.fillRect(x, 0, 2, 40, x % 8 ? Qt::black : Qt::white);
    }
    const QString file = dir + "/shot-test.png";
    src.save(file);

    Shot shot;
    if (!shot.load(file)) { std::printf("не открылась картинка\n"); return 1; }
    const QColor gray(128, 128, 128), red(0xef, 0x5b, 0x5b), blue(0x3d, 0x8b, 0xfd), green(0x34, 0xc7, 0x7b);

    auto one = [&](QVariantMap a) { return shot.render({a}, {}); };
    {
        const QImage r = one(item("rect", "#ef5b5b", 6, 50, 50, 150, 120));
        report("рамка: край красный, внутри фон", near(r.pixelColor(50, 85), red) && near(r.pixelColor(100, 85), gray) ? QString()
               : QStringLiteral("край %1, внутри %2").arg(r.pixelColor(50, 85).name(), r.pixelColor(100, 85).name()));
    }
    {
        const QImage r = one(item("arrow", "#3d8bfd", 5, 200, 50, 350, 50));
        report("стрелка: линия и наконечник", near(r.pixelColor(250, 50), blue) && near(r.pixelColor(340, 50), blue)
               && near(r.pixelColor(338, 54), blue) && near(r.pixelColor(250, 60), gray) ? QString()
               : QStringLiteral("линия %1, остриё %2, крыло %3").arg(r.pixelColor(250, 50).name(), r.pixelColor(340, 50).name(), r.pixelColor(338, 54).name()));
    }
    {
        const QImage r = one(item("ellipse", "#34c77b", 6, 60, 150, 160, 250));
        report("овал: край зелёный, центр фон", near(r.pixelColor(61, 200), green) && near(r.pixelColor(110, 200), gray) ? QString()
               : QStringLiteral("край %1, центр %2").arg(r.pixelColor(61, 200).name(), r.pixelColor(110, 200).name()));
    }
    {
        QVariantMap m = item("marker", "#f5a623", 5, 0, 0, 0, 0);
        m["points"] = QVariantList{200, 200, 300, 200};
        const QImage r = one(m);
        const QColor c = r.pixelColor(250, 200);
        report("маркер полупрозрачный", !near(c, gray, 10) && !near(c, QColor(0xf5, 0xa6, 0x23), 20) ? QString() : c.name());
    }
    {
        QVariantMap t = item("text", "#ffffff", 4, 220, 150, 220, 150);
        t["text"] = "Hi"; t["size"] = 40;
        const QImage r = one(t);
        int white = 0;
        for (int y = 150; y < 200; ++y) for (int x = 220; x < 280; ++x) if (near(r.pixelColor(x, y), Qt::white, 20)) ++white;
        report("текст: белые буквы на месте", white > 80 ? QString() : QStringLiteral("белых пикселей %1").arg(white));
    }
    {
        QVariantMap s = item("step", "#ef5b5b", 5, 300, 250, 300, 250);
        s["n"] = 1;
        const QImage r = one(s);
        report("номер шага: красный кружок", near(r.pixelColor(310, 250), red) || near(r.pixelColor(288, 250), red) ? QString() : r.pixelColor(288, 250).name());
    }
    {
        const QImage r = one(item("pixel", "#000000", 1, 0, 0, 120, 40));
        const int b = Shot::pixelBlock(src.size());
        // внутри блока все пиксели одинаковые, полосок 2 px больше нет
        bool uniform = true;
        for (int y = 0; y < b && uniform; ++y) for (int x = 0; x < b; ++x) if (r.pixel(x, y) != r.pixel(0, 0)) { uniform = false; break; }
        const bool outside = near(r.pixelColor(200, 20), gray, 2);
        report("размытие: блоки ровные, вне — как было", uniform && outside ? QString() : QStringLiteral("блок %1, снаружи %2").arg(uniform).arg(outside));
    }
    {
        const QImage r = shot.render({}, {{"x", 10}, {"y", 20}, {"w", 100}, {"h", 50}});
        report("обрезка 100×50", r.size() == QSize(100, 50) ? QString() : QStringLiteral("%1×%2").arg(r.width()).arg(r.height()));
    }
    {
        const QString png = dir + "/out.png", jpg = dir + "/out.jpg";
        const bool ok = shot.save({item("rect", "#ef5b5b", 6, 50, 50, 150, 120)}, {}, png) && shot.save({}, {}, jpg);
        report("сохранение PNG и JPEG", ok && QImageReader(png).format() == "png" && QImageReader(jpg).format() == "jpeg" ? QString() : "не записалось");
        QFile::remove(png); QFile::remove(jpg);
    }
    report("«Сохранить» для чужой картинки — рядом, «(правка)»", shot.savePath().endsWith("shot-test (правка).png") ? QString() : shot.savePath());
    QFile::remove(file);
    std::printf("\nпровалено: %d\n", failed);
    return failed ? 1 : 0;
}
