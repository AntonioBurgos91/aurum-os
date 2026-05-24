# AurumOS default wallpapers

Drop `.jpg` / `.png` / `.webp` files in this directory and they will be
installed to `/usr/share/backgrounds/aurumos/` by the ISO builder. The file
named `default.jpg` is the one shown on first login.

The wallpaper engine ([../hypr/wallpaper.sh](../hypr/wallpaper.sh)) also
rotates through every image in this directory on a configurable interval
(`AURUM_WALLPAPER_INTERVAL`, default 1800s) when more than one is present.

Asset binaries are intentionally not committed here — Phase 1 ships with an
empty directory and a solid-color fallback. Drop the production assets in
before cutting an ISO.
