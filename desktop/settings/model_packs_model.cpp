#include "model_packs_model.h"

#include <QByteArray>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QStringList>
#include <QTextStream>

namespace aurum::settings {

namespace {

// --- Tiny YAML reader --------------------------------------------------------
// We deliberately avoid pulling in a YAML dependency for the Settings binary.
// The manifests Agent I writes are intentionally flat (top-level scalar keys
// plus a `models:` list we don't actually need on the GUI side — only the CLI
// consumes it). This reader handles:
//   - "key: value"  (string / int)
//   - "key: \"quoted value\""
//   - "# comment" lines and blank lines
// It IGNORES nested blocks (any line indented > 0) which is exactly the
// behavior we want — the `models:` subtree is opaque to us.
QHash<QString, QString> parse_flat_yaml(const QString& path) {
    QHash<QString, QString> out;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return out;

    QTextStream in(&f);
    while (!in.atEnd()) {
        const QString raw = in.readLine();
        // Skip blank lines / comments.
        const QString trimmed = raw.trimmed();
        if (trimmed.isEmpty() || trimmed.startsWith('#')) continue;
        // Skip indented (nested) lines — only top-level scalar keys matter.
        if (raw.startsWith(' ') || raw.startsWith('\t')) continue;

        const int colon = trimmed.indexOf(':');
        if (colon <= 0) continue;
        QString key = trimmed.left(colon).trimmed();
        QString value = trimmed.mid(colon + 1).trimmed();

        // Strip an inline "# comment" tail unless it sits inside quotes.
        if (!value.startsWith('"') && !value.startsWith('\'')) {
            const int hash = value.indexOf('#');
            if (hash >= 0) value = value.left(hash).trimmed();
        }
        // Unquote.
        if (value.size() >= 2 && ((value.startsWith('"') && value.endsWith('"')) ||
                                  (value.startsWith('\'') && value.endsWith('\'')))) {
            value = value.mid(1, value.size() - 2);
        }
        // An empty value typically means "block follows" — we don't use it.
        if (value.isEmpty()) continue;
        out.insert(key, value);
    }
    return out;
}

QString read_profile_conf(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return {};
    static const QRegularExpression re(R"(^\s*AURUM_PROFILE\s*=\s*(\w+))");
    while (!f.atEnd()) {
        const auto line = QString::fromUtf8(f.readLine());
        const auto m = re.match(line);
        if (m.hasMatch()) return m.captured(1);
    }
    return {};
}

QString resolve_cli_binary() {
    static const QStringList candidates = {
        "/usr/local/bin/aurum-model-pack",
        "/usr/bin/aurum-model-pack",
        QDir::homePath() + "/.local/bin/aurum-model-pack",
    };
    for (const auto& c : candidates)
        if (QFile::exists(c)) return c;
    return "aurum-model-pack";  // fall back to $PATH
}

quint64 directory_size_bytes(const QString& root) {
    QDirIterator it(root, QDirIterator::Subdirectories);
    quint64 sum = 0;
    while (it.hasNext()) {
        QFileInfo fi(it.next());
        if (fi.isFile() && !fi.isSymLink()) sum += fi.size();
    }
    return sum;
}

}  // namespace

// --- ctor / dtor -------------------------------------------------------------

ModelPacksModel::ModelPacksModel(QObject* parent) : QAbstractListModel(parent) {
    detectProfile();
    scanManifests();
}

ModelPacksModel::~ModelPacksModel() {
    // QProcess children are auto-deleted via QObject parent ownership.
}

// --- QAbstractListModel ------------------------------------------------------

int ModelPacksModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : m_packs.size();
}

QVariant ModelPacksModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_packs.size()) return {};
    const auto& p = m_packs.at(index.row());
    switch (role) {
        case IdRole:
            return p.id;
        case TitleRole:
            return p.title;
        case DescriptionRole:
            return p.description;
        case SizeBytesRole:
            return QVariant::fromValue(p.sizeBytes);
        case SizeHumanRole:
            return humanSize(p.sizeBytes);
        case MinProfileRole:
            return p.minProfile;
        case DocsUrlRole:
            return p.docsUrl;
        case StateRole:
            return p.state;
        case ProgressRole:
            return p.progress;
        case LastErrorRole:
            return p.lastError;
        case MeetsProfileRole:
            return meetsProfile(p.minProfile);
        default:
            return {};
    }
}

