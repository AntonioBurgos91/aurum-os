# core-services

Shared utilities every AurumOS Qt binary links against.

| Symbol                                | Use                                              |
|---------------------------------------|--------------------------------------------------|
| `aurum::core::DesktopEntry`           | Parsed XDG `.desktop` entry                      |
| `aurum::core::scan_desktop_entries()` | XDG search (honors `XDG_DATA_HOME` / `XDG_DATA_DIRS`) |
| `aurum::core::lookup_desktop_entry(id)` | Resolve a single entry by basename             |
| `aurum::core::launch_desktop_entry(e)`| `QProcess::startDetached` + strip XDG field codes |
| `aurum::core::launch_command(line)`   | Detached spawn for ad-hoc commands               |
| `init_core_services()` (C linkage)    | Idempotent global init; kept for legacy callers  |

Consumers: aurum-dock, aurum-spotlight (apps plugin), aurum-spotlight aggregator.
