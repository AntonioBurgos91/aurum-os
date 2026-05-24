#!/usr/bin/env bash
# ==============================================================================
# AurumOS Icon Installer — file-types + menubar applets
# ------------------------------------------------------------------------------
# Installs the AurumOS-specific icon set on top of WhiteSur:
#   * /usr/share/icons/AurumOS/64x64/mimetypes/  ← extension-named SVGs from
#                                                  themes/icons/file-types/
#                                                  plus fdo MIME-name symlinks
#   * /usr/share/icons/AurumOS/16x16/status/     ← menubar applet glyphs from
#                                                  themes/icons/applets/
#   * /usr/share/icons/AurumOS/index.theme       ← inherits WhiteSur,Adwaita
#
# Refreshes the GTK icon cache at the end. Idempotent: re-running is safe and
# simply overwrites/refreshes existing files.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="${SCRIPT_DIR}/icons"
SRC_FILETYPES="${SRC_ROOT}/file-types"
SRC_APPLETS="${SRC_ROOT}/applets"
SRC_HICOLOR="${SRC_ROOT}/hicolor"

DEST_ROOT="${AURUM_ICON_DEST:-/usr/share/icons/AurumOS}"
DEST_MIME="${DEST_ROOT}/64x64/mimetypes"
DEST_STATUS="${DEST_ROOT}/16x16/status"

log_info()    { echo -e "\e[34m[aurum-icons]\e[0m $*"; }
log_warn()    { echo -e "\e[33m[aurum-icons WARN]\e[0m $*"; }
log_error()   { echo -e "\e[31m[aurum-icons ERROR]\e[0m $*" >&2; }
log_success() { echo -e "\e[32m[aurum-icons OK]\e[0m $*"; }

# Bail out early if the source tree is missing — easier to debug than a 500-file
# silent skip later on.
for d in "${SRC_FILETYPES}" "${SRC_APPLETS}" "${SRC_HICOLOR}"; do
    if [[ ! -d "${d}" ]]; then
        log_error "missing source directory: ${d}"
        exit 1
    fi
done

# Only root can write to /usr/share — but allow override via AURUM_ICON_DEST
# for CI testing in a fakeroot/user dir.
if [[ ! -w "$(dirname "${DEST_ROOT}")" ]] && [[ "${EUID}" -ne 0 ]]; then
    log_error "need root (or set AURUM_ICON_DEST=<dir>) to write to $(dirname "${DEST_ROOT}")"
    exit 1
fi

install -d -m 0755 "${DEST_MIME}" "${DEST_STATUS}"

