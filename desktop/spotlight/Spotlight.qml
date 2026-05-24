// Spotlight overlay: centered glass panel with a single text input and a list
// of result groups (Apps, Files, Calculator, Hugging Face, arXiv).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Aurum.Aqua 1.0

Window {
    id: root
    visible: true
    width: 720
    height: Math.min(560, 120 + resultsView.contentHeight)
    // Position set imperatively in Component.onCompleted to avoid a binding
    // loop on `x` (Screen.width is constant but Qt's binding analyser flags
    // any expression that mixes window geometry with Screen.* at startup).
    x: 0
    y: 0
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    // Explicit AARRGGBB alpha=255 — see MenuBar.qml for the wlroots-headless
    // alpha-leak rationale. Theme.windowBg ("#1c1c1e") leaks alpha=0 under
    // Qt6 Wayland-EGL on the headless backend, producing pure-black frames
    // in wlr-screencopy. Hardcoding the AA byte fixes it.
    color: "#FF1c1c1e"
    title: "aurum-spotlight"

    Component.onCompleted: {
        x = Math.round((Screen.width  - width)  / 2)
        y = Math.round( Screen.height / 4)
        queryInput.forceActiveFocus()
    }

    // Esc closes the overlay (Hyprland will respawn it next Cmd+Space).
    Shortcut { sequence: "Esc";    onActivated: Qt.quit() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

    GlassPanel {
        id: panel
        anchors.fill: parent
        anchors.margins: 6
        radius: 16

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // --- Query field ----------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                radius: 10
                color: Theme.surfaceRaised
                border.color: Theme.border
                border.width: 1
                height: 44

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "⌕"
                        font.pixelSize: 20
                        color: Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    TextField {
                        id: queryInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 50
                        placeholderText: "Spotlight — try: hf llama, arxiv attention, 2+2"
                        font.pixelSize: 16
                        color: Theme.textPrimary
                        background: null
                        onTextChanged: typingTimer.restart()
                        Keys.onReturnPressed: resultsView.activateSelected()
                        Keys.onDownPressed:   resultsView.moveSelection(+1)
                        Keys.onUpPressed:     resultsView.moveSelection(-1)
                    }
                }
            }

            // Debounce typing into the aggregator: cheap plugins respond in
            // microseconds, but web plugins do their own debouncing too, so
            // we just need to coalesce the trailing keystroke at 80 ms.
            Timer {
                id: typingTimer
                interval: 80
                repeat: false
                onTriggered: aggregator.setQuery(queryInput.text)
            }

            // --- Results --------------------------------------------------
            ListView {
                id: resultsView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: aggregator.groups
                spacing: 8

                // Flat selection across all groups. We compute (groupIdx, rowIdx)
                // from a single 0-based selection number.
                property int selected: 0
                property int rowCountFlat: {
                    let n = 0
                    for (let i = 0; i < model.length; ++i) n += model[i].rows.length
                    return n
                }

                function moveSelection(d) {
                    if (rowCountFlat === 0) return
                    selected = Math.max(0, Math.min(rowCountFlat - 1, selected + d))
                }
                function activateSelected() {
                    if (rowCountFlat === 0) return
                    let n = selected
                    for (let i = 0; i < model.length; ++i) {
                        if (n < model[i].rows.length) {
                            aggregator.activate(model[i].rows[n].action)
                            Qt.quit()
                            return
                        }
                        n -= model[i].rows.length
                    }
                }

                delegate: ColumnLayout {
                    width: resultsView.width
                    spacing: 2

                    Text {
                        text: modelData.title
                        color: Theme.textSecondary
                        font.bold: true
                        font.pixelSize: 10
                        Layout.topMargin: 4
                    }

                    // Compute the flat index of the first row of this group.
                    property int groupFirstFlat: {
                        let n = 0
                        for (let i = 0; i < index; ++i) n += resultsView.model[i].rows.length
                        return n
                    }

                    Repeater {
                        model: modelData.rows
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: 8
                            color: (groupFirstFlat + index === resultsView.selected)
                                   ? Theme.accent
                                   : hover.containsMouse
                                     ? Theme.surfaceRaised
                                     : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Rectangle {           // icon placeholder
                                    width: 22; height: 22; radius: 5
                                    color: Theme.surfaceRaised
                                    border.color: Theme.border
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        text: modelData.title
                                        color: (groupFirstFlat + index === resultsView.selected)
                                               ? Theme.accentText : Theme.textPrimary
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                        width: resultsView.width - 80
                                    }
                                    Text {
                                        text: modelData.subtitle
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        width: resultsView.width - 80
                                    }
                                }
                            }

                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { resultsView.selected = groupFirstFlat + index; resultsView.activateSelected() }
                            }
                        }
                    }
                }
            }
        }
    }
}
