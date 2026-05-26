#!/usr/bin/env bash
# AurumOS desktop preview — lanzador validado para DEVELOP-IA (NVIDIA RTX 5060 Ti)
# Requiere: nvidia-container-toolkit instalado en el host
#
# Uso: bash distro/demo/run-preview.sh
# Luego abrir: http://localhost:6080/vnc.html

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
[[ -f "${ROOT}/CMakeLists.txt" ]] || { echo "ERROR: no encuentro repo root" >&2; exit 1; }

# ── Verificar nvidia-container-toolkit ───────────────────────────────────────
if ! docker info 2>/dev/null | grep -q 'nvidia'; then
    echo "ERROR: nvidia runtime no disponible."
    echo "Instala nvidia-container-toolkit:"
    echo "  sudo apt-get install -y nvidia-container-toolkit"
    echo "  sudo nvidia-ctk runtime configure --runtime=docker"
    echo "  sudo systemctl restart docker"
    exit 1
fi

RENDER_GID=$(stat -c '%g' /dev/dri/renderD128 2>/dev/null || echo 992)
VIDEO_GID=44

# ── Build (usa cache — rápido si no hay cambios) ──────────────────────────────
if ! docker image inspect aurumos:dev >/dev/null 2>&1; then
    echo "▶ Building aurumos:dev (primera vez, ~10-15 min)..."
    docker build -t aurumos:dev "${ROOT}"
else
    echo "▶ aurumos:dev ya existe"
fi

echo "▶ Building aurumos:desktop..."
docker build -t aurumos:desktop \
    -f "${ROOT}/distro/demo/Dockerfile.desktop" \
    "${ROOT}"
echo "▶ Build OK"

# ── Lanzar contenedor ─────────────────────────────────────────────────────────
docker rm -f aurum-desktop 2>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AurumOS preview → http://localhost:6080/vnc.html"
echo "  Logs            → docker logs -f aurum-desktop"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

docker run -d \
    --name aurum-desktop \
    --runtime=nvidia \
    --gpus all \
    --device /dev/dri/card1:/dev/dri/card1 \
    --device /dev/dri/renderD128:/dev/dri/renderD128 \
    --group-add "$RENDER_GID" \
    --group-add "$VIDEO_GID" \
    --tmpfs /run:rw,mode=0755 \
    -p 6080:6080 \
    -p 5900:5900 \
    -e XDG_RUNTIME_DIR=/tmp/runtime \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e LIBSEAT_BACKEND=noop \
    -e WLR_NO_HARDWARE_CURSORS=1 \
    -e WLR_LIBINPUT_NO_DEVICES=1 \
    -e AQ_NO_MODIFIERS=1 \
    aurumos:desktop

echo "Contenedor iniciado. Esperando noVNC (hasta 120s)..."
# Use `_` as the unused loop var so shellcheck SC2034 doesn't fire
for _ in $(seq 1 60); do
    if curl -sf http://localhost:6080/vnc.html >/dev/null 2>&1; then
        echo "✓ noVNC listo → http://localhost:6080/vnc.html"
        exit 0
    fi
    sleep 2
    printf "."
done
echo ""
echo "noVNC no respondió. Revisa: docker logs aurum-desktop"
exit 1
