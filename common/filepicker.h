#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Выбор файла через xdg-desktop-portal (org.freedesktop.portal.FileChooser) — системное окно
// Nautilus/GTK. Ничего не грузит при запуске приложения: D-Bus — только по вызову open().
class FilePicker : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit FilePicker(QObject *parent = nullptr);
    bool busy() const { return !m_request.isEmpty(); }

    // filterName — «Изображения», patterns — {"*.jpg", "*.png"}; folder — где открыть (может быть пустым)
    Q_INVOKABLE void open(const QString &title, const QString &filterName, const QStringList &patterns,
                          const QString &folder = QString(), bool multiple = false);
    // выбрать папку (directory — портал 0.3+)
    Q_INVOKABLE void openFolder(const QString &title, const QString &folder = QString());
    // «Сохранить как»: currentName — предлагаемое имя файла
    Q_INVOKABLE void save(const QString &title, const QString &currentName, const QString &folder = QString());

signals:
    void picked(const QStringList &urls);
    void busyChanged();

private slots:
    void onResponse(uint response, const QVariantMap &results);

private:
    void request(const char *method, const QString &title, QVariantMap options);
    QString m_request;
};
