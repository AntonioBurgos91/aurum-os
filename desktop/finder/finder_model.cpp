#include "finder_model.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QStringList>
#include <QVariant>

#include "ml_integrations.h"

namespace aurum::finder {

namespace {

QString classify_row(const QFileInfo& fi) {
    if (fi.isDir()) return "dir";
    switch (aurum::ml::classify(fi.absoluteFilePath())) {
        case aurum::ml::FileKind::Notebook:
            return "notebook";
        case aurum::ml::FileKind::Safetensors:  // fall-through, same UI bucket
        case aurum::ml::FileKind::Model:
            return "model";
        case aurum::ml::FileKind::Parquet:  // fall-through
        case aurum::ml::FileKind::Dataset:
            return "dataset";
        default:
            return "file";
    }
}

}  // namespace

FinderModel::FinderModel(QObject* parent) : QAbstractListModel(parent) {
    m_current = QDir::homePath();
    reload();
}

QStringList FinderModel::breadcrumbs() const {
    QStringList out;
    QString acc;
    for (const auto& part : m_current.split('/', Qt::SkipEmptyParts)) {
        acc += "/" + part;
        out << acc;
    }
    return out;
}

void FinderModel::cd(const QString& path) {
    QFileInfo fi(path);
    if (!fi.exists() || !fi.isDir()) return;
    m_current = fi.absoluteFilePath();
    reload();
    emit currentPathChanged();
}

void FinderModel::cdUp() {
    QDir d(m_current);
    if (d.cdUp()) {
        m_current = d.absolutePath();
        reload();
        emit currentPathChanged();
    }
}

void FinderModel::refresh() {
    reload();
}

int FinderModel::setFilter(const QString& needle) {
    m_filter = needle.trimmed();
    apply_filter();
    return m_rows.size();
}

void FinderModel::reload() {
    // Re-read the directory into m_all_rows, then run the current filter to
    // refresh m_rows. Splitting "all" from "visible" lets us toggle the
    // search field on/off without re-hitting the filesystem.
    m_all_rows.clear();
    QDir dir(m_current);
    const auto entries = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot,
                                           QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
    m_all_rows.reserve(entries.size());
    for (const auto& fi : entries) {
        FileRow r;
        r.name = fi.fileName();
        r.absolutePath = fi.absoluteFilePath();
        r.isDir = fi.isDir();
        r.size = fi.size();
        r.mtimeIso = fi.lastModified().toString(Qt::ISODate);
        r.kind = classify_row(fi);
        m_all_rows.push_back(std::move(r));
    }
    apply_filter();
}

void FinderModel::apply_filter() {
    beginResetModel();
    m_rows.clear();
    if (m_filter.isEmpty()) {
        m_rows = m_all_rows;
    } else {
        m_rows.reserve(m_all_rows.size());
        for (const auto& r : m_all_rows) {
            if (r.name.contains(m_filter, Qt::CaseInsensitive)) m_rows.push_back(r);
        }
    }
    endResetModel();
}

int FinderModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant FinderModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size()) return {};
    const auto& r = m_rows[index.row()];
    switch (role) {
        case NameRole:
            return r.name;
        case PathRole:
            return r.absolutePath;
        case IsDirRole:
            return r.isDir;
        case SizeRole:
            return static_cast<qlonglong>(r.size);
        case MtimeRole:
            return r.mtimeIso;
        case KindRole:
            return r.kind;
    }
    return {};
}

QHash<int, QByteArray> FinderModel::roleNames() const {
    return {
        {NameRole, "name"}, {PathRole, "absolutePath"}, {IsDirRole, "isDir"},
        {SizeRole, "size"}, {MtimeRole, "mtime"},       {KindRole, "kind"},
    };
}

QVariant FinderModel::previewJson(int row) {
    if (row < 0 || row >= m_rows.size()) return {};
    const auto& r = m_rows[row];
    if (r.isDir) return {};
    const auto preview = aurum::ml::preview(r.absolutePath);
    // QML side reads strings; serializing to JSON keeps the QVariant API
    // simple and avoids exposing QJsonObject directly.
    return QString::fromUtf8(QJsonDocument(preview).toJson(QJsonDocument::Compact));
}

}  // namespace aurum::finder
