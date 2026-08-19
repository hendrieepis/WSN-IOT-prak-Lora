#!/usr/bin/env python3
"""Monitor pengirim dan penerima LoRa sekaligus untuk Modul 01.

Menampilkan kedua aliran serial dalam SATU jendela dengan timestamp bersama,
lalu meringkasnya saat berhenti: berapa paket dikirim, berapa yang tiba, dan
sebaran RSSI serta SNR-nya. Membandingkan nomor urut di dua jendela terpisah
jauh lebih sulit, karena tiap jendela punya sumbu waktunya sendiri.

    python3 week01_lora_uart/monitor_serial.py
    python3 week01_lora_uart/monitor_serial.py --log sesi1.txt
    python3 week01_lora_uart/monitor_serial.py --port TX=/dev/ttyUSB0
    python3 week01_lora_uart/monitor_serial.py --durasi 60      # berhenti sendiri

Butuh pyserial (`pip install pyserial`; sudah ikut terpasang bersama PlatformIO).
Hentikan dengan Ctrl-C, atau pakai `--durasi` agar berhenti otomatis.

SOAL RESET OTOMATIS. Pada Arduino Uno, jalur DTR terhubung ke pin RESET lewat
kapasitor. Membuka port serial **selalu me-reset board**, dan hal itu justru
dimanfaatkan di sini: pesan `setup()` beserta baris `Init LoRa ... OK` ikut
terekam tanpa perlu menekan tombol reset. Konsekuensinya, penghitung paket
kedua board kembali ke nol setiap kali monitor dijalankan — jalankan monitor
lebih dahulu, baru mulai mengukur, dan jangan membukanya di tengah percobaan
panjang.

Berbeda dengan board ESP32 pada lab WSN-IOT-prak, di sini DTR tidak tersambung
ke tombol mana pun, sehingga tidak ada risiko tombol terbaca tertekan.
"""
import argparse
import re
import signal
import sys
import threading
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial belum terpasang. Jalankan: pip install pyserial")

# Port bawaan mengikuti platformio.ini: sender di ttyACM0, receiver di ttyACM1.
# Uno asli muncul sebagai /dev/ttyACM*, klon ber-bridge CH340 sebagai
# /dev/ttyUSB* — sesuaikan lewat --port bila board yang dipakai berbeda.
DEFAULT_PORTS = [
    ("TX", "/dev/ttyACM0", "\033[33m"),   # kuning — pengirim
    ("RX", "/dev/ttyACM1", "\033[36m"),   # cyan   — penerima
]

# Pola yang dipanen dari baris serial untuk menyusun ringkasan
RE_NOMOR = re.compile(r"#(\d+)")
RE_RSSI = re.compile(r"RSSI\s*:\s*(-?\d+)")
RE_SNR = re.compile(r"SNR\s*:\s*(-?[\d.]+)")
RESET = "\033[0m"
DIM = "\033[2m"

print_lock = threading.Lock()
counts = {}
# Bahan ringkasan akhir; diisi reader, dibaca sekali saat program berhenti
nomor_tx, nomor_rx, daftar_rssi, daftar_snr = [], [], [], []
stop = threading.Event()
t0 = time.time()


def show(name, color, text, use_color, logfile):
    """Cetak satu baris dengan timestamp bersama, aman dari tumpang tindih."""
    stamp = f"{time.time() - t0:8.3f}"
    plain = f"[{stamp}] {name:<7} | {text}"
    with print_lock:
        if use_color:
            print(f"{DIM}[{stamp}]{RESET} {color}{name:<7}{RESET} | {text}", flush=True)
        else:
            print(plain, flush=True)
        if logfile:
            logfile.write(plain + "\n")
            logfile.flush()


def open_port(port, baud):
    """Buka port serial menuju board Arduino.

    Jalur DTR/RTS sengaja TIDAK disentuh. Menyetelnya sebelum open() ditolak
    oleh CDC ATmega16U2 pada Uno asli dan berakhir sebagai
    `[Errno 110] Connection timed out`; pada klon ber-bridge CH340 hal itu
    kebetulan lolos, sehingga kesalahannya mudah tidak terlihat bila diuji
    hanya pada satu jenis board.

    Membuka port tetap me-reset board sekali - itu memang yang diinginkan,
    karena pesan setup() ikut terekam - dan reset itu berupa pulsa dari
    kapasitor, bukan penahanan, sehingga board langsung berjalan normal.
    """
    return serial.Serial(port, baud, timeout=0.2)


def panen(name, text):
    """Ambil nomor paket, RSSI, dan SNR dari sebuah baris serial.

    Nomor dipanen dari kedua sisi supaya paket yang hilang dapat dihitung
    sebagai selisih, bukan diperkirakan dari jumlah baris.
    """
    m = RE_NOMOR.search(text)
    if m:
        (nomor_tx if name == "TX" else nomor_rx).append(int(m.group(1)))
    if name != "TX":
        if (m := RE_RSSI.search(text)):
            daftar_rssi.append(int(m.group(1)))
        if (m := RE_SNR.search(text)):
            daftar_snr.append(float(m.group(1)))


