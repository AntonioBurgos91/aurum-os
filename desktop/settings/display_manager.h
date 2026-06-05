#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

namespace aurum::settings {

// DisplayManager — Settings backend for monitors, brightness and night light
// on the AurumOS (Hyprland/Wayland) desktop.
//
// Control surfaces, by capability:
//   * Monitors (detect / arrange / resolution / scale): Hyprland IPC
//     (`hyprctl monitors -j` to read; `hyprctl keyword monitor ...` to set).
//   * Brightness (laptop panel): /sys/class/backlight/<dev>/brightness
//     (no external dep; writes need the user in the `video` group or a udev
//     rule, both shipped by the distro).
//   * Brightness (external monitor): DDC/CI via `ddcutil setvcp 10 <pct>`.
//   * Night light / warm light: color temperature in Kelvin via `hyprsunset
//     -t <kelvin>` (Hyprland's gamma daemon).
//
// The pure helpers (parse_monitors, build_monitor_keyword,
// kelvin_to_label, clamp_percent) are static so they can be unit-tested
// without a compositor or real displays.
class DisplayManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList monitors READ monitors NOTIFY monitorsChanged)
    Q_PROPERTY(int nightLightKelvin READ nightLightKelvin NOTIFY nightLightChanged)
    Q_PROPERTY(bool nightLightEnabled READ nightLightEnabled NOTIFY nightLightChanged)

public:
    explicit DisplayManager(QObject* parent = nullptr);

    // [ { name, description, width, height, refresh, x, y, scale, active,
    //     focused, brightness } ]  — one map per connected monitor.
    QVariantList monitors() const {
        return m_monitors;
    }
    int nightLightKelvin() const {
        return m_nightLightKelvin;
    }
    bool nightLightEnabled() const {
        return m_nightLightEnabled;
    }

    // ── live refresh ────────────────────────────────────────────────────────
    Q_INVOKABLE void refresh();

    // ── monitor arrangement ─────────────────────────────────────────────────
    // Apply a resolution + refresh + position + scale for one monitor via
    // `hyprctl keyword monitor`. Returns false if the IPC call failed.
    Q_INVOKABLE bool setMode(const QString& name, int width, int height, double refreshHz, int x,
                             int y, double scale);
    // Convenience layouts for the common two-monitor cases.
    Q_INVOKABLE bool arrangeExtend(const QString& leftName, const QString& rightName);
    Q_INVOKABLE bool arrangeMirror(const QString& primaryName, const QString& mirrorName);
    Q_INVOKABLE bool setEnabled(const QString& name, bool enabled);

    // ── brightness ──────────────────────────────────────────────────────────
    // 0..=100. Laptop panels go through sysfs backlight; external monitors via
    // ddcutil. `monitorName` selects which (empty = primary/first backlight).
    Q_INVOKABLE bool setBrightness(const QString& monitorName, int percent);

    // ── night light (warm color temperature) ────────────────────────────────
    // kelvin in [1000, 6500]; 6500 is neutral. enabled=false restores neutral.
    Q_INVOKABLE bool setNightLight(bool enabled, int kelvin);

    // QML-facing wrapper for the static kelvin_to_label (QML can't call statics).
    Q_INVOKABLE QString kelvinLabel(int kelvin) const {
        return kelvin_to_label(kelvin);
    }

    // ── pure helpers (static; unit-tested) ───────────────────────────────────
    // Parse `hyprctl monitors -j` JSON into the monitors() shape.
    static QVariantList parse_monitors(const QByteArray& hyprctlJson);
    // Build the value half of `hyprctl keyword monitor <value>`.
    // e.g. "DP-1,2560x1440@144,0x0,1.0".
    static QString build_monitor_keyword(const QString& name, int width, int height, double refresh,
                                         int x, int y, double scale);
    // Human label for a color temperature (e.g. 6500 -> "Neutral", 3400 -> "Warm").
    static QString kelvin_to_label(int kelvin);
    // Clamp an int to 0..=100.
    static int clamp_percent(int v);

signals:
    void monitorsChanged();
    void nightLightChanged();

private:
    QVariantList m_monitors;
    int m_nightLightKelvin = 6500;
    bool m_nightLightEnabled = false;
};

}  // namespace aurum::settings
