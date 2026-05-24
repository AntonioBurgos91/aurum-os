# AurumOS Fonts

This directory documents (but does **not** vendor) the typefaces shipped with
AurumOS.  Actual TTF/OTF files live in OS packages or are downloaded by
`themes/install-fonts.sh` at image-build time — we deliberately avoid
checking >1 MB binaries into git.

## Bundled families

| Family            | Role                                | Apple equivalent  | License | Source |
|-------------------|-------------------------------------|-------------------|---------|--------|
| **Inter**         | Default sans / body text            | SF Pro Text       | OFL 1.1 | <https://rsms.me/inter/> · `apt: fonts-inter` |
| **Inter Display** | Headlines (≥17 px)                  | SF Pro Display    | OFL 1.1 | <https://github.com/rsms/inter/releases/latest> |
| **JetBrains Mono**| Code / terminal / mono UI           | SF Mono           | OFL 1.1 | <https://www.jetbrains.com/lp/mono/> · `apt: fonts-jetbrains-mono` |
| DejaVu Sans       | Fallback (sans, broad glyph cover)  | —                 | Bitstream Vera + Public Domain additions | `apt: fonts-dejavu-core` |
| DejaVu Sans Mono  | Fallback (mono)                     | —                 | as above | `apt: fonts-dejavu-core` |

Apple's San Francisco family is **not** freely redistributable, so AurumOS uses
the libre alternatives above.  Inter is widely accepted as the closest legal
substitute (used by Spotify, GitHub, and most Apple-mimic Linux desktops).

## Installation flow

Two installer scripts are provided — both are idempotent and can be re-run:

| Script                          | Source       | When to use                                       |
|---------------------------------|--------------|---------------------------------------------------|
| `themes/install-fonts.sh`       | apt          | Live system / Ubuntu 24.04+ with current repos    |
| `themes/install_fonts.sh`       | GitHub OFL   | ISO build / reproducible, version-pinned installs |

The `install_fonts.sh` (underscore) variant fetches:

- **Inter** `v4.1` → `https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip`
- **JetBrains Mono** `v2.304` → `https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip`

into `/var/cache/aurum-fonts/`, then extracts to `/usr/share/fonts/aurum/{inter,jetbrains-mono}/`
and runs `fc-cache -f`.  Override pins with `INTER_VERSION` / `JBM_VERSION`
env vars.

> If the script lost its executable bit during `git checkout` (e.g. on a Windows
> host), run `chmod +x themes/install_fonts.sh` once before invoking.

The legacy `install-fonts.sh` (hyphen) additionally registers
`themes/aurum-fonts.conf` → `/etc/fonts/conf.d/99-aurum-fonts.conf`, mapping
`sans-serif` → Inter system-wide.  Run both for a complete setup.

## QML usage

QML components should pull family + size from `Aurum.Aqua.Theme`:

```qml
import Aurum.Aqua

Text {
    text: "Hello"
    font.family:    Theme.fontFamily
    font.pixelSize: Theme.fontSizeBody
    font.weight:    Theme.fontWeightRegular
}
```

See `docs/internal/typography.md` for the full type scale.

## Licenses

All shipped families are under the **SIL Open Font License v1.1**, which
permits redistribution, bundling, and modification with attribution.  Copies of
each `OFL.txt` are installed alongside the TTFs by the apt packages and by
`install-fonts.sh` for the manually-fetched Inter Display variant.
