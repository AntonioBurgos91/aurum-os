import QtQuick

// Reusable scale animation for popup overlays (Spotlight, app switcher).
// 200ms ease-out, matches compositor specialWorkspace timing.
// Bind via:
//   transform: Scale { id: s; origin.x: width/2; origin.y: height/2 }
//   Behavior on s.xScale { ScaleTransition {} }
//   Behavior on s.yScale { ScaleTransition {} }
NumberAnimation {
    duration: 200
    easing.type: Easing.OutCubic
}
