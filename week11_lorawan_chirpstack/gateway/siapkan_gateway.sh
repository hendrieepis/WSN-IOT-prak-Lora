#!/usr/bin/env bash
# Modul 11 - siapkan satu Raspberry Pi menjadi gateway kelompok (sekali jalan).
#
#     bash week11_lorawan_chirpstack/gateway/siapkan_gateway.sh --kelompok 2 \
#          --server 192.168.1.45
#
# Dipakai saat beberapa kelompok bekerja bersamaan: tiap Pi menjadi gateway
# kelompoknya sendiri, sementara ChirpStack cukup SATU untuk sekelas -- persis
# seperti LoRaWAN sungguhan, yang network server-nya memang milik bersama.
#
#   --kelompok N   1, 2, atau 3. Menentukan kanal EU433 yang didengar gateway
#                  (433.175 / 433.375 / 433.575 MHz) dan harus SAMA dengan
#                  -DKELOMPOK di platformio.ini kedua node.
#   --server IP    alamat ChirpStack. Kosongkan bila server dipasang di Pi ini
#                  juga -- pakai --dengan-server.
#   --dengan-server  pasang ChirpStack di Pi ini (memanggil setup_chirpstack.sh).
#   --token TOKEN  bila diisi, sekalian daftarkan gateway + kedua node ke server
#                  lewat REST API. Tanpa ini, pendaftaran dikerjakan praktikan
#                  lewat web UI (itu memang inti EXP-01).
#
# Yang dikerjakan: pasang dependensi Python, nyalakan SPI bila belum, hitung
# Gateway EUI, lalu cetak perintah persis untuk menjalankan gateway kelompok itu.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KELOMPOK=1
SERVER=""
DENGAN_SERVER=0
TOKEN=""

while [ $# -gt 0 ]; do
    case "$1" in
        --kelompok) KELOMPOK="$2"; shift 2 ;;
        --server) SERVER="$2"; shift 2 ;;
        --dengan-server) DENGAN_SERVER=1; shift ;;
        --token) TOKEN="$2"; shift 2 ;;
        -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "Opsi tidak dikenal: $1"; exit 1 ;;
    esac
done

case "$KELOMPOK" in
    1) FREQ=433175000 ;;
    2) FREQ=433375000 ;;
    3) FREQ=433575000 ;;
    *) echo "--kelompok harus 1, 2, atau 3 (EU433 hanya punya tiga kanal wajib)."
       echo "Kelompok keempat boleh berbagi kanal dengan kelompok 1, asalkan"
       echo "DevEUI dan AppKey-nya berbeda -- lihat Lampiran B di README."
       exit 1 ;;
esac

echo "=== Menyiapkan gateway kelompok ${KELOMPOK} (kanal ${FREQ} Hz) ==="

# ── 1. Dependensi ────────────────────────────────────────────────────────────
# Dipasang lewat apt, bukan pip: Raspberry Pi OS Bookworm ke atas menolak pip
# di luar virtualenv (externally-managed-environment).
echo "==> Memasang dependensi Python ..."
sudo apt-get update -qq
sudo apt-get install -y -qq python3-spidev python3-rpi-lgpio python3-paho-mqtt

# ── 2. SPI ───────────────────────────────────────────────────────────────────
if [ ! -e /dev/spidev0.0 ]; then
    echo "==> SPI belum aktif, menyalakan ..."
    sudo raspi-config nonint do_spi 0
    echo "    SPI baru berlaku setelah REBOOT. Jalankan ulang skrip ini sesudahnya."
    exit 0
fi
echo "==> SPI aktif (/dev/spidev0.0)"

# ── 3. Server (opsional) ─────────────────────────────────────────────────────
if [ "$DENGAN_SERVER" = "1" ]; then
    bash "$SRC_DIR/setup_chirpstack.sh"
    SERVER="${SERVER:-127.0.0.1}"
fi
SERVER="${SERVER:-127.0.0.1}"

# ── 4. Gateway EUI ───────────────────────────────────────────────────────────
# Diambil dari fungsi yang sama yang dipakai gateway itu sendiri, supaya tidak
# mungkin berbeda dengan yang nanti tercetak saat dijalankan.
EUI=$(cd "$SRC_DIR" && python3 -c \
    'import single_chan_pkt_fwd as g; print(g.default_gateway_id().upper())')

# ── 5. Pendaftaran otomatis (opsional) ───────────────────────────────────────
if [ -n "$TOKEN" ]; then
    echo "==> Mendaftarkan gateway + kedua node ke ${SERVER} ..."
    python3 "$SRC_DIR/provision_lab.py" --token "$TOKEN" --gateway-id "$EUI" \
        --kelompok "$KELOMPOK" --api "http://${SERVER}:8090"
fi

# ── 6. Ringkasan ─────────────────────────────────────────────────────────────
DEV_KK=$(printf '%02x' $((0x66 + (KELOMPOK - 1) * 0x11)))
KEY_KK=$(printf '%02x' $((KELOMPOK - 1)))
cat <<TXT

────────────────────────────────────────────────────────────────
 KELOMPOK ${KELOMPOK}  —  siap dijalankan
────────────────────────────────────────────────────────────────
 Gateway EUI : ${EUI}
 Kanal       : ${FREQ} Hz  SF7BW125
 Server      : ${SERVER}

 Jalankan gateway:
   cd ${SRC_DIR}
   python3 single_chan_pkt_fwd.py --server ${SERVER} --freq ${FREQ}

 Pantau data yang sudah didekripsi server:
   python3 uplink_listen.py --host ${SERVER}

 Di sisi node — platformio.ini, ubah SATU baris:
   -D KELOMPOK=${KELOMPOK}

 Nilai yang harus cocok di ChirpStack (EXP-01):
   DevEUI Node 1 : 001122334455${DEV_KK}01
   DevEUI Node 2 : 001122334455${DEV_KK}02
   AppKey Node 1 : ${KEY_KK}112233445566778899aabbccddeef1
   AppKey Node 2 : ${KEY_KK}112233445566778899aabbccddeef2
────────────────────────────────────────────────────────────────
TXT
