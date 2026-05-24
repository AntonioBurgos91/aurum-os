// AurumOS installer wizard. Linear StackView with seven pages; "Next" only
// enabled when the current page's `valid` property is true.
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
    title: "Install AurumOS"
    // Explicit AARRGGBB alpha=255 — see MenuBar.qml for the wlroots-headless
    // alpha-leak rationale. Theme.windowBg ("#1c1c1e") leaks alpha=0 under
    // Qt6 Wayland-EGL on the headless backend, producing pure-black frames
    // in wlr-screencopy. Hardcoding the AA byte fixes it.
    color: "#FF1c1c1e"

    // Close shortcuts.
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequence: "Esc";    onActivated: Qt.quit() }

    // Inline TrafficLight component — must be at root scope (Qt6 only finds
    // inline components in the immediate containing object's scope).
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
                text: "Install AurumOS"
                color: Theme.textPrimary
                font.pixelSize: 13
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }
            Item { Layout.fillWidth: true }
        }
    }

    readonly property var pages: [
        "pages/WelcomePage.qml",
        "pages/LocalePage.qml",
        "pages/DiskPage.qml",
        "pages/AccountPage.qml",
        "pages/SummaryPage.qml",
        "pages/InstallPage.qml",
        "pages/DonePage.qml"
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        StackView {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            initialItem: Qt.createComponent(root.pages[0])
        }

        // --- Footer with nav buttons ----------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: Theme.surface
            border.color: Theme.border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8

                Repeater {
                    model: root.pages.length
                    Rectangle {
                        // Inside a RowLayout, so use Layout.alignment rather
                        // than anchors (anchors on a layout-managed item are
                        // undefined behavior in Qt6 and trigger a warning).
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 8; implicitHeight: 8; radius: 4
                        color: index === stack.depth - 1 ? Theme.accent : Theme.border
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Back"
                    enabled: stack.depth > 1 && stack.depth <= root.pages.length - 2
                    onClicked: stack.pop()
                }
                Button {
                    text: stack.depth === root.pages.length ? "Reboot"
                        : stack.depth === root.pages.length - 2 ? "Install"
                        : "Next"
                    highlighted: true
                    enabled: !!stack.currentItem && (stack.currentItem.valid === undefined
                                                  || stack.currentItem.valid)
                    onClicked: {
                        if (stack.depth === root.pages.length) {
                            Qt.quit() // The live ISO's logout target reboots.
                            return
                        }
                        if (stack.depth === root.pages.length - 2) {
                            if (backend.start()) stack.push(Qt.createComponent(root.pages[stack.depth]))
                            return
                        }
                        stack.push(Qt.createComponent(root.pages[stack.depth]))
                    }
                }
            }
        }
    }
}
