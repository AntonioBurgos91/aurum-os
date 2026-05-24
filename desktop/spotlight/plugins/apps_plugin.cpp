#include "apps_plugin.h"

#include <QJsonArray>
#include <QJsonObject>

#include <algorithm>

namespace aurum::spotlight {

namespace {

// Simple substring score in [0..1]: 1.0 if the query is a prefix of the name,
// 0.6 if it's a contained substring anywhere in name, 0.4 if it matches the
// id (i.e. the desktop file basename). Lowercased on both sides.
double score(const aurum::core::DesktopEntry& e, const QString& q_lower) {
    if (q_lower.isEmpty()) return 0.0;
    const QString name_l = e.name.toLower();
    if (name_l.startsWith(q_lower))                return 1.0;
    if (name_l.contains(q_lower))                  return 0.6;
    if (e.id.toLower().contains(q_lower))          return 0.4;
    if (e.genericName.toLower().contains(q_lower)) return 0.3;
    return 0.0;
}

} // namespace

AppsPlugin::AppsPlugin(QObject* parent) : SpotlightPlugin(parent) {
    m_entries = aurum::core::scan_desktop_entries();
}

void AppsPlugin::search(const QString& query, int generation) {
    QJsonArray rows;
    const auto q = query.trimmed().toLower();
    if (!q.isEmpty()) {
        struct Hit { double s; const aurum::core::DesktopEntry* e; };
        QVector<Hit> hits;
        hits.reserve(m_entries.size());
        for (const auto& e : m_entries) {
            const auto s = score(e, q);
            if (s > 0.0) hits.push_back({s, &e});
        }
        const int limit = std::min<int>(8, static_cast<int>(hits.size()));
        std::partial_sort(
            hits.begin(),
            hits.begin() + limit,
            hits.end(),
            [](const Hit& a, const Hit& b) { return a.s > b.s; });

        const int n = limit;
        for (int i = 0; i < n; ++i) {
            const auto& e = *hits[i].e;
            rows.append(QJsonObject{
                {"title",    e.name},
                {"subtitle", e.genericName.isEmpty() ? e.comment : e.genericName},
                {"icon",     e.icon},
                {"score",    hits[i].s},
                {"action",   QJsonObject{
                    {"type",  "desktop_entry"},
                    {"id",    e.id},
                }},
            });
        }
    }
    emit resultsReady(id(), generation, rows);
}

} // namespace aurum::spotlight
