#pragma once

#include <QMutex>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include <atomic>
#include <memory>
#include <vector>

class QThread;

// Что занимает место: обход папки в фоновом потоке (без перехода по ссылкам и на другие диски, жёсткие ссылки —
// один раз), размер — занятое на диске (st_blocks), как у df/du. Мелкие файлы (< 1 МБ) в папке не хранятся
// по одному — только их число и сумма: так даже домашняя папка с сотнями тысяч файлов занимает немного памяти.
class Scanner : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(qint64 progressFiles READ progressFiles NOTIFY progressChanged)
    Q_PROPERTY(qint64 progressBytes READ progressBytes NOTIFY progressChanged)
    Q_PROPERTY(QString progressPath READ progressPath NOTIFY progressChanged)
    Q_PROPERTY(QVariantList partial READ partial NOTIFY progressChanged)   // уже досчитанные папки верхнего уровня
    Q_PROPERTY(QString root READ root NOTIFY treeChanged)
    Q_PROPERTY(int revision READ revision NOTIFY treeChanged)   // для привязок к children()
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY undoChanged)

public:
    struct Node {
        QString name;
        qint64 size = 0;        // на диске, байт (с вложенным)
        qint64 files = 0;       // файлов внутри (для папки)
        qint64 smallSize = 0;   // мелкие файлы этой папки — суммой
        int smallCount = 0;
        qint64 byKind[6] = {};  // видео, картинки, музыка, архивы, документы, другое — с вложенным
        bool dir = false;
        bool denied = false;    // нет прав прочитать — размер неполный
        Node *parent = nullptr;
        std::vector<std::unique_ptr<Node>> kids;
    };

    explicit Scanner(QObject *parent = nullptr);
    ~Scanner() override;

    bool scanning() const { return m_scanning; }
    qint64 progressFiles() const { return m_files.load(); }
    qint64 progressBytes() const { return m_bytes.load(); }
    QString progressPath() const;
    QVariantList partial() const;
    QString root() const { return m_rootPath; }
    int revision() const { return m_revision; }
    bool canUndo() const { return bool(m_undo.node); }

    Q_INVOKABLE void scan(const QString &path);
    Q_INVOKABLE void cancel();
    // содержимое папки по убыванию размера: [{name, path, size, files, dir, kind, small, denied}]
    Q_INVOKABLE QVariantList children(const QString &path) const;
    Q_INVOKABLE QVariantMap info(const QString &path) const;   // {size, files, denied, kinds: [{kind, size}]}
    // диски и разделы: [{name, path, total, used, fs}]
    Q_INVOKABLE QVariantList volumes() const;

    Q_INVOKABLE bool trash(const QString &path);   // в корзину; размеры выше пересчитываются
    Q_INVOKABLE bool undoTrash();
    Q_INVOKABLE void open(const QString &path) const;
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE QString home() const;

signals:
    void scanningChanged();
    void progressChanged();
    void treeChanged();
    void undoChanged();
    void error(const QString &message);

private:
    Node *find(const QString &path) const;
    void finish(std::unique_ptr<Node> tree, const QString &path);

    std::unique_ptr<Node> m_root;
    QString m_rootPath;
    int m_revision = 0;
    bool m_scanning = false;
    std::atomic<qint64> m_files{0}, m_bytes{0};
    std::atomic<bool> m_cancel{false};
    mutable QMutex m_pathLock;
    QString m_curPath;   // где сейчас обход (пишет поток, читает интерфейс)
    QList<QPair<QString, qint64>> m_partial;   // под тем же замком
    QTimer m_progress;
    QThread *m_thread = nullptr;
    struct Undo { std::unique_ptr<Node> node; QString original, inTrash; } m_undo;
};