QHash<int, QByteArray> ModelPacksModel::roleNames() const {
    return {
        {IdRole, "packId"},
        {TitleRole, "title"},
        {DescriptionRole, "description"},
        {SizeBytesRole, "sizeBytes"},
        {SizeHumanRole, "sizeHuman"},
        {MinProfileRole, "minProfile"},
        {DocsUrlRole, "docsUrl"},
        {StateRole, "state"},
        {ProgressRole, "progress"},
        {LastErrorRole, "lastError"},
        {MeetsProfileRole, "meetsProfile"},
    };
}

// --- Helpers -----------------------------------------------------------------

int ModelPacksModel::indexOf(const QString& packId) const {
    for (int i = 0; i < m_packs.size(); ++i)
        if (m_packs.at(i).id == packId) return i;
    return -1;
}

void ModelPacksModel::emitDataChanged(int row) {
    if (row < 0 || row >= m_packs.size()) return;
    const auto idx = index(row, 0);
    emit dataChanged(idx, idx);
}

int ModelPacksModel::profileRank(const QString& profile) {
    // Higher = more capable hardware.
    if (profile == "lite") return 0;
    if (profile == "standard") return 1;
    if (profile == "pro") return 2;
    if (profile == "workstation") return 3;
    // Unknown profile string defaults to "standard" for the comparison so a
    // manifest with a typo doesn't lock a user out of installing.
    return 1;
}

bool ModelPacksModel::meetsProfile(const QString& minProfile) const {
    return profileRank(m_currentProfile) >= profileRank(minProfile);
}

QString ModelPacksModel::humanSize(qint64 bytes) const {
    if (bytes < 0) return "—";
    const double kb = 1024.0;
    const double mb = kb * 1024.0;
    const double gb = mb * 1024.0;
    const double tb = gb * 1024.0;
    if (bytes >= tb) return QString::number(bytes / tb, 'f', 1) + " TB";
    if (bytes >= gb) return QString::number(bytes / gb, 'f', 1) + " GB";
    if (bytes >= mb) return QString::number(bytes / mb, 'f', 0) + " MB";
    if (bytes >= kb) return QString::number(bytes / kb, 'f', 0) + " KB";
    return QString::number(bytes) + " B";
}

QString ModelPacksModel::defaultCachePath() {
    const QString xdg = qEnvironmentVariable("XDG_CACHE_HOME", QDir::homePath() + "/.cache");
    return xdg + "/aurum/models";
}

QString ModelPacksModel::cachePath() const {
    return defaultCachePath();
}

void ModelPacksModel::detectProfile() {
    QString p = read_profile_conf(kProfileConf);
    if (p.isEmpty()) p = qEnvironmentVariable("AURUM_PROFILE");
    if (p.isEmpty()) p = "standard";  // safe default
    if (p != m_currentProfile) {
        m_currentProfile = p;
        emit currentProfileChanged();
    }
}

// --- Manifest scanning -------------------------------------------------------

