import QtQuick

// Reusable opacity fade for QML in/out (use with `Behavior on opacity { FadeTransition {} }`).
// Default 150ms ease-out matches the compositor's windowsIn timing for visual cohesion.
// See docs/internal/animation-policy.md for the broader selective-animation policy
// and the ADR-0006 performance budget this duration was chosen against.
NumberAnimation {
    duration: 150
    easing.type: Easing.OutCubic
}
