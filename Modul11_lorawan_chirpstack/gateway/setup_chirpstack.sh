#!/usr/bin/env bash
# Modul 11 - pasang ChirpStack v4 di Raspberry Pi 5 (sekali jalan, aman diulang).
#
#     bash Modul11_lorawan_chirpstack/gateway/setup_chirpstack.sh
#
# Yang dilakukan:
#   1. memasang Docker bila belum ada (skrip resmi get.docker.com)
#   2. mengambil chirpstack-docker resmi ke ~/chirpstack-docker
#   3. menyalin docker-compose.override.yml (EU433) ke dalamnya
#   4. menyalakan seluruh service dan menunggu API siap
#
# Sesudah selesai, buka http://<ip-pi>:8080 -- login awal admin / admin.
set -euo pipefail

TARGET="${HOME}/chirpstack-docker"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
    echo "==> Docker belum ada, memasang ..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    sudo usermod -aG docker "$USER"
    echo "    (log out/in sekali supaya bisa memakai docker tanpa sudo)"
fi

DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="sudo docker"

if [ ! -d "$TARGET" ]; then
    echo "==> Mengambil chirpstack-docker ..."
    git clone https://github.com/chirpstack/chirpstack-docker.git "$TARGET"
fi

echo "==> Memasang override EU433 ..."
cp "$SRC_DIR/docker-compose.override.yml" "$TARGET/docker-compose.override.yml"

echo "==> Menyalakan ChirpStack ..."
cd "$TARGET"
$DOCKER compose up -d

echo -n "==> Menunggu API siap "
for _ in $(seq 1 60); do
    if curl -sf -o /dev/null "http://127.0.0.1:8080"; then
        echo " siap."
        break
    fi
    echo -n "."
    sleep 2
done

IP=$(hostname -I | awk '{print $1}')
cat <<TXT

ChirpStack berjalan.

    Web UI  : http://${IP}:8080     (admin / admin)
    UDP     : ${IP}:1700            (untuk single_chan_pkt_fwd.py)
    MQTT    : ${IP}:1883            (untuk uplink_listen.py)

Langkah berikutnya ada di README bagian 6 (EXP-01):
    1. daftarkan gateway memakai EUI yang dicetak single_chan_pkt_fwd.py
    2. buat Device Profile region EU433, LoRaWAN 1.0.3, OTAA
    3. daftarkan Node 1 dan Node 2 beserta DevEUI + AppKey-nya

Belum pernah memakai Docker? Lampiran A di README modul ini berisi lima
perintah yang dipakai, cara membacanya, dan apa yang harus dilakukan bila
ada yang tidak beres.
TXT
