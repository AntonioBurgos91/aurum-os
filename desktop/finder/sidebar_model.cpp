#include "sidebar_model.h"

#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>

namespace aurum::finder {

namespace {

QString home_subdir(const QString& name) {
    return QDir::homePath() + "/" + name;
}

bool exists(const QString& path) {
    return QFileInfo::exists(path);
}

}  // namespace

SidebarModel::SidebarModel(QObject* parent) : QAbstractListModel(parent) {
    rebuild();
}

void SidebarModel::rebuild() {
    beginResetModel();
    m_rows.clear();

    // --- Favorites: XDG user dirs ---
    const auto add_fav = [&](const QString& name, const QString& path, const QString& icon) {
        if (exists(path)) m_rows.push_back({name, path, icon, "Favorites"});
    };
    add_fav("Home", QDir::homePath(), "user-home");
    add_fav("Desktop", QStandardPaths::writableLocation(QStandardPaths::DesktopLocation),
            "user-desktop");
    add_fav("Documents", QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
            "folder-documents");
    add_fav("Downloads", QStandardPaths::writableLocation(QStandardPaths::DownloadLocation),
            "folder-download");
    add_fav("Pictures", QStandardPaths::writableLocation(QStandardPaths::PicturesLocation),
            "folder-pictures");

    // --- ML section: bespoke to the AurumOS workspace convention ---
    const auto add_ml = [&](const QString& name, const QString& path, const QString& icon) {
        if (exists(path)) m_rows.push_back({name, path, icon, "ML"});
    };
    add_ml("Datasets", home_subdir("datasets"), "folder-database");
    add_ml("Models", home_subdir("models"), "folder-html");
    add_ml("Notebooks", home_subdir("notebooks"), "folder-templates");

    endResetModel();
}

int SidebarModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant SidebarModel::data(const QModelIndex& idx, int role) const {
    if (!idx.isValid() || idx.row() < 0 || idx.row() >= m_rows.size()) return {};
    const auto& r = m_rows[idx.row()];
    switch (role) {
        case NameRole:
            return r.name;
        case PathRole:
            return r.path;
        case IconRole:
            return r.icon;
        case SectionRole:
            return r.section;
    }
    return {};
}

QHash<int, QByteArray> SidebarModel::roleNames() const {
    return {
        {NameRole, "name"},
        {PathRole, "path"},
        {IconRole, "iconName"},
        {SectionRole, "section"},
    };
}

}  // namespace aurum::finder
