# aurum-mission-control

Fullscreen overlay (Cmd+↑, F3, Ctrl+↑) showing every workspace as a card
with miniature window tiles. Click a tile → focus that window. Click the
backdrop or press Esc → quit.

| File             | Role                                              |
|------------------|---------------------------------------------------|
| `main.cpp`       | Qt entry                                          |
| `hypr_client.*`  | Wraps `hyprctl -j workspaces/clients/activeworkspace` |
| `MissionControl.qml` | 4-column GridView + window tiles              |

Snapshot at open; not live. Refreshing it from `hyprctl events` is on the
post-v0.1 roadmap.
