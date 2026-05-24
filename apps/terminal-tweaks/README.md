# Terminal tweaks

AurumOS ships a curated terminal experience: **Ghostty** (GPU-accelerated),
**Fish 4.0** with **Starship**, and **Zellij** as multiplexer.

The deployable dotfiles live under [`distro/seed/`](../../distro/seed/) so the
ISO builder picks them up via the existing seed→`/etc/skel/.config/` flow:

- `distro/seed/ghostty/config` — Ghostty window + font settings
- `distro/seed/fish/config.fish` — Fish prompt, aliases, mise hook
- `distro/seed/starship.toml` — Starship prompt theme
- [`zellij.kdl`](zellij.kdl) — Zellij layout matching the macOS-like tiling UX

Why two locations: `distro/seed/` holds *deployable* config trees the ISO
rsyncs into a new user's `~/.config/`. This directory holds AurumOS-curated
overrides that aren't owned by any one app and would clutter `seed/` if
folded in alongside dotfiles.
