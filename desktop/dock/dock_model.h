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
        IdRole = Qt::UserRole + 1,
        NameRole,
        IconNameRole,
        IconUrlRole,  // file:// URL for QML Image; resolved via QIcon theme.
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
    Q_INVOKABLE void launchByName(const QString& appId);
    // Resolve a freedesktop icon name (e.g. "applications-science") to a
    // file:// URL a QML Image can load, via the installed icon theme (Papirus).
    // Returns an empty string if the theme can't resolve it, so callers can
    // fall back to a labeled chip. Used by the ML Tools drawer.
    Q_INVOKABLE QString iconUrlForName(const QString& iconName) const;

private:
    // Loads the user's favorites file (~/.config/aurum/dock.toml-style list)
    // or falls back to a built-in default if no user list exists.
    QStringList load_favorite_ids() const;
    void rebuild();

    QVector<aurum::core::DesktopEntry> m_entries;
};

}  // namespace aurum::dock
