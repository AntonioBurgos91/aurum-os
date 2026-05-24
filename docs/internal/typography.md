# AurumOS Typography

Aqua's typographic system tracks **macOS Sequoia (15.x)** at 1× density.  All
sizes, weights, line heights and letter-spacing values are exposed as readonly
properties on the `Aurum.Aqua.Theme` singleton so apps share one source of
truth.

> See `libs/aqua-qt/qml/Aurum/Aqua/Theme.qml` — Typography section.

## Families

| Token                       | Value             | Apple equivalent | When to use |
|-----------------------------|-------------------|------------------|-------------|
| `Theme.fontFamily`          | `"Inter"`         | SF Pro Text      | Body, UI labels, controls (< 17 px) |
| `Theme.fontFamilyDisplay`   | `"Inter Display"` | SF Pro Display   | Headlines, titles, hero text (≥ 17 px) |
| `Theme.fontFamilyMono`      | `"JetBrains Mono"`| SF Mono          | Code, terminal output, monospace UI |
| `Theme.fontFamilyFallback`  | `"Sans Serif"`    | —                | Qt's generic fallback (rarely needed thanks to fontconfig) |

Apple draws a careful distinction at 17 px between *Text* and *Display* — the
*Display* cut has tighter spacing and slightly thinner stems for headlines.
Inter does the same, so honor the boundary in your QML.

## Type scale

| Token                    | px | Notes |
|--------------------------|----|-------|
| `Theme.fontSizeTiny`     | 10 | Hairline labels — menubar applet badges (e.g. `"GPU"`, `"VRAM"`) |
| `Theme.fontSizeSmall`    | 11 | Secondary / caption text, dock tooltips |
| `Theme.fontSizeBody`     | 13 | **Default body** — matches the macOS system body size |
| `Theme.fontSizeMedium`   | 15 | Emphasized body, sidebar items, settings rows |
| `Theme.fontSizeLarge`    | 17 | Sub-headings (switch to `fontFamilyDisplay` here) |
| `Theme.fontSizeTitle`    | 22 | Window titles in Settings / Finder big-mode |
| `Theme.fontSizeHero`     | 34 | Splash screens, installer welcome panels |

## Weights

Use the named tokens — never raw numbers.  They map onto Qt's `Font.*` enum,
which themselves correspond to OpenType weight axes.

| Token                          | Qt enum         | Weight | Use |
|--------------------------------|-----------------|--------|-----|
| `Theme.fontWeightRegular`      | `Font.Normal`   | 400    | All running text |
| `Theme.fontWeightMedium`       | `Font.Medium`   | 500    | Emphasized labels, active sidebar item |
| `Theme.fontWeightSemibold`     | `Font.DemiBold` | 600    | Button labels, dialog titles |
| `Theme.fontWeightBold`         | `Font.Bold`     | 700    | Hero text only — reserve for impact |

Avoid Light/Thin weights at body sizes: they fail on the software renderer
without subpixel AA (see "Rendering" below).

## Line heights

Qt requires `lineHeightMode: Text.FixedHeight` (or `Text.ProportionalHeight`)
plus an explicit `lineHeight` value:

```qml
Text {
    text: lipsum
    font.family:        Theme.fontFamily
    font.pixelSize:     Theme.fontSizeBody
    lineHeightMode:     Text.ProportionalHeight
    lineHeight:         Theme.lineHeightBody    // 1.32
    wrapMode:           Text.Wrap
}
```

| Token                          | Multiplier | For |
|--------------------------------|------------|-----|
| `Theme.lineHeightBody`         | 1.32       | Body, default running text |
| `Theme.lineHeightDisplay`      | 1.18       | Display / headline (`fontFamilyDisplay`) |
| `Theme.lineHeightMono`         | 1.45       | Code, terminal — extra breathing room |

## Letter-spacing

**Gotcha:** Qt's `font.letterSpacing` is **pixels, not ems**.  The Theme
exposes pixel values directly so you never have to convert.

```qml
Text {
    text: "GPU"
    font.family:        Theme.fontFamily
    font.pixelSize:     Theme.fontSizeTiny
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Theme.letterSpacingCaps   // 0.5 px
}
```

| Token                            | Value (px) | Use |
|----------------------------------|------------|-----|
| `Theme.letterSpacingTight`       | -0.2       | Hero / very large display text |
| `Theme.letterSpacingNormal`      |  0.0       | Default — every body size |
| `Theme.letterSpacingCaps`        |  0.5       | ALL-CAPS labels (menubar applet codes, tab bars) |

## Sample QML snippets

### Body paragraph

```qml
import QtQuick
import Aurum.Aqua

Text {
    text:               paragraph
    font.family:        Theme.fontFamily
    font.pixelSize:     Theme.fontSizeBody
    font.weight:        Theme.fontWeightRegular
    color:              Theme.textPrimary
    lineHeightMode:     Text.ProportionalHeight
    lineHeight:         Theme.lineHeightBody
    wrapMode:           Text.WordWrap
}
```

### Window title

```qml
Text {
    text:               "Settings"
    font.family:        Theme.fontFamilyDisplay
    font.pixelSize:     Theme.fontSizeTitle
    font.weight:        Theme.fontWeightSemibold
    color:              Theme.textPrimary
    lineHeight:         Theme.lineHeightDisplay
    lineHeightMode:     Text.ProportionalHeight
}
```

### Monospace (code / terminal)

```qml
Text {
    text:               "$ aurum --version"
    font.family:        Theme.fontFamilyMono
    font.pixelSize:     Theme.fontSizeBody
    color:              Theme.textPrimary
    lineHeight:         Theme.lineHeightMono
    lineHeightMode:     Text.ProportionalHeight
}
```

### ALL-CAPS applet label

```qml
Text {
    text:                 "GPU"
    font.family:          Theme.fontFamily
    font.pixelSize:       Theme.fontSizeTiny
    font.weight:          Theme.fontWeightSemibold
    font.capitalization:  Font.AllUppercase
    font.letterSpacing:   Theme.letterSpacingCaps
    color:                Theme.textSecondary
}
```

## Rendering notes

AurumOS runs Qt Quick under the **software backend**
(`QT_QUICK_BACKEND=software`) because the compositor uses wlroots' pixman
renderer.  Practical consequences for typography:

- Subpixel (LCD) AA paths differ slightly between the software backend and the
  default OpenGL/RHI backend.  `themes/aurum-fonts.conf` enables
  `hintstyle=hintslight` + `rgba=rgb` + `lcdfilter=lcddefault` which produces
  the most macOS-like result on the software path.
- **Avoid hairline (≤ 300) weights** at body size — without sub-pixel
  positioning they shimmer when text scrolls.  The Theme tokens deliberately
  start at `Regular` (400).
- Letter-spacing values in `Theme` were tuned visually on the software
  backend; if we ever switch to RHI we should re-tune `letterSpacingTight`
  (the GPU path renders slightly tighter natively).

## Installation

Fonts are installed at image-build time by `themes/install-fonts.sh`.  See
`distro/assets/fonts/README.md` for the package list and license info.  The
fontconfig snippet (`themes/aurum-fonts.conf` →
`/etc/fonts/conf.d/99-aurum-fonts.conf`) makes generic `sans-serif` resolve to
Inter, so even non-Aqua GTK/Electron apps inherit the AurumOS look.
