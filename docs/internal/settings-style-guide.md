# Settings panel style guide (Wave 10E)

The AurumOS Settings app spans seven panels — General, GPU, CUDA, Python
venvs, MLOps, Hardware, Model Packs — written across waves 1-9 by half a
dozen different agents. Wave 10E harmonises them all under a single shared
visual contract that mirrors **macOS Sequoia → System Settings**: a stack of
rounded "cards" with a consistent header, internal padding, and row rhythm.

This document is the source of truth for that contract. Every new Settings
panel MUST consume the shared components below. Do NOT re-define card chrome
inline — if a panel needs a one-off variant, add a property to `SectionCard`
or `SettingsRow` and document it here.

---

## Shared components

All three live under `libs/aqua-qt/qml/Aurum/Aqua/` and are registered in
`qmldir`, so any QML file that already imports `Aurum.Aqua 1.0` picks them
up with no extra import.

| Component       | File                | Owned by      | Purpose                                     |
|-----------------|---------------------|---------------|---------------------------------------------|
| `SectionCard`   | `SectionCard.qml`   | Agent 10E     | Rounded card frame with header + content column |
| `SectionHeader` | `SectionHeader.qml` | Agent 10E     | 13px DemiBold title + optional subtitle / icon / action |
| `SettingsRow`   | `SettingsRow.qml`   | Agent 10E     | 40px label/control row with hover + hairline separator |

### SectionCard

```qml
SectionCard {
    title:    "MLflow"                      // required (or pass empty for headerless card)
    subtitle: "Saved to ~/.config/aurum/…"  // optional
    icon:     "chart.bar"                   // optional, SF Symbols name (placeholder for now)

    // Default property: any children stack inside the content column.
    SettingsRow { label: "Tracking URI"; control: TextField {} }
    SettingsRow { label: "Experiment";   control: TextField {}; isLast: true }
}
```

Visual contract (matches Sequoia System Settings card):

- background: `Theme.cardBg` (`#FF2c2c2e`)
- border: 1px `Theme.cardBorder` (`#33FFFFFF`)
- radius: `Theme.cardRadius` (12)
- internal padding: `Theme.cardPadding` (16)
- inter-card spacing (in panel ColumnLayout): `Theme.cardSpacing` (16)

### SectionHeader

Usually you don't instantiate this directly — `SectionCard` embeds one
configured from its `title` / `subtitle` / `icon`. Use it standalone only
when you need a section heading outside a card (rare).

The `action` slot reparents an optional trailing button:

```qml
SectionHeader {
    title:  "Catalog"
    action: Button { text: "Refresh"; flat: true }
}
```

### SettingsRow

40px tall, label on the left, control on the right (max 240px wide),
4px-radius hover background (`Theme.hoverBg`), and a 1px hairline separator
underneath. Mark the bottom row with `isLast: true` to suppress the
separator.

The `control` property is a children-list alias on the right-hand slot Item.
Any QtQuick.Controls widget can be assigned directly:

```qml
SettingsRow { label: "Theme";    control: ComboBox { model: ["Dark", "Light"] } }
SettingsRow { label: "Enabled";  control: Switch {} }
SettingsRow { label: "Path";     control: TextField {} ; isLast: true }
```

If you need a non-Item control (e.g. a Text label that "looks like" a value
because the row is read-only), wrap it in a `Text { ... }` directly — see
HardwarePanel.qml for the canonical example.

---

## Panel skeleton

Every Settings panel should follow this skeleton:

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    id: panel

    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: parent.parent.width - 48   // 24px outer panel margin per side
            x: 24
            y: 24
            spacing: Theme.cardSpacing        // 16px between cards

            SectionCard {
                Layout.fillWidth: true
                title: "…"
                /* SettingsRows or custom content */
            }

            SectionCard {
                Layout.fillWidth: true
                title: "…"
                /* … */
            }

            Item { Layout.fillHeight: true }  // bottom spring
        }
    }
}
```

**Outer panel padding** is 24px on all sides. The `ScrollView` is mandatory
so cards reflow when the Settings window is resized below the natural
content height.

---

## Theme tokens added in Wave 10

`libs/aqua-qt/qml/Aurum/Aqua/Theme.qml` gained the following readonly
properties in Wave 10C/10E. Use these — do **not** re-hardcode the hex
literals in panel code.

| Token              | Value      | Used by                            |
|--------------------|------------|------------------------------------|
| `Theme.cardBg`     | `#FF2c2c2e`| `SectionCard` background           |
| `Theme.cardBorder` | `#33FFFFFF`| `SectionCard` border               |
| `Theme.cardRadius` | `12`       | `SectionCard` radius               |
| `Theme.cardPadding`| `16`       | `SectionCard` internal padding     |
| `Theme.cardSpacing`| `16`       | gap between sibling cards in a panel |
| `Theme.hoverBg`    | `#1affffff`| `SettingsRow` hover background     |

All of these have safe `|| <hex>` fallbacks inside the components so the
files keep working in a tree that predates the Theme additions.

---

## Typography reference

Card titles match Sequoia's "section heading" style:

- title text: `13px`, `Theme.fontWeightSemibold` (`Font.DemiBold`)
- subtitle text: `11px`, regular, `Theme.textSecondary`
- row label: `13px` regular, `Theme.textPrimary`
- row control text: defaults to `13px` regular

Cross-reference `docs/internal/typography.md` for the wider type scale.

---

## Refactored panels (Wave 10E)

| Panel file                              | What changed                                                                                       |
|-----------------------------------------|----------------------------------------------------------------------------------------------------|
| `desktop/settings/HardwarePanel.qml`    | Three SectionCards (profile summary with SettingsRows, override, per-profile table)                |
| `desktop/settings/ModelPacksPanel.qml`  | Header + Catalog (wrapping the ListView) + Cache SectionCards                                      |
| `desktop/settings/sections/GeneralSection.qml`     | One SectionCard with three read-only SettingsRows                                       |
| `desktop/settings/sections/GpuSection.qml`         | One SectionCard wrapping the three stat tiles (Utilization, VRAM, Temperature)          |
| `desktop/settings/sections/CudaSection.qml`        | Overview + Installed-toolkits SectionCards                                              |
| `desktop/settings/sections/PythonVenvsSection.qml` | Create-new + Existing-venvs SectionCards                                                |
| `desktop/settings/sections/MlopsSection.qml`       | MLflow + W&B SectionCards using SettingsRows; Save/Reload as panel-footer buttons       |

`Settings.qml` (the parent shell that hosts the panel switcher) was **not**
touched — it's owned by another agent.
