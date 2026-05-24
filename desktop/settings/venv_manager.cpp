#include "venv_manager.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QVariantMap>

namespace aurum::settings {

namespace {

// Roots a venv directory is recognized at — every directory matching
// "<root>/<name>/bin/python" qualifies as a venv. Order is cosmetic only.
QStringList default_roots() {
    QStringList roots;
    roots << "/opt";
    roots << QDir::homePath() + "/venvs";
    roots << QDir::homePath() + "/.virtualenvs";
    roots << QDir::homePath() + "/.local/share/aurum/venvs";
    return roots;
}

bool is_system_locked(const QString& path) {
    // Reject things under /opt and /usr from delete operations.
    return path.startsWith("/opt/") || path.startsWith("/usr/");
}

QString uv_binary() {
    static const QStringList candidates = {
        "/usr/local/bin/uv", "/usr/bin/uv",
        QDir::homePath() + "/.local/bin/uv",
    };
    for (const auto& c : candidates) if (QFile::exists(c)) return c;
    return "uv"; // last resort: rely on PATH
}

QString resolve_python_version(const QString& venv_dir) {
    // `bin/python --version` is the canonical way; if Python is missing/broken
    // we surface "unknown" rather than crashing the panel.
    QProcess p;
    p.start(venv_dir + "/bin/python", {"--version"});
    if (!p.waitForFinished(800)) return "unknown";
    auto out = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
    if (out.isEmpty()) out = QString::fromUtf8(p.readAllStandardError()).trimmed();
    static const QRegularExpression re(R"(Python\s+([\d.]+))");
    const auto m = re.match(out);
    return m.hasMatch() ? m.captured(1) : "unknown";
}

quint64 directory_size_bytes(const QString& root) {
    // Rough estimate; we don't try to follow symlinks (uv venvs use hardlinks
    // for the python binary but copies for site-packages).
    QDirIterator it(root, QDirIterator::Subdirectories);
    quint64 sum = 0;
    while (it.hasNext()) {
        QFileInfo fi(it.next());
        if (fi.isFile() && !fi.isSymLink()) sum += fi.size();
    }
    return sum;
}

} // namespace

VenvManager::VenvManager(QObject* parent) : QObject(parent) {
    scan();
}

QStringList VenvManager::scan_roots() const { return default_roots(); }

QStringList VenvManager::availablePythons() const {
    // We could call `uv python list` here but parsing its output adds friction
    // for marginal value. Hardcode the AurumOS-supported Pythons; uv will
    // download whichever the user picks on demand.
    return {"3.13", "3.12", "3.11", "3.10"};
}

void VenvManager::refresh() { scan(); }

void VenvManager::scan() {
    m_venvs.clear();
    for (const auto& root : scan_roots()) {
        QDir dir(root);
        if (!dir.exists()) continue;
        const auto entries = dir.entryInfoList(
            QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const auto& fi : entries) {
            const QString candidate = fi.absoluteFilePath();
            if (!QFile::exists(candidate + "/bin/python")) continue;

            m_venvs << QVariantMap{
                {"name",        fi.fileName()},
                {"path",        candidate},
                {"pythonVer",   resolve_python_version(candidate)},
                {"sizeMB",      static_cast<qint64>(directory_size_bytes(candidate) / (1024*1024))},
                {"locked",      is_system_locked(candidate)},
                {"createdAt",   fi.birthTime().toString(Qt::ISODate)},
            };
        }
    }
    emit venvsChanged();
}

void VenvManager::setBusy(bool b) {
    if (m_busy == b) return;
    m_busy = b;
    emit busyChanged();
}

void VenvManager::setError(const QString& e) {
    if (m_lastError == e) return;
    m_lastError = e;
    emit lastErrorChanged();
}

bool VenvManager::createVenv(const QString& path, const QString& pythonSpec) {
    if (path.isEmpty() || pythonSpec.isEmpty()) {
        setError("path and python version are required");
        return false;
    }
    if (QFileInfo::exists(path)) {
        setError("target already exists: " + path);
        return false;
    }
    const auto uv = uv_binary();
    setBusy(true);
    setError({});
    QProcess p;
    // uv will download the requested CPython if not already present.
    p.start(uv, {"venv", "--python", pythonSpec, path});
    if (!p.waitForFinished(120'000)) {
        setError("uv venv timed out");
        setBusy(false);
        return false;
    }
    if (p.exitCode() != 0) {
        setError(QString::fromUtf8(p.readAllStandardError()).trimmed());
        setBusy(false);
        return false;
    }
    setBusy(false);
    scan();
    return true;
}

bool VenvManager::deleteVenv(const QString& path) {
    if (is_system_locked(path)) {
        setError("refusing to delete system-locked venv: " + path);
        return false;
    }
    if (!QFile::exists(path + "/bin/python")) {
        setError("not a venv: " + path);
        return false;
    }
    if (!QDir(path).removeRecursively()) {
        setError("removeRecursively failed for " + path);
        return false;
    }
    scan();
    return true;
}

} // namespace aurum::settings