# ─── 1. Copy file-type SVGs ─────────────────────────────────────────────────
# We accept both extension-named files (py.svg, ipynb.svg, ...) and fdo-named
# files (application-pdf.svg, x-python.svg, ...) — the manifest-driven
# _generate.py creates the latter — and just copy whatever is present.
n_files=0
for svg in "${SRC_FILETYPES}"/*.svg; do
    [[ -e "${svg}" ]] || continue
    install -m 0644 "${svg}" "${DEST_MIME}/"
    n_files=$((n_files + 1))
done
log_info "copied ${n_files} file-type SVGs to ${DEST_MIME}"

# ─── 2. Create fdo MIME-name symlinks from the manifest ────────────────────
# fdo spec says GTK/Qt look up icons by the MIME type with `/` replaced by `-`,
# e.g. `text/x-python` → `text-x-python`. Our source SVGs are extension-named
# (`py.svg`), so wire up the official MIME names as symlinks pointing back.
#
# We do NOT depend on python at install time — the mapping below is hand-
# curated to cover all entries in themes/icons/file-types/_manifest.json.
# Pairs are: "<fdo-name> <extension-source>"; only created when the target
# extension file exists.
mklink() {
    local fdo="$1" src="$2"
    if [[ -f "${DEST_MIME}/${src}" ]]; then
        ln -sf "${src}" "${DEST_MIME}/${fdo}.svg"
        return 0
    fi
    return 1
}

n_links=0
# Format: fdo name | extension source
while IFS='|' read -r fdo src; do
    fdo="${fdo// /}"; src="${src// /}"
    [[ -z "${fdo}" || "${fdo}" == \#* ]] && continue
    if mklink "${fdo}" "${src}"; then
        n_links=$((n_links + 1))
    fi
done <<'MIME_MAP'
# ── Code ───────────────────────────────────────────────
text-x-python              | py.svg
application-x-ipynb+json   | ipynb.svg
text-x-script.python       | py.svg
text-javascript            | js.svg
application-javascript     | js.svg
application-typescript     | ts.svg
text-x-typescript          | ts.svg
text-x-rust                | rs.svg
text-x-go                  | go.svg
text-x-c                   | c.svg
text-x-c++                 | cpp.svg
text-x-csrc                | c.svg
text-x-c++src              | cpp.svg
text-x-chdr                | h.svg
text-x-c++hdr              | h.svg
text-x-java                | java.svg
text-x-kotlin              | kt.svg
text-x-swift               | swift.svg
application-x-shellscript  | sh.svg
text-x-shellscript         | sh.svg
text-x-lua                 | lua.svg
application-x-ruby         | rb.svg
text-x-ruby                | rb.svg
application-x-php          | php.svg
text-x-php                 | php.svg
text-html                  | html.svg
text-css                   | css.svg
application-json           | json.svg
application-yaml           | yaml.svg
application-x-yaml         | yaml.svg
application-toml           | toml.svg
text-xml                   | xml.svg
application-xml            | xml.svg
application-sql            | sql.svg
text-x-sql                 | sql.svg
text-markdown              | md.svg
text-x-markdown            | md.svg
text-x-rst                 | rst.svg
text-x-tex                 | tex.svg
application-x-tex          | tex.svg
# ── Data / ML ──────────────────────────────────────────
application-x-parquet      | parquet.svg
application-vnd.apache.parquet | parquet.svg
text-csv                   | csv.svg
text-tab-separated-values  | tsv.svg
application-vnd.apache.arrow.file | arrow.svg
application-x-feather      | feather.svg
application-x-hdf          | h5.svg
application-x-hdf5         | hdf5.svg
application-x-pickle       | pkl.svg
application-x-pytorch      | pt.svg
application-x-safetensors  | safetensors.svg
application-x-onnx         | onnx.svg
application-x-gguf         | gguf.svg
application-x-ggml         | ggml.svg
application-x-protobuf     | pb.svg
application-x-tflite       | tflite.svg
application-x-numpy        | npy.svg
# ── Documents ──────────────────────────────────────────
application-pdf            | pdf.svg
application-vnd.openxmlformats-officedocument.wordprocessingml.document   | docx.svg
application-vnd.openxmlformats-officedocument.spreadsheetml.sheet         | xlsx.svg
application-vnd.openxmlformats-officedocument.presentationml.presentation | pptx.svg
application-vnd.oasis.opendocument.text         | odt.svg
application-vnd.oasis.opendocument.spreadsheet  | ods.svg
application-epub+zip                            | epub.svg
# ── Images ─────────────────────────────────────────────
image-png                  | png.svg
image-jpeg                 | jpg.svg
image-webp                 | webp.svg
image-svg+xml              | svg.svg
image-gif                  | gif.svg
# ── Video ──────────────────────────────────────────────
video-mp4                  | mp4.svg
video-quicktime            | mov.svg
video-x-matroska           | mkv.svg
# ── Audio ──────────────────────────────────────────────
audio-mpeg                 | mp3.svg
audio-x-wav                | wav.svg
audio-wav                  | wav.svg
audio-flac                 | flac.svg
audio-x-flac               | flac.svg
audio-ogg                  | ogg.svg
# ── Archives ───────────────────────────────────────────
application-zip            | zip.svg
application-x-tar          | tar.svg
application-gzip           | gz.svg
application-x-gzip         | gz.svg
application-x-bzip2        | bz2.svg
application-x-xz           | xz.svg
application-x-7z-compressed | 7z.svg
application-vnd.rar        | rar.svg
application-x-rar-compressed | rar.svg
application-vnd.debian.binary-package | deb.svg
application-x-rpm          | rpm.svg
application-x-iso9660-image | iso.svg
application-x-cd-image     | iso.svg
# ── Generic fallbacks ──────────────────────────────────
inode-directory            | folder.svg
folder                     | folder.svg
text-x-generic             | file-generic.svg
application-x-executable   | file-executable.svg
inode-symlink              | file-symlink.svg
MIME_MAP
log_info "created ${n_links} fdo MIME-name symlinks in ${DEST_MIME}"

# ─── 3. Copy menubar applet glyphs ─────────────────────────────────────────
n_applets=0
for svg in "${SRC_APPLETS}"/*.svg; do
    [[ -e "${svg}" ]] || continue
    install -m 0644 "${svg}" "${DEST_STATUS}/"
    n_applets=$((n_applets + 1))
done
log_info "copied ${n_applets} applet SVGs to ${DEST_STATUS}"

# ─── 4. Install the index.theme fragment ───────────────────────────────────
install -m 0644 "${SRC_HICOLOR}/index.theme" "${DEST_ROOT}/index.theme"
log_info "installed ${DEST_ROOT}/index.theme"

# ─── 5. Refresh GTK icon cache ─────────────────────────────────────────────
# gtk-update-icon-cache wants a theme dir with index.theme; --force overwrites
# the stale cache, --quiet suppresses the per-file noise.
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    if gtk-update-icon-cache --force --quiet "${DEST_ROOT}" 2>/dev/null; then
        log_info "refreshed GTK icon cache"
    else
        log_warn "gtk-update-icon-cache failed (non-fatal; icons still installed)"
    fi
else
    log_warn "gtk-update-icon-cache not on PATH — install libgtk-3-bin (Debian) or gtk3 (Arch)"
fi

log_success "AurumOS icons installed: ${n_files} files + ${n_links} symlinks + ${n_applets} applets"
