# AurumOS Settings — Style Guide (Wave 10E)

This document is the design spec for the `SectionCard` pattern that
unifies all panels in the AurumOS Settings app (`desktop/settings/`).
Every Settings page — General, GPU, CUDA, Python venvs, MLOps,
Hardware, Model Packs, About — wraps its content in one or more
`SectionCard` instances so the whole app reads as one coherent
macOS-Sequoia-class design rather than the seven-different-styles
patchwork that existed after Waves 7-9.

Owner: Wave 10 Agent 10E.

---

## 1. The component

`libs/aqua-qt/qml/Aurum/Aqua/SectionCard.qml` is a single reusable
`Rectangle` that:

- paints a `Theme.cardBg` surface (`#FF2c2c2e`, slightly raised vs.
  the window background `#FF1c1c1e`),
- draws a `Theme.cardBorder` outline (`#33FFFFFF`, 20 % white → very
  subtle 1 px hairline),
- has a 12 px radius (matches macOS Sequoia "System Settings" cards),
- pads its content by 16 px,
- shows an optional title / subtitle header via the bundled
  `SectionHeader`,
- accepts arbitrary children via the default property (no
  `contentItem.children: [ ... ]` indirection — just nest items
  directly inside `SectionCard { ... }`).

```qml
SectionCard {
    title:    "MLflow"
    subtitle: "Tracking server"

    SettingsRow { label: "Tracking URI"; control: TextField {} }
    SettingsRow { label: "Experiment";   control: TextField {}; isLast: true }
}
```

The companion components are:

| Component        | Purpose                                                  |
|------------------|----------------------------------------------------------|
| `SectionHeader`  | 13 px DemiBold title + 11 px subtitle + optional action  |
| `SectionCard`    | The full card surround (header + padded content slot)    |
| `SettingsRow`    | Label-left / control-right row with hover + hairline     |

---

## 2. Visual rhythm

```
┌───── window ────────────────────────────────────────────────────────┐
│ Sidebar │             ScrollView                                    │
│         │  ┌──────────────────────────────────────────────────┐     │
│         │  │ SectionCard                                      │     │
│         │  │  ┌────────────────────────────────────────────┐  │     │
│         │  │  │ Title  (13 px DemiBold)                    │  │     │
│         │  │  │ Subtitle (11 px secondary)                 │  │     │
│         │  │  ├────────────────────────────────────────────┤  │     │
│         │  │  │ SettingsRow  label ............ [control] │  │     │
│         │  │  │ SettingsRow  label ............ [control] │  │     │
│         │  │  └────────────────────────────────────────────┘  │     │
│         │  └──────────────────────────────────────────────────┘     │
│         │              ↕  16 px between sibling cards               │
│         │  ┌──────────────────────────────────────────────────┐     │
│         │  │ SectionCard                                      │     │
│         │  │  ...                                             │     │
│         │  └──────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘
        ↕ 20 px gutter left/right + 20 px top/bottom of scroll viewport
```

Constants (all in `Theme.qml`, Wave 10E):

| Token              | Value          | Purpose                              |
|--------------------|----------------|--------------------------------------|
| `Theme.cardBg`     | `#FF2c2c2e`    | Card surface                         |
| `Theme.cardBorder` | `#33FFFFFF`    | 1 px hairline outline                |
| `Theme.cardRadius` | `12`           | Corner radius (matches Sequoia)      |
| `Theme.cardPadding`| `16`           | Internal padding                     |
| `Theme.cardSpacing`| `16`           | Vertical spacing between sibling cards |
| `Theme.hoverBg`    | `#1affffff`    | SettingsRow hover tint               |

---

## 3. Migration recipe

For each `*Section.qml` / `*Panel.qml` in `desktop/settings/`:

### Before

```qml
Item {
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        Text { text: "GPU Monitoring"; font.pixelSize: 18; font.bold: true }
        Rectangle { ... gpu status ... }
        Rectangle { ... vram status ... }
    }
}
```

### After

```qml
Item {
    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: parent.parent.width - 40   // 20 px gutter
            x: 20
            y: 20
            spacing: Theme.cardSpacing

            SectionCard {
                Layout.fillWidth: true
                title:    "GPU Monitoring"
                subtitle: "Real-time utilization and thermal data."

                Rectangle { ... gpu status ... }
                Rectangle { ... vram status ... }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
```

Rules of thumb:

1. **One panel = one ScrollView.** Future-proofs against terminal sizes
   smaller than the panel's natural height.
2. **One conceptual group = one `SectionCard`.** If the panel has
   "GPU monitoring" plus "Power profile" plus "Fan control", wrap each
   in its own card.
3. **Single-section panels still get one card.** Even the trivial About
   panel uses a card so it sits at the same visual altitude as the
   busier sections.
4. **Preserve every binding.** IDs, signals, dialog references, model
   bindings — all stay verbatim. The migration is purely visual chrome.
5. **Use `SettingsRow` for label/control rows;** keep custom `Rectangle`
   tiles only for dashboard-style gauges (e.g. GPU utilization tile).
6. **Use the Theme tokens, not literals.** Don't hardcode `12` for the
   radius — use `Theme.cardRadius` (or `Theme.cardSpacing` for the
   gap between sibling cards).

---

## 4. Migrated panels (Wave 10E)

| Panel                                                | Cards | Notes                                                       |
|------------------------------------------------------|-------|-------------------------------------------------------------|
| `sections/GeneralSection.qml`                        | 1     | Read-only appearance/behaviour summary.                     |
| `sections/GpuSection.qml`                            | 1     | Live tiles kept as bespoke `Rectangle`s inside one card.    |
| `sections/CudaSection.qml`                           | 2     | Overview + installed toolkits.                              |
| `sections/PythonVenvsSection.qml`                    | 2     | Create-new card + existing list card.                       |
| `sections/MlopsSection.qml`                          | 2     | MLflow + W&B, save/reload row floats below the cards.       |
| `HardwarePanel.qml`                                  | 3     | Summary + override + per-profile defaults table.            |
| `ModelPacksPanel.qml`                                | 3     | Header + catalog ListView + cache controls.                 |
| `AboutPanel.qml` (new)                               | 3     | Hero / system / build cards.                                |

---

## 5. Adding a new Settings panel

1. Create `desktop/settings/MyPanel.qml` (or `sections/MySection.qml`).
2. Follow the "after" template in §3.
3. Add the panel to the `sections` model and a sibling `Loader` in
   `Settings.qml` — Settings.qml is owned by Agent 10A / the
   orchestrator, so submit your change as a `.diff` patch file next to
   it (e.g. `desktop/settings/Settings.qml.mything-patch.diff`) instead
   of editing in place.
4. If you need a new shared token (e.g. a new card colour for warning
   states), add it to `Theme.qml` first and reference it via the
   `Theme.*` accessor.
