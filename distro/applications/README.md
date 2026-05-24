# AurumOS system-wide application entries

The `.desktop` files here are staged to `/usr/share/applications/` by the ISO
builder. They are discovered by:

- The XDG menu (any compliant launcher / menu).
- `aurum-spotlight` (via `core-services::scan_desktop_entries`).
- `aurum-dock` (when an id is referenced in `~/.config/aurum/dock.list`).

Naming convention: every file starts with `aurum-` so we can tell at a glance
which entries we ship vs. which entries a downstream package dropped.
