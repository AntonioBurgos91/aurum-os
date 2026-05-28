#!/usr/bin/env bash
# Install AurumOS rendered assets — wallpaper + icons + .desktop entries.
# Runs INSIDE the container as root (so we can write to /usr/local/...).
#
# Idempotent: re-running overwrites the same files.
#
# What it does:
#   1. Copies icons to /usr/local/share/icons/hicolor/256x256/apps/<id>.png
#      where QIcon::fromTheme(<id>) finds them.
#   2. Writes <id>.desktop files to /usr/local/share/applications/ so the
#      core desktop-entry loader (libs/core) can resolve them by id.
#   3. Copies the wallpaper to /usr/share/aurum-os/wallpapers/.
#   4. Refreshes /usr/share/icons/hicolor's cache so QIcon picks them up.

set -euo pipefail

SRC_ICONS=/tmp/aurum-assets/icons
SRC_WPS=/tmp/aurum-assets/wallpapers

ICONS_DST=/usr/local/share/icons/hicolor/256x256/apps
APPS_DST=/usr/local/share/applications
WPS_DST=/usr/share/aurum-os/wallpapers

mkdir -p "$ICONS_DST" "$APPS_DST" "$WPS_DST"

# ── 1. Icons ──────────────────────────────────────────────────────────────────
echo "[install] icons →"
for png in "$SRC_ICONS"/*.png; do
  install -m 0644 "$png" "$ICONS_DST/$(basename "$png")"
  echo "    $ICONS_DST/$(basename "$png")"
done

# A minimal `index.theme` so Qt6's `QIcon::fromTheme(name)` enumerates this
# directory. Without it, even with the right search paths AND theme name set,
# Qt skips the directory because it can't determine the "supported sizes".
# We declare a single 256×256 apps context — enough for the dock.
THEME_FILE=/usr/local/share/icons/hicolor/index.theme
if [ ! -f "$THEME_FILE" ]; then
  cat > "$THEME_FILE" <<EOF
[Icon Theme]
Name=AurumOS
Comment=AurumOS native icons
Directories=256x256/apps

[256x256/apps]
Size=256
Type=Fixed
Context=Applications
EOF
  echo "    $THEME_FILE (created)"
else
  echo "    $THEME_FILE (already present)"
fi

# ── 2. Wallpapers ─────────────────────────────────────────────────────────────
echo "[install] wallpapers →"
for png in "$SRC_WPS"/*.png; do
  install -m 0644 "$png" "$WPS_DST/$(basename "$png")"
  echo "    $WPS_DST/$(basename "$png")"
done

# Symlink the default-resolution one to a canonical name swaybg & the desktop
# both reference. Easier than parameterising every consumer.
ln -sfn "$WPS_DST/aurum-purple-1024.png" "$WPS_DST/default.png"
ln -sfn "$WPS_DST/sequoia-dark-2880x1800.png" "$WPS_DST/default-2x.png"

# ── 3. .desktop entries ───────────────────────────────────────────────────────
# Each entry is minimal — Name, Exec, Icon, Type, Categories. Exec for the
# placeholder apps just runs `notify-send` so clicking in the dock has a
# visible effect even when the real app isn't installed yet.
echo "[install] .desktop entries →"

write_desktop () {
  # $1 = id, $2 = display name, $3 = exec line, $4 = categories
  local id=$1 name=$2 exec=$3 cats=$4
  cat > "$APPS_DST/${id}.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
GenericName=$name
Comment=$name (AurumOS)
Exec=$exec
Icon=$id
Terminal=false
Categories=$cats
StartupNotify=true
EOF
  echo "    $APPS_DST/${id}.desktop"
}

# Existing real binaries
write_desktop aurum-finder      "Finder"      "aurum-finder %F"                       "System;FileManager;"
write_desktop aurum-spotlight   "Spotlight"   "aurum-spotlight"                        "Utility;"
write_desktop aurum-settings    "Settings"    "aurum-settings"                         "Settings;"
write_desktop aurum-mission     "Mission"     "aurum-mission-control"                  "Utility;"

# Placeholder apps — when the user clicks, they get a notification.
# Replaced with real launchers as the apps are packaged.
# --- Real apps: present in the demo container, point Exec at the binary ---
# These check the binary exists first; if it doesn't (e.g. user is running
# install-assets.sh on a fresh image before installing them), we fall back
# to the aurum-coming-soon stub which renders a "not installed yet" dialog
# with the install hint.
write_real_or_stub () {
  # $1 id  $2 display  $3 real_exec  $4 install_hint  $5 categories
  local id=$1 display=$2 real=$3 hint=$4 cats=$5
  # First word of $real is the binary path.
  local bin="${real%% *}"
  if [ -x "$bin" ]; then
    write_desktop "$id" "$display" "$real" "$cats"
  else
    write_desktop "$id" "$display" "aurum-coming-soon $id $display $hint" "$cats"
  fi
}

write_real_or_stub aurum-browser     "Browser"     "/usr/bin/falkon"                            "apt-install-falkon"                    "Network;WebBrowser;"
write_real_or_stub aurum-terminal    "Terminal"    "/usr/local/bin/aurum-launch-terminal"       "apt-install-kitty-or-xterm"            "System;TerminalEmulator;"
write_real_or_stub aurum-editor      "Editor"      "/usr/local/bin/aurum-launch-editor"         "apt-install-code-or-codium"            "Development;TextEditor;"
write_real_or_stub aurum-jupyterlab  "JupyterLab"  "/usr/local/bin/aurum-launch-jupyter"        "pip-install-jupyterlab"                "Development;Science;"
write_real_or_stub aurum-marimo      "Marimo"      "/usr/local/bin/aurum-launch-marimo"         "pip-install-marimo"                    "Development;Science;"
write_real_or_stub aurum-ollama      "Ollama"      "/usr/local/bin/aurum-launch-ollama"         "curl-fsSL-ollama.com/install.sh"       "Development;Science;"
write_real_or_stub aurum-mlflow      "MLflow"      "/usr/local/bin/aurum-launch-mlflow"         "pip-install-mlflow"                    "Development;Science;"
write_real_or_stub aurum-tensorboard "TensorBoard" "/usr/local/bin/aurum-launch-tensorboard"    "pip-install-tensorboard"               "Development;Science;"

# ── 4. Refresh icon cache ────────────────────────────────────────────────────
# Hicolor cache speeds up QIcon lookup. If gtk-update-icon-cache isn't present
# we skip silently — QIcon falls back to scanning the directory.
if command -v gtk-update-icon-cache >/dev/null; then
  echo "[install] refreshing icon-theme cache"
  gtk-update-icon-cache -f -t /usr/local/share/icons/hicolor 2>/dev/null || true
fi

echo "[install] done."
