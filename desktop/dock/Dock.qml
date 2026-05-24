// AurumOS dock — pinned launchers with macOS-style magnification.
//
// Magnification model: each icon's scale is a Gaussian of the distance between
// its center and the cursor X position. Hovering one icon also pushes the
// immediate neighbors larger, exactly like macOS. When the cursor leaves the
// dock area, every icon eases back to 1.0.
import QtQuick
import QtQuick.Window
import QtQuick.Controls
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
    readonly property real magnificationPeak:  1.55
    readonly property real magnificationSigma: 70.0

    GlassPanel {
        id: dockShelf
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        height: Theme.dockHeight
        width:  iconsRow.width + dividerSpacer.width + gpuBadge.width + 48

        // Track cursor X relative to the row of icons. -1 means "not hovering".
        property real cursorX: -1

        // CRITICAL: we use HoverHandler — NOT a MouseArea — for cursor tracking.
        //
        // Earlier this was a MouseArea with `acceptedButtons: Qt.NoButton` +
        // `propagateComposedEvents: true`, which Qt5/X11 honors as "track hover
        // but pass clicks to children". On Qt6/Wayland that combination is
        // BROKEN: the outer MouseArea swallows the click events even with
        // NoButton, because Wayland delivers pointer.button events to the
        // first hit-tested surface and Qt's composition layer doesn't bubble
        // them to siblings. Result: hover events reached the icon (cursor
        // changed shape) but clicks never did — every dock icon was visually
        // alive but functionally dead.
        //
        // HoverHandler is the Qt6-native fix: it tracks hover state without
        // ever consuming pointer button events, so the inner per-icon
        // MouseAreas receive clicks normally. Costs us tracking inside icon
        // gaps (6 px spacing) — but the Gaussian magnification looks fine
        // because cursorX still updates each time the cursor crosses any icon.
        HoverHandler {
            id: hoverTracker
            target: parent
            onPointChanged: dockShelf.cursorX = hoverTracker.point.position.x - iconsRow.x
            onHoveredChanged: if (!hovered) dockShelf.cursorX = -1
        }

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

                    // Center of THIS icon in iconsRow coordinates.
                    readonly property real centerX: x + width / 2

                    // Gaussian magnification:
                    //   scale = 1 + (peak-1) * exp(-d² / σ²)
                    // d is the absolute distance from cursor to this icon's center.
                    // When cursor is absent (cursorX < 0), scale falls back to 1.
                    readonly property real distance:
                        dockShelf.cursorX < 0 ? 1e6 : Math.abs(centerX - dockShelf.cursorX)
                    readonly property real targetScale:
                        1 + (root.magnificationPeak - 1)
                            * Math.exp(- (distance * distance)
                                       / (root.magnificationSigma * root.magnificationSigma))

                    scale: targetScale
                    Behavior on scale {
                        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
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
}
