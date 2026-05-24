// Mission Control: grid of workspaces, each with miniature tiles for its
// clients. Click a tile to focus that window (Hyprland will switch workspace
// for us); ESC or click-on-background closes the overlay.
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
    color: "#000000cc"  // tinted backdrop; Hyprland still composites it over the wallpaper

    Component.onCompleted: hypr.refresh()

    // Keyboard close.
    Shortcut { sequence: "Esc";    onActivated: Qt.quit() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

    // Inline TrafficLight component — must be at root scope (Qt6 only finds
    // inline components in the immediate containing object's scope).
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
    // Mission Control is a frameless full-screen surface, so we provide our
    // own close/minimize/fullscreen affordances. z keeps them above the
    // background MouseArea that closes the overlay on backdrop click.
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

    // Click on the empty backdrop also closes.
    MouseArea {
        anchors.fill: parent
        onClicked: Qt.quit()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 60
        spacing: 24

        Text {
            text: "Mission Control"
            color: Theme.textPrimary
            font.bold: true
            font.pixelSize: 22
        }

        GridView {
            id: wsGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: hypr.workspaces
            cellWidth:  Math.max(360, width / 4)
            cellHeight: Math.max(220, height / 3)
            interactive: false

            delegate: Item {
                width: wsGrid.cellWidth - 16
                height: wsGrid.cellHeight - 16

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 8
                    radius: Theme.cornerRadius
                    color: modelData.id === hypr.activeWorkspaceId
                           ? Theme.accent : Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    opacity: 0.96

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6

                        Row {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "Space " + modelData.id
                                color: modelData.id === hypr.activeWorkspaceId
                                       ? Theme.accentText : Theme.textPrimary
                                font.bold: true
                                font.pixelSize: 13
                            }
                            Text {
                                text: " " + modelData.windows + " win"
                                color: Theme.textSecondary
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Window tiles.
                        Flow {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6
                            Repeater {
                                model: {
                                    var w = []
                                    for (var i = 0; i < hypr.clients.length; ++i) {
                                        if (hypr.clients[i].workspaceId === modelData.id)
                                            w.push(hypr.clients[i])
                                    }
                                    return w
                                }
                                Rectangle {
                                    width: 132
                                    height: 72
                                    radius: Theme.cornerRadiusSm
                                    color: Theme.surfaceRaised
                                    border.color: modelData.focused ? Theme.accent : Theme.border
                                    border.width: modelData.focused ? 2 : 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 2
                                        Text {
                                            text: modelData.class
                                            color: Theme.textPrimary
                                            font.bold: true
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: modelData.title
                                            color: Theme.textSecondary
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            hypr.focus(modelData.address)
                                            Qt.quit()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Click on workspace background → switch + close.
                    //
                    // NB: do NOT use `propagateComposedEvents: true` here — that
                    // pattern is known-broken on Qt6/Wayland (clicks get
                    // swallowed by the outer MouseArea regardless). Instead we
                    // rely on the `z: -1` ordering: the background MouseArea
                    // sits BEHIND the window-tile MouseAreas, so their hit-test
                    // wins for clicks inside a tile, and clicks on the empty
                    // workspace area fall through to this one naturally.
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            hypr.gotoWorkspace(modelData.id)
                            Qt.quit()
                        }
                        z: -1  // sit below the window tiles so their clicks win
                    }
                }
            }
        }
    }
}
