#include "imageeditor.h"
#include "glidetr.h"

#include <QBuffer>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QImageWriter>
#include <QPainter>
#include <QPointer>
#include <QProcess>
#include <QSaveFile>
#include <QSet>
#include <QTemporaryDir>
#include <QThreadPool>
#include <cmath>
#include <csignal>
#include <sys/prctl.h>
#include <sys/resource.h>

namespace {

const QSet<QString> kQtWrite{"jpg", "png", "webp", "bmp", "tiff"};
const QSet<QString> kFfmpegWrite{"avif", "jxl"};

QString normExt(QString e)
{
    e = e.toLower();
    if (e == "jpeg" || e == "jfif" || e == "jpe") return "jpg";
    if (e == "tif") return "tiff";
    return e;
}

bool lossy(const QString &ext) { return ext == "jpg" || ext == "webp" || ext == "avif" || ext == "jxl"; }

// поворот, отражение, обрезка — над тем изображением, что пришло (полным или уменьшенным образцом)
QImage transform(QImage img, const QVariantMap &o)
{
    const int rot = ((o.value("rotate").toInt() % 360) + 360) % 360;
    if (rot)
        img = img.transformed(QTransform().rotate(rot));
    Qt::Orientations flip;
    if (o.value("flipH").toBool()) flip |= Qt::Horizontal;
    if (o.value("flipV").toBool()) flip |= Qt::Vertical;
    if (flip)
        img = img.flipped(flip);
    const QVariantMap c = o.value("crop").toMap();
    if (!c.isEmpty()) {
        const QRect r(qRound(c.value("x").toDouble() * img.width()), qRound(c.value("y").toDouble() * img.height()),
                      std::max(1, qRound(c.value("w").toDouble() * img.width())),
                      std::max(1, qRound(c.value("h").toDouble() * img.height())));
        img = img.copy(r & img.rect());
    }
    return img;
}

// итоговый размер — без обработки пикселей
QSize finalSize(QSize s, const QVariantMap &o)
{
    if (std::abs(o.value("rotate").toInt()) % 180 == 90)
        s.transpose();
    const QVariantMap c = o.value("crop").toMap();
    if (!c.isEmpty())
        s = QSize(std::max(1, qRound(c.value("w").toDouble() * s.width())), std::max(1, qRound(c.value("h").toDouble() * s.height())));
    const int ls = o.value("longSide").toInt();
    if (ls > 0 && std::max(s.width(), s.height()) > ls)
        s = s.scaled(ls, ls, Qt::KeepAspectRatio);
    return s;
}

QImage flattenIfNeeded(const QImage &img, const QString &ext)
{
    // у JPEG/AVIF/BMP нет прозрачности: прозрачное — на белом, а не на чёрном
    if (!img.hasAlphaChannel() || ext == "png" || ext == "webp" || ext == "tiff" || ext == "jxl")
        return img;
    QImage out(img.size(), QImage::Format_RGB32);
    out.fill(Qt::white);
    QPainter p(&out);
    p.drawImage(0, 0, img);
    return out;
}

QByteArray encode(const QImage &src, const QString &ext, int quality, QString *err)
{
    const QImage img = flattenIfNeeded(src, ext);
    if (kQtWrite.contains(ext)) {
        QByteArray data;
        QBuffer buf(&data);
        buf.open(QIODevice::WriteOnly);
        QImageWriter w(&buf, ext.toLatin1());
        if (lossy(ext))
            w.setQuality(quality);
        if (!w.write(img)) {
            *err = w.errorString();
            return {};
        }
        return data;
    }
    // AVIF и JPEG XL — через ffmpeg: временный PNG → кодер
    QTemporaryDir tmp;
    const QString in = tmp.filePath("in.png"), out = tmp.filePath("out." + ext);
    if (!img.save(in, "PNG", 0)) {   // 0 — без сжатия: быстрее
        *err = glideTr(QStringLiteral("не удалось подготовить изображение"));
        return {};
    }
    QStringList args{"-hide_banner", "-nostdin", "-v", "error", "-y", "-i", in, "-frames:v", "1"};
    if (ext == "avif")
        args << "-c:v" << "libaom-av1" << "-still-picture" << "1" << "-cpu-used" << "6"
             << "-crf" << QString::number(qRound(12 + (100 - quality) * 0.45)) << "-pix_fmt" << "yuv420p";
    else
        args << "-c:v" << "libjxl" << "-distance" << QString::number((100 - quality) * 0.12, 'f', 2);
    args << out;
    QProcess p;
    p.setChildProcessModifier([] { ::prctl(PR_SET_PDEATHSIG, SIGTERM); ::setpriority(PRIO_PROCESS, 0, 10); });
    p.start("ffmpeg", args);
    if (!p.waitForFinished(180000) || p.exitCode() != 0) {
        const QStringList lines = QString::fromUtf8(p.readAllStandardError()).split('\n', Qt::SkipEmptyParts);
        *err = lines.isEmpty() ? glideTr(QStringLiteral("ffmpeg не справился")) : lines.last();
        return {};
    }
    QFile f(out);
    if (!f.open(QIODevice::ReadOnly)) {
        *err = f.errorString();
        return {};
    }
    return f.readAll();
}

} // namespace

ImageEditor::ImageEditor(QObject *parent) : QObject(parent) {}

ImageEditor::~ImageEditor()
{
    m_ticket = -1;
    QThreadPool::globalInstance()->waitForDone(5000);
}

bool ImageEditor::writable(const QString &ext)
{
    const QString e = normExt(ext);
    return kQtWrite.contains(e) || kFfmpegWrite.contains(e);
}

