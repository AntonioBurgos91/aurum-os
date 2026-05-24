// macOS-style close/minimize/maximize dots. Phase 2 ships them as a visual
// primitive only — wiring them to wlroots foreign-toplevel actions lands in
// the per-window decoration layer in a later phase.
import QtQuick
import Aurum.Aqua 1.0

Row {
    id: root
    spacing: 8

    signal closeRequested()
    signal minimizeRequested()
    signal maximizeRequested()

    Repeater {
        model: [
            { color: "#ff5f57", signalName: "closeRequested" },
            { color: "#febc2e", signalName: "minimizeRequested" },
            { color: "#28c840", signalName: "maximizeRequested" }
        ]
        delegate: Rectangle {
            width: 12
            height: 12
            radius: 6
            color: modelData.color
            border.color: Qt.darker(modelData.color, 1.4)
            border.width: 1

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (modelData.signalName === "closeRequested")    root.closeRequested()
                    if (modelData.signalName === "minimizeRequested") root.minimizeRequested()
                    if (modelData.signalName === "maximizeRequested") root.maximizeRequested()
                }
            }
        }
    }
}
