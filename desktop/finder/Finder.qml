// AurumOS Finder — three columns: sidebar, file list, Quick Look preview.
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 1100
    height: 700
    title: "Finder — " + finderModel.currentPath
    // Explicit AARRGGBB alpha=255 — see MenuBar.qml for the wlroots-headless
    // alpha-leak rationale. Theme.windowBg ("#1c1c1e") leaks alpha=0 under
    // Qt6 Wayland-EGL on the headless backend, producing pure-black frames
    // in wlr-screencopy. Hardcoding the AA byte fixes it.
    color: "#FF1c1c1e"

    // Selection lives on the window root so the preview pane can react.
    property int selectedRow: -1

    // Close shortcut. Esc is deliberately NOT bound here — the search field
    // uses Keys.onEscapePressed to clear/blur, and a global Esc would steal
    // that event before the field saw it.
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

    // Inline component — declared at root scope (Qt6 only finds inline
    // components in the immediate containing object's scope). A previous
    // version defined this inside the header's RowLayout which caused the
    // QML engine to silently fail loading the file at runtime — the binary
    // would print the aqua-qt init banner then exit 0 with no window.
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

    // --- Title bar / toolbar (macOS Sequoia style) --------------------------
    // Custom chrome because we set QT_WAYLAND_DISABLE_WINDOWDECORATION=1 to
    // stop Qt from drawing its own native title bar. We then draw the macOS
    // analogue ourselves: three traffic lights on the left, breadcrumb in the
    // middle, search field on the right. The title-bar is the same height as
    // the macOS Big Sur+ title bar (52 px) so the proportions read correctly.
    header: ToolBar {
        id: titleBar
        height: 52
        background: Rectangle {
            color: "#FF2a2a2e"        // very-slightly-lighter than windowBg
            Rectangle {                // 1-px hairline at the bottom edge
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: "#3c3c42"
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            // ----- Traffic lights (TrafficLight component declared at root) -
            Row {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter
                TrafficLight {
                    baseColor: "#ff5f57"            // red — close
                    onTrigger: Qt.quit()
                }
                TrafficLight {
                    baseColor: "#ffbd2e"            // yellow — minimize
                    onTrigger: root.showMinimized()
                }
                TrafficLight {
                    baseColor: "#28c941"            // green — toggle fullscreen
                    onTrigger: root.visibility === Window.FullScreen
                                 ? root.showNormal()
                                 : root.showFullScreen()
                }
            }

            // ----- Navigation buttons --------------------------------------
            Item { width: 8; height: 1 }   // small gap after the lights
            ToolButton {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 28; implicitHeight: 28
                text: "‹"
                font.pixelSize: 20
                onClicked: finderModel.cdUp()
                ToolTip.text: "Back"
                ToolTip.visible: hovered
                ToolTip.delay: 500
            }
            ToolButton {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 28; implicitHeight: 28
                text: "⟳"
                onClicked: finderModel.refresh()
                ToolTip.text: "Refresh"
                ToolTip.visible: hovered
                ToolTip.delay: 500
            }

            // ----- Breadcrumb (centre, takes leftover space) ---------------
            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: finderModel.currentPath
                color: Theme.textPrimary
                elide: Text.ElideMiddle
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
            }

            // ----- Search field --------------------------------------------
            // 220-px rounded text input. As the user types we call
            // finderModel.setFilter(text) which re-filters the listing in O(N).
            // Empty string clears.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 220
                implicitHeight: 28
                radius: 7
                color: Theme.surfaceRaised
                border.color: searchField.activeFocus ? Theme.accent : Theme.border
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6
                    Text {
                        text: "⌕"
                        color: Theme.textSecondary
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    TextField {
                        id: searchField
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 30
                        placeholderText: "Search in folder"
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        background: null    // we provide the chrome above
                        selectByMouse: true
                        onTextChanged: finderModel.setFilter(text)
                        Keys.onEscapePressed: { text = ""; focus = false }
                    }
                }
            }
        }
    }

    // --- Body: sidebar | list | preview -------------------------------------
    SplitView {
        anchors.fill: parent
        orientation: Qt.Horizontal

        // ---------- Sidebar ------------------------------------------------
        Rectangle {
            id: sidebar
            SplitView.preferredWidth: 200
            SplitView.minimumWidth: 160
            color: Theme.surface

            ListView {
                anchors.fill: parent
                anchors.margins: 8
                model: sidebarModel
                spacing: 2
                clip: true

                section.property: "section"
                section.criteria: ViewSection.FullString
                section.delegate: Text {
                    text: section
                    color: Theme.textSecondary
                    font.bold: true
                    font.pixelSize: 10
                    height: 22
                    leftPadding: 6
                    verticalAlignment: Text.AlignVCenter
                }

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 26
                    radius: 6
                    color: hovered.containsMouse ? Theme.surfaceRaised : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        spacing: 6
                        Rectangle {           // icon placeholder (no XDG icon resolver here)
                            width: 14; height: 14; radius: 3
                            color: Theme.textSecondary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: model.name
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: hovered
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.selectedRow = -1; finderModel.cd(model.path) }
                    }
                }
            }
        }

        // ---------- File list ---------------------------------------------
        ListView {
            id: filesList
            SplitView.fillWidth: true
            clip: true
            model: finderModel
            spacing: 0

            delegate: Rectangle {
                width: ListView.view.width
                height: 28
                color: index === root.selectedRow ? Theme.accent
                      : hover.containsMouse        ? Theme.surfaceRaised
                      :                              "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    spacing: 10

                    // Kind chip — tiny colored square so directories vs files
                    // vs notebooks vs models are scannable at a glance.
                    Rectangle {
                        width: 10; height: 10; radius: 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: model.kind === "dir"      ? Theme.accent
                             : model.kind === "notebook" ? Theme.warning
                             : model.kind === "model"    ? Theme.success
                             : model.kind === "dataset"  ? Theme.danger
                             :                              Theme.textSecondary
                    }

                    Text {
                        text: model.name
                        color: index === root.selectedRow ? Theme.accentText : Theme.textPrimary
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: Math.max(120, parent.width - 280)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: model.isDir ? "—" : humanSize(model.size)
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        width: 80
                        horizontalAlignment: Text.AlignRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: model.mtime ? model.mtime.substring(0, 16).replace("T", " ") : ""
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.selectedRow = index
                    onDoubleClicked: {
                        if (model.isDir) finderModel.cd(model.absolutePath)
                        // Files: launching a non-dir from Finder requires MIME
                        // handling, deferred to a later phase.
                    }
                }
            }
        }

        // ---------- Quick Look preview ------------------------------------
        Rectangle {
            id: previewPane
            SplitView.preferredWidth: 320
            SplitView.minimumWidth: 240
            color: Theme.surface

            // Re-derive the preview JSON whenever the selection changes.
            property var previewObj: ({})
            Connections {
                target: root
                function onSelectedRowChanged() {
                    if (root.selectedRow < 0) { previewPane.previewObj = ({}); return }
                    const raw = finderModel.previewJson(root.selectedRow)
                    try {
                        previewPane.previewObj = raw ? JSON.parse(raw) : ({})
                    } catch (e) {
                        previewPane.previewObj = { error: "preview decode failed" }
                    }
                }
            }

            ScrollView {
                anchors.fill: parent
                anchors.margins: 12
                clip: true

                ColumnLayout {
                    width: previewPane.width - 24
                    spacing: 8

                    Text {
                        text: "Quick Look"
                        color: Theme.textSecondary
                        font.bold: true
                        font.pixelSize: 10
                    }
                    Text {
                        text: previewPane.previewObj.path || "—"
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        wrapMode: Text.WrapAnywhere
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.border
                    }

                    // Format-specific payload renderers ----------------------
                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: previewPane.previewObj.error
                            ? errComp
                            : previewPane.previewObj.kind === "notebook"    ? nbComp
                            : previewPane.previewObj.kind === "safetensors" ? stComp
                            : previewPane.previewObj.kind === "parquet"     ? pqComp
                            : defaultComp
                    }
                }
            }

            // --- Renderers ----------------------------------------------
            Component {
                id: errComp
                Text {
                    text: "⚠ " + (previewPane.previewObj.error || "Unsupported file type")
                    color: Theme.warning
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
            Component {
                id: defaultComp
                Text {
                    text: "No preview available."
                    color: Theme.textSecondary
                    font.pixelSize: 12
                }
            }
            Component {
                id: nbComp
                ColumnLayout {
                    spacing: 6
                    Text {
                        text: "Notebook (" + (previewPane.previewObj.preview.total_cells || 0) + " cells)"
                        color: Theme.textPrimary
                        font.bold: true
                    }
                    Repeater {
                        model: previewPane.previewObj.preview.cells || []
                        Rectangle {
                            Layout.fillWidth: true
                            radius: 6
                            color: Theme.surfaceRaised
                            border.color: Theme.border
                            implicitHeight: cellTxt.implicitHeight + 16
                            Text {
                                id: cellTxt
                                text: (modelData.type === "code" ? "▷ " : "📝 ") + (modelData.source || "")
                                color: Theme.textPrimary
                                font.family: "FiraCode"
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                width: parent.width - 16
                                x: 8; y: 8
                            }
                        }
                    }
                }
            }
            Component {
                id: stComp
                ColumnLayout {
                    spacing: 6
                    Text {
                        text: previewPane.previewObj.preview.total_tensors + " tensors  ·  " +
                              previewPane.previewObj.preview.total_params  + " params"
                        color: Theme.textPrimary
                        font.bold: true
                    }
                    Repeater {
                        model: previewPane.previewObj.preview.tensors || []
                        Text {
                            Layout.fillWidth: true
                            text: modelData.name + "    " + modelData.dtype +
                                  "  " + JSON.stringify(modelData.shape)
                            color: Theme.textPrimary
                            font.family: "FiraCode"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }
            Component {
                id: pqComp
                ColumnLayout {
                    spacing: 6
                    Text {
                        text: (previewPane.previewObj.preview.rows || 0) + " rows"
                        color: Theme.textPrimary
                        font.bold: true
                    }
                    Repeater {
                        model: previewPane.previewObj.preview.schema || []
                        Text {
                            Layout.fillWidth: true
                            text: modelData.name + "    " + modelData.type
                            color: Theme.textPrimary
                            font.family: "FiraCode"
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    // Small helper: bytes → "12.4 MB" style.
    function humanSize(bytes) {
        if (!bytes) return "0 B"
        const units = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        let v = bytes
        while (v >= 1024 && i < units.length - 1) { v /= 1024; ++i }
        return v.toFixed(v < 10 && i > 0 ? 1 : 0) + " " + units[i]
    }
}
