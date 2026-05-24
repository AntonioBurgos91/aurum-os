# AurumOS animation policy

**Status:** active (Wave 10)
**Parent policy:** [ADR-0006 — Performance budget](../adr/0006-performance-budget.md)
**Owner:** desktop compositor + aqua-qt
**Files implementing this policy:**

- `distro/hyprland-fork/conf.d/animations.conf` — compositor whitelist
- `libs/aqua-qt/qml/Aurum/Aqua/FadeTransition.qml` — QML opacity behavior
- `libs/aqua-qt/qml/Aurum/Aqua/ScaleTransition.qml` — QML scale behavior

---

## TL;DR

AurumOS is a deep-learning workstation OS. **Animation is treated as a tax on
the GPU and the user's wall-clock**, not as a feature. We re-enable a tight set
of transient, user-triggered animations only — everything else stays off, and
nothing animates continuously in the background.

| Category | State | Why |
|----------|-------|-----|
| Window open (`windowsIn`) | ON — 150 ms ease-out, popin 95 % | Acknowledges the user's click/keystroke |
| Window close (`windowsOut`) | ON — 100 ms ease-out, popin 95 % | Confirms dismissal; shorter than open |
| Spotlight overlay (`specialWorkspace`) | ON — 200 ms ease-out, fade | Cmd-Space feels mechanical without it |
| Workspace switch (`workspaces`) | OFF | Slide would burn 16 ms × N frames every Cmd-Tab |
| Border pulse (`border`, `borderangle`) | OFF | Continuous redraw on every focus change |
| Layer fades (`fade`, `layersIn`, `layersOut`) | OFF | Menubar/notifications must appear instantly |
| Window move / resize (`windowsMove`) | OFF | Tile drags must snap, not glide |
| Global / catch-all (`global`) | OFF | Defensive — covers any new sub-event Hyprland adds |

## Why this exact set

The compositor's job during a training run is to **not exist**. Every animation
frame Hyprland renders is a frame the GPU cannot spend on the user's PyTorch
job, and every wakeup is power the laptop battery loses. So the bar for
enabling an animation is high:

1. **Triggered by an explicit user action** (not by app state, not by focus
   change, not by time). Opens, closes, and Cmd-Space qualify. Focus-follows-
   mouse border pulses do not.
2. **Strictly time-bounded** (≤ 200 ms). After the animation ends the
   compositor goes back to its idle state — no continuous repaint.
3. **Replaces a perceptual discontinuity** the user would otherwise read as a
   glitch (a window popping into existence vs. fading in).

Workspace switches, despite being user-triggered, are deliberately *not*
animated: power users Cmd-Tab dozens of times per minute, and a 200 ms slide
turns that into a flipbook. Snapping is faster and feels more responsive once
you build muscle memory — this matches the macOS "reduce motion" default that
most DL practitioners enable anyway.

## What stays OFF and why

- **`workspaces` / `workspacesIn` / `workspacesOut`** — would multiply by the
  switch frequency. A user who Cmd-Tabs 30 times/minute would see 30 × 200 ms
  = 6 s/min of animation = ~10 % of wall-clock spent on slide transitions.
- **`border` / `borderangle`** — these animate the active-window border every
  focus change. With focus-follows-mouse that's a continuous wakeup source.
- **`fade` (the layer-shell one)** — would fade the menubar/dock/notifications
  in/out on every show/hide. Notifications in particular need to appear
  *instantly* so a glance catches the toast before it dismisses.
- **`windowsMove`** — animating tile drags adds perceived input latency
  to the very interaction (window snapping) where users most demand crispness.

## Performance budget

| Metric | Target |
|--------|--------|
| Additional CPU per second during normal interactive use | ≤ 1 ms |
| Additional GPU frames per second during idle | 0 |
| Additional GPU frames per second during DL training | 0 |
| Worst-case animation playback length | 200 ms (Spotlight) |

"0 frames during training" is achievable because none of the three enabled
animations fire from background state — they all require a foreground user
gesture, which is rare-to-never during a long training run.

## QML-side equivalents

The compositor handles top-level window animations. *Within* a window, QML
components use the matching pair:

```qml
import Aurum.Aqua 1.0

// Opacity fade — match the 150 ms windowsIn duration
Item {
    Behavior on opacity { FadeTransition {} }
}

// Scale-in for popups — match the 200 ms Spotlight timing
Item {
    transform: Scale {
        id: popScale
        origin.x: width / 2
        origin.y: height / 2
    }
    Behavior on popScale.xScale { ScaleTransition {} }
    Behavior on popScale.yScale { ScaleTransition {} }
}
```

Using these shared Behaviors keeps in-window motion visually coherent with the
compositor and centralises future tuning in two QML files.

## Verifying the policy

### Confirm the compositor whitelist is loaded

```sh
hyprctl getoption animations:enabled       # → int: 1
hyprctl animations | grep -E 'windowsIn|windowsOut|specialWorkspace'
```

The three enabled animations should report `enabled: 1` and a non-zero
duration; all others should report `enabled: 0`.

### Watch frame counts during animation playback

```sh
# Baseline (no animation): note 'fps' field
hyprctl monitors -j | jq '.[] | {name, refreshRate, vrr, activeWorkspace}'

# Trigger an animation (Cmd-Space) then re-sample. Frame count should rise
# briefly and then plateau — no continuous bumping.
watch -n0.1 "hyprctl monitors -j | jq '.[] | .activelyTearing, .vrr'"
```

VRR should remain `true` throughout; if it flips to `false` while animations
play, the bezier or duration needs revisiting (the VRR controller treats
guaranteed-to-redraw periods specially).

### Sanity-check on a training run

```sh
nvidia-smi dmon -s u -c 30        # 30 s of GPU utilisation, 1 Hz
```

With a real training job running and the desktop idle, GPU utilisation should
match training-only baseline. If you see periodic 1–2 % bumps at the rate of
your focus-follows-mouse cadence, an animation has snuck back on — re-check
that `animations.conf` is being sourced (`source = /etc/aurum/hypr/conf.d/*.conf`
in `aurum.conf`) and that no later drop-in is re-enabling `border`.

## Change-control

Adding a new entry to the enabled set requires:

1. A note in the table at the top of this file justifying the new entry against
   the three "Why this exact set" criteria.
2. A measurement of the frame-time cost using the verification commands above.
3. A line in the CHANGELOG under a `wave-N` heading.

Removing an entry is freer — silence is always cheaper than motion.
