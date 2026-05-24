#include "mlops_config.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QTextStream>

namespace aurum::settings {

namespace {

QString config_path() {
    return qEnvironmentVariable("XDG_CONFIG_HOME",
                                QDir::homePath() + "/.config")
         + "/aurum/mlops.toml";
}

// Tiny TOML reader covering only what mlops.toml uses:
//   [section]
//   key = "value"
// Comments and blank lines pass-through. Unquoted values are read literally.
void read_kv(const QString& path,
             QString& mlflowUri, QString& mlflowExp,
             QString& wandbKey,  QString& wandbEntity) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return;
    QTextStream in(&f);

    QString section;
    static const QRegularExpression header(R"(^\s*\[\s*([\w-]+)\s*\])");
    // Custom delimiter (RX) so the literal can contain `)"` without closing the
    // raw string early — the kv regex needs `)"` inside the negated set.
    static const QRegularExpression kv    (R"RX(^\s*([\w_]+)\s*=\s*"?([^"]*)"?\s*$)RX");

    while (!in.atEnd()) {
        const auto line = in.readLine();
        if (line.trimmed().isEmpty() || line.trimmed().startsWith('#')) continue;
        auto h = header.match(line);
        if (h.hasMatch()) { section = h.captured(1); continue; }
        auto m = kv.match(line);
        if (!m.hasMatch()) continue;
        const auto k = m.captured(1);
        const auto v = m.captured(2);
        if (section == "mlflow") {
            if      (k == "tracking_uri") mlflowUri = v;
            else if (k == "experiment")   mlflowExp = v;
        } else if (section == "wandb") {
            if      (k == "api_key")      wandbKey = v;
            else if (k == "entity")       wandbEntity = v;
        }
    }
}

} // namespace

MlopsConfig::MlopsConfig(QObject* parent) : QObject(parent) {
    load();
}

void MlopsConfig::load() {
    m_mlflowTrackingUri = "http://localhost:5000";
    m_mlflowExperiment  = "Default";
    m_wandbApiKey.clear();
    m_wandbEntity.clear();
    read_kv(config_path(),
            m_mlflowTrackingUri, m_mlflowExperiment,
            m_wandbApiKey, m_wandbEntity);
    emit changed();
}

bool MlopsConfig::reload() { load(); return true; }

void MlopsConfig::setMlflowTrackingUri(const QString& v) {
    if (v == m_mlflowTrackingUri) return;
    m_mlflowTrackingUri = v; emit changed();
}
void MlopsConfig::setMlflowExperiment(const QString& v) {
    if (v == m_mlflowExperiment) return;
    m_mlflowExperiment = v; emit changed();
}
void MlopsConfig::setWandbApiKey(const QString& v) {
    if (v == m_wandbApiKey) return;
    m_wandbApiKey = v; emit changed();
}
void MlopsConfig::setWandbEntity(const QString& v) {
    if (v == m_wandbEntity) return;
    m_wandbEntity = v; emit changed();
}

bool MlopsConfig::save() {
    const auto path = config_path();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return false;
    QTextStream out(&f);
    out << "# Auto-managed by aurum-settings. Hand edits are preserved on the\n"
        << "# next save only if the key layout matches; comments are not.\n\n"
        << "[mlflow]\n"
        << "tracking_uri = \"" << m_mlflowTrackingUri << "\"\n"
        << "experiment   = \"" << m_mlflowExperiment  << "\"\n\n"
        << "[wandb]\n"
        << "api_key = \"" << m_wandbApiKey << "\"\n"
        << "entity  = \"" << m_wandbEntity << "\"\n";
    return true;
}

} // namespace aurum::settings
