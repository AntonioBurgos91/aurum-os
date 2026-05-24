# ADR 0006-Addendum: Selective compositor animations

## Status

Accepted (Wave 10F). Amends — does **not** replace —
[ADR-0006 — Performance budget](./0006-performance-budget.md). The performance
budget itself stands unchanged; this addendum narrows the "Disable Hyprland blur
and animations by default" clause from *all* animations to *a curated three*.

## Context

The original ADR-0006 set `animations { enabled = false }` in
`distro/hyprland-fork/aurum.conf` to guarantee zero compositor frame variance
during long training runs. Frame variance during a multi-hour PyTorch job is
observable: any background redraw competes with the kernel for the GPU and
shows up as periodic 1 %–2 % bumps in `nvidia-smi dmon`.

Wave 10 user testing surfaced the opposite complaint. With all motion off the
desktop reads as "lifeless" — windows snap into existence with no transition,
which users perceive as glitchy rather than fast. The macOS reference target
this OS visually mirrors uses sub-200 ms transitions for the same events, and
their absence is jarring once the rest of the chrome (rounding, shadow, glass)
is in place.

We need a middle ground that:

1. Preserves the "zero animation frames during training" guarantee.
2. Restores enough motion that user-triggered transitions read as intentional.
3. Adds **no** continuous, background, or focus-driven animation under any
   circumstances (those are the categories that actually cost GPU during a
   training run).

## Decision

Re-enable exactly three compositor animations, all transient and all gated on
explicit user gestures:

| Event | Duration | Curve | Why it qualifies |
|-------|----------|-------|------------------|
| `windowsIn` | 150 ms | `aurumEaseOut` popin 95 % | Acknowledges click/keystroke that spawned the window |
| `windowsOut` | 100 ms | `aurumEaseOut` popin 95 % | Confirms dismissal; shorter than open per Material guidance |
| `specialWorkspace` | 200 ms | `aurumEaseOut` fade | Spotlight (Cmd-Space) overlay feels mechanical without it |

Every other animation key Hyprland exposes is explicitly set to `0` in
`distro/hyprland-fork/conf.d/animations.conf` — including `global`,
`workspaces`, `border`, `borderangle`, `fade`, `layersIn`, `layersOut`,
`windowsMove`. Defaulting individual keys to `0` rather than relying on
`animations { enabled = false }` ensures forward-compatibility: if a future
Hyprland release adds a new sub-event the `global = 0` line catches it.

The QML side mirrors the policy with two shared `Behavior` animations
(`FadeTransition`, `ScaleTransition`) so in-window motion matches compositor
motion without each consumer hard-coding a duration.

The detailed per-key rationale and the verification commands live in
[`docs/internal/animation-policy.md`](../internal/animation-policy.md).

## Consequences

**Pros**
- UI reads as macOS-class on the three interactions where the eye most expects
  motion (window open, window close, Spotlight invoke).
- Training-time GPU baseline is unchanged: none of the three enabled animations
  fire from background state.
- The reset-then-whitelist structure in `animations.conf` is robust against
  Hyprland adding new sub-events in future releases.

**Cons**
- Worst-case extra GPU work per window-open is ~5 ms at 1080p — measurable but
  invisible to the user, and zero during training because no windows open on a
  training-only workload.
- One additional drop-in conf file (`conf.d/animations.conf`) to load. The
  ordering constraint with `aurum.conf` is real — see "Implementation notes".

**Alternatives considered**
- *Leave animations entirely off.* Rejected after user testing: the static feel
  was reported as the single most-noticed regression vs. macOS.
- *Enable Hyprland's defaults.* Rejected: defaults include `border` /
  `borderangle` continuous animations and `workspaces` slide, both of which
  violate the "no background motion during training" guarantee.
- *Per-app conditional animations via `windowrule`.* Rejected as too brittle —
  Hyprland's per-window animation toggles are 0.55+ and not in our pinned
  fork.

## Implementation notes

`aurum.conf` currently sources `conf.d/*.conf` at line 21 (before its own
`animations { enabled = false }` block at line 63). In Hyprland's config parser
the **last** assignment wins, so the drop-in's `animations { enabled = true }`
is overridden by the later block in `aurum.conf` and the policy silently
fails. The fix is either to delete the `animations { enabled = false }` block
from `aurum.conf` (preferred — the drop-in is now the single source of truth)
or to move the `source =` line below it. This addendum assumes the former.

## Verification

```sh
hyprctl getoption animations:enabled       # → int: 1
hyprctl animations | grep -E 'windowsIn|windowsOut|specialWorkspace'
```

All three should report `enabled: 1` with the durations above. Every other
animation should report `enabled: 0`. See
[`docs/internal/animation-policy.md`](../internal/animation-policy.md#verifying-the-policy)
for the full check, including the `nvidia-smi dmon` training-baseline test.

## Related

- [ADR-0006 — Performance budget](./0006-performance-budget.md)
- [`docs/internal/animation-policy.md`](../internal/animation-policy.md)
- [`docs/guides/animations.md`](../guides/animations.md)
- `distro/hyprland-fork/conf.d/animations.conf`
- `libs/aqua-qt/qml/Aurum/Aqua/FadeTransition.qml`
- `libs/aqua-qt/qml/Aurum/Aqua/ScaleTransition.qml`