void ModelPacksModel::scanManifests() {
    beginResetModel();
    // Preserve existing transient state (installing / progress) across a
    // refresh so a manual rescan doesn't snap the progress bar back to 0.
    QHash<QString, QPair<QString, int>> prevState;  // id -> (state, progress)
    for (const auto& pk : m_packs) prevState.insert(pk.id, {pk.state, pk.progress});

    m_packs.clear();
    QDir dir(kManifestDir);
    if (dir.exists()) {
        const auto entries = dir.entryInfoList(QStringList{"*.yaml", "*.yml"},
                                               QDir::Files | QDir::Readable, QDir::Name);
        for (const auto& fi : entries) {
            const auto kv = parse_flat_yaml(fi.absoluteFilePath());
            if (kv.isEmpty()) continue;
            ModelPack p;
            p.id = kv.value("id", fi.baseName());
            p.title = kv.value("title", p.id);
            p.description = kv.value("description");
            p.minProfile = kv.value("min_profile", "standard");
            p.docsUrl = kv.value("docs_url");
            bool ok = false;
            const qint64 sb = kv.value("size_bytes").toLongLong(&ok);
            p.sizeBytes = ok ? sb : 0;
            // Re-apply the prior transient state if this pack already existed.
            if (prevState.contains(p.id)) {
                const auto prev = prevState.value(p.id);
                p.state = prev.first;
                p.progress = prev.second;
            }
            // If the CLI is available, we could ask it whether the pack is
            // currently installed — but to keep the GUI responsive we leave
            // that to the optional `STATE:<id>:<state>` line the CLI may emit
            // on subsequent install/remove calls. The default is
            // "not_installed", which is correct for the freshly-scanned case.
            m_packs.push_back(std::move(p));
        }
    }
    endResetModel();
    emit countChanged();
}

void ModelPacksModel::refresh() {
    detectProfile();
    scanManifests();
}

// --- Install / remove --------------------------------------------------------

void ModelPacksModel::install(const QString& packId) {
    const int row = indexOf(packId);
    if (row < 0) return;
    if (m_jobs.contains(packId)) return;  // already running

    auto& pack = m_packs[row];
    pack.state = "installing";
    pack.progress = 0;
    pack.lastError.clear();
    emitDataChanged(row);
    emit packStateChanged(packId);

    auto* proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    // Inherit the user environment — the CLI may need $HOME, $XDG_CACHE_HOME,
    // proxy settings, $HF_TOKEN, etc.
    connect(proc, &QProcess::readyRead, this, &ModelPacksModel::onProcReadyRead);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            &ModelPacksModel::onProcFinished);

    RunningJob job{proc, {}, "install"};
    m_jobs.insert(packId, job);
    proc->setProperty("packId", packId);
    proc->start(resolve_cli_binary(), {"install", packId});
}

void ModelPacksModel::remove(const QString& packId) {
    const int row = indexOf(packId);
    if (row < 0) return;
    if (m_jobs.contains(packId)) return;

    // Remove is fast — we still run it as a tracked QProcess so the UI can
    // show a brief spinner state and the same progress/done lines apply.
    auto& pack = m_packs[row];
    pack.state = "installing";  // reuse "in flight" state
    pack.progress = 0;
    pack.lastError.clear();
    emitDataChanged(row);
    emit packStateChanged(packId);

    auto* proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(proc, &QProcess::readyRead, this, &ModelPacksModel::onProcReadyRead);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            &ModelPacksModel::onProcFinished);

    RunningJob job{proc, {}, "remove"};
    m_jobs.insert(packId, job);
    proc->setProperty("packId", packId);
    proc->start(resolve_cli_binary(), {"remove", packId});
}

void ModelPacksModel::onProcReadyRead() {
    auto* proc = qobject_cast<QProcess*>(sender());
    if (!proc) return;
    const QString packId = proc->property("packId").toString();
    auto it = m_jobs.find(packId);
    if (it == m_jobs.end()) return;

    it->buf.append(proc->readAll());
    // Split on newlines, leave the trailing partial chunk in the buffer.
    int nl;
    while ((nl = it->buf.indexOf('\n')) != -1) {
        const QByteArray line = it->buf.left(nl);
        it->buf.remove(0, nl + 1);
        handleProgressLine(line);
    }
}

