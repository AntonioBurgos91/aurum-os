# Icon theme

v0.1.0-beta uses **upstream WhiteSur Icon Theme** unmodified — pinned tag and
install steps in [`themes/install_themes.sh`](../install_themes.sh).

This directory will collect AurumOS-specific icon overrides as we add them
(JupyterLab, Marimo, PyTorch, custom Aurum apps). The plan:
1. Place SVG sources under `apps/<name>/`, scalable variants under
   `<size>/apps/<name>.svg`.
2. Extend `install_themes.sh::install_icon_theme()` to `cp` the tree on top
   of the freshly-installed WhiteSur dir.

Empty in v0.1 because the upstream WhiteSur set covers every shipped app.
