#!/usr/bin/env bash
# Modul 11 - bungkus image Docker ChirpStack ke satu berkas, untuk dipindahkan
# lewat flashdisk ke Raspberry Pi lain tanpa mengunduh ulang.
#
# Berguna bila internet lab lemah dan ada beberapa Pi yang masing-masing perlu
# menjalankan ChirpStack sendiri. Yang dihemat adalah unduhan image (ratusan MB);
# Docker engine-nya sendiri tetap harus terpasang di Pi tujuan.
#
#     # di Pi yang ChirpStack-nya sudah jalan:
#     bash simpan_image_docker.sh
#     bash simpan_image_docker.sh --keluar /media/pi/FLASHDISK/chirpstack.tar.gz
#
#     # di Pi tujuan (Docker sudah terpasang):
#     bash simpan_image_docker.sh --muat /media/pi/FLASHDISK/chirpstack.tar.gz
#     cd ~/chirpstack-docker && docker compose up -d
#
# Daftar image diambil langsung dari docker-compose.yml, jadi tidak mungkin
# ketinggalan bila suatu saat ChirpStack menambah komponen.
set -euo pipefail

COMPOSE_DIR="${HOME}/chirpstack-docker"
KELUAR="${HOME}/chirpstack-images.tar.gz"
MUAT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --keluar) KELUAR="$2"; shift 2 ;;
        --muat) MUAT="$2"; shift 2 ;;
        --compose-dir) COMPOSE_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,/^$/p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "Opsi tidak dikenal: $1"; exit 1 ;;
    esac
done

DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="sudo docker"

# pigz memakai seluruh inti prosesor; gzip biasa hanya satu. Di Raspberry Pi 5
# selisihnya terasa untuk arsip ratusan MB.
if command -v pigz >/dev/null 2>&1; then
    KOMPRES="pigz"; DEKOMPRES="pigz -d"
else
    KOMPRES="gzip"; DEKOMPRES="gzip -d"
fi

# ── Memuat ───────────────────────────────────────────────────────────────────
if [ -n "$MUAT" ]; then
    [ -f "$MUAT" ] || { echo "Berkas tidak ditemukan: $MUAT"; exit 1; }
    echo "==> Memuat image dari $MUAT (memakai $KOMPRES) ..."
    $DEKOMPRES -c "$MUAT" | $DOCKER load
    echo
    echo "Selesai. Lanjutkan dengan:"
    echo "    cd ~/chirpstack-docker && docker compose up -d"
    exit 0
fi

# ── Menyimpan ────────────────────────────────────────────────────────────────
if [ ! -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    echo "docker-compose.yml tidak ada di $COMPOSE_DIR."
    echo "Jalankan setup_chirpstack.sh dulu, atau tunjuk foldernya dengan --compose-dir."
    exit 1
fi

mapfile -t IMAGES < <(cd "$COMPOSE_DIR" && $DOCKER compose config --images | sort -u)
echo "==> ${#IMAGES[@]} image akan dibungkus:"
printf '      %s\n' "${IMAGES[@]}"

echo "==> Menulis $KELUAR ..."
$DOCKER save "${IMAGES[@]}" | $KOMPRES > "$KELUAR"

echo
echo "Selesai: $(du -h "$KELUAR" | cut -f1)  ->  $KELUAR"
echo "Salin ke flashdisk, lalu di Pi tujuan (Docker sudah terpasang):"
echo "    bash simpan_image_docker.sh --muat <berkas>"
