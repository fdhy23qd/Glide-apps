#include "converter.h"
#include "glidetr.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QTime>
#include <cmath>
#include <csignal>
#include <sys/prctl.h>
#include <sys/resource.h>

namespace {

const QString kRender = QStringLiteral("/dev/dri/renderD128");

struct Format { QString ext; bool video; bool audio; };
Format formatOf(const QString &f, const QString &inputExt)
{
    if (f == "mp4") return {"mp4", true, true};
    if (f == "mkv") return {"mkv", true, true};
    if (f == "webm") return {"webm", true, true};
    if (f == "gif") return {"gif", true, false};
    if (f == "webp") return {"webp", true, false};
    if (f == "mp3") return {"mp3", false, true};
    if (f == "m4a") return {"m4a", false, true};
    if (f == "opus") return {"opus", false, true};
    if (f == "flac") return {"flac", false, true};
    if (f == "wav") return {"wav", false, true};
    static const QSet<QString> audioExt{"mp3", "flac", "ogg", "oga", "opus", "m4a", "aac", "wav", "wma"};
    return {inputExt, !audioExt.contains(inputExt), true};   // same
}

QString seconds(qint64 ms) { return QString::number(ms / 1000.0, 'f', 3); }

// три ступени качества: высокое / среднее / маленький файл
template <typename T> T pick(const QString &q, T high, T medium, T small)
{
    return q == "high" ? high : q == "small" ? small : medium;
}

void setPriorityAndDeath()
{
    ::prctl(PR_SET_PDEATHSIG, SIGTERM);   // приложение закрыли или оно упало — ffmpeg не остаётся сиротой
    ::setpriority(PRIO_PROCESS, 0, 10);   // кодирование не мешает смотреть и работать
}

} // namespace

Converter::Converter(QObject *parent) : QObject(parent) {}

Converter::~Converter()
{
    if (m_proc) {
        m_cancelled = true;
        m_proc->kill();
        m_proc->waitForFinished(1000);
        QFile::remove(m_output);
    }
}

void Converter::prepareChild(QProcess *p)
{
    p->setChildProcessModifier(setPriorityAndDeath);
}

// ---------- сведения ----------
void Converter::probe(const QString &path)
{
    m_probing = path;
    auto *p = new QProcess(this);
    prepareChild(p);
    connect(p, &QProcess::finished, this, [this, p, path](int code) {
        p->deleteLater();
        if (path != m_probing)
            return;   // уже открыли другой файл
        QVariantMap m{{"path", path}, {"ok", code == 0}};
        const QJsonObject root = QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        const QJsonObject fmt = root.value("format").toObject();
        m["duration"] = qint64(fmt.value("duration").toString().toDouble() * 1000);
        m["bytes"] = fmt.value("size").toString().toLongLong();
        m["bitrate"] = fmt.value("bit_rate").toString().toLongLong();
        m["container"] = fmt.value("format_name").toString();
        bool video = false, audio = false;
        for (const QJsonValue &v : root.value("streams").toArray()) {
            const QJsonObject s = v.toObject();
            const QString type = s.value("codec_type").toString();
            if (type == "video" && !video && s.value("disposition").toObject().value("attached_pic").toInt() == 0) {
                video = true;
                int w = s.value("width").toInt(), h = s.value("height").toInt();
                int rot = 0;   // телефоны пишут поворот метаданными
                for (const QJsonValue &sd : s.value("side_data_list").toArray())
                    if (sd.toObject().contains("rotation"))
                        rot = sd.toObject().value("rotation").toInt();
                if (std::abs(rot) % 180 == 90)
                    std::swap(w, h);
                m["width"] = w;
                m["height"] = h;
                m["vcodec"] = s.value("codec_name").toString();
                const QStringList fr = s.value("avg_frame_rate").toString().split('/');
                m["fps"] = fr.size() == 2 && fr[1].toDouble() > 0 ? fr[0].toDouble() / fr[1].toDouble() : 0.0;
            } else if (type == "audio" && !audio) {
                audio = true;
                m["acodec"] = s.value("codec_name").toString();
                m["channels"] = s.value("channels").toInt();
            }
        }
        m["hasVideo"] = video;
        m["hasAudio"] = audio;
        m_info = m;
        emit infoChanged();
    });
    p->start("ffprobe", {"-v", "error", "-print_format", "json", "-show_format", "-show_streams", path});
}

