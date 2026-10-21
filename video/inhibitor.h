#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

// Пока идёт видео, экран не гаснет и не запирается: org.freedesktop.ScreenSaver.Inhibit (его отдаёт
// niri, а IdleMonitor Glide Shell уважает запреты). Аудио без картинки экран не держит.
class Inhibitor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)

public:
    explicit Inhibitor(QObject *parent = nullptr) : QObject(parent) {}
    ~Inhibitor() override;

    bool active() const { return m_cookie != 0; }
    void setActive(bool on);

signals:
    void activeChanged();

private:
    uint m_cookie = 0;
    bool m_want = false;
};
