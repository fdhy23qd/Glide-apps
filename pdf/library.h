#pragma once

#include <QJsonObject>
#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Где остановились в каждом документе: страница, место на ней, масштаб
// (~/.local/state/glide-apps/pdf-positions.json). Плюс сведения о файле и «показать в папке».
class Library : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit Library(QObject *parent = nullptr);
    ~Library() override;

    Q_INVOKABLE QVariantMap position(const QString &path) const;   // {page, offset, fit, scale} или пусто
    Q_INVOKABLE void savePosition(const QString &path, const QVariantMap &pos);
    Q_INVOKABLE QVariantMap fileInfo(const QString &path) const;    // {name, bytes, modified, folder}
    Q_INVOKABLE QString localPath(const QString &pathOrUrl) const;
    Q_INVOKABLE QUrl fileUrl(const QString &path) const;
    Q_INVOKABLE void showInFolder(const QString &path) const;

private:
    void flush();

    QJsonObject m_data;
    QString m_file;
    QTimer m_saveTimer;
};
