#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

// Куда сохранять: ~/Изображения/Камера и ~/Видео/Камера (папки создаются при первом снимке).
class Paths : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool cameraOff READ cameraOff CONSTANT)   // GLIDE_CAMERA_OFF=1 — проверка интерфейса без камеры

public:
    using QObject::QObject;
    bool cameraOff() const;

    Q_INVOKABLE QString newPhoto() const;   // полный путь для нового снимка (.jpg)
    Q_INVOKABLE QString newVideo() const;   // … и для видео (.mp4)
    Q_INVOKABLE QString photoFolder() const;
    Q_INVOKABLE QString videoFolder() const;
    Q_INVOKABLE QString latest() const;      // последний снимок или видео в этих папках — для миниатюры
};
