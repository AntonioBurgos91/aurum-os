# ISO builder

[`build.sh`](build.sh) takes the upstream Pop!_OS 24.04 ISO and produces
`build/aurumos-v<VERSION>.iso`. High-level steps:

1. Fetch / use the supplied Pop!_OS base ISO.
2. Extract squashfs into a chroot.
3. Stage source trees + post-install scripts + `.desktop` entries.
4. Run `chroot_setup.sh` inside: apt installs, builds Hyprland fork
   ([`build-hyprland.sh`](build-hyprland.sh)), runs the Phase-4 DL stack
   installer, compiles Qt/C++ desktop binaries, builds Rust daemons.
5. Rebuild squashfs with zstd, regenerate md5sum.txt, xorriso the hybrid ISO.

Usage:
```bash
sudo distro/iso-builder/build.sh -o build/aurumos.iso
```

Tagged releases are built by the workflow at
[`.github/workflows/release.yml`](../../.github/workflows/release.yml) on a
self-hosted `iso-builder` runner; details in
[`docs/adr/0007-release-process.md`](../../docs/adr/0007-release-process.md).
