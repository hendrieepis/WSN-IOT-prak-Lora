#!/usr/bin/env python3
"""Upload otomatis ke Modul 10 (Slotted ALOHA) — port serial dideteksi sendiri.

Alternatif untuk menjalankan manual:
    pio run -d week10_lora_slotted_aloha -e gateway -t upload -t monitor
    pio run -d week10_lora_slotted_aloha -e node1   -t upload -t monitor
    pio run -d week10_lora_slotted_aloha -e node2   -t upload -t monitor

Skrip ini memindai port /dev/ttyACM*/ttyUSB* yang sedang aktif, memetakannya
ke environment `gateway` (port pertama), `node1` (port kedua), dan `node2`
(port ketiga), lalu menjalankan `pio run` dengan --upload-port sesuai hasil
deteksi -- platformio.ini tidak perlu diedit tiap kali port berganti nama.

Bawaannya HANYA upload (tanpa membuka pio device monitor). Sesudah ketiga
board selesai di-upload, skrip bertanya apakah mau langsung menjalankan
lora_monitor.py -- bila ya, dijalankan dengan --gateway ... --n1 ... --n2 ...
persis memakai port yang barusan dipakai upload (bukan deteksi ulang),
supaya tidak mungkin salah pasang.

    python3 week10_lora_slotted_aloha/upload_auto.py
        -> upload ketiga board, port otomatis, lalu tanya mau monitor atau tidak

    python3 week10_lora_slotted_aloha/upload_auto.py --monitor
        -> upload lalu buka pio device monitor satu per satu (Ctrl-C untuk
           lanjut ke board berikutnya) -- bukan sekaligus seperti lora_monitor.py

    python3 week10_lora_slotted_aloha/upload_auto.py --only gateway
        -> upload satu environment saja

    python3 week10_lora_slotted_aloha/upload_auto.py --gateway /dev/ttyACM0 --node1 /dev/ttyACM1 --node2 /dev/ttyACM2
        -> timpa hasil deteksi otomatis secara manual
"""
import argparse
import glob
import subprocess
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent
ENV_URUTAN = ["gateway", "node1", "node2"]
# Nama environment PlatformIO -> nama opsi CLI yang dipakai lora_monitor.py
ENV_KE_OPSI = {"gateway": "--gateway", "node1": "--n1", "node2": "--n2"}


def deteksi_port_aktif():
    """Port serial USB yang sedang tersambung, terurut nama device.

    Pola yang sama dipakai tools/deteksi_port.py dan lora_monitor.py: Uno
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
    """Tanya apakah mau langsung memantau, lalu jalankan lora_monitor.py
    dengan port gateway/node1/node2 PERSIS seperti yang baru dipakai upload
    -- bukan hasil deteksi ulang, supaya tidak mungkin meleset dari yang
    barusan di-flash.
    """
    if not sys.stdin.isatty():
        return  # dipanggil non-interaktif (mis. dari skrip lain) -- jangan menunggu input

    try:
        jawab = input("\nJalankan lora_monitor.py sekarang? [Y/n] ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        print()
        return
    if jawab not in ("", "y", "ya"):
        return

    cmd = [sys.executable, str(PROJECT_DIR / "lora_monitor.py")]
    for env, opsi in ENV_KE_OPSI.items():
        if env in port_env:
            cmd += [opsi, port_env[env]]

    print("  $", " ".join(cmd))
    try:
        subprocess.call(cmd)
    except KeyboardInterrupt:
        # Ctrl-C dikirim ke seluruh process group, jadi proses induk ini pun
        # ikut menerima SIGINT selagi menunggu (os.waitpid) lora_monitor.py
        # yang sudah membersihkan dirinya sendiri -- cukup diam, jangan
        # biarkan traceback ikut tercetak di atas ringkasan yang sudah rapi.
        print()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gateway", metavar="/dev/ttyXXX",
                    help="timpa port gateway (lewati deteksi otomatis)")
    ap.add_argument("--node1", metavar="/dev/ttyXXX",
                    help="timpa port node1 (lewati deteksi otomatis)")
    ap.add_argument("--node2", metavar="/dev/ttyXXX",
                    help="timpa port node2 (lewati deteksi otomatis)")
    ap.add_argument("--only", choices=ENV_URUTAN,
                    help="upload satu environment saja (gateway, node1, atau node2)")
    ap.add_argument("--monitor", action="store_true",
                    help="buka pio device monitor per board sesudah upload "
                         "(bawaan: upload saja -- pakai lora_monitor.py untuk memantau ketiganya sekaligus)")
    args = ap.parse_args()

    aktif = deteksi_port_aktif()
    manual = {"gateway": args.gateway, "node1": args.node1, "node2": args.node2}

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
