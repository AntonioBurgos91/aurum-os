#include "dock_model.h"

#include <QDir>
#include <QFile>
#include <QIcon>
#include <QStandardPaths>
#include <QTextStream>
#include <QUrl>

namespace aurum::dock {

namespace {

// Default pinned apps if the user has no ~/.config/aurum/dock.list yet.
// These are the canonical AurumOS launcher ids — every one resolves to a
// .desktop written by distro/assets/install-assets.sh, whose Exec points at an
// aurum-launch-* wrapper (or a native aurum-* binary). The wrappers degrade
// gracefully when the underlying tool isn't installed, so a dock click always
// does something instead of silently failing on a missing third-party binary.
const QStringList kDefaultFavorites = {
    "aurum-terminal",    // foot/kitty/... via aurum-launch-terminal
    "aurum-editor",      // code/zed/nano via aurum-launch-editor
    "aurum-browser",     // falkon/firefox/... via aurum-launch-browser
    "aurum-finder",      // native Qt6 binary
    "aurum-jupyterlab",  // aurum-launch-jupyter
    "aurum-marimo",      // aurum-launch-marimo
    "aurum-ollama",      // aurum-launch-ollama
    "aurum-settings",    // native Qt6 binary
};

QString themed_icon_url(const QString& icon_name) {
    if (icon_name.isEmpty()) return {};

    // Absolute path passed through.
    if (icon_name.startsWith('/')) return QUrl::fromLocalFile(icon_name).toString();

    QIcon icon = QIcon::fromTheme(icon_name);
    if (icon.isNull()) return {};

    // Pick the largest reasonable size we can request from the theme. QML's
    // Image will scale further as needed for the dock magnification.
    const auto sizes = icon.availableSizes();
    QSize target(64, 64);
    for (const auto& s : sizes) {
        if (s.width() >= 64 && s.width() <= 256) {
            target = s;
            break;
        }
    }

    // Convert the QPixmap into a temporary file: QML can't load directly from
    // a QIcon, and image://theme/ providers require extra registration plumbing
    // we don't need yet. A short-lived file under XDG_RUNTIME_DIR is fine.
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR", QDir::tempPath());
    const QString cache_dir = runtime + "/aurum-dock-icons";
    QDir().mkpath(cache_dir);
    const QString out = QString("%1/%2.png").arg(cache_dir, icon_name);
    if (!QFile::exists(out)) {
        icon.pixmap(target).save(out, "PNG");
    }
    return QUrl::fromLocalFile(out).toString();
}

}  // namespace

DockModel::DockModel(QObject* parent) : QAbstractListModel(parent) {
    rebuild();
}

QStringList DockModel::load_favorite_ids() const {
    const QString config_home =
        qEnvironmentVariable("XDG_CONFIG_HOME", QDir::homePath() + "/.config");
    const QString path = config_home + "/aurum/dock.list";

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return kDefaultFavorites;

    QStringList out;
    QTextStream in(&f);
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty() || line.startsWith('#')) continue;
        out << line;
    }
    return out.isEmpty() ? kDefaultFavorites : out;
}

void DockModel::rebuild() {
    beginResetModel();
    m_entries.clear();
    for (const auto& id : load_favorite_ids()) {
        auto e = aurum::core::lookup_desktop_entry(id);
        if (!e.isValid()) continue;  // missing app — skip silently
        m_entries.push_back(e);
    }
    endResetModel();
}

void DockModel::reload() {
    rebuild();
}

int DockModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : m_entries.size();
}

QVariant DockModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size()) return {};
    const auto& e = m_entries[index.row()];
    switch (role) {
        case IdRole:
            return e.id;
        case NameRole:
            return e.name.isEmpty() ? e.id : e.name;
        case IconNameRole:
            return e.icon;
        case IconUrlRole:
            return themed_icon_url(e.icon);
        case ExecRole:
            return e.exec;
        case IsRunningRole:
            return false;  // Phase 3: foreign-toplevel hookup.
    }
    return {};
}

QHash<int, QByteArray> DockModel::roleNames() const {
    return {
        {IdRole, "appId"},        {NameRole, "name"},     {IconNameRole, "iconName"},
        {IconUrlRole, "iconUrl"}, {ExecRole, "execLine"}, {IsRunningRole, "isRunning"},
    };
}

void DockModel::launch(int row) {
    if (row < 0 || row >= m_entries.size()) return;
    aurum::core::launch_desktop_entry(m_entries[row]);
}

void DockModel::launchByName(const QString& appId) {
    auto entry = aurum::core::lookup_desktop_entry(appId);
    if (entry.isValid()) {
        aurum::core::launch_desktop_entry(entry);
    }
}

QString DockModel::iconUrlForName(const QString& iconName) const {
    return themed_icon_url(iconName);
}

}  // namespace aurum::dock
