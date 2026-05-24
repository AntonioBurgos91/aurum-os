#include "search_aggregator.h"

#include <QClipboard>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QJsonObject>
#include <QUrl>
#include <QVariantMap>

#include <algorithm>

#include "core_services.h"

namespace aurum::spotlight {

SearchAggregator::SearchAggregator(QObject* parent) : QObject(parent) {}

void SearchAggregator::addPlugin(SpotlightPlugin* p) {
    p->setParent(this);
    m_plugins.push_back(p);
    connect(p, &SpotlightPlugin::resultsReady,
            this, &SearchAggregator::onPluginResults);
}

void SearchAggregator::setQuery(const QString& q) {
    ++m_generation;
    m_results.clear();
    for (auto* p : m_plugins) p->search(q, m_generation);
    rebuildGroups(); // emit empty groups immediately so the UI clears
}

void SearchAggregator::onPluginResults(QString pluginId, int generation, QJsonArray rows) {
    // Drop stale: a later query already ran.
    if (generation != m_generation) return;
    m_results[pluginId] = rows;
    rebuildGroups();
}

void SearchAggregator::rebuildGroups() {
    // Plugins sorted by priority (ascending). Each non-empty plugin becomes a
    // group { id, title, rows }.
    QVector<SpotlightPlugin*> sorted = m_plugins;
    std::sort(sorted.begin(), sorted.end(),
        [](SpotlightPlugin* a, SpotlightPlugin* b) { return a->priority() < b->priority(); });

    QVariantList groups;
    for (auto* p : sorted) {
        const auto& rows = m_results.value(p->id());
        if (rows.isEmpty()) continue;
        groups.append(QVariantMap{
            {"id",    p->id()},
            {"title", p->displayName()},
            {"rows",  rows.toVariantList()},
        });
    }
    m_groups_cached = groups;
    emit groupsChanged();
}

bool SearchAggregator::activate(const QVariantMap& action) {
    const auto type = action.value("type").toString();
    if (type == "desktop_entry") {
        const auto id = action.value("id").toString();
        auto entry = aurum::core::lookup_desktop_entry(id);
        if (!entry.isValid()) return false;
        return aurum::core::launch_desktop_entry(entry) > 0;
    }
    if (type == "open_path") {
        const auto path = action.value("path").toString();
        return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    }
    if (type == "open_url") {
        return QDesktopServices::openUrl(QUrl(action.value("url").toString()));
    }
    if (type == "copy") {
        QGuiApplication::clipboard()->setText(action.value("value").toString());
        return true;
    }
    if (type == "exec") {
        return aurum::core::launch_command(action.value("cmd").toString()) > 0;
    }
    return false;
}

} // namespace aurum::spotlight