void Converter::detectHardware()
{
    if (m_hwChecked)
        return;
    m_hwChecked = true;
    if (!QFileInfo::exists(kRender))
        return;
    auto *p = new QProcess(this);
    prepareChild(p);
    connect(p, &QProcess::finished, this, [this, p](int code) {
        p->deleteLater();
        if (code == 0) {
            m_hardware = QStringLiteral("VA-API");
            emit hardwareChanged();
        }
    });
    // пробное кодирование нескольких кадров: драйвера VA-API нет — ошибка за миллисекунды
    p->start("ffmpeg", {"-hide_banner", "-nostdin", "-v", "error", "-vaapi_device", kRender,
                        "-f", "lavfi", "-i", "color=s=256x144:d=0.2", "-vf", "format=nv12,hwupload",
                        "-c:v", "h264_vaapi", "-f", "null", "-"});
}

// ---------- что получится ----------
bool Converter::canCopy(const QVariantMap &o) const
{
    if (o.value("height").toInt() > 0 || o.value("rotate").toInt() != 0)
        return false;
    const QString f = o.value("format").toString();
    const QString vc = m_info.value("vcodec").toString(), ac = m_info.value("acodec").toString();
    const bool hasV = m_info.value("hasVideo").toBool(), hasA = m_info.value("hasAudio").toBool();
    const QSet<QString> mp4V{"h264", "hevc", "av1", "mpeg4"}, mp4A{"aac", "mp3", "opus", "ac3", "eac3", "alac", "flac"};
    if (f == "same" || f == "mkv")
        return true;
    if (f == "mp4")
        return (!hasV || mp4V.contains(vc)) && (!hasA || mp4A.contains(ac));
    if (f == "webm")
        return (!hasV || QSet<QString>{"vp8", "vp9", "av1"}.contains(vc)) && (!hasA || QSet<QString>{"opus", "vorbis"}.contains(ac));
    if (f == "mp3") return ac == "mp3";
    if (f == "m4a") return ac == "aac" || ac == "alac";
    if (f == "opus") return ac == "opus";
    if (f == "flac") return ac == "flac";
    return false;   // gif, webp, wav — всегда кодируем
}

QString Converter::outputPath(const QVariantMap &o) const
{
    const QFileInfo in(o.value("input").toString());
    const Format fmt = formatOf(o.value("format").toString(), in.suffix().toLower());
    const bool trimmed = o.value("start").toLongLong() > 0 || o.value("end").toLongLong() > 0;
    const QString base = in.absolutePath() + '/' + in.completeBaseName() + (trimmed ? glideTr(" — фрагмент") : "");
    QString out = base + '.' + fmt.ext;
    for (int n = 2; QFileInfo::exists(out) || out == in.absoluteFilePath(); ++n)
        out = QStringLiteral("%1 (%2).%3").arg(base).arg(n).arg(fmt.ext);
    return out;
}

QString Converter::outputName(const QVariantMap &opts) const
{
    return QFileInfo(outputPath(opts)).fileName();
}

