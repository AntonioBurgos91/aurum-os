# aurum-settings

Settings panel with five sections (sidebar nav + StackLayout).

| Section            | Backend                                        | Privilege boundary |
|--------------------|------------------------------------------------|--------------------|
| General            | read-only                                      | none               |
| GPU                | `org.aurumos.GpuMonitorService`                | none (read-only)   |
| CUDA               | [`cuda_manager.*`](cuda_manager.cpp)           | pkexec for system-wide symlink change |
| Python venvs       | [`venv_manager.*`](venv_manager.cpp) → `uv venv` | user scope only  |
| MLOps              | [`mlops_config.*`](mlops_config.cpp) → `~/.config/aurum/mlops.toml` | user scope |

Privileged operations route through [`helpers/aurum-cuda-switch`](helpers/aurum-cuda-switch),
authorized by the policy in [`polkit/`](polkit/).
