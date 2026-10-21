#pragma once

#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Папка с картинками: список (естественная сортировка, как в файловом менеджере), текущая,
// сведения о файле по заголовку (без декодирования), корзина с отменой, буфер обмена.
class Gallery : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString folder READ folder NOTIFY listChanged)
    Q_PROPERTY(int count READ count NOTIFY listChanged)
    Q_PROPERTY(int revision READ revision NOTIFY listChanged)   // для привязок к urlAt()/infoAt()
    Q_PROPERTY(int index READ index WRITE setIndex NOTIFY currentChanged)
    Q_PROPERTY(QString path READ path NOTIFY currentChanged)
    Q_PROPERTY(QVariantMap info READ info NOTIFY currentChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY undoChanged)

public:
    explicit Gallery(QObject *parent = nullptr);

    QString folder() const { return m_folder; }
    int count() const { return int(m_files.size()); }
    int revision() const { return m_revision; }
    int index() const { return m_index; }
    void setIndex(int i);
    QString path() const;
    QVariantMap info() const;
    bool canUndo() const { return !m_trashed.isEmpty(); }

    // открыть файл (или первую картинку папки); принимает путь и file:// URL
    Q_INVOKABLE bool open(const QString &pathOrUrl);
    Q_INVOKABLE void next() { setIndex(m_index + 1); }
    Q_INVOKABLE void prev() { setIndex(m_index - 1); }
    Q_INVOKABLE QString urlAt(int i) const;
    Q_INVOKABLE QVariantMap infoAt(int i) const;

    Q_INVOKABLE bool trash();       // текущий файл — в корзину (freedesktop Trash)
    Q_INVOKABLE bool undoTrash();   // вернуть последний
    // «Заменить оригинал» в правке: оригинал в корзине, на его месте (или рядом) — replacement
    Q_INVOKABLE void recordReplace(const QString &original, const QString &inTrash, const QString &replacement);
    Q_INVOKABLE bool copyImage() const;
    Q_INVOKABLE void copyPath() const;
    Q_INVOKABLE void showInFolder() const;

    static bool isImage(const QString &path);
    Q_INVOKABLE bool canShow(const QString &path) const { return isImage(path); }

signals:
    void listChanged();
    void currentChanged();
    void undoChanged();
    void error(const QString &message);

private:
    void rescan(const QString &keep);
    void scheduleRescan() { m_rescan.start(); }

    QString m_folder;
    QStringList m_files;       // имена файлов в m_folder
    int m_index = -1;
    int m_revision = 0;
    QFileSystemWatcher m_watcher;
    QTimer m_rescan;
    struct Trashed { QString original, inTrash, replacement; };
    QList<Trashed> m_trashed;
    mutable QHash<QString, QVariantMap> m_infoCache;   // путь → сведения (с mtime для проверки)
};
