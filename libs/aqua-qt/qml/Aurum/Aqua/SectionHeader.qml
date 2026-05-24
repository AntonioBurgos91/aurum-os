// SectionHeader — macOS Sequoia "System Settings" style section heading.
//
// A 13px DemiBold title, optional 11px secondary subtitle below it, an
// optional 20×20 leading icon (SF Symbols glyph name; renders as text for
// now since AurumOS doesn't bundle SF — Agent 10D's IconLoader can be wired
// in later without changing this file's interface), and an optional
// right-side `action` button slot.
//
// Owned by Wave 10 Agent 10E. The visual contract here is shared by
// SectionCard.qml and every desktop/settings panel. Keep it stable.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Aurum.Aqua 1.0

Item {
    id: header

    // --- Public API -------------------------------------------------------
    property string title:    ""
    property string subtitle: ""
    property string icon:     ""   // SF Symbols name, or empty for no glyph

    // Optional trailing action: assign a Button (or anything) via
    //     SectionHeader { action: Button { text: "Reset" } }
    // and it lands flush-right on the title row. Implemented as a
    // children-list alias on the slot Item so assignments reparent the
    // child automatically (same trick as SettingsRow.control).
    property alias  action:   actionSlot.data

    // Layout: title row (icon + title + flex + action) on top,
    //         optional subtitle below.
    implicitWidth:  600
    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        anchors.left:  parent.left
        anchors.right: parent.right
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Leading icon slot (20×20). Renders the SF Symbols name as a
            // tiny placeholder label until Agent 10D wires real glyphs.
            // Hidden when `icon` is empty so spacing collapses cleanly.
            Item {
                visible: header.icon.length > 0
                Layout.preferredWidth:  20
                Layout.preferredHeight: 20
                Text {
                    anchors.centerIn: parent
                    text: header.icon.length > 0 ? "◉" : ""
                    color: Theme.textSecondary
                    font.pixelSize: 14
                }
            }

            Text {
                text: header.title
                color: Theme.textPrimary
                // Use Theme.fontWeightSemibold when present (Agent 10C),
                // fall back to Font.DemiBold to keep this file independent
                // of agent ordering.
                font.weight: (Theme.fontWeightSemibold !== undefined)
                             ? Theme.fontWeightSemibold
                             : Font.DemiBold
                font.pixelSize: 13
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // The action slot. Sized from the first child's implicit size
            // when present; collapses to zero otherwise so the title still
            // fills the row.
            Item {
                id: actionSlot
                Layout.preferredHeight: children.length > 0 && children[0].implicitHeight
                                        ? children[0].implicitHeight : 0
                Layout.preferredWidth:  children.length > 0 && children[0].implicitWidth
                                        ? children[0].implicitWidth  : 0
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                visible: children.length > 0
                onChildrenChanged: {
                    for (var i = 0; i < children.length; ++i) {
                        var c = children[i]
                        if (c && c.anchors && !c.anchors.fill)
                            c.anchors.fill = actionSlot
                    }
                }
            }
        }

        Text {
            visible: header.subtitle.length > 0
            text: header.subtitle
            color: Theme.textSecondary
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
