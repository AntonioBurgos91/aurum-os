# gpu-monitor

Rust daemon that polls NVIDIA NVML every second and republishes the values
on the session bus. Falls back to a deterministic simulation when NVML is
unavailable so the desktop is developable on non-NVIDIA hardware.

| Bus name      | `org.aurumos.GpuMonitorService`              |
| Object        | `/org/aurumos/GpuMonitor`                    |
| Interface     | `org.aurumos.GpuMonitor`                     |
| Methods       | `gpu_name()`, `gpu_utilization()`, `vram_total()`, `vram_used()`, `temperature()`, `power_draw_mw()` |

Started via [`systemd/aurum-gpu-monitor.service`](systemd/aurum-gpu-monitor.service)
as a user unit pulled in by `graphical-session.target`.
