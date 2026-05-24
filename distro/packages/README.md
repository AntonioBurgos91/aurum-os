# Package lists

| File                       | Consumer                          | Purpose                                    |
|----------------------------|-----------------------------------|--------------------------------------------|
| `system.list`              | ISO chroot                        | APT packages for the base system + DE deps |
| `dl.list`                  | ISO chroot                        | NVIDIA / CUDA / cuDNN / TensorRT (apt)     |
| `pip-requirements.txt`     | `02-install-dl-stack.sh`          | Python DL stack (uv-resolved)              |

`pip-requirements.txt` is the **single source of truth** for the Python
surface — the Phase 4 cleanup removed the older regex hack that extracted
Python lines from `dl.list`. CI installs the exact file via
`uv pip install -r distro/packages/pip-requirements.txt`.
