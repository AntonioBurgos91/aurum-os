// SettingsRow — one macOS-Sequoia-style label/control row inside a SectionCard.
//
// 40px tall, label left (13px regular), control right (max 240px wide).
// Hovering paints a 4px-radius hover background; a 1px hairline separator
// underlines the row unless `isLast: true` is set on the bottom row.
//
// Use as:
//
//     SettingsRow {
//         label:   "Tracking URI"
//         control: TextField { text: cfg.uri; onTextChanged: cfg.uri = text }
//     }
//     SettingsRow {
//         label:   "Experiment"
//         control: TextField { text: cfg.exp }
//         isLast:  true
//     }
//
// The `control` property reparents whatever Item you assign into the right
// slot, the same trick Qt's own Loader uses, so any QtQuick.Controls widget
// (Switch, ComboBox, Button, TextField, ProgressBar, …) drops in directly.
//
// Owned by Wave 10 Agent 10E.
import QtQuick
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    id: row

    // --- Public API -------------------------------------------------------
    property string label:  ""
    // `control` is a children-list alias on the right-hand slot Item: when a
    // caller writes `control: Switch {}`, the Switch becomes a child of
    // `controlSlot` and gets anchored/laid-out automatically. This is the
    // same default-property trick QtQuick uses for `Item { children: [...] }`.
    property alias  control: controlSlot.data
    property bool   isLast: false      // suppress the bottom hairline separator

    // --- Sizing ----------------------------------------------------------
    height: 40
    // Stretch to parent ColumnLayout width when one is present, fall back
    // to 600 (the SectionCard implicitWidth) when used standalone.
    implicitWidth: 600
    Layout.fillWidth: true

    // --- Hover background (rounded 4px) -----------------------------------
    Rectangle {
        anchors.fill: parent
        // `Theme.hoverBg` is the macOS Sequoia ~10% white tint, defined in
        // Theme.qml by Wave 10C; the `||` fallback keeps SettingsRow usable
        // in trees where Theme.qml predates that block.
        color:   hover.hovered ? (Theme.hoverBg || "#1affffff") : "transparent"
        radius:  4
    }
    HoverHandler { id: hover }

    // --- Label + control row ---------------------------------------------
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin:  12
        anchors.rightMargin: 12
        spacing: 12

        Text {
            text: row.label
            color: Theme.textPrimary
            font.pixelSize: 13
            Layout.fillWidth: true
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        // The control slot. Children assigned via `control: Switch {}` land
        // here; we anchor them ourselves at construction so callers don't
        // need to repeat layout boilerplate.
        // Max width 240px so multi-line TextFields don't blow the layout;
        // callers can override by binding Layout.preferredWidth on the
        // control itself.
        Item {
            id: controlSlot
            Layout.preferredWidth:  240
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            // Anchor every assigned child to fill the slot. Loop instead of
            // assuming a single child so a RowLayout-with-multiple-controls
            // pattern still works (e.g. two buttons side-by-side).
            onChildrenChanged: {
                for (var i = 0; i < children.length; ++i) {
                    var c = children[i]
                    if (c && c.anchors && !c.anchors.fill)
                        c.anchors.fill = controlSlot
                }
            }
        }
    }

    // --- Hairline separator (last row suppresses it) ----------------------
    Rectangle {
        visible: !row.isLast
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        height:  1
        color:   Theme.border
        opacity: 0.5
    }
}
