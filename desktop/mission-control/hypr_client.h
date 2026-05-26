#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

namespace aurum::mc {

// Thin wrapper around `hyprctl -j` (Hyprland JSON IPC). We avoid the
// hyprland-ipc library to keep this binary's transitive deps minimal: a
// 30 ms subprocess at overlay open time is invisible against the visible
// fade-in animation.
class HyprClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList workspaces READ workspaces NOTIFY refreshed)
    Q_PROPERTY(QVariantList clients READ clients NOTIFY refreshed)
    Q_PROPERTY(int activeWorkspaceId READ activeWorkspaceId NOTIFY refreshed)

public:
    explicit HyprClient(QObject* parent = nullptr);

    QVariantList workspaces() const {
        return m_workspaces;
    }
    QVariantList clients() const {
        return m_clients;
    }
    int activeWorkspaceId() const {
        return m_active;
    }

    Q_INVOKABLE void refresh();

    // Focus the window with the given Hyprland address (hex string like
    // "0x55e...") via `hyprctl dispatch focuswindow address:<addr>`.
    Q_INVOKABLE bool focus(const QString& address);

    // Switch to workspace `id` via `hyprctl dispatch workspace <id>`.
    Q_INVOKABLE bool gotoWorkspace(int id);

signals:
    void refreshed();

private:
    QByteArray runHyprctl(const QStringList& args) const;

    QVariantList m_workspaces;
    QVariantList m_clients;
    int m_active = -1;
};

}  // namespace aurum::mc
