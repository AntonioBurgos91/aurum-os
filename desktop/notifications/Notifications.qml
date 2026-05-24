// AurumOS Notifications — top-right stack of macOS-style notification cards.
//
// Currently a placeholder: one static "Welcome to AurumOS" card. The eventual
// D-Bus org.freedesktop.Notifications dispatcher will append to `notifModel`
// and the ListView below will animate cards in/out without further QML work.
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Aurum.Aqua 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 380
    // Tall enough for several stacked cards; the background is transparent
    // so empty space below the cards reads as the desktop, not a panel slab.
    height: 600
    title: "Notifications"

    // Frameless on-top tool window — no decorations, no taskbar entry, always
    // above normal app windows. Same flag combo used elsewhere for chrome.
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool

    // Explicit AARRGGBB alpha=255 — see MenuBar.qml/Dock.qml for the
    // wlroots-headless alpha-leak rationale. Theme.windowBg ("#1c1c1e")
    // leaks alpha=0 under Qt6 Wayland-EGL on the headless backend, producing
    // pure-black frames in wlr-screencopy. Hardcoding the AA byte fixes it.
    color: "#FF1c1c1e"

    // Anchor to the right edge of the screen, just under the menubar.
    Component.onCompleted: {
        x = Screen.width - width - 12
        y = 36
    }

    // Close shortcuts. The panel is a frameless on-top tool — no traffic
    // lights here (same rationale as Spotlight: it's an overlay, not a
    // proper app window).
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequence: "Esc";    onActivated: Qt.quit() }

    // Static placeholder model. Replace by exposing a C++ QAbstractListModel
    // as `notifModel` once the D-Bus bridge lands.
    ListModel {
        id: notifModel
        ListElement {
            title: "Welcome to AurumOS"
            body:  "Your desktop is ready. Click the dock to launch an app, or press Cmd+Space to search."
        }
    }

    // Vertical stack of cards anchored to the top of the panel; each card
    // sizes to its content and the list grows downward.
    ListView {
        id: stack
        anchors.fill: parent
        anchors.margins: 8
        spacing: 10
        interactive: false
        model: notifModel
        delegate: notifCard
    }

    Component {
        id: notifCard
        Rectangle {
            width: stack.width
            // Sized to content with comfortable padding.
            height: cardCol.implicitHeight + 24
            // Hairline border + rounded corners; matches ComingSoon.qml.
            radius: 12
            color: Theme.surfaceRaised
            border.color: Theme.border
            border.width: 1

            Column {
                id: cardCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                Text {
                    text: model.title
                    color: Theme.textPrimary
                    font.pixelSize: 14
                    font.bold: true
                    width: parent.width
                    elide: Text.ElideRight
                }
                Text {
                    text: model.body
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            // Click anywhere on the card to dismiss it. The real dispatcher
            // will route this back to the notification daemon as a
            // "NotificationClosed" signal.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: notifModel.remove(index)
            }
        }
    }
}
