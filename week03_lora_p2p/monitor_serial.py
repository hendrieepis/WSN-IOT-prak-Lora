#!/usr/bin/env python3
"""Monitor kedua peer LoRa sekaligus untuk Modul 03.

Menampilkan kedua aliran serial dalam SATU jendela dengan timestamp bersama,
lalu meringkasnya saat berhenti: berapa siklus Ping-Pong yang selesai, berapa
kali initiator terpaksa mengulang, dan berapa waktu pulang-perginya.

Payload modul ini tidak bernomor (`DeviceA:Ping`, `DeviceB:Pong`), sehingga
paket hilang tidak dapat dihitung dari lompatan angka seperti pada Modul 01.
Yang diukur di sini adalah **waktu pulang-pergi** — selang dari sebuah paket
dikirim sampai balasannya tiba — dan jumlah baris `[RETRY]`, yaitu berapa kali
percakapan sempat macet lalu dipulihkan sendiri oleh initiator.

    python3 week03_lora_p2p/monitor_serial.py
    python3 week03_lora_p2p/monitor_serial.py --log sesi1.txt
    python3 week03_lora_p2p/monitor_serial.py --port RX=/dev/ttyACM0
    python3 week03_lora_p2p/monitor_serial.py --durasi 60      # berhenti sendiri

Butuh pyserial (`pip install pyserial`; sudah ikut terpasang bersama PlatformIO).
Hentikan dengan Ctrl-C, atau pakai `--durasi` agar berhenti otomatis.

SOAL RESET OTOMATIS. Pada Arduino Uno, jalur DTR terhubung ke pin RESET lewat
kapasitor. Membuka port serial **selalu me-reset board**, dan hal itu justru
dimanfaatkan di sini: pesan `setup()` beserta baris `Init LoRa ... OK` ikut
terekam tanpa perlu menekan tombol reset. Konsekuensinya, penghitung paket
kedua board kembali ke nol setiap kali monitor dijalankan — jalankan monitor
lebih dahulu, baru mulai mengukur, dan jangan membukanya di tengah percobaan
panjang.

Pada Uno, DTR hanya menyentuh jalur RESET dan tidak tersambung ke GPIO mana pun,
sehingga membuka port tidak pernah membuat sebuah pin terbaca seolah ditekan.
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

# Pengirim memakai board klon ber-bridge CH340 (/dev/ttyUSB0), penerima memakai
# Uno asli (/dev/ttyACM1). Sesuaikan lewat --port bila urutannya berbeda.
DEFAULT_PORTS = [
    ("A", "/dev/ttyUSB0", "\033[33m"),   # kuning — Device A, initiator
    ("B", "/dev/ttyACM1", "\033[36m"),   # cyan   — Device B, responder
]

# Pola yang dipanen dari baris serial untuk menyusun ringkasan
RE_TX = re.compile(r"^\[TX\]\s*(\S+)")
RE_RX = re.compile(r"^\[RX\] Pesan\s*:\s*(\S+)")
RE_RETRY = re.compile(r"^\[RETRY\]")
RE_RSSI = re.compile(r"RSSI\s*:\s*(-?\d+)")
RE_SNR = re.compile(r"SNR\s*:\s*(-?[\d.]+)")
RESET = "\033[0m"
DIM = "\033[2m"

print_lock = threading.Lock()
counts = {}
# Bahan ringkasan akhir; diisi reader, dibaca sekali saat program berhenti
kirim = {}        # nama -> jumlah paket dikirim
terima = {}       # nama -> jumlah paket diterima
retry = {}        # nama -> jumlah pengiriman ulang
rtt = []          # waktu pulang-pergi Device A, detik
rssi_per = {}     # nama -> daftar RSSI yang dilihat node itu
snr_per = {}
tx_terakhir = {}  # nama -> waktu [TX] terakhir, untuk menghitung rtt
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
    """Ambil kejadian TX, RX, RETRY, RSSI, dan SNR dari sebuah baris serial.

    Waktu pulang-pergi dihitung sebagai selang antara [TX] sebuah node dengan
    [RX] berikutnya pada node yang sama - itulah satu putaran penuh Ping-Pong.
    """
    sekarang = time.time()
    if RE_TX.match(text):
        kirim[name] = kirim.get(name, 0) + 1
        tx_terakhir[name] = sekarang
    elif RE_RX.match(text):
        terima[name] = terima.get(name, 0) + 1
        if name in tx_terakhir:
            rtt.append(sekarang - tx_terakhir.pop(name))
    elif RE_RETRY.match(text):
        retry[name] = retry.get(name, 0) + 1
        # Retry berarti balasan sebelumnya tidak pernah datang; jangan dihitung
        # sebagai waktu pulang-pergi.
        tx_terakhir.pop(name, None)

    if (m := RE_RSSI.search(text)):
        rssi_per.setdefault(name, []).append(int(m.group(1)))
    if (m := RE_SNR.search(text)):
        snr_per.setdefault(name, []).append(float(m.group(1)))


def ringkasan():
    """Cetak hasil ukur tautan: loss, RSSI, dan SNR."""
    print("\n" + "-" * 60)
    print(f"Durasi: {time.time() - t0:.1f} s")
    for nama in counts:
        print(f"  {nama:<7} : {counts.get(nama, 0)} baris")

    if not kirim and not terima:
        print("\nTidak ada lalu lintas Ping-Pong yang terbaca - periksa tautan.")
        return

    print()
    for nama in counts:
        print(f"  {nama:<7} kirim {kirim.get(nama, 0):<4} terima {terima.get(nama, 0):<4}"
              f" retry {retry.get(nama, 0)}")
        r, sn = rssi_per.get(nama), snr_per.get(nama)
        if r:
            print(f"          RSSI min/maks/rata-rata : {min(r)} / {max(r)} / "
                  f"{sum(r) / len(r):.1f} dBm")
        if sn:
            print(f"          SNR  min/maks/rata-rata : {min(sn):.2f} / {max(sn):.2f} / "
                  f"{sum(sn) / len(sn):.2f} dB")

    if rtt:
        print(f"\n  Siklus Ping-Pong selesai : {len(rtt)}")
        print(f"  Waktu pulang-pergi min/maks/rata-rata : "
              f"{min(rtt) * 1000:.0f} / {max(rtt) * 1000:.0f} / "
              f"{sum(rtt) / len(rtt) * 1000:.0f} ms")
    else:
        print("\n  Tidak ada siklus penuh yang terukur.")


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
