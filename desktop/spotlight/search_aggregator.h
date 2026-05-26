#pragma once

#include <QHash>
#include <QJsonArray>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVector>

#include "plugins/plugin.h"

namespace aurum::spotlight {

// Owns every plugin, fans queries out to them, and merges their responses
// into a single QML-visible model: an ordered list of category groups, each
// with up to N rows. Stale responses (older generation than current) are
// dropped on arrival.
class SearchAggregator : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList groups READ groups NOTIFY groupsChanged)

public:
    explicit SearchAggregator(QObject* parent = nullptr);

    void addPlugin(SpotlightPlugin* p);

    QVariantList groups() const {
        return m_groups_cached;
    }

    // QML calls this on every text change. Generation bumps so stale plugin
    // responses are ignored once they arrive.
    Q_INVOKABLE void setQuery(const QString& q);

    // Executes the row's `action` object. Returns true if the action was
    // dispatched successfully.
    Q_INVOKABLE bool activate(const QVariantMap& action);

signals:
    void groupsChanged();

private slots:
    void onPluginResults(QString pluginId, int generation, QJsonArray rows);

private:
    void rebuildGroups();

    QVector<SpotlightPlugin*> m_plugins;
    QHash<QString, QJsonArray> m_results;  // pluginId → latest rows
    QVariantList m_groups_cached;
    int m_generation = 0;
};

}  // namespace aurum::spotlight
