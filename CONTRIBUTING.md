# Contributing to AurumOS

Thanks for your interest! AurumOS builds a full Linux distribution, so
contributions are held to OS-level scrutiny — especially anything that runs
during the ISO build or as root on user machines.

## Ground rules

1. **Open an issue first** for anything non-trivial, so we agree on the
   approach before you invest time.
2. **One logical change per PR**, with a commit message that explains *why*.
3. **CI must be green**: shellcheck (warnings are errors), clang-format,
   rustfmt + clippy, all C++/Rust/shell/Python tests.
4. **Honest scope in the PR description**: state what you verified (and how)
   and what you did NOT verify. This project documents unvalidated paths in
   `docs/validation-status.md` — PRs that claim more than they tested will be
   asked to revise.

## Security-sensitive areas (extra review)

Changes under `distro/` (ISO build, post-install, polkit), `tools/aurum-update*`
(runs as root via pkexec), `.github/workflows/` or anything touching GPG
verification get a stricter review and may need a second maintainer pass.
Fork PRs never receive repository secrets; workflow runs from first-time
contributors require maintainer approval.

## Dev quickstart

- C++ (Qt6): `cmake -S . -B build -DBUILD_TESTS=ON && cmake --build build && ctest --test-dir build`
- Rust daemons: `cargo test` inside each `daemons/*`
- Shell tests: `bash tests/shell/test_aurum_update.sh`
- Python trainer smoke: `python3 apps/pointcloud-viewer/training/test_smoke.py`
