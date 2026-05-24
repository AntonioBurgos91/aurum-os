# aurum-dock

Bottom dock with macOS-style magnification (Gaussian falloff to neighbors)
and a live GPU utilization badge. Launches apps from XDG `.desktop` entries
listed in `~/.config/aurum/dock.list` (built-in defaults in
[`dock_model.cpp`](dock_model.cpp)).

| File             | Role                                                       |
|------------------|------------------------------------------------------------|
| `main.cpp`       | Qt entry + `GpuClient` D-Bus bridge to gpu-monitor         |
| `dock_model.*`   | `QAbstractListModel` of pinned launchers (XDG-resolved)    |
| `Dock.qml`       | Magnification math + glass shelf rendering                 |

Hyprland positions/anchors via `windowrulev2` in [`aurum.conf`](../../distro/hyprland-fork/aurum.conf).
