// AboutPanel — "About AurumOS" tab in the Settings app.
//
// Apple-style About card: distro name + version, build date, detected
// hardware tier, GPU, RAM, license, and a small copyright footer. All
// wrapped in shared SectionCards so it matches the rest of Settings.
//
// Data source: `profileClient` context property (already wired in main.cpp
// for HardwarePanel). Version / build date / license come from a small
// QML-side property block here so the panel works even when the host has
// no `aurum-version` binary installed (e.g. dev checkout). When that CLI
// lands in a later wave, swap the bindings to ProcessClient.runOnce().
//
// Owned by Wave 10 Agent 10E.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    id: panel

    // --- Static metadata (replace with ProcessClient lookups later) ---------
    readonly property string version:    "0.10.0-wave10"
    readonly property string buildDate:  "2026-05-26"
    readonly property string license:    "Apache 2.0"
    readonly property string codename:   "Sequoia"

    function _formatRam() {
        // Some ProfileClient builds expose ramGb; older ones report ramMb only.
        if (typeof profileClient === "undefined") return "—"
        if (profileClient.ramGb !== undefined) return profileClient.ramGb + " GB"
        if (profileClient.ramMb !== undefined) return (profileClient.ramMb / 1024).toFixed(1) + " GB"
        return "—"
    }

    function _formatProfile() {
        if (typeof profileClient === "undefined" || !profileClient.profile) return "—"
        const p = profileClient.profile
        return p.charAt(0).toUpperCase() + p.slice(1)
    }

    function _formatGpu() {
        if (typeof profileClient === "undefined") return "—"
        return profileClient.gpuName || "(no discrete GPU)"
    }

    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: parent.parent.width - 40
            x: 20
            y: 20
            spacing: Theme.cardSpacing

            // ---- Hero card: distro name + version --------------------------
            SectionCard {
                Layout.fillWidth: true
                title:    "AurumOS " + panel.version
                subtitle: "macOS-class AI workstation built on Debian. "
                        + "Codename " + panel.codename + " — built " + panel.buildDate + "."

                // Big "AurumOS" wordmark block.
                Rectangle {
                    Layout.preferredWidth: 240
                    Layout.preferredHeight: 80
                    radius: Theme.cornerRadius
                    color: Theme.accent
                    border.color: Theme.border
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 2
                        Text {
                            text: "AurumOS"
                            color: "#FFFFFF"
                            font.pixelSize: 28
                            font.bold: true
                        }
                        Text {
                            text: panel.version
                            color: "#E0E0E0"
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // ---- System summary -------------------------------------------
            SectionCard {
                Layout.fillWidth: true
                title:    "System"
                subtitle: "Detected by aurum-detect-profile at install time."

                SettingsRow {
                    label:   "Profile"
                    control: Text {
                        text: panel._formatProfile()
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                }
                SettingsRow {
                    label:   "GPU"
                    control: Text {
                        text: panel._formatGpu()
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
                SettingsRow {
                    label:   "RAM"
                    control: Text {
                        text: panel._formatRam()
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                }
                SettingsRow {
                    label:   "License"
                    isLast:  true
                    control: Text {
                        text: panel.license
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }

            // ---- Build & footer --------------------------------------------
            SectionCard {
                Layout.fillWidth: true
                title:    "Build"
                subtitle: "Build " + panel.version + " — " + panel.buildDate

                SettingsRow {
                    label:   "Codename"
                    control: Text {
                        text: panel.codename
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                }
                SettingsRow {
                    label:   "Channel"
                    isLast:  true
                    control: Text {
                        text: "stable"
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Footer line (sits inside the same card so the copyright is
                // visually tied to the build info).
                Text {
                    text: "© AurumOS contributors. " + panel.license + " licensed."
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 8
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
