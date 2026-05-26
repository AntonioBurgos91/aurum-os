#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

namespace aurum::settings {

// Manages user-scope Python virtual environments through `uv`.
// We deliberately stay in user scope (no privileged ops): system-wide venvs
// like /opt/aurum-dl-venv are listed read-only as "Locked".
class VenvManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList venvs READ venvs NOTIFY venvsChanged)
    Q_PROPERTY(QStringList availablePythons READ availablePythons CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit VenvManager(QObject* parent = nullptr);

    QVariantList venvs() const {
        return m_venvs;
    }
    QStringList availablePythons() const;
    bool busy() const {
        return m_busy;
    }
    QString lastError() const {
        return m_lastError;
    }

    Q_INVOKABLE void refresh();

    // path: absolute target; pythonSpec: e.g. "3.12", "3.13", "cpython-3.11".
    // Returns false synchronously on bad input or if uv is missing.
    Q_INVOKABLE bool createVenv(const QString& path, const QString& pythonSpec);

    // Deletes the directory tree at `path` after refusing system-locked roots.
    Q_INVOKABLE bool deleteVenv(const QString& path);

signals:
    void venvsChanged();
    void busyChanged();
    void lastErrorChanged();

private:
    void setBusy(bool b);
    void setError(const QString& e);
    void scan();
    QStringList scan_roots() const;

    QVariantList m_venvs;
    bool m_busy = false;
    QString m_lastError;
};

}  // namespace aurum::settings
