#pragma once

#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusPendingCallWatcher>

#include "plugin.h"

namespace aurum::spotlight {

// Queries the aurum-spotlight-indexer daemon over D-Bus. The call is async so
// the UI stays responsive on a cold cache; results arrive via resultsReady.
class FilesPlugin : public SpotlightPlugin {
    Q_OBJECT
public:
    explicit FilesPlugin(QObject* parent = nullptr);

    QString id() const override          { return "files"; }
    QString displayName() const override { return "Files"; }
    int     priority() const override    { return 1; }
    void    search(const QString& query, int generation) override;

private slots:
    void onPendingFinished(QDBusPendingCallWatcher* w);

private:
    QDBusInterface* m_iface = nullptr;
    int m_active_generation = -1;
};

} // namespace aurum::spotlight
