# aurum-menubar

Top strip with five applets at 1 Hz: GPU%, VRAM, GPU °C, network throughput,
clock. Left section shows the Apple-menu glyph and the focused-app class
(via `hyprctl activewindow -j`).

| File          | Role                                                |
|---------------|-----------------------------------------------------|
| `main.cpp`    | `SystemClient` (GPU D-Bus + `/proc/net/dev` poll)   |
| `MenuBar.qml` | Layout + inline `Applet` component                  |

Color thresholds: ≥ 70% warning, ≥ 90% danger (palette tokens from
`Aurum.Aqua`).
