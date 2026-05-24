# Security Policy

## Reporting vulnerabilities

Please report security vulnerabilities **privately** by email to:

- **`security@aurumos.local`** *(placeholder — the maintainer will
  publish the real address on the first stable release)*

If you can, encrypt your report with our PGP key:

```bash
gpg --recv-keys 0xDEADBEEFCAFEBABE   # placeholder fingerprint
```

**Do not** open a public GitHub issue, pull request, or discussion
thread for an unpatched vulnerability. We will acknowledge receipt
within 72 hours and keep you updated as the fix progresses.

When reporting, please include:

- A description of the issue and the impact you anticipate.
- Steps to reproduce (a minimal PoC is ideal).
- Affected version(s) — `git rev-parse HEAD` of the commit you
  tested, or the `VERSION` file contents.
- Any mitigation you've already identified.

## What's in scope

The following are explicitly in scope for the security program:

- **Privilege escalation in `aurum-installer`** — the live-ISO
  install wizard invokes `pkexec` to run `distinst`. Bypasses of the
  policy file, argument-injection into `pkexec`, or any path from
  unprivileged user input to root execution are in scope.
- **Privilege escalation in `aurum-cuda-switch`** — the helper used
  by the Settings → CUDA section to swap CUDA runtime versions.
  Runs as root via polkit; treat similarly to the installer.
- **Session-bus D-Bus services** — the daemons
  `org.aurumos.GpuMonitorService`, `org.aurumos.SpotlightIndexerService`,
  and `org.aurumos.MlJobsTrackerService`. These are intended to be
  read-only telemetry/indexing surfaces; report any method that has
  observable side effects on the system, or any path that reads
  outside the user's home directory.
- **Command injection via `launch_desktop_entry`** — the launcher in
  `libs/core-services/` parses XDG `.desktop` files. Crafted `Exec=`
  fields, environment variable expansion bugs, or shell metachar
  handling issues are in scope.
- **Wayland compositor configuration injection** — the pinned
  Hyprland fork loads config from `~/.config/hypr/`. Any path where
  remote/untrusted input ends up in those files (or in
  `hyprctl dispatch` payloads) is in scope.

## What's out of scope

- The **Docker preview container** intentionally exposes `wayvnc`
  on `0.0.0.0:5900` and noVNC on `0.0.0.0:6080` for developer
  convenience. The production installed system binds `wayvnc` to
  `127.0.0.1` only and ships with neither port exposed. Reports
  about the demo container's network exposure will be closed as
  *won't fix*.
- **Upstream dependency bugs** — please file these with the upstream
  project directly. Notable upstreams: Qt 6, Hyprland, tantivy,
  MLflow, NVIDIA NVML, Pop!_OS. If an upstream issue affects
  AurumOS in a way the upstream patch alone doesn't fix, then a
  separate AurumOS report is welcome.
- Theoretical attacks requiring root/physical access that's already
  been granted.
- Missing security headers or TLS configuration on
  `*.aurumos.local` placeholder hostnames.

## Disclosure timeline

We follow a **coordinated disclosure** model:

- **Day 0** — Report received, acknowledged within 72 hours.
- **Day 0–14** — Triage, CVSS 3.1 scoring, and reproduction.
- **Day 14–90** — Fix developed, tested, and released. We aim to
  ship a patch release well before the 90-day deadline.
- **Day 90** — Public disclosure, even if a fix is not yet shipped.
  This can be brought forward if the vendor acknowledges and a fix
  is already in flight, or extended by mutual agreement if a
  particularly invasive fix is required.

Severity is classified using **CVSS 3.1**. Critical and high-severity
issues are eligible for an out-of-band point release; medium and low
are usually rolled into the next scheduled release.

## Hall of Fame

We credit researchers who report responsibly. The list below will
grow as reports come in.

*(No entries yet — be the first!)*

## Past advisories

| CVE | Severity | Fix version | Summary |
| --- | -------- | ----------- | ------- |
| *(no advisories published yet)* | | | |
