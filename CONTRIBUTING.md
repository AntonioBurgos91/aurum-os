# Contributing to AurumOS

## Welcome

**AurumOS** is a macOS-Sequoia-inspired Linux distribution built on top of
**Pop!_OS 24.04 LTS**, targeted at deep-learning workstations. It pairs a
bespoke Qt6/QML desktop (dock, menubar, finder, spotlight, mission control,
settings) with Rust async daemons that expose GPU telemetry, full-text
search, and MLflow job tracking over D-Bus. Contributions of all sizes are
welcome — bug reports, doc tweaks, new spotlight plugins, ADRs, kernel
tuning profiles, packaging fixes, you name it. Read this guide, open an
issue if you want to discuss the design first, and send a PR when you're
ready.

## Code of conduct

This project adheres to the **Contributor Covenant 2.1**. By participating
you are expected to uphold it. Read the full text here:

<https://www.contributor-covenant.org/version/2/1/code_of_conduct/>

Report unacceptable behaviour to `conduct@aurumos.local` (placeholder).
Reports are confidential. Maintainers commit to enforcement as described
in the Covenant.

## Project structure

The repository is a monorepo. The top-level layout:

- `desktop/` — Qt6/QML desktop apps (C++23):
  `dock`, `menubar`, `finder`, `spotlight`, `settings`,
  `mission-control`, `notifications`, `installer`, `coming-soon`.
- `libs/` — shared C++ libraries:
  - `aqua-qt/` — color tokens, palette, Fusion init, `Aurum.Aqua` QML
    module. **Always** consume colors through `Theme.*` from here.
  - `core-services/` — XDG `.desktop` entry scanner + launcher.
  - `ml-integrations/` — Quick Look + previewers for `.ipynb`,
    `.safetensors`, `.parquet`.
- `daemons/` — Rust async daemons (tokio + zbus + tracing):
  - `gpu-monitor/` — NVML wrapper → `org.aurumos.GpuMonitorService`.
  - `spotlight-indexer/` — tantivy index + inotify watcher.
  - `ml-jobs-tracker/` — MLflow REST poller → D-Bus signals.
- `distro/` — distro bits: pinned Hyprland fork, ISO builder,
  post-install asset installer, Docker preview launcher
  (`distro/demo/run-preview.sh`).
- `tools/` — image render helpers written in Rust + `tiny-skia`
  (`aurum-mockup`), and the smoke test runner.
- `tests/` — integration + acceptance harness (boot bench, idle bench,
  DL stack smoke + bench).
- `docs/` — architecture decision records (`docs/adr/`) and user guides
  (`docs/guides/`).

## Dev environment setup

The fastest way to a usable desktop is the Docker preview container — it
ships Hyprland + the daemons + every Qt app already built, accessible
through noVNC in your browser:

```bash
# From the repo root
./distro/demo/run-preview.sh        # builds + runs the container
open http://localhost:6080/vnc.html # access the desktop in your browser
./tools/smoke-test.sh               # run the 52-check health suite
```

For native builds outside the container, see the top of
`distro/demo/Dockerfile` for the exact apt + cargo bootstrap.

## Coding standards

### C++ (Qt6, C++23)

- Use Qt6 — no Qt5 shims, no Qt-private headers.
- Naming: `snake_case` for member functions, `camelCase` for Qt
  signals and slots, `PascalCase` for types.
- Comments: `// line comments`, **not** `/* … */` blocks.
- Header guards: `#pragma once` at the top — no `#ifndef` ladders.
- Logging: `qInfo()` / `qWarning()` / `qCritical()` — **never**
  `std::cerr` or `printf`. Categories live in `libs/aqua-qt/`.
- No raw `new` for QObject subclasses — use parented allocation
  (`new Foo(parent)` only when ownership is explicit).

### QML

- Indent 4 spaces. No tabs.
- All color tokens come from the `Theme` singleton in
  `libs/aqua-qt/qml/Aurum/Aqua/Theme.qml`. **Never** hardcode hex
  colors, *except* on the root window `color:` property where you
  must write `"#FF1c1c1e"` (the `#FF` alpha prefix works around a
  wlroots alpha-leak bug — see `docs/adr/0004-wlroots-alpha.md`).
- Prefer declarative bindings to imperative `Component.onCompleted`
  blocks where possible.

### Rust

