# Animations

AurumOS ships with a deliberately tiny set of compositor animations on by
default. This page covers how to tune them, turn them off entirely, or
re-enable Hyprland's defaults if you want a more conventional desktop feel.

The full design rationale lives in
[ADR-0006-Addendum — Selective compositor animations](../adr/0006-selective-animations.md);
the per-event whitelist and verification commands are in
[`docs/internal/animation-policy.md`](../internal/animation-policy.md). This
guide is the operator-facing how-to.

## What's animated by default

| Event | When you'll see it | Duration |
|-------|--------------------|----------|
| Window open | A new app spawns or you launch from the dock | 150 ms |
| Window close | You close a window (`Cmd-W`, traffic-light click) | 100 ms |
| Spotlight overlay | `Cmd-Space` invokes Spotlight | 200 ms |

Everything else — workspace switches, border focus pulses, layer-shell fade
(menubar/notifications), tile drag — is explicitly disabled. This is the
"transient user gesture only" policy described in the ADR.

## Disabling all animations

If you're running long training jobs and want the absolute minimum compositor
activity, drop one of the following into your **own** Hyprland config
(typically `~/.config/hypr/hyprland.conf`). Your conf is sourced *after*
`/etc/aurum/hypr/aurum.conf`, so any value you set here takes precedence.

```conf
# ~/.config/hypr/hyprland.conf — appended after `source = /etc/aurum/hypr/aurum.conf`

animations {
    enabled = no
}
```

Apply it without restarting:

```sh
hyprctl reload
```

Confirm:

```sh
hyprctl getoption animations:enabled    # → int: 0
```

The QML-side `FadeTransition` / `ScaleTransition` will still fire inside
individual aurum-qt apps (150 ms opacity, 200 ms scale) — they're independent
of the compositor. If you want them off too, set
`AURUM_DISABLE_ANIMATIONS=1` in your environment before launching the desktop
session; the aqua-qt loader reads it and short-circuits the Behaviors.

## Tweaking individual animations

The defaults live in `/etc/aurum/hypr/conf.d/animations.conf`. Rather than
editing the system file (which `apt upgrade` may overwrite), override per-key
in your user conf. Hyprland merges later assignments on top of earlier ones,
so you can change just the one curve you care about:

```conf
# Slow the Spotlight fade from 200 ms to 350 ms
bezier = mySlowEase, 0.16, 1, 0.3, 1
animation = specialWorkspace, 1, 3.5, mySlowEase, fade
```

Reload and check:

```sh
hyprctl reload
hyprctl animations | grep specialWorkspace
```

## Re-enabling Hyprland's defaults

Not recommended on a DL workstation (the defaults include border-angle
animations that wake the GPU on every focus change), but supported:

```conf
# ~/.config/hypr/hyprland.conf
animations {
    enabled = yes
    # Don't source the AurumOS whitelist — let Hyprland use its built-in defaults.
}
```

…and remove the `source = /etc/aurum/hypr/conf.d/*.conf` line if you have it.
Note that you'll lose the drop-ins for vLLM, ComfyUI, etc. too — they live in
the same directory. To keep those but skip animations only:

```sh
sudo mv /etc/aurum/hypr/conf.d/animations.conf /etc/aurum/hypr/conf.d/animations.conf.disabled
hyprctl reload
```

## Troubleshooting

### "Animations don't fire even though `enabled = 1`"

Check the load order. `hyprctl getoption animations:enabled` reflects the
final merged state, so if it says `1` but no animation plays, an individual
`animation = <name>, 0` line later in the chain has disabled the specific
sub-event. List them all:

```sh
hyprctl animations
```

…and look for the event you expected (`windowsIn`, `windowsOut`,
`specialWorkspace`). Each should report `enabled: 1` and a non-zero
`speed:` value.

### "GPU utilisation rises during a training run"

If `nvidia-smi dmon -s u -c 30` shows periodic 1–2 % bumps at the rate of
your focus-follows-mouse motion, an animation has snuck back on (almost
always `border` or `borderangle`). Re-check that `animations.conf` is
being sourced:

```sh
hyprctl animations | grep -E 'border |borderangle '
# Both should report enabled: 0
```

If they don't, a later-sourced conf is re-enabling them. Search:

```sh
grep -rE 'animation\s*=\s*border' /etc/aurum/hypr/ ~/.config/hypr/
```

### "The Spotlight overlay flashes black before fading in"

That's the QML `Window.color` defaulting to transparent on some Wayland
backends. The fix lives in `desktop/spotlight/Spotlight.qml` (the
`color: "#FF1c1c1e"` line documented there); if you forked Spotlight,
make sure your fork also pins the alpha byte.

## Applying changes at runtime

Hyprland reads conf changes via:

```sh
hyprctl reload
```

…which is non-destructive (no window relayout, no compositor restart). If
that doesn't pick up a change, the conf has a syntax error — check:

```sh
journalctl --user -u aurum-session --since "1 minute ago" | grep -i hypr
```

Hyprland prints parse errors there.

## See also

- [ADR-0006-Addendum — Selective compositor animations](../adr/0006-selective-animations.md)
- [`docs/internal/animation-policy.md`](../internal/animation-policy.md) — the per-event whitelist with rationale
- [ADR-0006 — Performance budget](../adr/0006-performance-budget.md) — the parent budget this policy serves
- `distro/hyprland-fork/conf.d/animations.conf` — the canonical whitelist
- `libs/aqua-qt/qml/Aurum/Aqua/FadeTransition.qml` — QML opacity Behavior
- `libs/aqua-qt/qml/Aurum/Aqua/ScaleTransition.qml` — QML scale Behavior
