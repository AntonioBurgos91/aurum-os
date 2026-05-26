#pragma once

#include <QAbstractListModel>
#include <QFileInfo>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVector>

namespace aurum::finder {

// One entry in the file list: name + size + mtime + a coarse kind so the QML
// side can pick an icon and a Quick Look backend.
struct FileRow {
    QString name;
    QString absolutePath;
    bool isDir = false;
    qint64 size = 0;
    QString mtimeIso;
    QString kind;  // "dir" | "notebook" | "model" | "dataset" | "file"
};

// Browse-style model: holds the current directory's children and exposes them
// to QML. `cd()` navigates, `preview(row)` runs the ml-integrations preview.
class FinderModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QStringList breadcrumbs READ breadcrumbs NOTIFY currentPathChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        IsDirRole,
        SizeRole,
        MtimeRole,
        KindRole,
    };
    Q_ENUM(Roles)

    explicit FinderModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString currentPath() const {
        return m_current;
    }
    QStringList breadcrumbs() const;

    Q_INVOKABLE void cd(const QString& path);
    Q_INVOKABLE void cdUp();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariant previewJson(int row);

    // Local "Search in folder" — case-insensitive substring filter on the
    // current directory listing. Empty string clears the filter.
    // Returns the new row count so QML can show "N results" if it wants.
    Q_INVOKABLE int setFilter(const QString& needle);

signals:
    void currentPathChanged();

private:
    void reload();
    void apply_filter();  // rebuilds m_visible from m_all_rows + m_filter

    QString m_current;
    QString m_filter;
    QVector<FileRow> m_all_rows;  // every entry from the disk listing
    QVector<FileRow> m_rows;      // currently visible (possibly filtered)
};

}  // namespace aurum::finder
