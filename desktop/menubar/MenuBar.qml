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

            // --- Right section: live applets --------------------------------
            Applet {
                label: "GPU"
                value: gpuClient.gpuUtilization + "%"
                tone: gpuClient.gpuUtilization >= 90 ? Theme.danger
                    : gpuClient.gpuUtilization >= 70 ? Theme.warning
                    :                                   Theme.success
                tooltip: gpuClient.gpuName
            }

            Applet {
                label: "VRAM"
                value: gpuClient.vramUsedGb.toFixed(1) + "/" +
                       gpuClient.vramTotalGb.toFixed(0) + "G"
                tone: (gpuClient.vramTotalGb > 0 &&
                       gpuClient.vramUsedGb / gpuClient.vramTotalGb >= 0.9)
                      ? Theme.danger : Theme.textPrimary
                tooltip: "VRAM in use across the primary GPU"
            }

            Applet {
                label: "°C"
                value: gpuClient.gpuTemp + ""
                tone: gpuClient.gpuTemp >= 85 ? Theme.danger
                    : gpuClient.gpuTemp >= 75 ? Theme.warning
                    :                            Theme.textPrimary
                tooltip: "GPU core temperature"
            }

            Applet {
                label: "NET"
                value: systemClient.netThroughput
                tone: Theme.textPrimary
                tooltip: "Aggregate RX across all interfaces"
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
    // Daemon-health "stale" indicator: if `value` hasn't changed in 30s we
    // assume the backing daemon died and show the last value dimmed with a
    // "(stale)" suffix. Restart of the timer on every value change is cheap
    // (~1 µs per Qt timer reset) and totally avoids polling the daemon's
    // liveness directly.
    component Applet: Item {
        id: applet
        property string label: ""
        property string value: ""
        property color  tone: Theme.textPrimary
        property string tooltip: ""
        property string lastValue: ""
        property bool   stale: false

        implicitHeight: Theme.menubarHeight
        implicitWidth: row.implicitWidth + 10

        Timer {
            id: staleTimer
            interval: 30000
            repeat: false
            onTriggered: applet.stale = true
        }
        onValueChanged: {
            lastValue = value
            stale = false
            staleTimer.restart()
        }
        Component.onCompleted: staleTimer.start()

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
