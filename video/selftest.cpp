// Самотест редактора: настоящий ffmpeg по матрице параметров, результат проверяется ffprobe.
//   build/video/glide-video-selftest ПАПКА_С_ТЕСТОВЫМИ_ФАЙЛАМИ
// В папке: clip1.mp4 (1280×720, 40 с, h264+aac), clip2.webm (vp9+opus), clip3-vertical.mp4 (720×1280),
// song.mp3. Результаты пишутся туда же и удаляются после проверки.
#include "converter.h"

#include <QCoreApplication>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTimer>
#include <cstdio>

struct Probe { double dur = 0; int w = 0, h = 0; QString v, a; };

static Probe probe(const QString &f)
{
    QProcess p;
    p.start("ffprobe", {"-v", "error", "-print_format", "json", "-show_format", "-show_streams", f});
    p.waitForFinished(10000);
    const QJsonObject r = QJsonDocument::fromJson(p.readAllStandardOutput()).object();
    Probe out;
    out.dur = r.value("format").toObject().value("duration").toString().toDouble();
    for (const QJsonValue &s : r.value("streams").toArray()) {
        const QJsonObject o = s.toObject();
        if (o.value("codec_type") == "video" && out.v.isEmpty()) { out.v = o.value("codec_name").toString(); out.w = o.value("width").toInt(); out.h = o.value("height").toInt(); }
        if (o.value("codec_type") == "audio" && out.a.isEmpty()) out.a = o.value("codec_name").toString();
    }
    return out;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QString dir = argc > 1 ? QString::fromLocal8Bit(argv[1]) : ".";
    int failed = 0;

    auto run = [&](const char *name, QVariantMap opts, auto check, int cancelAfterMs = -1) {
        Converter c;
        QEventLoop loop;
        QObject::connect(&c, &Converter::infoChanged, &loop, &QEventLoop::quit);
        c.probe(opts.value("input").toString());
        loop.exec();
        bool ok = false;
        QString out, err;
        QObject::connect(&c, &Converter::finished, &loop, [&](bool o, const QString &f, const QString &e) { ok = o; out = f; err = e; loop.quit(); });
        QObject::connect(&c, &Converter::runningChanged, &loop, [&] { if (!c.running() && cancelAfterMs >= 0) loop.quit(); });
        const bool copyOk = c.canCopy(opts);
        if (opts.value("quality") == "copy" && !copyOk) opts["quality"] = "medium";
        QElapsedTimer t; t.start();
        c.start(opts);
        const QString planned = c.output();
        if (cancelAfterMs >= 0) QTimer::singleShot(cancelAfterMs, &c, &Converter::cancel);
        QTimer::singleShot(120000, &loop, &QEventLoop::quit);
        loop.exec();
        QString verdict;
        if (cancelAfterMs >= 0) {
            verdict = !QFileInfo::exists(planned) ? QString() : "после отмены остался файл";
        } else if (!ok) {
            verdict = "ffmpeg: " + err;
        } else {
            verdict = check(probe(out));
            QFile::remove(out);
        }
        std::printf("%-46s %s  %5lld мс  %s\n", name, verdict.isEmpty() ? "OK  " : "FAIL",
                    (long long)t.elapsed(), qPrintable(verdict.isEmpty() ? QFileInfo(cancelAfterMs >= 0 ? planned : out).fileName() : verdict));
        if (!verdict.isEmpty()) ++failed;
    };
    auto near = [](double a, double b, double tol) { return std::abs(a - b) <= tol; };
    const QString c1 = dir + "/clip1.mp4", c2 = dir + "/clip2.webm", c3 = dir + "/clip3-vertical.mp4", song = dir + "/song.mp3";

    // копия режет по ключевым кадрам: начало уходит к предыдущему (в clip1 они раз в 8,3 с)
    run("фрагмент 5–15 с, без перекодир. (по ключ. кадрам)", {{"input", c1}, {"start", 5000}, {"end", 15000}, {"format", "same"}, {"quality", "copy"}},
        [&](Probe p) { return p.dur >= 9.9 && p.dur <= 18.5 && p.v == "h264" && p.a == "aac" ? QString() : QString("dur=%1 %2/%3").arg(p.dur).arg(p.v, p.a); });
    run("первые 10 с, без перекодир.", {{"input", c1}, {"end", 10000}, {"format", "mp4"}, {"quality", "copy"}},
        [&](Probe p) { return near(p.dur, 10, 0.2) ? QString() : QString("dur=%1").arg(p.dur); });
    run("фрагмент 5–15 с, MP4, точно (перекодир.)", {{"input", c1}, {"start", 5000}, {"end", 15000}, {"format", "mp4"}, {"quality", "small"}},
        [&](Probe p) { return near(p.dur, 10, 0.15) ? QString() : QString("dur=%1").arg(p.dur); });
    run("WebM 360p среднее", {{"input", c1}, {"end", 6000}, {"format", "webm"}, {"quality", "medium"}, {"height", 360}},
        [&](Probe p) { return p.v == "vp9" && p.a == "opus" && p.h == 360 && p.w == 640 ? QString() : QString("%1/%2 %3x%4").arg(p.v, p.a).arg(p.w).arg(p.h); });
    run("GIF 0–3 с маленький", {{"input", c1}, {"end", 3000}, {"format", "gif"}, {"quality", "small"}},
        [&](Probe p) { return p.v == "gif" && p.a.isEmpty() && p.h == 240 ? QString() : QString("%1 a=%2 h=%3").arg(p.v, p.a).arg(p.h); });
    run("WebP анимация 0–2 с", {{"input", c1}, {"end", 2000}, {"format", "webp"}, {"quality", "medium"}},
        [&](Probe p) { return p.v.startsWith("webp") ? QString() : QString("v=%1").arg(p.v); });
    run("MP3 из видео", {{"input", c1}, {"end", 5000}, {"format", "mp3"}, {"quality", "high"}},
        [&](Probe p) { return p.v.isEmpty() && p.a == "mp3" && near(p.dur, 5, 0.2) ? QString() : QString("%1/%2 %3").arg(p.v, p.a).arg(p.dur); });
    run("вертикальное → MP4, поворот 90°, 480p", {{"input", c3}, {"format", "mp4"}, {"quality", "medium"}, {"height", 480}, {"rotate", 90}},
        [&](Probe p) { return p.w == 854 && p.h == 480 ? QString() : QString("%1x%2").arg(p.w).arg(p.h); });
    run("WebM (vp9) → MP4: копия невозможна → h264", {{"input", c2}, {"format", "mp4"}, {"quality", "copy"}},
        [&](Probe p) { return p.v == "h264" && p.a == "aac" ? QString() : QString("%1/%2").arg(p.v, p.a); });
    run("MKV без звука, без перекодир.", {{"input", c1}, {"end", 5000}, {"format", "mkv"}, {"quality", "copy"}, {"mute", true}},
        [&](Probe p) { return p.v == "h264" && p.a.isEmpty() ? QString() : QString("%1/%2").arg(p.v, p.a); });
    run("MP3 → Opus маленький", {{"input", song}, {"format", "opus"}, {"quality", "small"}},
        [&](Probe p) { return p.a == "opus" && near(p.dur, 20, 0.2) ? QString() : QString("%1 %2").arg(p.a).arg(p.dur); });
    run("MP3 → WAV", {{"input", song}, {"format", "wav"}, {"quality", "medium"}},
        [&](Probe p) { return p.a == "pcm_s16le" ? QString() : p.a; });
    run("отмена через 300 мс — файла нет", {{"input", c1}, {"format", "webm"}, {"quality", "high"}}, [](Probe) { return QString(); }, 300);

    // кадр
    {
        Converter c;
        QEventLoop loop;
        QString file;
        QObject::connect(&c, &Converter::snapshotSaved, &loop, [&](const QString &f) { file = f; loop.quit(); });
        QObject::connect(&c, &Converter::failed, &loop, &QEventLoop::quit);
        c.snapshot(c1, 2500);
        QTimer::singleShot(10000, &loop, &QEventLoop::quit);
        loop.exec();
        const Probe p = probe(file);
        const bool ok = p.v == "png" && p.w == 1280;
        std::printf("%-46s %s  %s\n", "кадр 0:02,5 → PNG", ok ? "OK  " : "FAIL", qPrintable(QFileInfo(file).fileName()));
        if (!ok) ++failed;
        QFile::remove(file);
    }
    std::printf("\nпровалено: %d\n", failed);
    return failed ? 1 : 0;
}
