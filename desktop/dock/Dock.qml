// AurumOS dock — pinned launchers with macOS-style magnification.
//
// Magnification model: each icon's scale is a Gaussian of the distance between
// its center and the cursor X position. Hovering one icon also pushes the
// immediate neighbors larger, exactly like macOS. When the cursor leaves the
// dock area, every icon eases back to 1.0.
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Window {
    id: root
    visible: true
    width: dockShelf.width + 40
    height: Theme.dockHeight + 16
    title: "aurum-dock"

    // Position at bottom center. Hyprland's windowrules (see
    // distro/seed/hypr/hyprland.conf) keep it pinned and chrome-less.
    x: 0
    y: 0
    Component.onCompleted: {
        x = (Screen.width  - width)  / 2
        y =  Screen.height - height - 8
    }
    onWidthChanged: {
        x = (Screen.width  - width)  / 2
    }

    // See MenuBar.qml: removed `Qt.WindowDoesNotAcceptFocus` because Qt6 on
    // Wayland (Hyprland 0.55) interprets it as "don't deliver input at all",
    // which broke every dock-icon click.
    flags: Qt.FramelessWindowHint
         | Qt.WindowStaysOnTopHint
         | Qt.Tool
    // See MenuBar.qml for the rationale: explicit AARRGGBB alpha=255 keeps
    // wlroots headless screencopy from emitting black pixels. The Theme.windowBg
    // string is the same #1c1c1e but Qt6 Wayland-EGL can leak alpha=0 from the
    // EGL clearcolor on headless backends.
    color: "#FF1c1c1e"

    // --- Magnification parameters ---------------------------------------------
    // sigma controls falloff width; bigger sigma = more icons grow at once.
    // peak is the scale factor of the icon directly under the cursor.
    readonly property real magnificationPeak:  1.8
    readonly property real magnificationSigma: 90.0

    GlassPanel {
        id: dockShelf
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        height: Theme.dockHeight
        width:  iconsRow.width + dividerSpacer.width + gpuBadge.width + 48

        // Index of the icon the pointer is currently over; -1 == none.
        //
        // IMPORTANT — why index-based and not cursor-X-based:
        // Under wlroots + wayvnc (the headless preview transport), Qt only
        // receives pointer ENTER/EXIT for a surface — it does NOT get the
        // continuous pointer-MOTION stream. We verified this with logging: a
        // MouseArea's onEntered/onExited and a per-icon containsMouse both
        // fire, but onPositionChanged / HoverHandler.point.position never
        // update. So a Gaussian-of-cursor-X effect can't work here. Instead we
        // magnify by DISTANCE-IN-ICONS from whichever icon reports
        // containsMouse: hovered icon biggest, immediate neighbours a step
        // smaller. Looks macOS-like and only needs enter/exit, which we have.
        property int hoveredIndex: -1

        Row {
            id: iconsRow
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: dockModel

                delegate: Item {
                    id: cell
                    width:  Theme.dockIconSize
                    height: Theme.dockIconSize
                    anchors.verticalCenter: parent.verticalCenter

                    // Magnify by distance-in-icons from the hovered one. The
                    // hovered icon (d=0) gets the full peak; each step away
                    // falls off on a Gaussian in INDEX space (sigma ~1.3 icons),
                    // which mimics the macOS neighbour bulge without needing the
                    // continuous cursor X that wayvnc won't deliver.
                    readonly property int idxDist:
                        dockShelf.hoveredIndex < 0 ? 999
                                                   : Math.abs(index - dockShelf.hoveredIndex)
                    readonly property real targetScale:
                        dockShelf.hoveredIndex < 0
                            ? 1.0
                            : 1 + (root.magnificationPeak - 1)
                                  * Math.exp(- (idxDist * idxDist) / (1.3 * 1.3))

                    scale: targetScale
                    Behavior on scale {
                        NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic }
                    }
                    transformOrigin: Item.Bottom

                    // --- Icon -------------------------------------------------
                    Image {
                        id: iconImg
                        anchors.fill: parent
                        source: model.iconUrl
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        cache: true
                        visible: status === Image.Ready

                        // Fallback chip when the XDG icon theme didn't resolve.
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.cornerRadiusSm
                            color: Theme.surfaceRaised
                            border.color: Theme.border
                            visible: iconImg.status !== Image.Ready
                            Text {
                                anchors.centerIn: parent
                                text: model.name ? model.name.charAt(0) : "?"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: 18
                            }
                        }
                    }

                    // Tooltip with the app's full name.
                    ToolTip.visible: clickArea.containsMouse
                    ToolTip.text:    model.name
                    ToolTip.delay:   400

                    // Running indicator dot (mocked in Phase 2).
                    Rectangle {
                        width: 4; height: 4; radius: 2
                        color: Theme.textPrimary
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -6
                        visible: model.isRunning
                    }

                    MouseArea {
                        id: clickArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dockModel.launch(index)
                        // enter/exit DO arrive under wayvnc — drive the
                        // magnification from them.
                        onEntered: dockShelf.hoveredIndex = index
                        onExited:  if (dockShelf.hoveredIndex === index)
                                       dockShelf.hoveredIndex = -1
                    }
                }
            }

            // ML Tools Group
            Item {
                id: mlToolsCell
                width:  Theme.dockIconSize
                height: Theme.dockIconSize
                anchors.verticalCenter: parent.verticalCenter

                // ML cell magnifies on its own hover (enter/exit), consistent
                // with the index-based model used by the main shelf.
                readonly property real targetScale:
                    mlToolsClickArea.containsMouse ? root.magnificationPeak : 1.0

                scale: targetScale
                Behavior on scale {
                    NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic }
                }
                transformOrigin: Item.Bottom

                Image {
                    id: mlToolsIconImg
                    anchors.fill: parent
                    // freedesktop name resolved via the installed icon theme
                    // (Papirus) through DockModel::iconUrlForName, the same
                    // QIcon::fromTheme path the main shelf uses. Falls back to
                    // the labeled chip below if the theme can't resolve it.
                    source: dockModel.iconUrlForName("applications-science")
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: status === Image.Ready

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadiusSm
                        color: Theme.surfaceRaised
                        border.color: Theme.border
                        visible: mlToolsIconImg.status !== Image.Ready
                        Text {
                            anchors.centerIn: parent
                            text: "ML"
                            color: Theme.textPrimary
                            font.bold: true
                            font.pixelSize: 14
                        }
                    }
                }

                ToolTip.visible: mlToolsClickArea.containsMouse
                ToolTip.text:    "ML Tools"
                ToolTip.delay:   400

                MouseArea {
                    id: mlToolsClickArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        drawerWindow.toggle()
                    }
                }
            }
        }

        // --- Divider + GPU badge ---------------------------------------------
        Item {
            id: dividerSpacer
            anchors.left: iconsRow.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            width: 1
            height: 36
            Rectangle {
                anchors.fill: parent
                color: Theme.border
            }
        }

        MetricBadge {
            id: gpuBadge
            anchors.left: dividerSpacer.right
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            label: "GPU"
            valueNumeric: gpuClient.gpuUtilization
            valueText: gpuClient.gpuUtilization + "%"

            ToolTip.visible: gpuMouse.containsMouse
            ToolTip.text: gpuClient.gpuName + "\n" +
                          "VRAM: " + gpuClient.vramUsedGb.toFixed(1) +
                          " / "    + gpuClient.vramTotalGb.toFixed(1) + " GB\n" +
                          "Temp: " + gpuClient.gpuTemp + " °C"
            ToolTip.delay: 200

            MouseArea {
                id: gpuMouse
                anchors.fill: parent
                hoverEnabled: true
            }
        }
    }

    // --- Inline component for drawer icons ---
    component DrawerIcon: ColumnLayout {
        id: di
        property string iconName: ""
        property string label: ""
        // freedesktop icon name used for theme resolution; defaults to the
        // same science glyph the ML .desktop files declare.
        property string themeIcon: "applications-science"
        signal triggered()

        spacing: 4
        Layout.preferredWidth: 48
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            id: iconFrame
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            Layout.alignment: Qt.AlignHCenter
            radius: 8
            color: iconMouse.containsMouse ? Theme.surfaceRaised : "transparent"
            border.color: iconMouse.containsMouse ? Theme.border : "transparent"

            Image {
                id: diIcon
                anchors.centerIn: parent
                width: 32; height: 32
                // Resolve via the icon theme; the .desktop files for these apps
                // use the freedesktop name "applications-science", so we use the
                // same here and fall back to a labeled chip if it can't resolve.
                source: dockModel.iconUrlForName(di.themeIcon)
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: status === Image.Ready
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.cornerRadiusSm
                color: Theme.surfaceRaised
                border.color: Theme.border
                visible: diIcon.status !== Image.Ready
                Text {
                    anchors.centerIn: parent
                    text: di.label ? di.label.charAt(0) : "?"
                    color: Theme.textPrimary
                    font.bold: true
                    font.pixelSize: 14
                }
            }

            MouseArea {
                id: iconMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: di.triggered()
            }
        }

        Text {
            text: di.label
            color: Theme.textPrimary
            font.pixelSize: 10
            Layout.alignment: Qt.AlignHCenter
            elide: Text.ElideRight
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // --- ML Tools Drawer Window ---
    Window {
        id: drawerWindow
        visible: false
        width: 200
        height: 90
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
        color: "#FF1c1c1e" // solid sequoia dark

        property real slideY: height

        onVisibleChanged: {
            if (visible) {
                // Position above the ML Tools cell
                let globalPos = mlToolsCell.mapToItem(null, 0, 0)
                drawerWindow.x = root.x + globalPos.x + (mlToolsCell.width * mlToolsCell.scale - drawerWindow.width) / 2
                drawerWindow.y = root.y - drawerWindow.height - 8
                slideAnim.start()
            }
        }

        function toggle() {
            if (visible) {
                visible = false
            } else {
                visible = true
            }
        }

        NumberAnimation {
            id: slideAnim
            target: drawerWindow
            property: "slideY"
            from: drawerWindow.height
            to: 0
            duration: Theme.durationFast
            easing.type: Easing.OutCubic
        }

        GlassPanel {
            id: drawerPanel
            anchors.fill: parent
            radius: Theme.cornerRadius
            y: drawerWindow.slideY

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                Text {
                    text: "ML Tools"
                    color: Theme.textSecondary
                    font.bold: true
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.alignment: Qt.AlignHCenter
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Layout.alignment: Qt.AlignHCenter

                    DrawerIcon {
                        iconName: "aurum-model-manager"
                        label: "Models"
                        onTriggered: {
                            drawerWindow.visible = false
                            dockModel.launchByName("aurum-model-manager")
                        }
                    }

                    DrawerIcon {
                        iconName: "aurum-mlflow"
                        label: "MLflow"
                        onTriggered: {
                            drawerWindow.visible = false
                            dockModel.launchByName("aurum-mlflow")
                        }
                    }

                    DrawerIcon {
                        iconName: "aurum-tensorboard"
                        label: "TensorBoard"
                        onTriggered: {
                            drawerWindow.visible = false
                            dockModel.launchByName("aurum-tensorboard")
                        }
                    }
                }
            }
        }
    }
}
