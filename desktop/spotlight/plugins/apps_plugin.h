#pragma once

#include "core_services.h"
#include "plugin.h"

namespace aurum::spotlight {

// Fuzzy-matches the query against installed .desktop entry names + ids.
// Cheap: the desktop scanner runs once at construction and we re-rank a
// QVector<DesktopEntry> on every keystroke.
class AppsPlugin : public SpotlightPlugin {
    Q_OBJECT
public:
    explicit AppsPlugin(QObject* parent = nullptr);

    QString id() const override {
        return "apps";
    }
    QString displayName() const override {
        return "Applications";
    }
    int priority() const override {
        return 0;
    }
    void search(const QString& query, int generation) override;

private:
    QVector<aurum::core::DesktopEntry> m_entries;
};

}  // namespace aurum::spotlight
