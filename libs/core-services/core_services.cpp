#include "core_services.h"

#include <QByteArray>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QString>
#include <QStringList>
#include <QTextStream>
#include <map>
#include <memory>
#include <mutex>

namespace aurum::core {

namespace {

// Max wall-time we will wait for any one `hyprctl` invocation. Hyprland is
// fast (sub-millisecond on idle) so 800ms is generous; we'd rather degrade
// to "spawn anyway" than block the UI thread on a wedged IPC.
constexpr int kHyprctlTimeoutMs = 800;

// Sources searched in XDG order: $XDG_DATA_HOME, then $XDG_DATA_DIRS, then the
// hardcoded fallback. First hit wins on duplicate ids.
QStringList desktop_search_paths() {
    QStringList roots;

    auto home = qEnvironmentVariable("XDG_DATA_HOME");
    if (home.isEmpty()) home = QDir::homePath() + "/.local/share";
    roots << home + "/applications";

    auto dirs = qEnvironmentVariable("XDG_DATA_DIRS", "/usr/local/share:/usr/share");
    for (const auto& d : dirs.split(':', Qt::SkipEmptyParts)) roots << d + "/applications";

    // Flatpak exports go through this path even without XDG_DATA_DIRS munging.
    roots << "/var/lib/flatpak/exports/share/applications";

    return roots;
}

DesktopEntry parse_one(const QString& path) {
    // .desktop files are UTF-8 by spec; Qt6's QSettings INI default is UTF-8
    // so we don't need (and Qt6 has removed) setIniCodec.
    QSettings ini(path, QSettings::IniFormat);
    ini.beginGroup("Desktop Entry");

    DesktopEntry e;
    e.path = path;
    e.id = QFileInfo(path).completeBaseName();
    e.name = ini.value("Name").toString();
    e.genericName = ini.value("GenericName").toString();
    e.comment = ini.value("Comment").toString();
    e.icon = ini.value("Icon").toString();
    e.exec = ini.value("Exec").toString();
    e.tryExec = ini.value("TryExec").toString();
    e.workingDirectory = ini.value("Path").toString();
    e.terminal = ini.value("Terminal").toBool();
    e.noDisplay = ini.value("NoDisplay").toBool();
    e.hidden = ini.value("Hidden").toBool();

    auto cats = ini.value("Categories").toString();
    if (!cats.isEmpty()) e.categories = cats.split(';', Qt::SkipEmptyParts);

    if (ini.value("Type").toString() != "Application") e.id.clear();

    ini.endGroup();
    return e;
}

}  // namespace

// Field codes per the XDG Desktop Entry spec, section "The Exec key".
// We drop them entirely for the simple "user clicks dock icon" flow — file
// arguments belong to MIME-handler invocation, which this layer doesn't do.
// Exposed at namespace scope (rather than the anonymous namespace) so tests
// can exercise it directly.
QString strip_field_codes(QString exec) {
    static const QRegularExpression re("%[fFuUickdDnNvm]");
    return exec.remove(re).simplified();
}

QVector<DesktopEntry> scan_desktop_entries() {
    QVector<DesktopEntry> out;
    QStringList seen_ids;
    seen_ids.reserve(256);

    for (const auto& root : desktop_search_paths()) {
        QDir dir(root);
        if (!dir.exists()) continue;
        const auto files = dir.entryInfoList(QStringList{"*.desktop"}, QDir::Files);
        for (const auto& fi : files) {
            DesktopEntry e = parse_one(fi.absoluteFilePath());
            if (!e.isValid()) continue;
            if (e.noDisplay || e.hidden) continue;
            if (seen_ids.contains(e.id)) continue;  // earlier root wins
            seen_ids << e.id;
            out << e;
        }
    }
    return out;
}

DesktopEntry lookup_desktop_entry(const QString& id) {
    for (const auto& root : desktop_search_paths()) {
        const QString candidate = QDir(root).filePath(id + ".desktop");
        if (QFile::exists(candidate)) {
            DesktopEntry e = parse_one(candidate);
            if (e.isValid()) return e;
        }
    }
    return {};
}

qint64 launch_command(const QString& command_line) {
    const auto parts = QProcess::splitCommand(command_line);
    if (parts.isEmpty()) {
        qWarning() << "[core] empty command line; nothing to launch";
        return 0;
    }
    qint64 pid = 0;
    const bool ok = QProcess::startDetached(parts.first(), parts.mid(1), QString{}, &pid);
    if (!ok) {
        qWarning() << "[core] failed to spawn:" << command_line;
        return 0;
    }
    return pid;
}

// Resolve the absolute path to hyprctl once. Hyprland's children inherit an
// empty PATH, so `QProcess::start("hyprctl"...)` doesn't find the binary;
// using an explicit path is the robust fix. Returns "" if hyprctl isn't on
// disk (production install without the dev compositor — fine, dedup just
// degrades to "always spawn").
static QString resolve_hyprctl() {
    static const QString cached = []() -> QString {
        for (const auto& c : {"/usr/bin/hyprctl", "/usr/local/bin/hyprctl", "/bin/hyprctl"}) {
            if (QFileInfo::exists(c)) return QString::fromLatin1(c);
        }
        return {};
    }();
    return cached;
}

// True iff Hyprland reports at least one window with `class == cls`. This
// is the source of truth for "is this app already open on the desktop?":
//
//   * `/proc/<pid>/comm` lookups are unreliable for shell-wrapped exec
//     lines (`sh -c '…'`) because the basename we'd be searching for is
//     "sh", and the wrapper exits the moment its child errors — there's
//     never a long-lived process to find. The dedup then silently failed
//     for every placeholder .desktop and clicks spawned duplicates.
//
//   * Hyprland's `clients` IPC is authoritative — if there's a window with
//     this app's class on any workspace, the user wants us to focus it.
//
// We parse `hyprctl clients -j` (JSON) with a single QJsonDocument call.
static bool hyprctl_has_window_with_class(const QString& cls) {
    const QString hyprctl = resolve_hyprctl();
    if (hyprctl.isEmpty() || cls.isEmpty()) return false;
    QProcess p;
    p.start(hyprctl, {"clients", "-j"});
    if (!p.waitForFinished(kHyprctlTimeoutMs)) {
        p.kill();
        return false;
    }
    if (p.exitCode() != 0) return false;
    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(p.readAllStandardOutput(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isArray()) return false;
    for (const auto& v : doc.array()) {
        if (v.toObject().value("class").toString() == cls) return true;
    }
    return false;
}

// Serialise per-id launches so two rapid clicks on the same dock icon don't
// race past the hyprctl_has_window check and spawn duplicates. The map grows
// monotonically (one entry per ever-launched id) — fine, it's tiny.
// std::map (red-black tree) used rather than std::unordered_map because QString
// has no std::hash specialization out of the box but does support operator<.
// Exposed at namespace scope so tests can verify the per-id locking semantics.
std::mutex& launch_mutex_for(const QString& id) {
    static std::mutex map_mutex;
    static std::map<QString, std::unique_ptr<std::mutex>> mutexes;
    std::lock_guard<std::mutex> g(map_mutex);
    auto it = mutexes.find(id);
    if (it == mutexes.end()) {
        auto m = std::make_unique<std::mutex>();
        std::mutex& ref = *m;
        mutexes.emplace(id, std::move(m));
        return ref;
    }
    return *it->second;
}

// Tell Hyprland to focus the first window matching the given class.
static bool hyprctl_focus_class(const QString& cls) {
    const QString hyprctl = resolve_hyprctl();
    if (hyprctl.isEmpty() || cls.isEmpty()) return false;
    QProcess p;
    p.start(hyprctl, {"dispatch", "focuswindow", "class:" + cls});
    if (!p.waitForFinished(kHyprctlTimeoutMs)) {
        p.kill();
        return false;
    }
    return p.exitCode() == 0;
}

qint64 launch_desktop_entry(const DesktopEntry& entry) {
    if (!entry.isValid() || entry.exec.isEmpty()) {
        qWarning() << "[core] cannot launch invalid entry" << entry.id;
        return 0;
    }
    QString cmdline = strip_field_codes(entry.exec);

    if (entry.terminal) {
        // Use the user's preferred terminal, falling back to ghostty (shipped).
        const QString term = qEnvironmentVariable("AURUM_TERMINAL", "ghostty");
        cmdline = term + " -e " + cmdline;
    }

    const auto parts = QProcess::splitCommand(cmdline);
    if (parts.isEmpty()) return 0;

    // ── Per-id launch serialisation ───────────────────────────────────────
    // Hyprland IPC takes 5-50ms; without this lock two clicks landing within
    // that window both observe "no window present" and both call
    // startDetached → duplicate windows. The lock is per-id so launches for
    // *different* apps don't block each other.
    std::lock_guard<std::mutex> launch_guard(launch_mutex_for(entry.id));

    // ── Singleton check (macOS "activate or launch") ──────────────────────
    // Source of truth is Hyprland's window list, NOT /proc — a previous
    // implementation looked up the basename of the exec command, which broke
    // entirely for shell-wrapped placeholders (`sh -c '…'` → basename "sh",
    // which exits the moment the wrapped command does).
    //
    // If there's already a window with `class == entry.id` on any workspace,
    // focus it and short-circuit.
    if (hyprctl_has_window_with_class(entry.id)) {
        hyprctl_focus_class(entry.id);
        qInfo().noquote() << "[core] focused existing window" << entry.id;
        return -1;  // sentinel: "handled, no new pid"
    }

    qint64 pid = 0;
    const bool ok = QProcess::startDetached(
        parts.first(), parts.mid(1),
        entry.workingDirectory.isEmpty() ? QString{} : entry.workingDirectory, &pid);
    if (!ok) {
        qWarning() << "[core] failed to spawn entry" << entry.id << "→" << cmdline;
        return 0;
    }
    qInfo().noquote() << "[core] launched" << entry.id << "→" << cmdline
                      << "(pid=" + QString::number(pid) + ")";
    return pid;
}

}  // namespace aurum::core

// Resolve the QML file path. Centralised so every desktop app uses the same
// search order (dev override → system install → local install → build tree).
// Previously duplicated across nine main.cpp files with subtle drift; the
// dock's version was canonical so we keep its semantics (existence check on
// each candidate, fall through to the last candidate as a "best effort" path
// that QQmlApplicationEngine::load will then fail loudly on).
QString resolve_qml_path(const QString& filename, const char* argv0) {
    const QStringList candidates = {
        qEnvironmentVariable("AURUM_QML_DIR") + "/" + filename,
        "/usr/share/aurum-os/qml/" + filename,
        "/usr/local/share/aurum-os/qml/" + filename,
        QFileInfo(QString::fromUtf8(argv0)).absolutePath() + "/qml/" + filename,
    };
    for (const auto& c : candidates) {
        if (QFile::exists(c)) return QFileInfo(c).absoluteFilePath();
    }
    return QString();
}

extern "C" void init_core_services() {
    static std::once_flag init_flag;
    std::call_once(init_flag, []() {
        // Qt logging by convention: stdout is reserved for tool output (e.g.
        // the test binaries that emit JSON). Filter via QT_LOGGING_RULES.
        qInfo().noquote() << "[core-services] initialized; xdg search paths="
                          << aurum::core::desktop_search_paths().join(':');
    });
}
