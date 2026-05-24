# Window Chrome Migration Guide

Status: Wave 10A landed (2026-05-26). Per-app wiring is scheduled for the next
wave / first manual pass.

Until Wave 10A every AurumOS app drew its own traffic lights inline. They drifted
in size, spacing, hover behaviour and even colour. The new `Aurum.Aqua.WindowChrome`
component is the single source of truth — one drop-in replaces all of them and
also draws the centered title, hairline divider, and the draggable header.

## TL;DR — three steps

1. `import Aurum.Aqua 1.0`
2. Set `flags: Qt.FramelessWindowHint` on the `Window` / `ApplicationWindow`
   (Wave 9 already does this via `QT_WAYLAND_DISABLE_WINDOWDECORATION=1`, so on
   Wayland you can leave the flag off — frameless is the default on session).
3. Drop a `WindowChrome { ... }` at the top of the window and anchor your body
   under it.

## Minimal example

```qml
import QtQuick
import QtQuick.Window
import Aurum.Aqua 1.0

Window {
    id: window
    width: 960; height: 600
    color: Theme.windowBg
    visible: true

    WindowChrome {
        id: chrome
        title: "Finder"
        onClose:    window.close()
        onMinimize: window.showMinimized()
        onMaximize: window.visibility === Window.FullScreen
                        ? window.showNormal()
                        : window.showFullScreen()
    }

    // ALL existing body content moves below the chrome:
    Item {
        anchors.top:    chrome.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        // ... your old root content here
    }
}
```

## Replacing an existing inline TrafficLight row

Most of the nine apps today have something like this near the top of their root
window:

```qml
RowLayout {
    spacing: 8
    Repeater {
        model: [...]
        delegate: Rectangle { /* red/yellow/green dot + MouseArea */ }
    }
    Text { text: "Finder"; ... }
}
```

Delete the whole RowLayout (plus the `Text` it contains, plus any `MouseArea`
covering the header that called `startSystemMove`) and replace it with:

```qml
WindowChrome {
    title: "Finder"
    onClose:    window.close()
    onMinimize: window.showMinimized()
    onMaximize: window.visibility === Window.FullScreen
                    ? window.showNormal() : window.showFullScreen()
}
```

That's the entire migration per app. Re-anchor the body content below
`chrome.bottom` and remove any leftover header padding the old design needed.

## Per-app notes

| App              | Path                                       | Notes                                                            |
|------------------|--------------------------------------------|------------------------------------------------------------------|
| finder           | `desktop/finder/Finder.qml`                | Has the canonical inline `component TrafficLight` — delete it.   |
| settings         | `desktop/settings/Settings.qml`            | Add a sidebar-toggle button via `rightContent`.                  |
| mission-control  | `desktop/mission-control/MissionControl.qml` | Full-screen — set `showTrafficLights: false` and `title: ""`.    |
| spotlight        | `desktop/spotlight/Spotlight.qml`          | Borderless overlay — do NOT use WindowChrome.                    |
| notifications    | `desktop/notifications/Notifications.qml`  | Small toast windows — do NOT use WindowChrome.                   |
| installer        | `desktop/installer/Installer.qml`          | Use `closeEnabled: false` until install finishes.                |
| coming-soon      | `desktop/coming-soon/ComingSoon.qml`       | Straight WindowChrome drop-in.                                   |
| dock             | `desktop/dock/Dock.qml`                    | Strip — no chrome. Skip.                                         |
| menubar          | `desktop/menubar/MenuBar.qml`              | Strip — no chrome. Skip.                                         |

## Optional toolbar buttons (right slot)

`WindowChrome` exposes `rightContent` as a default-property alias on an
internal `Row`. Pass widgets declaratively:

```qml
WindowChrome {
    title: "Finder"
    rightContent: [
        ToolButton { icon.name: "arrow-left"; onClicked: history.back() },
        ToolButton { icon.name: "view-refresh"; onClicked: model.refresh() }
    ]
}
```

The slot is right-aligned and vertically centered automatically.

## Inactive-window dimming

`WindowChrome.isActive` defaults to `Window.window.active`, so the traffic
lights collapse to a uniform mid-gray when the window loses focus — same as
macOS. Override with `isActive: false` if you want the dimmed look unconditionally
(e.g. modal that owns its parent's focus visually).

## Drag-to-move

The whole header is a drag handle. Double-click on the empty area toggles
maximize. `Window.startSystemMove()` is used on Qt6 — it's a no-op on backends
that don't support it, so the worst case is a non-draggable header (rather than
a crash). The traffic-light `MouseArea` instances stack above the header drag
area, so clicks on the dots never start a drag.

## Theme tokens

Wave 10A added these to `Theme.qml`:

```qml
readonly property int   windowChromeHeight: 28
readonly property color windowChromeBg:     "#FF1c1c1e"
readonly property color trafficClose:       "#FF5F57"
readonly property color trafficMin:         "#FEBC2E"
readonly property color trafficMax:         "#28C840"
readonly property color trafficDisabled:    "#555555"
```

Use them if you ever need to hand-paint a chrome-coloured surface (e.g. the
lock-screen panel in Wave 11).
