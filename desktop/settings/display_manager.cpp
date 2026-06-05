#include "display_manager.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTextStream>
#include <QVariantMap>

namespace aurum::settings {

namespace {

constexpr int kIpcTimeoutMs = 1500;
constexpr auto kBacklightRoot = "/sys/class/backlight";

// Resolve hyprctl once; Hyprland children inherit an empty PATH so an explicit
// path is the robust choice. Empty string when not installed (e.g. preview).
QString resolve_bin(std::initializer_list<const char*> candidates) {
    for (const auto* c : candidates) {
        if (QFileInfo::exists(QString::fromLatin1(c))) return QString::fromLatin1(c);
    }
    return {};
}

QString hyprctl_bin() {
    return resolve_bin({"/usr/bin/hyprctl", "/usr/local/bin/hyprctl", "/bin/hyprctl"});
}
QString hyprsunset_bin() {
    return resolve_bin({"/usr/bin/hyprsunset", "/usr/local/bin/hyprsunset"});
}
QString ddcutil_bin() {
    return resolve_bin({"/usr/bin/ddcutil", "/usr/local/bin/ddcutil"});
}

// Run a command, return true on exit 0. Best-effort: a missing binary (preview
// without the compositor) returns false rather than crashing the UI.
bool run(const QString& bin, const QStringList& args, int timeoutMs = kIpcTimeoutMs) {
    if (bin.isEmpty()) return false;
    QProcess p;
    p.start(bin, args);
    if (!p.waitForFinished(timeoutMs)) {
        p.kill();
        return false;
    }
    return p.exitCode() == 0;
}

QByteArray run_capture(const QString& bin, const QStringList& args, int timeoutMs = kIpcTimeoutMs) {
    if (bin.isEmpty()) return {};
    QProcess p;
    p.start(bin, args);
    if (!p.waitForFinished(timeoutMs)) {
        p.kill();
        return {};
    }
    if (p.exitCode() != 0) return {};
    return p.readAllStandardOutput();
}

// First laptop backlight device under /sys/class/backlight (e.g. amdgpu_bl1).
QString primary_backlight() {
    QDir d(kBacklightRoot);
    const auto entries = d.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    return entries.isEmpty() ? QString() : entries.first();
}

}  // namespace

DisplayManager::DisplayManager(QObject* parent) : QObject(parent) {
    refresh();
}

// ── pure helpers ────────────────────────────────────────────────────────────

QVariantList DisplayManager::parse_monitors(const QByteArray& hyprctlJson) {
    QVariantList out;
    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(hyprctlJson, &err);
    if (err.error != QJsonParseError::NoError || !doc.isArray()) return out;

    for (const auto& v : doc.array()) {
        const QJsonObject m = v.toObject();
        // Hyprland reports current mode as width/height/refreshRate and the
        // layout position as x/y; scale is a double.
        QVariantMap mon{
            {"name", m.value("name").toString()},
            {"description", m.value("description").toString()},
            {"width", m.value("width").toInt()},
            {"height", m.value("height").toInt()},
            {"refresh", m.value("refreshRate").toDouble()},
            {"x", m.value("x").toInt()},
            {"y", m.value("y").toInt()},
            {"scale", m.value("scale").toDouble(1.0)},
            {"active", !m.value("disabled").toBool(false)},
            {"focused", m.value("focused").toBool(false)},
        };
        out << mon;
    }
    return out;
}

QString DisplayManager::build_monitor_keyword(const QString& name, int width, int height,
                                              double refresh, int x, int y, double scale) {
    // Format Hyprland expects: NAME,WIDTHxHEIGHT@REFRESH,XxY,SCALE
    // Refresh and scale are trimmed to a tidy representation.
    const QString res =
        QStringLiteral("%1x%2@%3").arg(width).arg(height).arg(QString::number(refresh, 'g', 6));
    const QString pos = QStringLiteral("%1x%2").arg(x).arg(y);
    const QString sc = QString::number(scale, 'g', 4);
    return QStringLiteral("%1,%2,%3,%4").arg(name, res, pos, sc);
}

QString DisplayManager::kelvin_to_label(int kelvin) {
    if (kelvin >= 6000) return QStringLiteral("Neutral");
    if (kelvin >= 5000) return QStringLiteral("Cool");
    if (kelvin >= 4000) return QStringLiteral("Soft");
    if (kelvin >= 3000) return QStringLiteral("Warm");
    return QStringLiteral("Very warm");
}

int DisplayManager::clamp_percent(int v) {
    if (v < 0) return 0;
    if (v > 100) return 100;
    return v;
}

// ── live refresh ──────────────────────────────────────────────────────────

void DisplayManager::refresh() {
    const QByteArray json = run_capture(hyprctl_bin(), {"monitors", "-j"});
    m_monitors = parse_monitors(json);

    // Annotate each monitor with its current brightness (laptop panel only;
    // external DDC reads are slow, so we lazy-read those on demand in the UI).
    const QString bl = primary_backlight();
    if (!bl.isEmpty() && !m_monitors.isEmpty()) {
        const QString base = QString("%1/%2").arg(kBacklightRoot, bl);
        QFile cur(base + "/brightness"), max(base + "/max_brightness");
        if (cur.open(QIODevice::ReadOnly) && max.open(QIODevice::ReadOnly)) {
            const double c = cur.readAll().trimmed().toDouble();
            const double mx = max.readAll().trimmed().toDouble();
            if (mx > 0) {
                auto first = m_monitors.first().toMap();
                first["brightness"] = qRound(100.0 * c / mx);
                m_monitors[0] = first;
            }
        }
    }
    emit monitorsChanged();
}

// ── monitor arrangement ─────────────────────────────────────────────────────

bool DisplayManager::setMode(const QString& name, int width, int height, double refreshHz, int x,
                             int y, double scale) {
    const QString kw = build_monitor_keyword(name, width, height, refreshHz, x, y, scale);
    const bool ok = run(hyprctl_bin(), {"keyword", "monitor", kw});
    if (ok) refresh();
    return ok;
}

bool DisplayManager::arrangeExtend(const QString& leftName, const QString& rightName) {
    // Place leftName at 0x0 (preferred mode, auto), rightName immediately to
    // its right via Hyprland's "auto-right" positioning.
    bool ok = run(hyprctl_bin(),
                  {"keyword", "monitor", QStringLiteral("%1,preferred,0x0,1").arg(leftName)});
    ok = run(hyprctl_bin(),
             {"keyword", "monitor", QStringLiteral("%1,preferred,auto-right,1").arg(rightName)}) &&
         ok;
    if (ok) refresh();
    return ok;
}

bool DisplayManager::arrangeMirror(const QString& primaryName, const QString& mirrorName) {
    bool ok = run(hyprctl_bin(),
                  {"keyword", "monitor", QStringLiteral("%1,preferred,0x0,1").arg(primaryName)});
    ok = run(hyprctl_bin(),
             {"keyword", "monitor",
              QStringLiteral("%1,preferred,0x0,1,mirror,%2").arg(mirrorName, primaryName)}) &&
         ok;
    if (ok) refresh();
    return ok;
}

bool DisplayManager::setEnabled(const QString& name, bool enabled) {
    const QString kw = enabled ? QStringLiteral("%1,preferred,auto,1").arg(name)
                               : QStringLiteral("%1,disable").arg(name);
    const bool ok = run(hyprctl_bin(), {"keyword", "monitor", kw});
    if (ok) refresh();
    return ok;
}

// ── brightness ──────────────────────────────────────────────────────────────

bool DisplayManager::setBrightness(const QString& monitorName, int percent) {
    const int pct = clamp_percent(percent);

    // Laptop panel: write sysfs backlight (scaled to max_brightness).
    // monitorName empty OR matching the internal panel → use the first
    // backlight device.
    const QString bl = primary_backlight();
    const bool internal =
        monitorName.isEmpty() || monitorName.startsWith("eDP") || monitorName.startsWith("LVDS");
    if (!bl.isEmpty() && internal) {
        const QString base = QString("%1/%2").arg(kBacklightRoot, bl);
        QFile max(base + "/max_brightness");
        if (max.open(QIODevice::ReadOnly)) {
            const qint64 mx = max.readAll().trimmed().toLongLong();
            const qint64 val = mx * pct / 100;
            QFile cur(base + "/brightness");
            if (cur.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                cur.write(QByteArray::number(val));
                cur.close();
                refresh();
                return true;
            }
        }
        return false;
    }

    // External monitor: DDC/CI VCP feature 0x10 is luminance.
    const bool ok = run(ddcutil_bin(), {"setvcp", "10", QString::number(pct)}, 4000);
    return ok;
}

// ── night light ───────────────────────────────────────────────────────────

bool DisplayManager::setNightLight(bool enabled, int kelvin) {
    // Clamp to hyprsunset's sane range; 6500 is neutral daylight.
    if (kelvin < 1000) kelvin = 1000;
    if (kelvin > 6500) kelvin = 6500;

    // hyprsunset is a persistent daemon; -t sets temperature, and passing
    // 6500 (identity) is how we "turn it off" without killing the daemon.
    const int target = enabled ? kelvin : 6500;
    const bool ok = run(hyprsunset_bin(), {"-t", QString::number(target)});

    m_nightLightEnabled = enabled;
    m_nightLightKelvin = kelvin;
    emit nightLightChanged();
    return ok;
}

}  // namespace aurum::settings
