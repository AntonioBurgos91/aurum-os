// TrafficLight — single macOS Sequoia traffic-light dot.
//
// Extracted from desktop/finder/Finder.qml's inline `component TrafficLight`
// so every AurumOS app (and the Wave-11 lock screen / login manager) renders
// the close/minimize/maximize affordance identically.
//
// Visual rules (Sequoia):
//   - 12x12 px circle, 1-px darker hairline border, subtle vertical gradient.
//   - When the parent window is INACTIVE all three dots collapse to a single
//     mid-gray (#7F7F7F). When ACTIVE each kind has its own hue.
//   - Hover: brighten ~15% AND reveal the macOS symbol overlay (×, −, +) in
//     dark gray (#1f1f1f) so the user can see which dot does what.
//   - Click feedback: scale to 0.9 for 80 ms before emitting `activated()`.
//
// This file is intentionally self-contained — it does NOT pull in Theme so it
// can be used from the lock screen (which runs before the user session and
// therefore before the Aqua singleton is necessarily resolvable).
import QtQuick

Item {
    id: root

    // ---- public API --------------------------------------------------------
    property string kind: "close"        // "close" | "minimize" | "maximize"
    property bool   isActive: true       // false → dim/inactive look
    signal activated()

    // ---- geometry ----------------------------------------------------------
    implicitWidth: 12
    implicitHeight: 12

    // ---- color table -------------------------------------------------------
    // Active hues from Sequoia; inactive collapses to a uniform gray as macOS
    // does when the window loses key focus.
    readonly property color _activeColor:
        kind === "close"    ? "#FF5F57" :
        kind === "minimize" ? "#FEBC2E" :
        kind === "maximize" ? "#28C840" :
                              "#7F7F7F"
    readonly property color _inactiveColor: "#7F7F7F"
    readonly property color _baseColor: isActive ? _activeColor : _inactiveColor

    // Hover state: brighten ~15% (Qt.lighter 1.15 is the Sequoia approximation).
    readonly property color _hoverColor: Qt.lighter(_baseColor, 1.15)

    // Symbol overlay text for each kind.
    readonly property string _symbol:
        kind === "close"    ? "\u00D7" :    // ×
        kind === "minimize" ? "\u2212" :    // −
        kind === "maximize" ? "+"      :
                              ""

    // ---- visual ------------------------------------------------------------
    Rectangle {
        id: dot
        anchors.fill: parent
        radius: width / 2
        color: hoverArea.containsMouse ? root._hoverColor : root._baseColor
        border.color: Qt.darker(color, 1.4)
        border.width: 1

        // Subtle top-to-bottom gradient inside the dot for the glossy look.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(dot.color, 1.30) }
                GradientStop { position: 1.0; color: dot.color }
            }
        }

        // Symbol overlay — only painted when the user hovers AND the window
        // is active. Matches the Sequoia behaviour where inactive lights stay
        // uniformly gray with no symbol.
        Text {
            anchors.centerIn: parent
            text: root._symbol
            visible: hoverArea.containsMouse && root.isActive
            color: "#1f1f1f"
            font.pixelSize: 10
            font.weight: Font.Bold
        }

        // Click feedback: scale 0.9 for 80 ms via a SequentialAnimation that
        // fires on press. We trigger `activated()` from onReleased so the
        // animation has time to start (the eye picks up the dip even though
        // the signal handler runs immediately after).
        scale: 1.0
        Behavior on scale {
            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: dot.scale = 0.9
        onReleased: {
            dot.scale = 1.0
            if (containsMouse) root.activated()
        }
        onCanceled: dot.scale = 1.0
    }
}
