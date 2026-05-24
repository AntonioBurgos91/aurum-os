# Inter — placeholder

This directory is intentionally empty in git.  Inter is the OFL-licensed
substitute AurumOS uses for Apple's San Francisco (SF Pro) family, which is
not redistributable.  We do **not** vendor the ~25 MB of TTF/OTF binaries in
the repository — `themes/install_fonts.sh` downloads them at image-build time.

## Source

- Releases: <https://github.com/rsms/inter/releases/latest>
- Asset:    `Inter-<VERSION>.zip` (contains `Inter Desktop/Inter-roman.var.ttf`,
            `Inter Desktop/Inter-italic.var.ttf`, plus static OTFs).
- Version pin: `INTER_VERSION=4.1` (see `themes/install_fonts.sh`).
- License: SIL Open Font License, Version 1.1.

## How it gets installed

Boot order (relevant for the QML fallback chain):

1. `themes/install_fonts.sh` runs as a post-install step.
2. Files land in `/usr/share/fonts/aurum/inter/`.
3. `fc-cache -f` rebuilds the system fontconfig cache.
4. Qt's QML engine loads `Aurum.Aqua.Theme` later (when the first app starts),
   by which time `Inter` is already resolvable by fontconfig — so the
   `fontFamilyText: "Inter, SF Pro Text, system-ui, sans-serif"` chain
   resolves to Inter on the first hop.

If you are developing on a system without Inter, the chain gracefully
degrades through `system-ui` to whatever Qt's default sans is (usually DejaVu
Sans on Ubuntu, which is what AurumOS shipped pre-Wave-10).