def ringkasan():
    """Cetak hasil ukur tautan: loss, RSSI, dan SNR."""
    print("\n" + "-" * 60)
    print(f"Durasi: {time.time() - t0:.1f} s")
    for nama in counts:
        print(f"  {nama:<7} : {counts.get(nama, 0)} baris")

    if not nomor_tx and not nomor_rx:
        print("\nTidak ada paket bernomor yang terbaca — periksa tautan.")
        return

    kirim, terima = set(nomor_tx), set(nomor_rx)
    print(f"\n  Paket dikirim  : {len(kirim)}"
          + (f"  (nomor {min(kirim)}..{max(kirim)})" if kirim else ""))
    print(f"  Paket diterima : {len(terima)}"
          + (f"  (nomor {min(terima)}..{max(terima)})" if terima else ""))

    # Hanya nomor yang benar-benar terlihat dikirim yang dihitung sebagai hilang,
    # sehingga paket sebelum monitor dijalankan tidak ikut dianggap gagal.
    if kirim:
        hilang = sorted(kirim - terima)
        loss = len(hilang) / len(kirim) * 100
        print(f"  Paket hilang   : {len(hilang)} ({loss:.1f} %)")
        if hilang:
            print(f"  Nomor hilang   : {', '.join(str(n) for n in hilang[:20])}"
                  + (" ..." if len(hilang) > 20 else ""))

    if daftar_rssi:
        print(f"  RSSI  min/maks/rata-rata : {min(daftar_rssi)} / {max(daftar_rssi)} / "
              f"{sum(daftar_rssi) / len(daftar_rssi):.1f} dBm")
    if daftar_snr:
        print(f"  SNR   min/maks/rata-rata : {min(daftar_snr):.2f} / {max(daftar_snr):.2f} / "
              f"{sum(daftar_snr) / len(daftar_snr):.2f} dB")


def reader(name, port, color, baud, use_color, logfile):
    counts[name] = 0
    try:
        ser = open_port(port, baud)
    except Exception as e:
        show(name, color, f"!! tidak bisa dibuka: {e}", use_color, logfile)
        return

    show(name, color, f"-- tersambung ke {port} @ {baud} --", use_color, logfile)
    buf = b""
    while not stop.is_set():
        try:
            data = ser.read(256)
        except Exception as e:
            show(name, color, f"!! port terputus: {e}", use_color, logfile)
            break
        if not data:
            continue
        buf += data
        # Pesan dipecah per baris agar output tiga board tidak saling menyisip
        # di tengah kalimat.
        *lines, buf = buf.split(b"\n")
        for line in lines:
            text = line.decode("utf-8", "replace").rstrip("\r")
            if text.strip():
                counts[name] += 1
                panen(name, text)
                show(name, color, text, use_color, logfile)
    ser.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", action="append", metavar="NAMA=/dev/ttyXXX",
                    help="ganti port TX atau RX, mis. RX=/dev/ttyACM0; boleh diulang")
    # Modul 01-04 memakai 9600; Modul 05 memakai 115200.
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--durasi", type=float, metavar="DETIK",
                    help="berhenti otomatis setelah sekian detik (mis. --durasi 60)")
    ap.add_argument("--log", metavar="FILE", help="simpan juga ke file teks")
    ap.add_argument("--no-color", action="store_true")
    args = ap.parse_args()

    ports = {name: (port, color) for name, port, color in DEFAULT_PORTS}
    for item in args.port or []:
        if "=" not in item:
            sys.exit(f"format --port salah: {item!r} (harus NAMA=/dev/ttyXXX)")
        name, port = item.split("=", 1)
        _, color = ports.get(name.upper(), (None, "\033[35m"))
        ports[name.upper()] = (port, color)

    use_color = not args.no_color and sys.stdout.isatty()
    logfile = open(args.log, "w") if args.log else None

    # SIGTERM (mis. dijalankan lewat `timeout 30 ...`) diperlakukan sama dengan
    # Ctrl-C supaya ringkasan tetap tercetak.
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt))

    batas = f" · berhenti otomatis {args.durasi:.0f} s" if args.durasi else ""
    print(f"Monitor LoRa TX/RX @ {args.baud} baud — Ctrl-C untuk berhenti{batas}"
          f"{' · log: ' + args.log if args.log else ''}")
    print("-" * 60)

    threads = [threading.Thread(target=reader,
                                args=(name, port, color, args.baud, use_color, logfile),
                                daemon=True)
               for name, (port, color) in ports.items()]
    for t in threads:
        t.start()

    batasWaktu = t0 + args.durasi if args.durasi else None
    try:
        while any(t.is_alive() for t in threads):
            if batasWaktu and time.time() >= batasWaktu:
                break
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        for t in threads:
            t.join(timeout=1.0)
        ringkasan()
        if logfile:
            logfile.close()
            print(f"\nLog tersimpan di {args.log}")


if __name__ == "__main__":
    main()
