#include "profile_client.h"

#include <QByteArray>
#include <QDebug>
#include <QFile>
#include <QTextStream>

namespace aurum {

namespace {

// Trim ASCII whitespace + a single matched pair of quotes (either ' or ").
// We don't try to be a full bash parser — the writer (00-detect-profile.sh)
// only emits two simple shapes per line:
//   KEY=value
//   KEY="some value with spaces"
// Anything fancier would mean the user hand-edited the file, which we tell
// them not to do (comment header in profile.conf.template).
QString unquote(QString s) {
    s = s.trimmed();
    if (s.size() >= 2) {
        const QChar a = s.front(), b = s.back();
        if ((a == '"' && b == '"') || (a == '\'' && b == '\'')) {
            s = s.mid(1, s.size() - 2);
        }
    }
    return s;
}

}  // namespace

ProfileClient& ProfileClient::instance() {
    // Meyers singleton — thread-safe init since C++11. The destructor never
    // fires in the typical Qt app lifecycle (main returns and the process
    // exits) which is exactly what we want for a config snapshot.
    static ProfileClient inst;
    return inst;
}

ProfileClient::ProfileClient() {
    // Allow tests / dev runs to point at a fixture without touching /etc.
    // Production deploys leave the env unset and read the real path.
    m_path = qEnvironmentVariable("AURUM_PROFILE_CONF", "/etc/aurum/profile.conf");
    parse(m_path);
}

void ProfileClient::parse(const QString& path) {
    std::lock_guard<std::mutex> g(m_mu);
    m_kv.clear();

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning().noquote() << "[profile-client] cannot read" << path
                             << "→ falling back to all-defaults (lite-ish)";
        // Seed a minimal map so callers don't return empty strings out of
        // nowhere; the UI then shows "lite" and the launchers degrade to
        // their safest path.
        m_kv["AURUM_PROFILE"] = "lite";
        m_kv["AURUM_VRAM_MB"] = "0";
        m_kv["AURUM_RAM_GB"] = "0";
        m_kv["AURUM_GPU_NAME"] = "none";
        m_kv["AURUM_HAS_CUDA"] = "0";
        return;
    }

    QTextStream in(&f);
    while (!in.atEnd()) {
        QString line = in.readLine();
        const auto trimmed = line.trimmed();
        if (trimmed.isEmpty() || trimmed.startsWith('#')) continue;

        const int eq = line.indexOf('=');
        if (eq <= 0) continue;  // no key, or "=value" with empty key

        const QString key = line.left(eq).trimmed();
        const QString val = unquote(line.mid(eq + 1));
        if (key.isEmpty()) continue;
        m_kv.insert(key, val);
    }
}

QString ProfileClient::profile() const {
    std::lock_guard<std::mutex> g(m_mu);
    return m_kv.value("AURUM_PROFILE", "lite");
}

int ProfileClient::vramMb() const {
    std::lock_guard<std::mutex> g(m_mu);
    return m_kv.value("AURUM_VRAM_MB", "0").toInt();
}

int ProfileClient::ramGb() const {
    std::lock_guard<std::mutex> g(m_mu);
    return m_kv.value("AURUM_RAM_GB", "0").toInt();
}

QString ProfileClient::gpuName() const {
    std::lock_guard<std::mutex> g(m_mu);
    return m_kv.value("AURUM_GPU_NAME", "none");
}

bool ProfileClient::hasCuda() const {
    std::lock_guard<std::mutex> g(m_mu);
    // The conf writes "1" / "0"; treat anything truthy-ish as true so a
    // hand-edited "yes"/"true" still works.
    const auto v = m_kv.value("AURUM_HAS_CUDA", "0").trimmed().toLower();
    return v == "1" || v == "true" || v == "yes";
}

QString ProfileClient::get(const QString& key, const QString& fallback) const {
    std::lock_guard<std::mutex> g(m_mu);
    return m_kv.value(key, fallback);
}

void ProfileClient::reload() {
    parse(m_path);
}

}  // namespace aurum
