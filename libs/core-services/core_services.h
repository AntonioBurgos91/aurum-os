#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVector>
#include <mutex>

namespace aurum::core {

// Parsed subset of an XDG .desktop file. We only keep what the dock and
// spotlight consume; the full spec has dozens of keys nothing on the UI side
// will ever look at.
struct DesktopEntry {
    QString id;  // basename without .desktop (e.g. "org.zed.editor")
    QString name;
    QString genericName;
    QString comment;
    QString icon;  // icon NAME (resolve via QIcon::fromTheme)
    QString exec;  // raw Exec= line, still with %u/%f/%U fields
    QString tryExec;
    QStringList categories;
    QString workingDirectory;
    bool terminal = false;
    bool noDisplay = false;
    bool hidden = false;
    QString path;  // absolute path to the .desktop source file

    bool isValid() const {
        return !id.isEmpty();
    }
};

// Scans the standard XDG locations and returns one entry per visible app.
// Honors XDG_DATA_DIRS / XDG_DATA_HOME and skips NoDisplay/Hidden entries.
QVector<DesktopEntry> scan_desktop_entries();

// Resolve a single entry by its id (basename without .desktop). The returned
// value has isValid()==false when not found.
DesktopEntry lookup_desktop_entry(const QString& id);

// Launch the app described by `entry`. Strips XDG Exec= field codes (%f, %u,
// %F, %U, %i, %c, %k) before spawning, runs detached in a clean process
// group, and wraps with the user's terminal when Terminal=true.
// Returns the spawned PID on success, 0 on failure.
qint64 launch_desktop_entry(const DesktopEntry& entry);

// Launch a bare command line (favorites that aren't full .desktop entries).
qint64 launch_command(const QString& command_line);

/// Strip XDG Exec field codes (%f, %u, %F, %U, %i, %c, %k, etc.) from a
/// command line. Public for testing; production callers use it implicitly
/// through `launch_desktop_entry`.
QString strip_field_codes(QString exec);

/// Returns the per-id mutex used to serialise concurrent launches of the
/// same desktop entry id. Public for testing.
std::mutex& launch_mutex_for(const QString& id);

// ── Telemetry formatting (menubar readout) ──────────────────────────────────
// Pure helpers extracted from aurum-menubar's SystemClient so the values the
// user actually sees can be unit-tested without a D-Bus daemon.

/// Format a received-bytes-per-second delta as the menubar's network readout.
/// Below 0.1 MB/s it switches to KB/s (one decimal); at/above, MB/s (one
/// decimal). e.g. 0 -> "0.0 KB/s", 524288 -> "512.0 KB/s", 5242880 -> "5.0 MB/s".
QString format_net_throughput(qulonglong bytes_per_sec);

/// The applet relabels GPU/VRAM as CPU/RAM on the CPU-fallback backend.
/// `source_kind` is the daemon's source_kind() ("nvml"|"amd-sysfs"|"cpu"|...).
/// Returns "CPU" for the cpu backend, "GPU" otherwise.
QString util_label_for(const QString& source_kind);
/// Returns "RAM" for the cpu backend, "VRAM" otherwise.
QString mem_label_for(const QString& source_kind);

/// Convert a byte count to gibibytes (1024^3). Used for the VRAM/RAM readout.
double bytes_to_gib(qulonglong bytes);

}  // namespace aurum::core

/// Resolve a QML file path by checking, in order:
///  1. $AURUM_QML_DIR/{filename} (dev override)
///  2. /usr/share/aurum-os/qml/{filename}    (production install)
///  3. /usr/local/share/aurum-os/qml/{filename}  (local install)
///  4. {dir-of-argv0}/qml/{filename}         (running from build tree)
/// Returns the first path that exists, or QString() if none.
QString resolve_qml_path(const QString& filename, const char* argv0);

// Global init, kept at C linkage so existing main.cpp callers don't need
// updating. Idempotent.
extern "C" void init_core_services();
