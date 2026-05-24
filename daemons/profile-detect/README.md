# profile-detect

Boot-time oneshot that regenerates `/etc/aurum/profile.conf` to match the
current hardware. Owned by the Hardware Profile agent (Agent G, Wave 8).

## Pieces

| Path                                                  | Role                              |
|-------------------------------------------------------|-----------------------------------|
| `distro/post-install/00-detect-profile.sh`            | The actual detection script       |
| `/usr/local/bin/aurum-detect-profile`                 | Symlink installed by ISO builder  |
| `daemons/profile-detect/systemd/aurum-detect-profile.service` | oneshot, `WantedBy=multi-user.target` |
| `/etc/aurum/profile.conf`                             | Generated KEY=VALUE conf          |

## Why oneshot, not on-demand?

Hardware can change between boots (eGPU plugged in, RAM upgraded, dual-boot
from a different distro that left an nvidia driver mismatch). Regenerating on
every boot keeps the conf honest without paying the cost of probing on every
launcher invocation.

## Install path

The ISO builder's `chroot_setup.sh` must:

1. Copy `distro/post-install/00-detect-profile.sh` →
   `/usr/local/bin/aurum-detect-profile` (chmod +x).
2. Copy `daemons/profile-detect/systemd/aurum-detect-profile.service` →
   `/etc/systemd/system/`.
3. `systemctl enable aurum-detect-profile.service`.
4. Run it once before any per-profile install step:
   `bash /usr/local/bin/aurum-detect-profile`.