void ModelPacksModel::handleProgressLine(const QByteArray& raw) {
    const QString line = QString::fromUtf8(raw).trimmed();
    if (line.isEmpty()) return;

    // PROGRESS:<id>:<percent>
    if (line.startsWith("PROGRESS:")) {
        const auto parts = line.mid(9).split(':');
        if (parts.size() < 2) return;
        const QString id = parts.at(0);
        bool ok = false;
        int pct = parts.at(1).toInt(&ok);
        if (!ok) return;
        pct = qBound(0, pct, 100);
        const int row = indexOf(id);
        if (row < 0) return;
        m_packs[row].progress = pct;
        emitDataChanged(row);
        emit installProgress(id, pct);
        return;
    }
    // DONE:<id>
    if (line.startsWith("DONE:")) {
        const QString id = line.mid(5).trimmed();
        const int row = indexOf(id);
        if (row < 0) return;
        // The terminal state depends on which op was running — set in
        // onProcFinished based on the job's op field. Here we just lock
        // progress to 100 so the bar reads full at the moment of completion.
        m_packs[row].progress = 100;
        emitDataChanged(row);
        return;
    }
    // ERROR:<id>:<message>
    if (line.startsWith("ERROR:")) {
        const auto parts = line.mid(6).split(':');
        if (parts.isEmpty()) return;
        const QString id = parts.at(0);
        const QString msg = parts.mid(1).join(':');
        const int row = indexOf(id);
        if (row < 0) return;
        m_packs[row].lastError = msg;
        emitDataChanged(row);
        return;
    }
    // STAGE:<id>:<text> — informational only; we don't surface it yet but it's
    // part of the documented protocol so Agent I can emit it freely.
    if (line.startsWith("STAGE:")) {
        qInfo().noquote() << "[model-packs]" << line;
        return;
    }
    // Anything else: log for debug.
    qInfo().noquote() << "[model-packs]" << line;
}

void ModelPacksModel::onProcFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    auto* proc = qobject_cast<QProcess*>(sender());
    if (!proc) return;
    const QString packId = proc->property("packId").toString();
    auto it = m_jobs.find(packId);
    if (it == m_jobs.end()) {
        proc->deleteLater();
        return;
    }
    // Flush any trailing partial line that didn't end in \n.
    if (!it->buf.isEmpty()) {
        handleProgressLine(it->buf);
        it->buf.clear();
    }

    const bool ok = (exitStatus == QProcess::NormalExit && exitCode == 0);
    const QString op = it->op;
    const int row = indexOf(packId);
    if (row >= 0) {
        auto& pack = m_packs[row];
        if (!ok) {
            pack.state = "error";
            if (pack.lastError.isEmpty())
                pack.lastError = QString("aurum-model-pack exited with code %1").arg(exitCode);
        } else if (op == "install") {
            pack.state = "installed";
            pack.progress = 100;
        } else {  // remove
            pack.state = "not_installed";
            pack.progress = 0;
        }
        emitDataChanged(row);
        emit packStateChanged(packId);
        emit installFinished(packId, ok, pack.lastError);
    }
    m_jobs.remove(packId);
    proc->deleteLater();
}

// --- Cache management --------------------------------------------------------

qint64 ModelPacksModel::cacheSize() {
    // Try the CLI first (it knows about deduplicated blobs across packs);
    // fall back to a directory walk if the CLI isn't installed.
    QProcess p;
    p.start(resolve_cli_binary(), {"cache-size", "--bytes"});
    if (p.waitForFinished(2000) && p.exitCode() == 0) {
        const auto out = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
        bool ok = false;
        const qint64 n = out.toLongLong(&ok);
        if (ok) return n;
    }
    const QString path = defaultCachePath();
    if (!QDir(path).exists()) return 0;
    return static_cast<qint64>(directory_size_bytes(path));
}

void ModelPacksModel::clearCache() {
    QProcess p;
    p.start(resolve_cli_binary(), {"cache-clear"});
    if (!p.waitForFinished(60'000)) {
        qWarning() << "[model-packs] cache-clear timed out";
        return;
    }
    // Reset transient state for every pack (everything is gone from disk).
    for (int i = 0; i < m_packs.size(); ++i) {
        m_packs[i].state = "not_installed";
        m_packs[i].progress = 0;
        m_packs[i].lastError.clear();
        emitDataChanged(i);
    }
}

}  // namespace aurum::settings
