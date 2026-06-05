#!/usr/bin/env bash
# ==============================================================================
# AurumOS - enable Flatpak + Flathub for third-party desktop apps
#
# Why: AurumOS ships a curated AI/ML stack via apt + the model-pack manager,
# but a desktop OS also needs a safe, standard way to install third-party GUI
# apps (browsers, chat, OBS, IDEs, etc.). Flatpak is that standard: apps run
# sandboxed, update independently of the base system, and do not pollute the
# host with PPAs. Pop!_OS (our base) already uses it, so this fits.
#
# What this does (idempotent):
#   1. Installs flatpak + the GNOME Software/Pop!_Shop backend plugin.
#   2. Registers the Flathub remote (system-wide, so all users see it).
#   3. Drops a short AurumOS note documenting the policy + common commands.
#
# Designed to be invoked by the post-install runner (lexical order). Safe to
# run standalone for manual installs / dev iteration.
# ==============================================================================

set -euo pipefail

log()  { echo -e "\e[34m[flatpak]\e[0m $*"; }
warn() { echo -e "\e[33m[flatpak]\e[0m $*" >&2; }
die()  { echo -e "\e[31m[flatpak]\e[0m $*" >&2; exit 1; }

FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"
NOTE_DEST="/etc/aurum/flatpak-README.md"

require_root_or_writable() {
    if [[ $EUID -ne 0 ]]; then
        if ! [[ -w /usr/bin && -w /etc ]]; then
            die "must be run as root (try: sudo bash $0)"
        fi
    fi
}

install_flatpak() {
    if command -v flatpak >/dev/null 2>&1; then
        log "flatpak already present: $(flatpak --version)"
        return 0
    fi
    log "installing flatpak + software backend plugin..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    # gnome-software-plugin-flatpak wires Flathub into the graphical store.
    # If that plugin is not available (Pop uses its own shop), fall back to
    # just flatpak -- the CLI + remote still work.
    if ! apt-get install -y --no-install-recommends flatpak gnome-software-plugin-flatpak 2>/dev/null; then
        warn "gnome-software-plugin-flatpak unavailable; installing flatpak only"
        apt-get install -y --no-install-recommends flatpak
    fi
}

register_flathub() {
    log "registering Flathub remote (system-wide)..."
    # --if-not-exists makes this idempotent; --system so every account sees it.
    flatpak remote-add --if-not-exists --system flathub "${FLATHUB_URL}"
    if flatpak remotes --system 2>/dev/null | grep -q flathub; then
        log "Flathub registered."
    else
        die "Flathub remote did not register"
    fi
}

write_note() {
    log "writing policy note    -> ${NOTE_DEST}"
    install -d -m 0755 "$(dirname "${NOTE_DEST}")"
    cat > "${NOTE_DEST}" <<'NOTE'
# Installing third-party apps on AurumOS

AurumOS curates its AI/ML stack via apt and the model-pack manager. For
general third-party desktop apps, use Flatpak / Flathub -- apps run sandboxed
and update independently of the base system.

## Graphical
Open the software store and search; Flathub results install with one click.

## Command line
    flatpak search obs            # find an app
    flatpak install flathub com.obsproject.Studio
    flatpak run com.obsproject.Studio
    flatpak update                # update all flatpak apps
    flatpak uninstall com.obsproject.Studio

## Other formats
- AppImage: download from the vendor, chmod +x app.AppImage, run it.
  (LM Studio's GUI ships this way -- see 03-install-llm-runtimes.sh.)
- .deb from a website: sudo apt install ./app.deb. Least safe (no auto-updates,
  you trust the source); prefer Flathub when available.
NOTE
    chmod 0644 "${NOTE_DEST}"
}

post_check() {
    log "post-install sanity:"
    log "  flatpak : $(command -v flatpak >/dev/null 2>&1 && flatpak --version || echo MISSING)"
    log "  flathub : $(flatpak remotes --system 2>/dev/null | grep -q flathub && echo registered || echo MISSING)"
    log "  note    : $(ls "${NOTE_DEST}" 2>/dev/null || echo MISSING)"
}

main() {
    require_root_or_writable
    install_flatpak
    register_flathub
    write_note
    post_check
    log "done. Try: flatpak search <app>  then  flatpak install flathub <app-id>"
}

main "$@"
