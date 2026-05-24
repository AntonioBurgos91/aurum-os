// WindowChrome — reusable macOS Sequoia title-bar for every AurumOS app.
//
// One source of truth replaces the nine slightly-different per-app traffic-
// light + drag-bar blocks that exist today (Finder, Settings, Mission
// Control, Spotlight, Notifications, Installer, Coming Soon, Dock, MenuBar).
// Wave-11's lock screen and login manager render this same component.
//
// Usage:
//   ApplicationWindow {
//       id: window
//       // QT_WAYLAND_DISABLE_WINDOWDECORATION=1 is set globally so Qt does
//       // not draw a native title bar; we draw our own:
//       WindowChrome {
//           title: "Finder"
//           onMinimize: window.showMinimized()
//           onMaximize: window.visibility === Window.FullScreen
//                           ? window.showNormal()
//                           : window.showFullScreen()
//           onClose:    window.close()
//           rightContent: [ /* optional toolbar buttons */ ]
//       }
//       // body items anchor below the chrome via `anchors.top: chrome.bottom`.
//   }
//
// The component is an `Item` (not a Rectangle wrapping the whole window) so
// apps can place it as `header:` of an ApplicationWindow or anchor it
// manually inside a plain Window. It draws its own opaque background and a
// 1-px hairline divider at the bottom, mirroring macOS.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Aurum.Aqua 1.0

Item {
    id: chrome

    // ---- public API --------------------------------------------------------
    property string title: ""
    // Opaque AARRGGBB. We default to Theme.windowBg painted opaque; the
    // explicit alpha prefix prevents the Qt6 Wayland-EGL alpha-leak that
    // turns colors into pure-black frames under the headless backend
    // (see CLAUDE.md / Finder.qml for the rationale).
    property color backgroundColor: Theme.windowBg
    // Default property hack: expose the right-slot Row's children so callers
    // can drop arbitrary toolbar widgets in declaratively via `rightContent`.
    property alias rightContent: rightSlot.children
    property int headerHeight: 38
    // Dim traffic-light hue when the window is not the focused/active one.
    // `Window.window` is null while the component is being torn down so we
    // fall back to `true` to avoid binding warnings during destruction.
    property bool isActive: Window.window ? Window.window.active : true

    // ---- signals -----------------------------------------------------------
    signal minimize()
    signal maximize()
    signal close()

    // ---- geometry ----------------------------------------------------------
    implicitHeight: headerHeight
    anchors.left:  parent ? parent.left  : undefined
    anchors.right: parent ? parent.right : undefined
    anchors.top:   parent ? parent.top   : undefined

    // ---- opaque background (Qt6/Wayland alpha-leak guard) ------------------
    Rectangle {
        id: bg
        anchors.fill: parent
        color: chrome.backgroundColor
        opacity: 1.0
    }

    // ---- hairline divider at the bottom (macOS chrome cue) -----------------
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.border
    }

    // ---- drag-to-move ------------------------------------------------------
    // Whole header is a drag handle (just like macOS). Double-click on the
    // bare header toggles maximize. We attach the MouseArea BEFORE the
    // RowLayout so the traffic-light MouseAreas (added later in z-order via
    // the RowLayout) win the press event on the dots themselves.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: function(mouse) {
            if (Window.window && Window.window.startSystemMove)
                Window.window.startSystemMove()
        }
        onDoubleClicked: chrome.maximize()
    }

    // ---- header layout -----------------------------------------------------
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        // Traffic lights — exact macOS Sequoia order: red, yellow, green.
        TrafficLight {
            kind: "close"
            isActive: chrome.isActive
            Layout.alignment: Qt.AlignVCenter
            onActivated: chrome.close()
        }
        TrafficLight {
            kind: "minimize"
            isActive: chrome.isActive
            Layout.alignment: Qt.AlignVCenter
            onActivated: chrome.minimize()
        }
        TrafficLight {
            kind: "maximize"
            isActive: chrome.isActive
            Layout.alignment: Qt.AlignVCenter
            onActivated: chrome.maximize()
        }

        // Breathing room between the lights and the title block.
        Item { Layout.preferredWidth: 8 }

        // Greedy spacers centre the title (matches Sequoia centred-title look).
        Item { Layout.fillWidth: true }
        Text {
            text: chrome.title
            font.pixelSize: 13
            font.weight: Font.Medium
            color: chrome.isActive ? Theme.textPrimary : Theme.textSecondary
            Layout.alignment: Qt.AlignVCenter
            elide: Text.ElideMiddle
        }
        Item { Layout.fillWidth: true }

        // Right-side slot for app-specific buttons (Finder's back/refresh/
        // search field, Settings' sidebar toggle, etc.). Apps pass widgets
        // via the `rightContent` default-property alias.
        Row {
            id: rightSlot
            spacing: 8
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
