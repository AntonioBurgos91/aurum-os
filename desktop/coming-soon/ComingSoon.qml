// ComingSoon — small modal-looking window saying "this app isn't installed".
// macOS Sequoia-style: rounded panel, glass dark, traffic light to dismiss,
// install hint + Copy-to-clipboard button.
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Aurum.Aqua 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 520
    height: 320
    title: displayName
    color: "#FF1c1c1e"
    flags: Qt.FramelessWindowHint | Qt.Dialog

    // Re-centre on the active screen at start.
    Component.onCompleted: {
        x = Math.round((Screen.width  - width)  / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    Rectangle {
        anchors.fill: parent
        color: "#FF1c1c1e"
        radius: 12
        border.color: "#3c3c42"
        border.width: 1

        // ── Title bar with single traffic light (close) ─────────────────
        Rectangle {
            id: bar
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 36
            color: "#FF2a2a2e"
            radius: 12
            // Square off the bottom corners so the bar reads as the top of the panel.
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.radius
                color: parent.color
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: "#3c3c42"
            }

            Rectangle {
                id: closeBtn
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 13; height: 13; radius: 6.5
                color: "#ff5f57"
                border.color: Qt.darker(color, 1.4)
                border.width: 1
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.quit()
                }
            }
        }

        // ── Body ────────────────────────────────────────────────────────
        Column {
            anchors {
                top: bar.bottom;  topMargin: 28
                left: parent.left; leftMargin: 32
                right: parent.right; rightMargin: 32
            }
            spacing: 14

            Text {
                text: displayName
                color: Theme.textPrimary
                font.pixelSize: 22
                font.bold: true
            }

            Text {
                text: "This app is not installed in the AurumOS preview yet."
                color: Theme.textSecondary
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                width: parent.width
            }

            // Install-hint chip — shown only if a hint was passed.
            Rectangle {
                visible: installHint && installHint.length > 0
                width: parent.width
                height: hintRow.implicitHeight + 18
                radius: 8
                color: Theme.surface
                border.color: "#3c3c42"
                border.width: 1

                Row {
                    id: hintRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "$"
                        color: Theme.accent
                        font.bold: true
                        font.pixelSize: 14
                        font.family: "monospace"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: installHint
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.family: "monospace"
                        elide: Text.ElideRight
                        width: hintRow.width - 80
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // Copy-to-clipboard chip on the right.
                    Rectangle {
                        width: 56; height: 24; radius: 4
                        color: copyMA.containsMouse ? Qt.lighter(Theme.surfaceRaised, 1.25) : Theme.surfaceRaised
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: copyState.copied ? "✓" : "Copy"
                            color: Theme.textPrimary
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: copyMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                clipboardHelper.text = installHint
                                clipboardHelper.copy()
                                copyState.copied = true
                                resetTimer.restart()
                            }
                        }
                    }
                    QtObject { id: copyState; property bool copied: false }
                    Timer {
                        id: resetTimer
                        interval: 1500
                        onTriggered: copyState.copied = false
                    }
                    TextEdit {
                        id: clipboardHelper
                        visible: false
                        function copy() { selectAll(); copy() }
                    }
                }
            }

            Text {
                text: "Click the red dot above (or press ⌘Q) to close."
                color: Theme.textSecondary
                font.pixelSize: 12
            }
        }
    }

    // Close shortcut — Cmd-Q on macOS, Super-Q on AurumOS.
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequence: "Esc";    onActivated: Qt.quit() }
}
