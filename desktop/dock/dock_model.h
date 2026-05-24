#pragma once

#include <QAbstractListModel>
#include <QIcon>
#include <QString>
#include <QVector>

#include "core_services.h"

namespace aurum::dock {

// Backs the dock's QML Repeater. One row per pinned launcher; the entry is
// resolved against installed .desktop files on construction (and on rescan)
// so we get the localized name, themed icon, and Exec line from XDG.
class DockModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        IdRole       = Qt::UserRole + 1,
        NameRole,
        IconNameRole,
        IconUrlRole,    // file:// URL for QML Image; resolved via QIcon theme.
        ExecRole,
        IsRunningRole,  // mocked for Phase 2; foreign-toplevel landing later.
    };
    Q_ENUM(Roles)

    explicit DockModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void launch(int row);
    Q_INVOKABLE void reload();

private:
    // Loads the user's favorites file (~/.config/aurum/dock.toml-style list)
    // or falls back to a built-in default if no user list exists.
    QStringList load_favorite_ids() const;
    void rebuild();

    QVector<aurum::core::DesktopEntry> m_entries;
};

} // namespace aurum::dock
