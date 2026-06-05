// AurumOS menubar — top strip with Apple-menu placeholder, focused-app name,
// and right-side applets (GPU util, GPU VRAM, GPU temp, network throughput,
// clock). Layout deliberately matches macOS Sequoia: left section (logo + app
// menus), right section (status menus), no center content.
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Window {
    id: root
    visible: true
    width: Screen.width
    height: Theme.menubarHeight
    x: 0
    y: 0
    // NOTE: `Qt.WindowDoesNotAcceptFocus` was here originally to prevent the
    // bar from stealing keyboard focus from the user's apps. On Qt6/Wayland
    // (Hyprland 0.55) that flag is honored AT THE INPUT LAYER — the
    // compositor stops delivering pointer events to the surface too, which
    // breaks every applet hover/tooltip and made the menubar clicks
    // unresponsive in the noVNC preview. Trade-off: the bar will briefly
    // gain keyboard focus when clicked. Mitigated by giving each Applet
    // `MouseArea { hoverEnabled: true }` and the bar's Window
    // `acceptedButtons: Qt.LeftButton` so right-click / drag isn't captured.
    flags: Qt.FramelessWindowHint
         | Qt.WindowStaysOnTopHint
         | Qt.Tool
    // Window root is opaque so wlroots screencopy + headless compositors get
    // a real RGBA frame to encode. We force alpha=255 explicitly via the
    // AARRGGBB form because Qt6 Wayland-EGL otherwise produces ARGB buffers
    // where the clearcolor's alpha leaks to 0 on the headless backend — which
    // wlr-screencopy then renders as pure black. The inner Rectangle MUST
    // also stay at opacity 1.0 for the same reason; macOS subtlety is
    // re-introduced via a slightly lighter inner panel color instead of
    // alpha blending.
    color: "#FF1c1c1e"
    title: "aurum-menubar"

    // Daemon liveness: true when the gpu-monitor daemon has stopped answering.
    // Driven by watching gpuClient.daemonHeartbeat (a monotonic counter the C++
    // client bumps on every successful poll). If it doesn't advance for
    // `staleAfterMs`, the daemon is considered down and daemon-backed applets
    // render "(stale)". A constant *value* (idle VRAM) does NOT trip this —
    // only a frozen heartbeat does.
    property bool daemonStale: false
    property int  _lastHeartbeat: 0
    readonly property int staleAfterMs: 5000

    Timer {
        id: heartbeatWatcher
        interval: root.staleAfterMs
        repeat: true
        running: true
        onTriggered: {
            // If the heartbeat hasn't moved since the last check, the daemon
            // is unresponsive. Otherwise it's alive — clear stale and latch
            // the new value for the next interval.
            if (gpuClient.daemonHeartbeat === root._lastHeartbeat) {
                root.daemonStale = true
            } else {
                root.daemonStale = false
                root._lastHeartbeat = gpuClient.daemonHeartbeat
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#FF1c1c1e"
        opacity: 1.0

        // Hairline border at the bottom, like the macOS divider.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.border
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 16

            // --- Left section: Apple menu + focused app ---------------------
            Text {
                text: ""
                font.pixelSize: 16
                color: Theme.textPrimary
                Layout.alignment: Qt.AlignVCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: console.log("[menubar] Aurum menu (todo)")
                }
            }

            Text {
                text: systemClient.focusedApp || "AurumOS"
                font.bold: true
                font.pixelSize: 13
                color: Theme.textPrimary
                Layout.alignment: Qt.AlignVCenter
            }

            // Greedy spacer pushes the applets to the right edge.
            Item { Layout.fillWidth: true }

            // Active ML training run tracker (pulses when active, slides out when idle)
            Applet {
                id: mlApplet
                visible: systemClient.hasActiveJob
                label: "RUNNING"
                value: systemClient.activeJobName
                tone: Theme.accent
                tooltip: systemClient.activeJobDetails

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: mlApplet.visible
                    NumberAnimation { from: 1.0; to: 0.5; duration: 1200; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.5; to: 1.0; duration: 1200; easing.type: Easing.InOutQuad }
                }
            }

            // --- Right section: live applets --------------------------------
            Applet {
                dependsOnDaemon: true
                label: gpuClient.utilLabel
                value: gpuClient.gpuUtilization + "%"
                tone: gpuClient.gpuUtilization >= 90 ? Theme.danger
                    : gpuClient.gpuUtilization >= 70 ? Theme.warning
                    :                                   Theme.success
                tooltip: gpuClient.gpuName + " — live " + gpuClient.utilLabel + " utilization"
            }

            Applet {
                dependsOnDaemon: true
                label: gpuClient.memLabel
                value: gpuClient.vramUsedGb.toFixed(1) + "/" +
                       gpuClient.vramTotalGb.toFixed(1) + "G"
                tone: (gpuClient.vramTotalGb > 0 &&
                       gpuClient.vramUsedGb / gpuClient.vramTotalGb >= 0.9)
                      ? Theme.danger : Theme.textPrimary
                tooltip: gpuClient.memLabel + " in use (" + gpuClient.gpuName + ")"
            }

            Applet {
                dependsOnDaemon: true
                label: "°C"
                value: gpuClient.gpuTemp + ""
                tone: gpuClient.gpuTemp >= 85 ? Theme.danger
                    : gpuClient.gpuTemp >= 75 ? Theme.warning
                    :                            Theme.textPrimary
                tooltip: gpuClient.utilLabel + " package temperature"
            }

            Applet {
                label: "NET"
                value: systemClient.netThroughput
                tone: Theme.textPrimary
                tooltip: "Aggregate RX across all interfaces"
            }

            // Update-available indicator: only visible when aurum-update found a
            // newer signed release. Click to apply (opens the updater in a
            // terminal, which prompts + escalates via pkexec). Never auto-applies.
            Item {
                id: updateApplet
                visible: updateClient.updateAvailable
                implicitHeight: Theme.menubarHeight
                implicitWidth: updRow.implicitWidth + 14
                Row {
                    id: updRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: "\u2191"  // up arrow
                        font.bold: true
                        font.pixelSize: 12
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Update"
                        font.pixelSize: 12
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                ToolTip.visible: updMa.containsMouse
                ToolTip.text: "AurumOS " + updateClient.latestVersion +
                              " is available (you have " + updateClient.installedVersion +
                              "). Click to install."
                ToolTip.delay: 300
                MouseArea {
                    id: updMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: updateClient.applyUpdate()
                }
            }

            Applet {
                label: ""
                value: systemClient.systemTime
                tone: Theme.textPrimary
                tooltip: Qt.formatDateTime(new Date(), "dddd, d MMMM yyyy")
            }
        }
    }

    // Inline applet component — single line "LABEL value", colored value text,
    // hover-tooltip. Local to the menubar instead of an Aurum.Aqua singleton
    // because it's tightly coupled to the strip's rhythm.
    //
    // Daemon-health "stale" indicator: an applet is stale only when the
    // telemetry DAEMON has stopped responding — never because a value is
    // legitimately constant (idle VRAM, a parked network link). Applets that
    // read from the gpu-monitor daemon set `dependsOnDaemon: true`; the root's
    // heartbeatWatcher flips `root.daemonStale` when gpuClient.daemonHeartbeat
    // stops advancing. Host-local applets (clock, network read from
    // /proc/net/dev) leave dependsOnDaemon=false and are never marked stale.
    component Applet: Item {
        id: applet
        property string label: ""
        property string value: ""
        property color  tone: Theme.textPrimary
        property string tooltip: ""
        property bool   dependsOnDaemon: false
        readonly property bool stale: dependsOnDaemon && root.daemonStale

        implicitHeight: Theme.menubarHeight
        implicitWidth: row.implicitWidth + 10

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 4
            Text {
                visible: applet.label !== ""
                text: applet.label
                font.bold: true
                font.pixelSize: 10
                color: Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: applet.value + (applet.stale ? " (stale)" : "")
                font.pixelSize: 12
                color: applet.stale ? Theme.textSecondary : applet.tone
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        ToolTip.visible: ma.containsMouse && applet.tooltip.length > 0
        ToolTip.text:    applet.stale
                         ? applet.tooltip + " (no update in 30s — daemon may be down)"
                         : applet.tooltip
        ToolTip.delay:   400
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
        }
    }
}
