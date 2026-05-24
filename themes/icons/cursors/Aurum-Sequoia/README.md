# Aurum-Sequoia cursor theme

This is an **inheritance-only** cursor theme: it ships no XCursor binary files
of its own and relies entirely on `Inherits=WhiteSur-cursors,Adwaita,default`
in `index.theme` to resolve every shape (default, pointer, text, wait,
crosshair, hand1/2, sb_h_double_arrow, sb_v_double_arrow, fleur, not-allowed,
…).

## Why inherit, not fork

The upstream WhiteSur cursor set already nails the macOS Sequoia look (pure
white fill, 1px black outline, no shadow, classic 11x18 arrow). Forking +
re-rendering all variants for ~30 minutes of build time would burn the wave's
entire icon-system budget and produce a near-identical artifact.

Instead, `install_themes.sh` already deposits `WhiteSur-cursors` at
`/usr/share/icons/WhiteSur-cursors`, and `install-icons.sh` deposits this
theme directory at `/usr/share/icons/Aurum-Sequoia/`. The XCursor library
walks the `Inherits=` chain so every Aurum surface that sets
`XCURSOR_THEME=Aurum-Sequoia` resolves through WhiteSur.

## License

`index.theme` and `cursor.theme` are CC0. The cursors they resolve to are
covered by WhiteSur's GPL-3.0-or-later license (see
`/usr/share/icons/WhiteSur-cursors/LICENSE`).