- Edition **2021**, MSRV **1.75**.
- Async runtime: **tokio**. D-Bus: **zbus**. Logging: **tracing**.
- Error handling: bubble errors with `?` and a top-level `Result<…,
  anyhow::Error>`. **Never** call `.unwrap()` or `.expect()` in
  daemon code paths. Test code under `#[cfg(test)]` may unwrap freely.
- Public APIs get rustdoc; daemons get a top-of-`main.rs` doc comment
  summarising the D-Bus surface.
- Run `cargo fmt && cargo clippy --all-targets -- -D warnings`
  before pushing.

### Bash scripts

- Shebang: `#!/usr/bin/env bash`.
- First non-comment line: `set -uo pipefail`. **Do not** add `-e` —
  the smoke test runner deliberately omits it so failed checks
  accumulate instead of aborting on first failure. See the comment
  block at the top of `tools/smoke-test.sh`.
- Quote every variable expansion. `shellcheck` clean.

## Submitting changes

1. **Fork** the repo, create a branch off `main` named
   `feature/<short-slug>` or `fix/<short-slug>`.
2. Keep PRs **small and focused** — a single concern, ideally
   under 400 LOC of net change. Split sprawling work into a series.
3. Run `./tools/smoke-test.sh` locally before pushing — the output
   must show **52/52 PASS**, or your PR description must explain
   which checks regressed and why.
4. **New daemons**: add unit tests under `daemons/<name>/tests/`.
   Aim for coverage of the public D-Bus interface, not the internals.
5. **New desktop apps**: add unit tests using **QtTest** under
   `desktop/<name>/tests/`. Headless tests should use
   `QT_QPA_PLATFORM=offscreen`.
6. **Sign your commits** with `git commit -s`. The `Signed-off-by:`
   trailer implies acceptance of the Developer Certificate of Origin
   (DCO) — see <https://developercertificate.org/>.
7. Reference the issue your PR closes with `Closes #NNN` in the body.
8. Be patient — reviews land within a few days. Address comments by
   pushing new commits (don't force-push during review; squash on
   merge instead).

## Architecture decisions

Anything that changes a contract between subsystems (D-Bus interface,
on-disk schema, IPC protocol, packaging layout, new external dependency)
needs an **Architecture Decision Record**. The format and rationale
live in `docs/adr/0001-record-architecture-decisions.md`.

Existing ADRs: `0001`..`0007`. **Next ADR number: `0008`.**

Workflow:

1. Copy `docs/adr/0001-record-architecture-decisions.md` to
   `docs/adr/0008-<your-slug>.md`.
2. Fill in *Context*, *Decision*, *Consequences*. Status: `Proposed`.
3. Open the PR with the ADR and the implementation in the same
   change. Flip status to `Accepted` on merge.

## D-Bus naming convention

All AurumOS session-bus services follow the same triple. Pick a
**PascalCase** service name and derive everything else mechanically:

| Element        | Pattern                          | Example                                  |
| -------------- | -------------------------------- | ---------------------------------------- |
| Bus name       | `org.aurumos.<Name>Service`      | `org.aurumos.GpuMonitorService`          |
| Interface name | `org.aurumos.<Name>`             | `org.aurumos.GpuMonitor`                 |
| Object path    | `/org/aurumos/<Name>`            | `/org/aurumos/GpuMonitor`                |

Use `org.freedesktop.DBus.Properties` for property access; emit
`PropertiesChanged` on mutation. Reserve `org.aurumos.System.*` for
the (currently empty) system-bus namespace.

## Adding a new dock app

Quick recipe — say you're adding a hypothetical *Snippets* app:

1. Add the icon. Open `tools/aurum-mockup/src/bin/icons.rs` and add
   a render function that draws the SVG/tiny-skia primitive into the
   icon set. Add it to the `ICONS` table at the top.
2. Register it in the user's dock layout. Append the app id to
   `~/.config/aurum/dock.list` (one id per line). The dock watches
   this file with inotify and reloads.
3. Write the `.desktop` entry. Add a stanza to
   `distro/post-install/02-install-assets.sh` so
   `aurum-install-assets` drops a file into
   `/usr/share/applications/aurum-snippets.desktop` with the
   correct `Exec=`, `Icon=`, and `Categories=AurumOS;` keys.
4. Run `./tools/smoke-test.sh` — checks 41–46 verify dock entries.

Thanks for contributing!
