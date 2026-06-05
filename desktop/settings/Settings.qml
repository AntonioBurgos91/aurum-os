// AurumOS Settings — sidebar nav + StackLayout of section pages.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Aurum.Aqua 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 880
    height: 600
    title: "Settings"
    // Explicit AARRGGBB alpha=255 — see MenuBar.qml for the wlroots-headless
    // alpha-leak rationale. Theme.windowBg ("#1c1c1e") leaks alpha=0 under
    // Qt6 Wayland-EGL on the headless backend, producing pure-black frames
    // in wlr-screencopy. Hardcoding the AA byte fixes it.
    color: "#FF1c1c1e"

    property int currentSection: 1  // default to GPU

    // Close shortcuts.
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequence: "Esc";    onActivated: Qt.quit() }

    // Inline TrafficLight component — must be at root scope (Qt6 only finds
    // inline components in the immediate containing object's scope). See
    // Finder.qml for the cautionary tale about defining it inside a child.
    component TrafficLight: Rectangle {
        id: tl
        property color baseColor: "#888"
        signal trigger()
        width: 13; height: 13; radius: 6.5
        color: baseColor
        border.color: Qt.darker(baseColor, 1.4)
        border.width: 1
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(tl.baseColor, 1.35) }
                GradientStop { position: 1.0; color: tl.baseColor }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tl.trigger()
        }
    }

    // Custom title bar with traffic lights on the left.
    header: ToolBar {
        height: 38
        background: Rectangle {
            color: "#FF2a2a2e"
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: "#3c3c42"
            }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12
            Row {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter
                TrafficLight {
                    baseColor: "#ff5f57"
                    onTrigger: Qt.quit()
                }
                TrafficLight {
                    baseColor: "#ffbd2e"
                    onTrigger: root.showMinimized()
                }
                TrafficLight {
                    baseColor: "#28c941"
                    onTrigger: root.visibility === Window.FullScreen
                                 ? root.showNormal()
                                 : root.showFullScreen()
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Settings"
                color: Theme.textPrimary
                font.pixelSize: 13
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }
            Item { Layout.fillWidth: true }
        }
    }

    readonly property var sections: [
        { id: "general",  title: "General",      icon: "⚙" },
        { id: "gpu",      title: "GPU",          icon: "▶" },
        { id: "display",  title: "Displays",     icon: "▦" },
        { id: "cuda",     title: "CUDA",         icon: "◆" },
        { id: "venv",     title: "Python venvs", icon: "🐍" },
        { id: "mlops",    title: "MLOps",        icon: "↔" },
        { id: "hardware", title: "Hardware",     icon: "▣" },
        { id: "packs",    title: "Model Packs",  icon: "▤" },
        { id: "about",    title: "About",        icon: "ⓘ" }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // --- Sidebar -----------------------------------------------------
        Rectangle {
            Layout.preferredWidth: 200
            Layout.fillHeight: true
            color: Theme.surface

            ListView {
                anchors.fill: parent
                anchors.margins: 8
                model: sections
                spacing: 4
                interactive: false
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 36
                    radius: 8
                    color: index === root.currentSection
                          ? Theme.accent
                          : hov.containsMouse ? Theme.surfaceRaised : "transparent"
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10
                        Text {
                            text: modelData.icon
                            font.pixelSize: 16
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: modelData.title
                            font.pixelSize: 13
                            color: index === root.currentSection
                                   ? Theme.accentText : Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: hov
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentSection = index
                    }
                }
            }
        }

        // --- Pages -------------------------------------------------------
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentSection

            Loader { source: "sections/GeneralSection.qml" }
            Loader { source: "sections/GpuSection.qml" }
            Loader { source: "sections/DisplaySection.qml" }
            Loader { source: "sections/CudaSection.qml" }
            Loader { source: "sections/PythonVenvsSection.qml" }
            Loader { source: "sections/MlopsSection.qml" }
            // Hardware panel lives at the settings root (not sections/) per the
            // Wave 8 profile-detect spec — it surfaces ProfileClient values.
            Loader { source: "HardwarePanel.qml" }
            // Model Packs panel (Wave 9 — Agent H). Steam-Workshop-style
            // downloader backed by the `aurum-model-pack` CLI.
            Loader { source: "ModelPacksPanel.qml" }
            // About panel (Wave 10E — Agent 10E). Distro version, build
            // date, license, and the detected hardware summary in one card.
            Loader { source: "AboutPanel.qml" }
        }
    }
}
