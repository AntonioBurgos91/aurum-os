# Typography Guide — AurumOS Wave 10C

AurumOS targets a macOS-Sequoia look-and-feel for every QML app.  Apple uses
**SF Pro Display** (≥ 20 pt), **SF Pro Text** (< 20 pt) and **SF Mono** in
its system UI, but the SF family is not redistributable.  We therefore ship
the closest libre equivalents:

| Apple family    | AurumOS substitute | License |
|-----------------|--------------------|---------|
| SF Pro Display  | **Inter Display**  | OFL 1.1 |
| SF Pro Text     | **Inter**          | OFL 1.1 |
| SF Mono         | **JetBrains Mono** | OFL 1.1 |

Inter is the same family GitHub, Figma, Linear, Notion and Spotify use to
mimic SF — there is broad industry consensus that it is the legal stand-in.

## Where the tokens live

Everything is exposed by the `Aurum.Aqua.Theme` singleton at
`libs/aqua-qt/qml/Aurum/Aqua/Theme.qml`.  QML components should never
hard-code a `font.pixelSize` or `font.family` literal — always pull from
`Theme`.

```qml
import Aurum.Aqua

Text {
    text:           "Settings"
    font.family:    Theme.fontFamilyText
    font.pixelSize: Theme.fontSizeBody
    font.weight:    Theme.fontWeightRegular
}
```

## Family tokens

| Token                          | Resolves to                                       | Use for          |
|--------------------------------|---------------------------------------------------|------------------|
| `Theme.fontFamily`             | `Inter`                                           | Default body     |
| `Theme.fontFamilyText`         | `Inter, SF Pro Text, system-ui, sans-serif`       | Body, multi-host |
| `Theme.fontFamilyDisplay`      | `Inter Display`                                   | Headlines ≥ 17 px|
| `Theme.fontFamilyDisplayCSS`   | `Inter Display, Inter, SF Pro Display, system-ui` | Headlines, multi-host |
| `Theme.fontFamilyMono`         | `JetBrains Mono`                                  | Code, terminals  |
| `Theme.fontFamilyMonoCSS`      | `JetBrains Mono, Menlo, Monaco, monospace`        | Code, multi-host |
| `Theme.fontFamilyFallback`     | `Sans Serif`                                      | Qt fallback only |

The plain `fontFamily*` tokens hold a single family — use when you want Qt
to resolve precisely.  The `*CSS` tokens are comma-lists for fontconfig /
Qt6 multi-family resolution and degrade gracefully on hosts that don't have
Inter installed yet (e.g. during early boot before `install_fonts.sh` runs).

## HIG-aligned size scale (Wave 10C)

Pixel-perfect mapping to macOS Sequoia at 1× density.

| Token                       | px | macOS HIG name | Typical use                              |
|-----------------------------|----|----------------|------------------------------------------|
| `Theme.fontSizeLargeTitle`  | 34 | Large Title    | Installer welcome, splash screens        |
| `Theme.fontSizeTitle1`      | 28 | Title 1        | Window titles, dialog headers            |
| `Theme.fontSizeTitle2`      | 22 | Title 2        | Section headers                          |
| `Theme.fontSizeTitle3`      | 20 | Title 3        | Sub-section headers                      |
| `Theme.fontSizeHeadline`    | 17 | Headline       | Body bold (semibold is implicit here)    |
| `Theme.fontSizeBody`        | 13 | Body           | **Default**                              |
| `Theme.fontSizeCallout`     | 12 | Callout        | Inline emphasis, tooltips                |
| `Theme.fontSizeSubheadline` | 11 | Subheadline    | Secondary labels, dock tooltips          |
| `Theme.fontSizeFootnote`    | 10 | Footnote       | Hairline labels, menubar applet badges   |
| `Theme.fontSizeCaption1`    |  9 | Caption 1      | Caption                                  |
| `Theme.fontSizeCaption2`    |  8 | Caption 2      | Microcopy                                |

The legacy `fontSize{Tiny, Small, Body, Medium, Large, Title, Hero}` tokens
remain for backwards compatibility — values are aligned so either name
resolves to the same pixel size.

## Weight tokens

| Token                       | Qt enum          | Apple weight |
|-----------------------------|------------------|--------------|
| `Theme.fontWeightRegular`   | `Font.Normal`    | Regular (400) |
| `Theme.fontWeightMedium`    | `Font.Medium`    | Medium (500)  |
| `Theme.fontWeightSemibold`  | `Font.DemiBold`  | Semibold (600)|
| `Theme.fontWeightBold`      | `Font.Bold`      | Bold (700)    |

## Letter-spacing tokens

Negative tracking matches SF Pro's tighter rhythm at body sizes.

| Token                          | px    | Use for                              |
|--------------------------------|-------|--------------------------------------|
| `Theme.letterSpacingTight`     | -0.2  | Body text — gives Inter SF-like feel |
| `Theme.letterSpacingNormal`    |  0.0  | Default                              |
| `Theme.letterSpacingWide`      |  0.2  | Spaced labels (Quick Look chips)     |
| `Theme.letterSpacingCaps`      |  0.5  | ALL-CAPS micro-labels (GPU, VRAM…)   |

## Migration table

Use this when refactoring existing QML that still has hard-coded values:

| Old                                                    | New                                                                 |
|--------------------------------------------------------|---------------------------------------------------------------------|
| `font.pixelSize: 13`                                   | `font.pixelSize: Theme.fontSizeBody`                                |
| `font.pixelSize: 11`                                   | `font.pixelSize: Theme.fontSizeSubheadline`                         |
| `font.pixelSize: 17`                                   | `font.pixelSize: Theme.fontSizeHeadline`                            |
| `font.pixelSize: 22`                                   | `font.pixelSize: Theme.fontSizeTitle2`                              |
| `font.family: "sans-serif"`                            | `font.family: Theme.fontFamilyText`                                 |
| `font.family: "monospace"`                             | `font.family: Theme.fontFamilyMonoCSS`                              |
| `font.bold: true; font.pixelSize: 17`                  | `font.pixelSize: Theme.fontSizeHeadline` (semibold implied at 17px) |
| `font.bold: true`                                      | `font.weight: Theme.fontWeightSemibold`                             |
| `font { family: "DejaVu Sans"; pointSize: 10 }`        | `font.family: Theme.fontFamilyText; font.pixelSize: Theme.fontSizeFootnote` |

## Boot-order safety

`themes/install_fonts.sh` runs at image build, dropping fonts into
`/usr/share/fonts/aurum/`.  `fontconfig` rescans `/usr/share/fonts` at boot,
**before** any Qt application starts — so by the time the QML engine loads
`Aurum.Aqua.Theme`, Inter is already resolvable.  The fallback chain
(`Inter, SF Pro Text, system-ui, sans-serif`) only kicks in on a developer
host where `install_fonts.sh` was never run, in which case `system-ui` will
resolve to whatever distro default exists — graceful degradation, no crash.

## See also

- `distro/assets/fonts/README.md` — install procedure + version pins
- `libs/aqua-qt/qml/Aurum/Aqua/Theme.qml` — token definitions
- `docs/guides/window-chrome-migration.md` — companion Wave 10A guide
