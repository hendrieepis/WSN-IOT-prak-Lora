#!/usr/bin/env python3
"""Kenali jenis board pada tiap port serial, untuk lab dengan board bercampur.

Arduino Uno asli dan klon memakai mikrokontroler yang sama (ATmega328P) dan
firmware yang sama persis; yang berbeda hanya chip jembatan USB-ke-serial di
atas board. Perbedaan itu tidak menyentuh program sama sekali, tetapi mengubah
**nama port** di sistem operasi - dan itulah satu-satunya hal yang perlu
disesuaikan pada platformio.ini.

    python3 tools/deteksi_port.py
    python3 tools/deteksi_port.py --ini      # cetak baris siap tempel

Tanpa argumen, skrip mencetak daftar port beserta jenis jembatannya. Dengan
--ini, keluarannya berupa potongan platformio.ini yang tinggal disalin.
"""
import argparse
import glob
import os

# VID:PID jembatan USB yang lazim ditemui pada board Uno dan turunannya
JEMBATAN = {
    "2341:0043": ("Uno asli", "ATmega16U2 (Arduino LLC)"),
    "2341:0001": ("Uno asli", "ATmega8U2 (Arduino LLC)"),
    "2a03:0043": ("Uno asli", "ATmega16U2 (Arduino SRL)"),
    "1a86:7523": ("klon", "CH340/CH341"),
    "1a86:55d3": ("klon", "CH343"),
    "0403:6001": ("klon", "FTDI FT232"),
    "10c4:ea60": ("klon", "Silicon Labs CP2102"),
}


def baca(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def daftar_port():
    """Kumpulkan port serial USB beserta VID:PID-nya dari sysfs."""
    hasil = []
    for dev in sorted(glob.glob("/dev/ttyACM*") + glob.glob("/dev/ttyUSB*")):
        nama = os.path.basename(dev)
        # Jalur device di sysfs berbeda kedalamannya antara CDC-ACM dan
        # konverter USB-serial, jadi ditelusuri ke atas sampai VID ditemukan.
        d = os.path.realpath(f"/sys/class/tty/{nama}/device")
        vid = pid = ""
        for _ in range(4):
            d = os.path.dirname(d)
            vid, pid = baca(f"{d}/idVendor"), baca(f"{d}/idProduct")
            if vid and pid:
                break
        kunci = f"{vid}:{pid}".lower()
        jenis, chip = JEMBATAN.get(kunci, ("tidak dikenal", "-"))
        hasil.append((dev, kunci if vid else "?", jenis, chip))
    return hasil


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ini", action="store_true",
                    help="cetak potongan platformio.ini siap tempel")
    args = ap.parse_args()

    port = daftar_port()
    if not port:
        print("Tidak ada port serial USB yang terdeteksi.")
        print("Periksa kabel data (bukan charge-only) dan hak akses grup dialout.")
        return

    if args.ini:
        print("; Tempel ke environment yang sesuai pada platformio.ini")
        for i, (dev, _, jenis, _) in enumerate(port):
            print(f"; board {i + 1} - {jenis}")
            print(f"upload_port  = {dev}")
            print(f"monitor_port = {dev}")
        return

    print(f"{'Port':<16} {'VID:PID':<12} {'Jenis':<14} Jembatan USB")
    print("-" * 62)
    for dev, vp, jenis, chip in port:
        print(f"{dev:<16} {vp:<12} {jenis:<14} {chip}")
    print()
    print("Firmware kedua jenis board IDENTIK - keduanya ATmega328P dengan")
    print("protokol unggah 'arduino'. Yang berbeda hanya nama port di atas,")
    print("jadi cukup sesuaikan upload_port/monitor_port pada platformio.ini.")


if __name__ == "__main__":
    main()
