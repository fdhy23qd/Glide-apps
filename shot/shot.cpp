#include "shot.h"
#include "glidetr.h"

#include <QBuffer>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontMetricsF>
#include <QImageReader>
#include <QImageWriter>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QPainterPath>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QtMath>

namespace {

// папка скриншотов из настройки niri `screenshot-path` (как у клавиши Print), иначе ~/Pictures/Screenshots
QString niriScreenshotFolder()
{
    const QString home = QDir::homePath();
    QFile cfg(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/niri/config.kdl");
    if (cfg.open(QIODevice::ReadOnly)) {
        static const QRegularExpression re(R"re(^\s*screenshot-path\s+"([^"]+)")re");
        for (const QByteArray &raw : cfg.readAll().split('\n')) {
            const auto m = re.match(QString::fromUtf8(raw));
            if (m.hasMatch()) {
                QString p = m.captured(1);
                if (p.startsWith("~/"))
                    p = home + p.mid(1);
                return QFileInfo(p).absolutePath();
            }
        }
    }
    return home + "/Pictures/Screenshots";
}

QPointF pt(const QVariantMap &a, const char *x, const char *y) { return {a.value(x).toDouble(), a.value(y).toDouble()}; }

} // namespace

Shot::Shot(QObject *parent) : QObject(parent), m_folder(niriScreenshotFolder())
{
    m_giveUp.setSingleShot(true);
    m_giveUp.setInterval(120000);
    connect(&m_giveUp, &QTimer::timeout, this, [this] { stopEvents(); emit captureGaveUp(); });
}

Shot::~Shot()
{
    stopEvents();
    if (!m_pixelFile.isEmpty())
        QFile::remove(m_pixelFile);
}

QUrl Shot::url() const
{
    QUrl u = QUrl::fromLocalFile(m_path);
    u.setQuery(QStringLiteral("v=%1").arg(QFileInfo(m_path).lastModified().toMSecsSinceEpoch()));
    return u;
}

QString Shot::localPath(const QString &url) const
{
    return url.startsWith("file:") ? QUrl(url).toLocalFile() : url;
}

// ---------- снимок ----------
void Shot::capture(const QString &mode)
{
    if (m_events)
        return;
    QDir().mkpath(m_folder);
    m_target = m_folder + "/Screenshot from " + QDateTime::currentDateTime().toString("yyyy-MM-dd HH-mm-ss") + ".png";
    QStringList action{"msg", "action"};
    if (mode == "screen") action << "screenshot-screen" << "-p" << "false";
    else if (mode == "window") action << "screenshot-window";
    else action << "screenshot";
    action << "--path" << m_target;

    m_events = new QProcess(this);
    auto started = std::make_shared<bool>(false);
    connect(m_events, &QProcess::readyReadStandardOutput, this, [this, action, started] {
        while (m_events && m_events->canReadLine()) {
            const QByteArray line = m_events->readLine();
            if (!*started) {   // поток событий подключён — теперь можно просить снимок
                *started = true;
                QProcess::startDetached("niri", action);
            }
            const QJsonObject ev = QJsonDocument::fromJson(line).object().value("ScreenshotCaptured").toObject();
            if (ev.isEmpty())
                continue;
            const QString p = ev.value("path").toString();
            if (!p.isEmpty() && p != m_target)
                continue;   // чужой снимок (клавиша Print) — не наш
            stopEvents();
            if (load(m_target))
                m_fresh = true;
            emit loaded();
            return;
        }
    });
    connect(m_events, &QProcess::finished, this, [this] {
        if (m_events) { stopEvents(); emit failed(glideTr(QStringLiteral("niri не отвечает"))); }
    });
    m_events->start("niri", {"msg", "--json", "event-stream"});
    m_giveUp.start();
    emit capturingChanged();
}

void Shot::stopEvents()
{
    m_giveUp.stop();
    if (!m_events)
        return;
    QProcess *p = m_events;
    m_events = nullptr;
    p->disconnect(this);
    p->kill();
    p->waitForFinished(500);
    p->deleteLater();
    emit capturingChanged();
}

bool Shot::load(const QString &pathOrUrl)
{
    const QString p = QFileInfo(localPath(pathOrUrl)).absoluteFilePath();
    QImageReader r(p);
    r.setAutoTransform(true);
    QImage img = r.read();
    if (img.isNull()) {
        emit failed(glideTr(QStringLiteral("Не удалось открыть: %1")).arg(QFileInfo(p).fileName()));
        return false;
    }
    m_image = img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    m_path = p;
    m_fresh = false;
    m_pixels = QImage();
    if (!m_pixelFile.isEmpty()) { QFile::remove(m_pixelFile); m_pixelFile.clear(); emit pixelChanged(); }
    emit loaded();
    return true;
}

void Shot::preparePixels()
{
    if (!m_pixels.isNull() || m_image.isNull())
        return;
    const int b = pixelBlock(m_image.size());
    const QSize small((m_image.width() + b - 1) / b, (m_image.height() + b - 1) / b);
    // блоки ровно по сетке: уменьшаем до «один пиксель на блок», увеличиваем без сглаживания
    m_pixels = m_image.scaled(small, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                   .scaled(small * b, Qt::IgnoreAspectRatio, Qt::FastTransformation)
                   .copy(QRect(QPoint(0, 0), m_image.size()));
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    m_pixelFile = QStringLiteral("%1/glide-shot-%2-pixels.png").arg(dir.isEmpty() ? QDir::tempPath() : dir).arg(QCoreApplication::applicationPid());
    m_pixels.save(m_pixelFile, "PNG", 0);
    emit pixelChanged();
}

// ---------- итог ----------
QImage Shot::render(const QVariantList &items, const QVariantMap &crop) const
{
    QImage out = m_image;
    QPainter p(&out);
    p.setRenderHint(QPainter::Antialiasing);
    p.setRenderHint(QPainter::TextAntialiasing);
    for (const QVariant &v : items) {
        const QVariantMap a = v.toMap();
        const QString type = a.value("type").toString();
        QColor c(a.value("color").toString());
        const double w = a.value("width").toDouble();
        const QPointF p1 = pt(a, "x1", "y1"), p2 = pt(a, "x2", "y2");
        const QRectF r = QRectF(p1, p2).normalized();
        QPen pen(c, w, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
        p.setBrush(Qt::NoBrush);
        p.setPen(pen);
        if (type == "rect") {
            p.drawRect(r);
        } else if (type == "ellipse") {
            p.drawEllipse(r);
        } else if (type == "line") {
            p.drawLine(p1, p2);
        } else if (type == "arrow") {
            // наконечник: длина ~4,5 толщины, основание — на 0,8 длины от острия
            const QPointF d = p2 - p1;
            const double len = std::hypot(d.x(), d.y());
            if (len < 1) continue;
            const QPointF u = d / len, n(-u.y(), u.x());
            const double head = std::max(w * 4.5, 16.0), half = head * 0.55;
            const QPointF base = p2 - u * head * 0.8;
            p.drawLine(p1, base);
            p.setPen(Qt::NoPen);
            p.setBrush(c);
            p.drawPolygon(QPolygonF{p2, p2 - u * head + n * half, base, p2 - u * head - n * half});
        } else if (type == "pen" || type == "marker") {
            const QVariantList pts = a.value("points").toList();
            QPolygonF poly;
            for (int i = 0; i + 1 < pts.size(); i += 2)
                poly << QPointF(pts[i].toDouble(), pts[i + 1].toDouble());
            if (type == "marker") {
                c.setAlphaF(0.38);
                pen.setColor(c);
                pen.setWidthF(w * 4);
                p.setPen(pen);
            }
            p.drawPolyline(poly);
        } else if (type == "text") {
            QFont f(QStringLiteral("Inter"));
            f.setPixelSize(std::max(6, a.value("size").toInt()));
            f.setBold(true);
            QPainterPath path;
            path.addText(p1.x(), p1.y() + QFontMetricsF(f).ascent(), f, a.value("text").toString());
            // тёмная обводка — читается на любом фоне
            p.strokePath(path, QPen(QColor(0, 0, 0, 150), f.pixelSize() / 7.0, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
            p.fillPath(path, c);
        } else if (type == "step") {
            const double rad = std::max(14.0, w * 3.2);
            p.setPen(QPen(QColor(255, 255, 255), std::max(2.0, rad / 7)));
            p.setBrush(c);
            p.drawEllipse(p1, rad, rad);
            QFont f(QStringLiteral("Inter"));
            f.setPixelSize(int(rad * 1.15));
            f.setBold(true);
            p.setFont(f);
            p.setPen(QColor(255, 255, 255));
            p.drawText(QRectF(p1.x() - rad, p1.y() - rad, rad * 2, rad * 2), Qt::AlignCenter, a.value("n").toString());
        } else if (type == "pixel") {
            const_cast<Shot *>(this)->preparePixels();
            const QRect rr = r.toAlignedRect() & m_pixels.rect();
            p.drawImage(rr.topLeft(), m_pixels, rr);
        }
    }
    p.end();
    const QRect cr(qRound(crop.value("x").toDouble()), qRound(crop.value("y").toDouble()),
                   qRound(crop.value("w").toDouble()), qRound(crop.value("h").toDouble()));
    if (!crop.isEmpty() && cr.width() > 1 && cr.height() > 1)
        out = out.copy(cr & out.rect());
    return out;
}

QString Shot::savePath() const
{
    if (m_fresh)
        return m_path;   // свой свежий снимок — поверх него
    const QFileInfo fi(m_path);
    QString out = fi.absolutePath() + '/' + fi.completeBaseName() + glideTr(" (правка).png");
    for (int n = 2; QFileInfo::exists(out); ++n)
        out = glideTr(QStringLiteral("%1/%2 (правка %3).png")).arg(fi.absolutePath(), fi.completeBaseName()).arg(n);
    return out;
}

bool Shot::save(const QVariantList &items, const QVariantMap &crop, const QString &target)
{
    const QString file = localPath(target);
    const QImage img = render(items, crop);
    QByteArray fmt = QFileInfo(file).suffix().toLower().toLatin1();
    if (fmt == "jpeg") fmt = "jpg";
    if (fmt.isEmpty() || !QImageWriter::supportedImageFormats().contains(fmt))
        fmt = "png";
    QSaveFile f(file);
    if (!f.open(QIODevice::WriteOnly)) {
        emit failed(f.errorString());
        return false;
    }
    QImageWriter w(&f, fmt);
    if (fmt == "jpg")
        w.setQuality(92);
    if (!w.write(fmt == "jpg" ? img.convertToFormat(QImage::Format_RGB32) : img) || !f.commit()) {
        emit failed(w.errorString());
        return false;
    }
    return true;
}

bool Shot::copy(const QVariantList &items, const QVariantMap &crop)
{
    // через wl-copy: он остаётся владельцем буфера и после закрытия редактора
    QByteArray png;
    QBuffer buf(&png);
    buf.open(QIODevice::WriteOnly);
    render(items, crop).save(&buf, "PNG");
    QProcess p;
    p.start("wl-copy", {"--type", "image/png"});
    if (!p.waitForStarted(2000)) {
        emit failed(glideTr(QStringLiteral("Нет wl-copy (пакет wl-clipboard)")));
        return false;
    }
    p.write(png);
    p.closeWriteChannel();
    p.waitForFinished(5000);
    return p.exitCode() == 0;
}

void Shot::showInFolder(const QString &file) const
{
    QDBusMessage msg = QDBusMessage::createMethodCall("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                                                      "org.freedesktop.FileManager1", "ShowItems");
    msg << QStringList{QUrl::fromLocalFile(localPath(file)).toString()} << QString();
    QDBusConnection::sessionBus().asyncCall(msg);
}
