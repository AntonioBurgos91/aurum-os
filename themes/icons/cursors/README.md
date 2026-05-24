# AurumOS cursor theme strategy

AurumOS ships two layered cursor options to deliver the macOS Big Sur / Sequoia
look without rebuilding any binaries at install time:

1. **`Aurum-Sequoia/` (default in this repo)** — inheritance-only theme;
   resolves every shape via `Inherits=WhiteSur-cursors,Adwaita,default`.
   WhiteSur cursors are GPL-3.0+ and already installed by
   `themes/install_themes.sh`. See `Aurum-Sequoia/README.md` for the rationale.

2. **macOS-Cursors fork (optional, recommended for the closest fidelity)** —
   <https://github.com/ful1e5/apple_cursor>, BSD-3-Clause licensed (compatible
   with our GPL distribution). This fork renders Apple's Big Sur cursor SVGs to
   XCursor binaries and is the most pixel-accurate libre option available.

Both end up under `/usr/share/icons/` and are interchangeable — the only
difference is which value you set in `XCURSOR_THEME`.

---

## Option 1 — default WhiteSur inheritance (already wired)

Already handled by `themes/install_themes.sh::install_cursor_theme()`:
```
/usr/share/icons/WhiteSur-cursors/   ← upstream tarball, unmodified
/usr/share/icons/Aurum-Sequoia/      ← our inheritance shim (no binaries)
```

The Hyprland and GTK envs in `aurum.conf` / `/etc/environment` should point at
`Aurum-Sequoia` so future per-shape overrides land transparently.

---

## Option 2 — macOS-BigSur (apple_cursor fork)

Install path target:
```
/usr/share/icons/macOS-BigSur/cursors/
```

Build & install (one-shot, requires `python3-clickgen` + `inkscape`):
```bash
git clone https://github.com/ful1e5/apple_cursor.git /tmp/apple_cursor
cd /tmp/apple_cursor
ctgen build.toml -p x11 -d bin/xcursors -n 'macOS-BigSur'
sudo cp -r bin/xcursors /usr/share/icons/macOS-BigSur
```

Or grab a pre-rolled tarball from the project's releases page and untar into
`/usr/share/icons/`. Either way you end up with `index.theme` + a populated
`cursors/` subdirectory in the install path above.

---

## Required environment variables

Hyprland reads `XCURSOR_*` env vars set in `aurum.conf` (Agent 10A owns that
file — do not edit it from this agent; the entries below are what 10A must
add):
```
env = XCURSOR_THEME,macOS-BigSur
env = XCURSOR_SIZE,24
```

GTK and XWayland clients read the same vars from `/etc/environment` (do NOT
edit this file from this agent; document only):
```
XCURSOR_THEME=macOS-BigSur
XCURSOR_SIZE=24
```

If sticking with Option 1, swap `macOS-BigSur` for `Aurum-Sequoia` in both
places. The `XCURSOR_SIZE=24` matches macOS at 1x density and is what the rest
of the Aqua-Qt theme is tuned for (see `libs/aqua-qt/qml/Aurum/Aqua/Theme.qml`
`dockIconSize=48`, which is exactly 2× the cursor for visual harmony).

---

## Why we don't pick one and force it

Different downstream users have different licensing tolerances:
* Strict-GPL distributions can ship Option 1 with no extra dependencies.
* Image-fidelity-first installs (workstations, kiosks) can opt into Option 2
  by setting the env var and running the one-time install above.

The default ISO picks Option 1; the post-install script asks once and flips
the env vars if the user wants to enable Option 2 at first boot.