QString ImageEditor::outputExt(const QVariantMap &o) const
{
    const QString f = o.value("format").toString();
    if (f != "same" && !f.isEmpty())
        return f;
    const QString e = normExt(QFileInfo(o.value("path").toString()).suffix());
    return writable(e) ? e : QStringLiteral("png");   // GIF, SVG, ICO… Qt записать не умеет
}

void ImageEditor::forget()
{
    QMutexLocker l(&m_cacheLock);
    m_cache = QImage();
    m_cachePath.clear();
}

QImage ImageEditor::base(const QString &path, QString *err)
{
    const QDateTime mtime = QFileInfo(path).lastModified();
    {
        QMutexLocker l(&m_cacheLock);
        if (path == m_cachePath && mtime == m_cacheTime && !m_cache.isNull())
            return m_cache;
    }
    QImageReader r(path);
    r.setAutoTransform(true);   // поворот по EXIF — сразу в пиксели
    QImage img = r.read();
    if (img.isNull()) {
        *err = r.errorString();
        return img;
    }
    QMutexLocker l(&m_cacheLock);
    m_cache = img;
    m_cachePath = path;
    m_cacheTime = mtime;
    return img;
}

// ---------- оценка размера файла ----------
void ImageEditor::requestEstimate(const QVariantMap &opts)
{
    QMutexLocker l(&m_pendingLock);
    m_pending = opts;
    m_hasPending = true;
    if (m_estimating.exchange(true))
        return;   // поток уже считает — возьмёт свежую заявку, когда закончит
    const int ticket = ++m_ticket;
    QThreadPool::globalInstance()->start([this, ticket] { runEstimate({}, ticket); });
}

void ImageEditor::runEstimate(QVariantMap, int ticket)
{
    QPointer<ImageEditor> self(this);
    for (;;) {
        QVariantMap o;
        {
            QMutexLocker l(&m_pendingLock);
            if (!m_hasPending || m_ticket < 0) {
                m_estimating = false;
                return;
            }
            o = m_pending;
            m_hasPending = false;
        }
        QString err;
        const QImage full = base(o.value("path").toString(), &err);
        qint64 bytes = -1;
        QSize size;
        if (!full.isNull()) {
            size = finalSize(full.size(), o);
            const QString ext = outputExt(o);
            // образец: кодировать 24 Мп ради оценки долго — уменьшаем и пересчитываем по площади
            const double limit = kFfmpegWrite.contains(ext) ? 0.6e6 : 3e6;
            const double finalPx = double(size.width()) * size.height();
            const double k = finalPx > limit ? std::sqrt(limit / finalPx) : 1.0;
            const QImage small = k < 1 ? full.scaled(full.size() * k, Qt::KeepAspectRatio, Qt::SmoothTransformation) : full;
            QImage sample = transform(small, o);
            const QSize want = k < 1 ? size * k : size;
            if (sample.size() != want && want.isValid())
                sample = sample.scaled(want, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            const QByteArray data = encode(sample, ext, o.value("quality").toInt(), &err);
            if (!data.isEmpty())
                bytes = qint64(data.size() * (finalPx / std::max(1.0, double(sample.width()) * sample.height())));
        }
        if (!self)
            return;
        QMetaObject::invokeMethod(this, [this, bytes, size] {
            m_estimate = bytes;
            m_outSize = size;
            emit estimated();
        }, Qt::QueuedConnection);
    }
    Q_UNUSED(ticket);
}

// ---------- сохранение ----------
void ImageEditor::save(const QVariantMap &opts)
{
    if (m_saving)
        return;
    m_saving = true;
    emit busyChanged();
    QPointer<ImageEditor> self(this);
    QThreadPool::globalInstance()->start([this, self, opts] {
        QString err, file, inTrash;
        const QString path = opts.value("path").toString();
        const QFileInfo src(path);
        const QString ext = outputExt(opts);
        const bool replace = opts.value("mode").toString() == "replace";
        QImage img = base(path, &err);
        QByteArray data;
        if (!img.isNull()) {
            img = transform(img, opts);
            const QSize size = finalSize(QSize(img.width(), img.height()), QVariantMap{{"longSide", opts.value("longSide")}});
            if (size != img.size())
                img = img.scaled(size, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            data = encode(img, ext, opts.value("quality").toInt(), &err);
        }
        if (!data.isEmpty()) {
            const QString dir = src.absolutePath(), name = src.completeBaseName();
            QString target = replace ? dir + '/' + name + '.' + ext : dir + '/' + name + glideTr(" (изменено).") + ext;
            for (int n = 2; QFileInfo::exists(target) && !(replace && target == src.absoluteFilePath()); ++n)
                target = QStringLiteral("%1/%2 (%3%4).%5").arg(dir, name, replace ? "" : glideTr("изменено ")).arg(n).arg(ext);
            // заменить: оригинал — в корзину (вернуть можно), затем записать новый
            if (replace && !QFile::moveToTrash(path, &inTrash))
                err = glideTr(QStringLiteral("не удалось переместить оригинал в корзину"));
            if (err.isEmpty()) {
                QSaveFile f(target);
                if (f.open(QIODevice::WriteOnly) && f.write(data) == data.size() && f.commit()) {
                    file = target;
                } else {
                    err = f.errorString();
                    if (!inTrash.isEmpty() && QFile::rename(inTrash, path))   // не вышло — оригинал обратно
                        inTrash.clear();
                }
            }
        }
        if (!self)
            return;
        QMetaObject::invokeMethod(this, [this, file, path, inTrash, err] {
            m_saving = false;
            emit busyChanged();
            if (file.isEmpty())
                emit failed(err.isEmpty() ? glideTr(QStringLiteral("не удалось сохранить")) : err);
            else
                emit saved(file, path, inTrash);
        }, Qt::QueuedConnection);
    });
}
