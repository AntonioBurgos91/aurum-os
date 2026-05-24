#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

namespace aurum::settings {

// Reads the CUDA layout under /usr/local/cuda* and lets the user pick which
// toolkit is the "active" one. AurumOS doesn't try to manage CUDA via apt
// pinning — too brittle. Instead we manage `/usr/local/cuda` as a symlink
// (system-wide, requires polkit) AND a per-user override file at
// `~/.config/aurum/cuda.env` consumed by /etc/profile.d/aurum-dl.sh.
//
// User scope is the default action (no auth prompt). System scope is what
// installers and the dl-venv pick up.
class CudaManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList toolkits READ toolkits NOTIFY toolkitsChanged)
    Q_PROPERTY(QString systemActive READ systemActive NOTIFY toolkitsChanged)
    Q_PROPERTY(QString userActive   READ userActive   NOTIFY toolkitsChanged)
    Q_PROPERTY(QString driverVersion READ driverVersion NOTIFY toolkitsChanged)

public:
    explicit CudaManager(QObject* parent = nullptr);

    // [ { version, path, isSystemActive, isUserActive } ]
    QVariantList toolkits() const     { return m_toolkits; }
    QString systemActive() const      { return m_systemActive; }
    QString userActive()   const      { return m_userActive; }
    QString driverVersion() const     { return m_driverVersion; }

    Q_INVOKABLE void refresh();

    // Persist a user-scope CUDA choice (writes ~/.config/aurum/cuda.env).
    Q_INVOKABLE bool setUserActive(const QString& version);

    // Attempt to rewire /usr/local/cuda → /usr/local/cuda-<version>.
    // Requires root via pkexec; returns false if the helper failed.
    Q_INVOKABLE bool setSystemActive(const QString& version);

signals:
    void toolkitsChanged();

private:
    void scan();

    QVariantList m_toolkits;
    QString      m_systemActive;
    QString      m_userActive;
    QString      m_driverVersion;
};

} // namespace aurum::settings
