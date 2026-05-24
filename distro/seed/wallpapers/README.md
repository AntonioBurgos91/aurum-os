# AurumOS default wallpapers

Drop `.jpg` / `.png` / `.webp` files in this directory and they will be
installed to `/usr/share/backgrounds/aurumos/` by the ISO builder. The file
named `default.jpg` (or `sequoia-aurum-amber.png` — see priority below) is
the one shown on first login.

The wallpaper engine ([../hypr/wallpaper.sh](../hypr/wallpaper.sh)) also
rotates through every image in this directory on a configurable interval
(`AURUM_WALLPAPER_INTERVAL`, default 1800s) when more than one is present.

## Bundled set (Wave 10)

Six Sequoia-style wallpapers are generated procedurally by
[`tools/aurum-wallpaper-gen`](../../../tools/aurum-wallpaper-gen). After
running `./tools/aurum-wallpaper-gen/gen.sh` from the repo root, this
directory will contain:

| File                              | Description                              |
|-----------------------------------|------------------------------------------|
| `sequoia-aurum-amber.png`         | Warm amber→gold diagonal (default)        |
| `sequoia-aurum-aqua.png`          | Teal→cyan→indigo vertical                 |
| `sequoia-aurum-obsidian.png`      | Near-black with subtle purple radial      |
| `sequoia-aurum-dawn.png`          | Pink→peach→cream sunrise                  |
| `sequoia-aurum-aurora.png`        | Green→teal→violet conic (northern lights) |
| `sequoia-aurum-void.png`          | Pure black with one dim deep-blue radial  |

Each is 3840×2400 (16:10 native; tiles down cleanly to 1920×1200 and
1280×800).

## Default selection per profile

The post-install profile detector
([`distro/post-install/00-detect-profile.sh`](../../post-install/00-detect-profile.sh))
symlinks one of the wallpapers to `default.jpg` based on the detected
hardware tier:

| Profile     | Default wallpaper           | Rationale                                  |
|-------------|-----------------------------|--------------------------------------------|
| lite        | `sequoia-aurum-void.png`    | OLED-friendly, minimum chrome              |
| standard    | `sequoia-aurum-aqua.png`    | Calm, neutral, dark-enough for the dock    |
| pro         | `sequoia-aurum-amber.png`   | The AurumOS signature                      |
| workstation | `sequoia-aurum-aurora.png`  | Most visually rich; rewards big monitors   |

The user can override via Settings → Wallpapers or by exporting
`AURUM_WALLPAPER` before login.

## Why are the PNGs not committed?

The renderer is bit-reproducible, so the PNGs would diff cleanly across
runs — but committing six ~2 MB PNGs adds ~12 MB to every repo clone.
Release engineering runs `gen.sh` once per release and commits the
resulting PNGs as part of the ISO snapshot, not as part of the repo
mainline. The empty seed directory + the generator is the source of truth.

If you have just cloned and need a working installer image, run:

```bash
./tools/aurum-wallpaper-gen/gen.sh
```

from the repo root before invoking the ISO builder.
