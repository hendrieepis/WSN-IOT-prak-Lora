#!/usr/bin/env python3
"""Upload otomatis ke Modul 05 (LoRa Master-Slave) — port serial dideteksi sendiri.

Alternatif untuk menjalankan manual:
    pio run -d Modul05_lora_master_slave -e master  -t upload -t monitor
    pio run -d Modul05_lora_master_slave -e slave1  -t upload -t monitor
    pio run -d Modul05_lora_master_slave -e slave2  -t upload -t monitor

Skrip ini memindai port /dev/ttyACM*/ttyUSB* yang sedang aktif, memetakannya
ke environment `master` (port pertama), `slave1` (port kedua), dan `slave2`
(port ketiga), lalu menjalankan `pio run` dengan --upload-port sesuai hasil
deteksi -- platformio.ini tidak perlu diedit tiap kali port berganti nama.

Bawaannya HANYA upload (tanpa membuka pio device monitor). Sesudah ketiga
board selesai di-upload, skrip bertanya mau menjalankan lora_monitor.py
(dashboard 3-panel), monitor_serial.py (log gabungan satu jendela), atau
keluar saja -- yang mana pun dipilih, portnya PERSIS port master/slave1/
slave2 yang barusan dipakai upload (bukan deteksi ulang), supaya tidak
mungkin salah pasang.

    python3 Modul05_lora_master_slave/upload_auto.py
        -> upload ketiga board, port otomatis, lalu tanya mau monitor atau tidak

    python3 Modul05_lora_master_slave/upload_auto.py --monitor
        -> upload lalu buka pio device monitor satu per satu (Ctrl-C untuk
           lanjut ke board berikutnya) -- bukan sekaligus seperti monitor_serial.py

    python3 Modul05_lora_master_slave/upload_auto.py --only master
        -> upload satu environment saja

    python3 Modul05_lora_master_slave/upload_auto.py --master /dev/ttyACM0 --slave1 /dev/ttyACM1 --slave2 /dev/ttyACM2
        -> timpa hasil deteksi otomatis secara manual
"""
import argparse
import glob
import subprocess
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent
ENV_URUTAN = ["master", "slave1", "slave2"]
# Nama environment PlatformIO -> nama peran yang dipakai monitor_serial.py
ENV_KE_PERAN = {"master": "MASTER", "slave1": "S1", "slave2": "S2"}
# Nama environment PlatformIO -> nama opsi CLI yang dipakai lora_monitor.py
ENV_KE_OPSI = {"master": "--master", "slave1": "--s1", "slave2": "--s2"}


def deteksi_port_aktif():
    """Port serial USB yang sedang tersambung, terurut nama device.

    Pola yang sama dipakai tools/deteksi_port.py dan monitor_serial.py: Uno
    asli muncul sebagai /dev/ttyACM*, klon ber-bridge CH340/CP2102/FTDI
    sebagai /dev/ttyUSB*.
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


def jalankan_monitor(cmd):
    """Jalankan skrip monitor terpilih, menyerap Ctrl-C dengan rapi.

    Ctrl-C dikirim ke seluruh process group, jadi proses induk ini pun ikut
    menerima SIGINT selagi menunggu (os.waitpid) monitor yang sudah
    membersihkan dirinya sendiri -- cukup diam, jangan biarkan traceback
    ikut tercetak di atas ringkasan yang sudah rapi.
    """
    print("  $", " ".join(cmd))
    try:
        subprocess.call(cmd)
    except KeyboardInterrupt:
        print()


def tanya_lalu_monitor(port_env):
    """Tanya mau pakai monitor yang mana, lalu jalankan dengan port
    master/slave1/slave2 PERSIS seperti yang baru dipakai upload -- bukan
    hasil deteksi ulang, supaya tidak mungkin meleset dari yang barusan
    di-flash.
    """
    if not sys.stdin.isatty():
        return  # dipanggil non-interaktif (mis. dari skrip lain) -- jangan menunggu input

    print("\nJalankan monitor sekarang?")
    print("  [1] lora_monitor.py    (dashboard 3-panel real-time + CSV)")
    print("  [2] monitor_serial.py  (log gabungan satu jendela)")
    print("  [3] Tidak, keluar saja")
    try:
        jawab = input("Pilihan [1/2/3] (bawaan 3): ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return

    if jawab == "1":
        cmd = [sys.executable, str(PROJECT_DIR / "lora_monitor.py")]
        for env, opsi in ENV_KE_OPSI.items():
            if env in port_env:
                cmd += [opsi, port_env[env]]
        jalankan_monitor(cmd)
    elif jawab == "2":
        cmd = [sys.executable, str(PROJECT_DIR / "monitor_serial.py")]
        for env, peran in ENV_KE_PERAN.items():
            if env in port_env:
                cmd += ["--port", f"{peran}={port_env[env]}"]
        jalankan_monitor(cmd)
    # "3", kosong, atau apa pun selain 1/2 -> keluar saja tanpa menjalankan apa-apa


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--master", metavar="/dev/ttyXXX",
                    help="timpa port master (lewati deteksi otomatis)")
    ap.add_argument("--slave1", metavar="/dev/ttyXXX",
                    help="timpa port slave1 (lewati deteksi otomatis)")
    ap.add_argument("--slave2", metavar="/dev/ttyXXX",
                    help="timpa port slave2 (lewati deteksi otomatis)")
    ap.add_argument("--only", choices=ENV_URUTAN,
                    help="upload satu environment saja (master, slave1, atau slave2)")
    ap.add_argument("--monitor", action="store_true",
                    help="buka pio device monitor per board sesudah upload "
                         "(bawaan: upload saja -- pakai monitor_serial.py untuk memantau ketiganya sekaligus)")
    args = ap.parse_args()

    aktif = deteksi_port_aktif()
    manual = {"master": args.master, "slave1": args.slave1, "slave2": args.slave2}

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
            print(f"  -> {nama:<9} = {port_env[nama]}  ({sumber})")
        else:
            print(f"  -> {nama:<9} = TIDAK ADA PORT TERSISA "
                  f"— sambungkan board atau tentukan --{nama} /dev/ttyXXX")

    daftar = [args.only] if args.only else ENV_URUTAN
    hilang = [n for n in daftar if n not in port_env]
    if hilang:
        sys.exit(f"\nTidak bisa lanjut: port untuk {', '.join(hilang)} tidak ditemukan.\n"
                  f"Sambungkan board-nya atau tentukan lewat --{hilang[0]} /dev/ttyXXX")

    for nama in daftar:
        if not jalankan_pio(nama, port_env[nama], monitor=args.monitor):
            sys.exit(f"\nGagal pada environment '{nama}' — proses dihentikan.")

    print("\nSelesai.")
    tanya_lalu_monitor(port_env)


if __name__ == "__main__":
    main()