QStringList Converter::buildArgs(const QVariantMap &o, const QVariantMap &info, bool hw, const QString &out)
{
    const QString input = o.value("input").toString();
    const Format fmt = formatOf(o.value("format").toString(), QFileInfo(input).suffix().toLower());
    QString q = o.value("quality").toString();
    const qint64 start = o.value("start").toLongLong(), end = o.value("end").toLongLong();
    const bool mute = o.value("mute").toBool() || !fmt.audio;
    const int rotate = ((o.value("rotate").toInt() % 360) + 360) % 360;
    const int shortSide = o.value("height").toInt();
    const bool srcVideo = info.value("hasVideo").toBool(), srcAudio = info.value("hasAudio").toBool();
    const bool video = fmt.video && srcVideo;
    const QString ext = fmt.ext;

    QStringList a{"-hide_banner", "-nostdin", "-y", "-v", "error", "-progress", "pipe:1", "-nostats"};
    const bool copy = q == "copy";
    const bool h264 = !copy && video && QSet<QString>{"mp4", "mkv", "mov", "m4v", "avi", "ts", "3gp"}.contains(ext);
    const bool useHw = hw && h264;
    if (useHw)
        a << "-vaapi_device" << kRender;
    if (start > 0)
        a << "-ss" << seconds(start);   // до -i: быстрый переход; при копии — по ближайшему ключевому кадру
    a << "-i" << input;
    if (end > 0)
        a << "-t" << seconds(end - std::max<qint64>(0, start));

    // ---- какие потоки ----
    const bool anim = ext == "gif" || ext == "webp";
    if (video && !anim)   // у GIF/WebP поток даёт -filter_complex/-vf; лишний -map — пустой второй поток
        a << "-map" << "0:v:0";
    else if (anim)
        a << "-map" << "0:v:0?";
    else
        a << "-vn";
    if (!mute && srcAudio)
        a << "-map" << (fmt.video ? "0:a?" : "0:a:0");
    else
        a << "-an";
    if (ext == "mkv" && copy)
        a << "-map" << "0:s?";   // субтитры: MKV возьмёт любые
    else
        a << "-sn";

    if (copy) {
        a << "-c" << "copy" << "-avoid_negative_ts" << "make_zero";
        if (ext == "mp4" || ext == "m4a")
            a << "-movflags" << "+faststart";
        a << out;
        return a;
    }

    // ---- фильтры: поворот, затем размер по короткой стороне ----
    QStringList vf;
    if (rotate == 90) vf << "transpose=1";
    else if (rotate == 270) vf << "transpose=2";
    else if (rotate == 180) vf << "hflip,vflip";
    int w = info.value("width").toInt(), h = info.value("height").toInt();
    if (rotate == 90 || rotate == 270)
        std::swap(w, h);
    const bool portrait = h > w;
    auto scaleTo = [&](int side) {
        if (side > 0 && side < std::min(w, h))
            vf << (portrait ? QStringLiteral("scale=%1:-2:flags=lanczos").arg(side)
                            : QStringLiteral("scale=-2:%1:flags=lanczos").arg(side));
    };

    if (ext == "gif" || ext == "webp") {
        const int fps = pick(q, 15, 12, 10);
        const int side = shortSide > 0 ? shortSide : pick(q, 480, 360, 240);
        vf.prepend(QStringLiteral("fps=%1").arg(fps));
        scaleTo(side);
        if (ext == "gif") {
            a.removeAll("-map"); a.removeAll("0:v:0?");   // поток задаёт сам граф фильтров
            a << "-filter_complex" << QStringLiteral("[0:v:0]%1,split[a][b];[a]palettegen=stats_mode=diff[p];"
                                                     "[b][p]paletteuse=dither=bayer:bayer_scale=5").arg(vf.join(','))
              << "-loop" << "0";
        } else {
            a << "-vf" << vf.join(',') << "-c:v" << "libwebp_anim" << "-q:v" << QString::number(pick(q, 80, 65, 45))
              << "-loop" << "0";
        }
        a << out;
        return a;
    }

    if (video) {
        scaleTo(shortSide);
        if (ext == "webm") {
            if (!vf.isEmpty()) a << "-vf" << vf.join(',');
            a << "-c:v" << "libvpx-vp9" << "-crf" << QString::number(pick(q, 30, 34, 40)) << "-b:v" << "0"
              << "-deadline" << "realtime" << "-cpu-used" << "8" << "-row-mt" << "1";
        } else if (useHw) {
            vf << "format=nv12" << "hwupload";
            a << "-vf" << vf.join(',') << "-c:v" << "h264_vaapi" << "-qp" << QString::number(pick(q, 20, 24, 28));
        } else {
            if (!vf.isEmpty()) a << "-vf" << vf.join(',');
            a << "-c:v" << "libx264" << "-preset" << "veryfast" << "-crf" << QString::number(pick(q, 18, 23, 28))
              << "-pix_fmt" << "yuv420p";
        }
    }
    if (!mute && srcAudio) {
        if (ext == "webm" || ext == "opus")
            a << "-c:a" << "libopus" << "-b:a" << pick(q, QString("192k"), QString("128k"), QString("64k"));
        else if (ext == "mp3")
            a << "-c:a" << "libmp3lame" << "-q:a" << pick(q, QString("0"), QString("2"), QString("5"));
        else if (ext == "flac")
            a << "-c:a" << "flac";
        else if (ext == "wav")
            a << "-c:a" << "pcm_s16le";
        else
            a << "-c:a" << "aac" << "-b:a" << pick(q, QString("256k"), QString("160k"), QString("96k"));
    }
    if (ext == "mp4" || ext == "m4a")
        a << "-movflags" << "+faststart";
    a << out;
    return a;
}

