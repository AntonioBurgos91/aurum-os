// SectionCard — the unified macOS Sequoia "System Settings" panel card.
//
// Every Settings panel (GpuSection, CudaSection, PythonVenvsSection,
// MlopsSection, HardwarePanel, ModelPacksPanel, …) wraps its content blocks
// in one or more SectionCards so the whole app reads as one coherent design
// rather than the seven-different-styles patchwork we had after waves 7-9.
//
// Visual contract:
//   • white-ish background (Theme.cardBg, falls back to #2c2c2e)
//   • 1px Theme.border outline, 8px radius
//   • 16px internal padding, 12px vertical rhythm between header and content
//
// Use as:
//
//     SectionCard {
//         title:    "MLflow"
//         subtitle: "Tracking server"
//         icon:     "chart.bar"
//
//         SettingsRow { label: "Tracking URI"; control: TextField {} }
//         SettingsRow { label: "Experiment";   control: TextField {}; isLast: true }
//     }
//
// Owned by Wave 10 Agent 10E.
import QtQuick
import QtQuick.Layouts
import Aurum.Aqua 1.0

Rectangle {
    id: card

    // --- Public API -------------------------------------------------------
    property string title:    ""
    property string subtitle: ""
    property string icon:     ""           // SF Symbols name or empty
    // Default property: any children declared inside `SectionCard {}` land
    // in the contentColumn below, stacked with 8px spacing.
    default property alias content: contentColumn.data

    // --- Visual ----------------------------------------------------------
    // `Theme.cardBg`, `Theme.cardBorder`, `Theme.cardRadius` are the canonical
    // macOS Sequoia "raised surface" tokens, defined in Theme.qml (Wave 10E).
    // The `||` fallbacks keep this file safe to import in older trees where
    // Theme.qml predates the cardBg/cardBorder block.
    color:        Theme.cardBg     || "#FF2c2c2e"
    radius:       Theme.cardRadius || 12
    border.width: 1
    border.color: Theme.cardBorder || Theme.border

    // Sizing: cards grow with their content but stretch to whatever parent
    // gives them (typical: a Layout.fillWidth ColumnLayout in the panel).
    implicitWidth:  600
    implicitHeight: layout.implicitHeight + 32   // 16px top + 16px bottom

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        SectionHeader {
            id: header
            Layout.fillWidth: true
            title:    card.title
            subtitle: card.subtitle
            icon:     card.icon
            // Header collapses entirely when no title/subtitle/icon — useful
            // for the rare "card with only rows, no heading" case.
            visible:  card.title.length > 0
                   || card.subtitle.length > 0
                   || card.icon.length > 0
        }

        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            spacing: 8
        }
    }
}
