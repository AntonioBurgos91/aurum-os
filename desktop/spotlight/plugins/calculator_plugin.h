#pragma once

#include <QJSEngine>

#include "plugin.h"

namespace aurum::spotlight {

// Treats the query as a math expression and evaluates it with QJSEngine. We
// deliberately restrict the evaluation surface (no globals, no JSON, no fetch)
// so a Spotlight query can't be turned into a JS shell. The plugin only emits
// a row when the query is plausibly an expression (digits + operators).
class CalculatorPlugin : public SpotlightPlugin {
    Q_OBJECT
public:
    explicit CalculatorPlugin(QObject* parent = nullptr);

    QString id() const override {
        return "calculator";
    }
    QString displayName() const override {
        return "Calculator";
    }
    int priority() const override {
        return 2;
    }
    void search(const QString& query, int generation) override;

private:
    QJSEngine m_engine;
};

}  // namespace aurum::spotlight
