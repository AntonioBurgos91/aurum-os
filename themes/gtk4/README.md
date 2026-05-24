# GTK4 theme

For v0.1.0-beta AurumOS ships **upstream WhiteSur GTK** unmodified — the
pinned tag and install steps live in [`themes/install_themes.sh`](../install_themes.sh).

This directory holds the **fork delta**: any patches, color overrides, or
material adjustments we'll layer on top in future releases. Empty in v0.1
because no upstream change has been needed yet.

Workflow once the fork is needed:
1. Drop a numbered patch here (`0001-tweak-headerbar.patch`).
2. Extend `install_themes.sh::install_gtk_theme()` to `git apply` it after
   the tarball is extracted.
3. Document the rationale in [`docs/adr/`](../../docs/adr/).
