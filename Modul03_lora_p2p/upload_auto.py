#!/usr/bin/env python3
"""Upload otomatis ke Modul 03 (LoRa P2P) — port serial dideteksi sendiri.

Alternatif untuk menjalankan manual:
    pio run -d Modul03_lora_p2p -e devicea -t upload -t monitor
    pio run -d Modul03_lora_p2p -e deviceb -t upload -t monitor

Skrip ini memindai port /dev/ttyACM*/ttyUSB* yang sedang aktif, memetakannya
ke environment `devicea` (port pertama) dan `deviceb` (port kedua), lalu
menjalankan `pio run` dengan --upload-port sesuai hasil deteksi --
platformio.ini tidak perlu diedit tiap kali port berganti nama.

Bawaannya HANYA upload (tanpa membuka pio device monitor). Sesudah kedua
board selesai di-upload, skrip bertanya apakah mau langsung menjalankan
monitor_serial.py -- bila ya, dijalankan dengan --port A=... --port B=...
persis memakai port devicea/deviceb yang barusan dipakai upload (bukan
deteksi ulang), supaya tidak mungkin salah pasang.

    python3 Modul03_lora_p2p/upload_auto.py
        -> upload kedua board, port otomatis, lalu tanya mau monitor atau tidak

    python3 Modul03_lora_p2p/upload_auto.py --monitor
        -> upload lalu buka pio device monitor untuk devicea, lanjut deviceb
           (Ctrl-C untuk keluar dari tiap monitor sebelum lanjut ke board
           berikutnya) -- pemantauan satu board per satu waktu, bukan
           sekaligus seperti monitor_serial.py

    python3 Modul03_lora_p2p/upload_auto.py --only devicea
        -> upload satu environment saja

    python3 Modul03_lora_p2p/upload_auto.py --devicea /dev/ttyACM0 --deviceb /dev/ttyACM1
        -> timpa hasil deteksi otomatis secara manual
"""
import argparse
import glob
import subprocess
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent
ENV_URUTAN = ["devicea", "deviceb"]
# Nama environment PlatformIO -> nama peran yang dipakai monitor_serial.py
ENV_KE_PERAN = {"devicea": "A", "deviceb": "B"}


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


def tanya_lalu_monitor(port_env):
    """Tanya apakah mau langsung memantau, lalu jalankan monitor_serial.py
    dengan port devicea/deviceb PERSIS seperti yang baru dipakai upload --
    bukan hasil deteksi ulang, supaya tidak mungkin meleset dari yang barusan
    di-flash.
    """
    if not sys.stdin.isatty():
        return  # dipanggil non-interaktif (mis. dari skrip lain) -- jangan menunggu input

    try:
        jawab = input("\nJalankan monitor_serial.py sekarang? [Y/n] ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        print()
        return
    if jawab not in ("", "y", "ya"):
        return

    cmd = [sys.executable, str(PROJECT_DIR / "monitor_serial.py")]
    for env, peran in ENV_KE_PERAN.items():
        if env in port_env:
            cmd += ["--port", f"{peran}={port_env[env]}"]

    print("  $", " ".join(cmd))
    try:
        subprocess.call(cmd)
    except KeyboardInterrupt:
        # Ctrl-C dikirim ke seluruh process group, jadi proses induk ini pun
        # ikut menerima SIGINT selagi menunggu (os.waitpid) monitor_serial.py
        # yang sudah membersihkan dirinya sendiri -- cukup diam, jangan
        # biarkan traceback ikut tercetak di atas ringkasan yang sudah rapi.
        print()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--devicea", metavar="/dev/ttyXXX",
                    help="timpa port devicea (lewati deteksi otomatis)")
    ap.add_argument("--deviceb", metavar="/dev/ttyXXX",
                    help="timpa port deviceb (lewati deteksi otomatis)")
    ap.add_argument("--only", choices=ENV_URUTAN,
                    help="upload satu environment saja (devicea atau deviceb)")
    ap.add_argument("--monitor", action="store_true",
                    help="buka pio device monitor per board sesudah upload "
                         "(bawaan: upload saja -- pakai monitor_serial.py untuk memantau keduanya sekaligus)")
    args = ap.parse_args()

    aktif = deteksi_port_aktif()
    manual = {"devicea": args.devicea, "deviceb": args.deviceb}

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