// ---------- экспорт ----------
void Converter::start(const QVariantMap &opts)
{
    if (m_proc)
        return;
    m_opts = opts;
    m_output = outputPath(opts);
    const qint64 dur = m_info.value("duration").toLongLong();
    const qint64 s = std::max<qint64>(0, opts.value("start").toLongLong());
    const qint64 e = opts.value("end").toLongLong() > 0 ? opts.value("end").toLongLong() : dur;
    m_segmentUs = std::max<qint64>(1, (e - s) * 1000);
    launch(!m_hardware.isEmpty());
}

void Converter::launch(bool hw)
{
    m_hwRun = hw;
    m_cancelled = false;
    m_stderr.clear();
    m_progress = 0;
    m_speed = 0;
    m_eta = -1;
    emit progressChanged();
    m_proc = new QProcess(this);
    prepareChild(m_proc);
    connect(m_proc, &QProcess::readyReadStandardOutput, this, &Converter::onProgressOutput);
    connect(m_proc, &QProcess::readyReadStandardError, this, [this] { m_stderr += QString::fromUtf8(m_proc->readAllStandardError()); });
    connect(m_proc, &QProcess::finished, this, &Converter::onFinished);
    m_clock.start();
    m_proc->start("ffmpeg", buildArgs(m_opts, m_info, hw, m_output));
    emit runningChanged();
}

void Converter::onProgressOutput()
{
    while (m_proc && m_proc->canReadLine()) {
        const QString line = QString::fromUtf8(m_proc->readLine()).trimmed();
        if (line.startsWith("out_time_us=")) {
            const qint64 us = line.mid(12).toLongLong();
            m_progress = std::clamp(qreal(us) / m_segmentUs, 0.0, 1.0);
            const qint64 el = m_clock.elapsed();
            m_eta = m_progress > 0.02 ? int((1 - m_progress) * el / m_progress / 1000) : -1;
        } else if (line.startsWith("speed=")) {
            m_speed = line.mid(6).chopped(line.endsWith('x') ? 1 : 0).toDouble();
        } else if (line.startsWith("progress=")) {
            emit progressChanged();
        }
    }
}

void Converter::onFinished(int code, QProcess::ExitStatus status)
{
    QProcess *p = m_proc;
    m_proc = nullptr;
    if (p)
        p->deleteLater();
    const bool ok = !m_cancelled && status == QProcess::NormalExit && code == 0;
    if (!ok)
        QFile::remove(m_output);   // недоделанный файл не оставляем
    if (!ok && !m_cancelled && m_hwRun) {   // видеокарта не справилась — на процессоре
        launch(false);
        return;
    }
    emit runningChanged();
    if (m_cancelled)
        return;
    QString err;
    const QStringList lines = m_stderr.split('\n', Qt::SkipEmptyParts);
    if (!ok)
        err = lines.isEmpty() ? glideTr(QStringLiteral("ffmpeg завершился с кодом %1")).arg(code) : lines.last().trimmed();
    m_progress = ok ? 1 : 0;
    emit progressChanged();
    emit finished(ok, ok ? m_output : QString(), err);
}

void Converter::cancel()
{
    if (!m_proc)
        return;
    m_cancelled = true;
    m_proc->terminate();
}

// ---------- кадр ----------
void Converter::snapshot(const QString &path, qint64 ms)
{
    const QFileInfo in(path);
    const QString stamp = QTime::fromMSecsSinceStartOfDay(int(ms % 86400000)).toString("HH-mm-ss");
    QString out = glideTr(QStringLiteral("%1/%2 — кадр %3.png")).arg(in.absolutePath(), in.completeBaseName(), stamp);
    for (int n = 2; QFileInfo::exists(out); ++n)
        out = glideTr(QStringLiteral("%1/%2 — кадр %3 (%4).png")).arg(in.absolutePath(), in.completeBaseName(), stamp).arg(n);
    auto *p = new QProcess(this);
    prepareChild(p);
    connect(p, &QProcess::finished, this, [this, p, out](int code) {
        p->deleteLater();
        if (code == 0 && QFileInfo(out).size() > 0)
            emit snapshotSaved(out);
        else
            emit failed(glideTr(QStringLiteral("Не удалось сохранить кадр")));
    });
    p->start("ffmpeg", {"-hide_banner", "-nostdin", "-v", "error", "-ss", seconds(ms), "-i", path,
                        "-frames:v", "1", "-update", "1", out});
}
