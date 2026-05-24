# aqua-qt

AurumOS visual identity. Two surfaces:

1. **C++ shared library** exposed via [`style_engine.h`](style_engine.h):
   - `Tokens` (Sequoia-Dark color palette + corner radii)
   - `aqua_dark_palette()` — `QPalette` derived from the tokens
   - `aqua_default_font()` / `aqua_mono_font()` — Inter / FiraCode with
     substitution chains to SF-family fallbacks
   - `init_aqua_style()` — forces Fusion + applies palette + fonts;
     idempotent and safe to call before `QApplication` (warns and no-ops)

2. **QML module `Aurum.Aqua`** under [`qml/Aurum/Aqua/`](qml/Aurum/Aqua/):
   - `Theme` singleton (same tokens, QML-side)
   - `GlassPanel` — opaque tinted shelf (no real blur; ADR-0002)
   - `MetricBadge` — labeled value with threshold coloring
   - `TrafficLights` — close/minimize/maximize dots

Installed to `${CMAKE_INSTALL_LIBDIR}/qt6/qml/Aurum/Aqua/` so consumers can
`import Aurum.Aqua 1.0` without `QML2_IMPORT_PATH` tricks.
