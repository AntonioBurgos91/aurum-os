#pragma once

#include <QJsonArray>
#include <QObject>
#include <QString>

namespace aurum::spotlight {

// One result row delivered by a plugin to the aggregator.
// Kept as a flat QJsonObject in the wire protocol so QML can render it
// directly without intermediate marshaling.
//   title    — primary text
//   subtitle — secondary, dimmed
//   action   — opaque payload the aggregator consumes when the user activates
//              the row (e.g. {"type":"exec","cmd":"ghostty"})
//   icon     — XDG icon name OR empty
//   score    — 0..1; higher ranks first within the plugin's category

// Each plugin runs INSIDE the aurum-spotlight process. We deliberately did not
// pick out-of-process plugins for Phase 3 — process spawn latency would
// dominate the perceived "Spotlight feels instant" budget.
class SpotlightPlugin : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    ~SpotlightPlugin() override = default;

    // Stable identifier used in UI (category headers, debug logs).
    virtual QString id() const = 0;
    virtual QString displayName() const = 0;

    // Lower-priority plugins render lower on the page when their categories
    // are shown simultaneously. 0 = top.
    virtual int priority() const = 0;

    // Trigger a query. Plugins are encouraged to return synchronously when
    // cheap (apps, calculator) and via deferred signal when not (files, web).
    // `generation` is a strictly increasing counter; plugins MUST echo it
    // when emitting results so the aggregator can discard stale responses.
    virtual void search(const QString& query, int generation) = 0;

signals:
    void resultsReady(QString pluginId, int generation, QJsonArray rows);
};

} // namespace aurum::spotlight
