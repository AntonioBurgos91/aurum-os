#include "calculator_plugin.h"

#include <QJSValue>
#include <QJsonArray>
#include <QJsonObject>
#include <QRegularExpression>

namespace aurum::spotlight {

namespace {

// Accept queries that look like a math expression: must contain at least one
// digit, and may use the operator/grouping/whitespace/digit/`.` charset only.
// This filter avoids triggering the calculator on every word the user types.
bool looksLikeMath(const QString& q) {
    static const QRegularExpression mathy(R"(^[\s\d+\-*/().,%^]+$)");
    if (!mathy.match(q).hasMatch()) return false;
    static const QRegularExpression hasDigit(R"(\d)");
    static const QRegularExpression hasOp(R"([+\-*/^%])");
    return hasDigit.match(q).hasMatch() && hasOp.match(q).hasMatch();
}

// Re-map "^" to "**" so the user can type natural exponent syntax.
QString normalize(QString q) {
    return q.replace('^', "**");
}

}  // namespace

CalculatorPlugin::CalculatorPlugin(QObject* parent) : SpotlightPlugin(parent) {}

void CalculatorPlugin::search(const QString& query, int generation) {
    QJsonArray rows;
    const QString q = query.trimmed();
    if (!looksLikeMath(q)) {
        emit resultsReady(id(), generation, rows);
        return;
    }
    const QString expr = normalize(q);
    const QJSValue result = m_engine.evaluate("(" + expr + ")");
    if (result.isError() || !result.isNumber()) {
        emit resultsReady(id(), generation, rows);
        return;
    }
    const double value = result.toNumber();
    rows.append(QJsonObject{
        {"title", QString::number(value, 'g', 12)},
        {"subtitle", q + "  =  " + QString::number(value, 'g', 12)},
        {"icon", "accessories-calculator"},
        {"score", 1.0},
        {"action",
         QJsonObject{
             {"type", "copy"},
             {"value", QString::number(value, 'g', 12)},
         }},
    });
    emit resultsReady(id(), generation, rows);
}

}  // namespace aurum::spotlight
