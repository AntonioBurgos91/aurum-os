# Construir AurumOS y probar la app de nube de puntos

Guía para construir la ISO en TU máquina (AMD Ryzen, Linux Mint 22 / Ubuntu 24.04)
y arrancarla de forma segura para probar el visor de nube de puntos + el
entrenador de CV. Cada paso lo ejecutas tú; nada de esto toca tu disco hasta el
paso 5 (y ese es opcional).

> Estado honesto: el build de la ISO está integrado y verde en CI. El instalador
> gráfico (distinst) NO está validado de extremo a extremo. Por eso: **prueba en
> USB live primero**, y NO instales sobre tu disco de trabajo.

## 0. Requisitos
- ~20 GB de disco libre y conexión (debootstrap descarga Ubuntu base).
- Un USB de >= 8 GB que puedas borrar (solo para el paso 4).

## 1. Instalar dependencias del build
```bash
sudo apt-get update
sudo apt-get install -y \
  xorriso squashfs-tools rsync wget gpg curl \
  debootstrap grub-pc-bin grub-efi-amd64-bin grub-common
```

## 2. Clonar el repo (si no lo tienes ya)
```bash
git clone https://github.com/AntonioBurgos91/aurum-os.git
cd aurum-os
```

## 3. Construir la ISO (base Ubuntu, autocontenida)
```bash
sudo ./distro/iso-builder/build.sh --base ubuntu
```
- Tarda bastante (debootstrap + compilar el escritorio + stack DL). Paciencia.
- Salida: `build/aurumos-v0.1.0-beta.iso`
- Comprueba que existe:
```bash
ls -lh build/aurumos-v0.1.0-beta.iso
```

## 4. (Recomendado) Probar en una VM antes de tocar un USB
Sin riesgo para tu hardware. Si tienes QEMU:
```bash
sudo apt-get install -y qemu-system-x86 ovmf
qemu-system-x86_64 -m 4096 -enable-kvm \
  -drive file=build/aurumos-v0.1.0-beta.iso,format=raw,if=virtio \
  -bios /usr/share/OVMF/OVMF_CODE.fd
```

## 5. Grabar a USB y arrancar en LIVE (no instala nada)
**CUIDADO**: identifica bien el USB o puedes borrar el disco equivocado.
```bash
# 1) Conecta el USB y mira qué dispositivo es (p.ej. /dev/sdb, NO una particion sdb1):
lsblk -o NAME,SIZE,MODEL,TRAN
# 2) Graba (CAMBIA /dev/sdX por tu USB REAL; revisa dos veces):
sudo dd if=build/aurumos-v0.1.0-beta.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```
Reinicia, entra en el menú de arranque (F12/F10/ESC según placa), elige el USB,
y selecciona **"AurumOS (live)"**. Esto arranca en memoria, **sin tocar tu disco**.

## 6. Probar la app dentro de AurumOS (en la sesión live)
Una vez en el escritorio:
- Busca **"Point Cloud Viewer"** en el menú/dock → abre el visor.
  - Sin argumentos muestra la escena de demostración (baches/grietas).
  - Con un escaneo: `aurum-pointcloud-viewer /ruta/a/tu_scan.ply`
- Para una escena urbana clasificada (coches/edificios) renderizada a imagen:
```bash
pcv-render-offscreen /tmp/escena.png city
xdg-open /tmp/escena.png
```
- Entrenar el modelo de segmentación (CV Training Studio o terminal):
```bash
aurum-cv-train --epochs 60 --out /tmp/cvmodel
# resultados + métricas reales por clase en la terminal;
# /tmp/cvmodel/pred_scene.ply se puede abrir con el visor:
aurum-pointcloud-viewer /tmp/cvmodel/pred_scene.ply
```

## 7. Verificar que la app está realmente instalada en el SO
```bash
which aurum-pointcloud-viewer pcv-render-offscreen aurum-cv-train
ls /usr/share/applications/aurum-pointcloud-viewer.desktop
ls /usr/local/share/icons/hicolor/256x256/apps/aurum-pointcloud-viewer.png
```

## NO hagas esto todavía
- NO uses el instalador gráfico para instalar AurumOS sobre tu disco de trabajo:
  el instalador (distinst) no está validado de extremo a extremo. Usa SOLO el
  modo live hasta que eso se pruebe en hardware desechable + con backup.
