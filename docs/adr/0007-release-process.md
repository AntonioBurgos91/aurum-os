# ADR 0007: Release process

## Status
Accepted (Phase 6)

## Context
Phase 6 ships the first public beta. Beyond the engineering, the release
process itself needs to be reproducible: a user who downloads the ISO has to
be able to verify what they're getting, and a future developer has to be
able to rebuild a specific version from the lockfiles in that release.

## Decision

### Versioning
- Semantic versioning: `MAJOR.MINOR.PATCH`, stored in [VERSION](../../VERSION).
- A release tag is exactly `v${VERSION}`. The release workflow refuses to
  publish if `VERSION` in tree disagrees with the tag.

### Release artifact set
Every release publishes:
- `aurumos-vX.Y.Z.iso` — bootable hybrid ISO.
- `SHA256SUMS`, `SHA512SUMS` — checksums for the ISO above.
- `lockfiles.tar.gz` — bundled reproducibility manifest containing
  `distro/packages/pip-requirements.txt` and every `daemons/*/Cargo.lock`.

### Pipeline
[.github/workflows/release.yml](../../.github/workflows/release.yml):
1. Tag push `v*` triggers the workflow on a self-hosted runner labelled
   `iso-builder` (privileged, has `/dev/loop*` and `mount` rights — GitHub-
   hosted runners can't host a chroot mount tree).
2. The workflow verifies `VERSION` matches the tag.
3. Runs `distro/iso-builder/build.sh` to produce the ISO.
4. Computes checksums, packages lockfiles, creates a **draft** GitHub Release.
5. A human reviews the release, attaches release notes, then publishes.

### Channels
For the beta phase we use a single channel — the GitHub Releases page.
Post-1.0 we'll add `apt` repositories and a `aurum-update` daemon (separate ADR).

### Verifying a download
The publish notes will include the exact SHA256 line:

```
sha256sum -c SHA256SUMS
```

### Reproducibility
Anyone with the source tree at tag `vX.Y.Z` and the supplied `lockfiles.tar.gz`
can rebuild byte-equivalent binaries for the daemons (Cargo lockfile pinning)
and a functionally-equivalent Python venv (pip-requirements pin set). The
ISO itself is *not* bit-reproducible — squashfs ordering and the embedded
build timestamps prevent that — but the binary contents under `/usr/local/`
are.

### CI cache strategy
The `release.yml` runner should mount a persistent docker named volume at
`/uv-cache` and set `UV_NO_CACHE=0` + `UV_CACHE_DIR=/uv-cache` in the
chroot env. Without this the install re-downloads ~5 GB of wheels each
build (and uv's `--no-cache` mode has been observed to deadlock at high
parallelism; see pre-beta verification notes in CHANGELOG.md). Production
ISO defaults to `UV_NO_CACHE=1` because the squashfs must not carry the
wheel cache — only the wheels themselves end up inside the venv.

## Consequences
- **Pros** — Users can verify provenance; we can roll back a specific build
  cleanly by rebuilding from the lockfile bundle.
- **Cons** — Self-hosted runner required; loss of that runner blocks releases.
  Mitigation: the build script is reproducible on any privileged Ubuntu 24.04
  host, so a manual fallback exists.
