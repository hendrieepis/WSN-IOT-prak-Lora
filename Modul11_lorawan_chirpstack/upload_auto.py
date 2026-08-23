#!/usr/bin/env python3
"""Upload otomatis ke Modul 11 (LoRaWAN OTAA) — port serial dideteksi sendiri.

Alternatif untuk menjalankan manual:
    pio run -d Modul11_lorawan_chirpstack -e node1 -t upload -t monitor
    pio run -d Modul11_lorawan_chirpstack -e node2 -t upload -t monitor

Skrip ini memindai port /dev/ttyACM*/ttyUSB* yang sedang aktif, memetakannya ke
environment `node1` (port pertama) dan `node2` (port kedua), lalu menjalankan
`pio run` dengan --upload-port sesuai hasil deteksi -- platformio.ini tidak
perlu diedit tiap kali port berganti nama.

BERBEDA DARI MODUL SEBELUMNYA: modul ini hanya punya dua environment. Gateway
bukan Arduino melainkan Raspberry Pi yang menjalankan
gateway/single_chan_pkt_fwd.py, jadi tidak ada yang perlu di-upload untuknya.

    python3 Modul11_lorawan_chirpstack/upload_auto.py
        -> upload kedua node, port otomatis

    python3 Modul11_lorawan_chirpstack/upload_auto.py --monitor
        -> upload lalu buka pio device monitor satu per satu
           (Ctrl-C untuk lanjut ke board berikutnya)

    python3 Modul11_lorawan_chirpstack/upload_auto.py --only node2
        -> upload satu environment saja

    python3 Modul11_lorawan_chirpstack/upload_auto.py --node1 /dev/ttyACM0 --node2 /dev/ttyACM1
        -> timpa hasil deteksi otomatis secara manual

URUTAN YANG BENAR: nyalakan gateway di Raspberry Pi LEBIH DAHULU, baru unggah
node. JoinRequest yang dikirim saat gateway belum mendengar akan hilang tanpa
jejak, dan LMIC baru mencoba lagi setelah jeda yang makin panjang.
"""
import argparse
import glob
import subprocess
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent
ENV_URUTAN = ["node1", "node2"]


def deteksi_port_aktif():
    """Port serial USB yang sedang tersambung, terurut nama device.

    Pola yang sama dipakai tools/deteksi_port.py: Uno asli muncul sebagai
    /dev/ttyACM*, klon ber-bridge CH340/CP2102/FTDI sebagai /dev/ttyUSB*.
    """
    return sorted(glob.glob("/dev/ttyACM*") + glob.glob("/dev/ttyUSB*"))


def jalankan_pio(env, port, monitor):
    """Panggil `pio run` untuk satu environment dengan port hasil deteksi."""
    cmd = ["pio", "run", "-d", str(PROJECT_DIR), "-e", env, "--upload-port", port]
    if monitor:
        cmd += ["--monitor-port", port, "-t", "upload", "-t", "monitor"]
    else:
        cmd += ["-t", "upload"]
    print(f"\n=== {env.upper()} -> {port} ===")
    print("  $", " ".join(cmd))
    return subprocess.call(cmd) == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--node1", metavar="/dev/ttyXXX",
                    help="timpa port node1 (lewati deteksi otomatis)")
    ap.add_argument("--node2", metavar="/dev/ttyXXX",
                    help="timpa port node2 (lewati deteksi otomatis)")
    ap.add_argument("--only", choices=ENV_URUTAN,
                    help="upload satu environment saja (node1 atau node2)")
    ap.add_argument("--monitor", action="store_true",
                    help="buka pio device monitor per board sesudah upload")
    args = ap.parse_args()

    aktif = deteksi_port_aktif()
    manual = {"node1": args.node1, "node2": args.node2}

    port_env = {}
    sisa = list(aktif)
    for nama in ENV_URUTAN:
        if manual[nama]:
            port_env[nama] = manual[nama]
        elif sisa:
            port_env[nama] = sisa.pop(0)

    print(f"Port aktif terdeteksi: {', '.join(aktif) if aktif else '(tidak ada)'}")
    for nama in ENV_URUTAN:
        if nama in port_env:
            sumber = "manual" if manual[nama] else "otomatis"
            print(f"  -> {nama:<6} = {port_env[nama]}  ({sumber})")
        else:
            print(f"  -> {nama:<6} = TIDAK ADA PORT TERSISA "
                  f"— sambungkan board atau tentukan --{nama} /dev/ttyXXX")

    daftar = [args.only] if args.only else ENV_URUTAN
    hilang = [n for n in daftar if n not in port_env]
    if hilang:
        sys.exit(f"\nTidak bisa lanjut: port untuk {', '.join(hilang)} tidak ditemukan.\n"
                 f"Sambungkan board-nya atau tentukan lewat --{hilang[0]} /dev/ttyXXX")

    for nama in daftar:
        if not jalankan_pio(nama, port_env[nama], monitor=args.monitor):
            sys.exit(f"\nGagal pada environment '{nama}' — proses dihentikan.")

    print("\nSelesai. Pantau hasilnya di ChirpStack "
          "(Applications > praktikum-wsn > Devices > <node> > Events;\n"
          "kelompok selain 1: praktikum-wsn-k<n>), atau di Raspberry Pi:\n"
          "  python3 gateway/uplink_listen.py")


if __name__ == "__main__":
    main()
