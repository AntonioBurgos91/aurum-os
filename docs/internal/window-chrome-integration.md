# `WindowChrome` integration guide

Wave 10 ships one reusable QML component — `Aurum.Aqua.WindowChrome` — that
draws the macOS Sequoia title-bar (traffic lights, drag-to-move header,
1-px hairline divider, 12-px rounded corners on the parent window) so every
AurumOS app looks identical. This document is the recipe for swapping the
nine apps that currently roll their own.

> **Scope.** Wave-11's lock screen and login manager will reuse the exact
> same component — keep the public API stable.

---

## Public API (recap)

```qml
import Aurum.Aqua 1.0

WindowChrome {
    title:           "Finder"
    backgroundColor: Theme.windowBg            // optional, defaults to windowBg
    headerHeight:    38                        // optional, default 38
    isActive:        Window.window.active      // optional, auto-binds

    onMinimize: window.showMinimized()
    onMaximize: window.visibility === Window.FullScreen
                  ? window.showNormal()
                  : window.showFullScreen()
    onClose:    window.close()

    // Optional: drop arbitrary widgets into the right slot (back / refresh /
    // search field / sidebar toggle …). Anything passed via `rightContent`
    // becomes a child of the inner Row laid out on the right edge.
    rightContent: [
        ToolButton { text: "‹"; onClicked: model.back() },
        ToolButton { text: "⟳"; onClicked: model.refresh() }
    ]
}
```

Signals are `minimize()`, `maximize()`, `close()`. The component is an
`Item`, so callers can either set it as `header:` of an `ApplicationWindow`
or anchor it inside a plain `Window` (Mission Control / Spotlight do the
latter because they are frameless overlays).

---

## Apps that need integration

All nine apps below currently contain a hand-rolled traffic-light block.
They must each replace that block with a single `WindowChrome` call. The
orchestrator will wire them up in a follow-up pass — this doc is the
checklist.

| # | App              | Root QML file                                              | Notes                                       |
|---|------------------|------------------------------------------------------------|---------------------------------------------|
| 1 | Finder           | `desktop/finder/Finder.qml`                                | Move search field / nav buttons to `rightContent` |
| 2 | Settings         | `desktop/settings/Settings.qml`                            | Already polished — only swap if the per-app TrafficLights differ in colour / size from `WindowChrome` |
| 3 | Mission Control  | `desktop/mission-control/MissionControl.qml`               | Frameless overlay — anchor chrome at the top |
| 4 | Spotlight        | `desktop/spotlight/Spotlight.qml`                          | Floating panel — slim header, no title text |
| 5 | Notifications    | `desktop/notifications/Notifications.qml`                  | Per-notification chrome is separate         |
| 6 | Installer        | `desktop/installer/Installer.qml`                          | Uses pages from `desktop/installer/pages/`  |
| 7 | Coming Soon      | `desktop/coming-soon/ComingSoon.qml`                       | Placeholder splash window                   |
| 8 | Dock             | `desktop/dock/Dock.qml`                                    | Slim header only when window is detached    |
| 9 | MenuBar          | `desktop/menubar/MenuBar.qml`                              | Top strip — only the divider colour applies |

> **`Settings.qml` is already polished.** Don't break it. Only swap its
> per-app traffic-lights for `WindowChrome` if the visual diff is identical;
> otherwise leave it alone and revisit after the others land.

---

## Worked example — `MissionControl.qml`

`MissionControl.qml` is the simplest of the nine (frameless, single inline
`component TrafficLight`, fixed `Row` in the top-left corner), so it is
shown here as the reference diff.

### Before (lines 24-73, abridged)

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Aurum.Aqua 1.0

Window {
    id: root
    visible: true
    width: Screen.width
    height: Screen.height
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    color: "#000000cc"

    // Inline TrafficLight component — must be at root scope.
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

    // Floating traffic-light row in the top-left corner of the overlay.
    Row {
        z: 100
        x: 24
        y: 24
        spacing: 8
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

    // ... body ...
}
```

### After

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Aurum.Aqua 1.0

Window {
    id: root
    visible: true
    width: Screen.width
    height: Screen.height
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    color: "#000000cc"

    // One-line replacement: shared chrome with the same traffic-light hues
    // every other AurumOS app uses. Mission Control has no visible title.
    WindowChrome {
        title: ""
        backgroundColor: "#00000000"                  // keep the tinted backdrop
        onClose:    Qt.quit()
        onMinimize: root.showMinimized()
        onMaximize: root.visibility === Window.FullScreen
                       ? root.showNormal()
                       : root.showFullScreen()
    }

    // ... body unchanged; anchor it to chrome.bottom or leave a top margin ...
}
```

The inline `component TrafficLight` block and the standalone `Row` both
disappear — together that is ~50 lines removed in exchange for a single
declarative `WindowChrome { ... }`.

---

## Mechanical replacement pattern (all 9 apps)

1. Add `import Aurum.Aqua 1.0` if the file does not already import it.
2. Delete the inline `component TrafficLight:` block (if any).
3. Delete the `Row { … TrafficLight … TrafficLight … TrafficLight … }`
   block (or, for Finder, the entire `header: ToolBar { … }` block).
4. Insert at the very top of the window's child list:

   ```qml
   WindowChrome {
       title: "<App name>"
       onClose:    Qt.quit()           // or window.close() if multi-window
       onMinimize: window.showMinimized()
       onMaximize: window.visibility === Window.FullScreen
                       ? window.showNormal()
                       : window.showFullScreen()
       // rightContent: [ … app-specific toolbar widgets … ]
   }
   ```

5. Anchor the body to `chrome.bottom` (or set `anchors.topMargin: 38`).
6. Confirm `QT_WAYLAND_DISABLE_WINDOWDECORATION=1` is still active for the
   binary — `WindowChrome` is the replacement title-bar, not an extra one.

---

## Future Theme.qml additions (Agent 10C)

`WindowChrome` currently hard-codes two constants that should migrate to
`Theme.qml` once Agent 10C lands the typography pass:

* `headerHeight: 38` → `Theme.windowChromeHeight`
* Traffic-light dimensions (`12 × 12`, `8 px` spacing) → `Theme.trafficLightSize`
  / `Theme.trafficLightSpacing`

Until then they live as exposed properties of `WindowChrome` itself, so
apps can override per-window if absolutely required.
