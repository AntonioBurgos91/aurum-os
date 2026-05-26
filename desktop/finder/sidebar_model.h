#pragma once

#include <QAbstractListModel>
#include <QObject>
#include <QString>
#include <QVector>

namespace aurum::finder {

// Two-section sidebar:
//   * Favorites (Desktop, Documents, Downloads, Home)
//   * ML        (~/datasets, ~/models, ~/notebooks)  ← Phase 3 deliverable
// Entries point at a section absent until the directory actually exists, so
// users without an ML workspace see a clean Finder.
struct SidebarEntry {
    QString name;
    QString path;
    QString icon;     // icon NAME (XDG theme); resolved on the QML side
    QString section;  // "Favorites" | "ML"
};

class SidebarModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        IconRole,
        SectionRole,
    };
    Q_ENUM(Roles)

    explicit SidebarModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

private:
    void rebuild();
    QVector<SidebarEntry> m_rows;
};

}  // namespace aurum::finder
