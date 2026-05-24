# Seed dotfiles

Everything in this tree is rsynced to `/etc/skel/.config/` inside the ISO
chroot. New users on the installed system inherit it via the standard
`/etc/skel` mechanism.

| Subdir         | What it seeds                                          |
|----------------|--------------------------------------------------------|
| `hypr/`        | Hyprland config + `wallpaper.sh` engine                |
| `ghostty/`     | Ghostty terminal config                                |
| `fish/`        | Fish shell config (`config.fish`)                      |
| `starship.toml`| Starship prompt theme                                  |
| `wallpapers/`  | **NOT** a dotfile — built ISO routes these to `/usr/share/backgrounds/aurumos/` |

`wallpapers/` is the documented exception: the ISO builder excludes it from
the rsync and copies it system-wide instead.
