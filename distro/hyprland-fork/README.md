# AurumOS Hyprland Fork

AurumOS ships a pinned, source-built fork of Hyprland rather than the apt
package. This guarantees:

- A known-good version that matches our patches and config schema.
- Compositor behavior that does not regress when upstream changes defaults
  (corner radii, blur, animations, IME glitches, etc.).
- The ability to apply small, surgical patches without forking the whole
  source tree forever.

## Fork strategy

We treat Hyprland upstream as a "vendored, pinned" dependency:

- `UPSTREAM_REPO` — `https://github.com/hyprwm/Hyprland`
- `UPSTREAM_TAG`  — pinned in [build-hyprland.sh](../iso-builder/build-hyprland.sh)
- Patches under [patches/](patches/) are applied with `git am` in order.

There is no long-running fork branch on GitHub. The "fork" is the
combination of `(upstream tag) + (patches/) + (aurum.conf)`. This is the
same model Debian uses for packaged upstreams and avoids the maintenance
cost of a real downstream branch.

## What we customize

1. **Defaults** — [aurum.conf](aurum.conf) is sourced from the user's
   `hyprland.conf` and pins compositor-wide visuals (corner radius, gaps,
   border colors, shadow params) so individual users can override on top.
2. **Patches** — Anything that cannot be expressed in config goes in
   `patches/`. As of Phase 1, this set is empty; we ship a vanilla
   upstream build whose behavior is bent purely via config.

## Building

Run as part of the ISO build:

```bash
sudo ./distro/iso-builder/build.sh
```

Or standalone (inside the chroot, or on a dev box with the build deps):

```bash
sudo ./distro/iso-builder/build-hyprland.sh
```

The script installs to `/usr/local` so it shadows any `apt`-installed
`hyprland` from `system.list`.
