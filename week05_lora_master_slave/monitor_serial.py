#!/usr/bin/env python3
"""Monitor master dan kedua slave sekaligus untuk Modul 05.

Menampilkan kedua aliran serial dalam SATU jendela dengan timestamp bersama,
lalu meringkasnya saat berhenti: berapa siklus polling selesai, berapa lama
tiap siklus, dan berapa keberhasilan tiap slave secara terpisah.

Yang paling sulit dinilai dari tiga jendela terpisah adalah pertanyaan inti
modul ini: benarkah slave hanya menjawab ketika namanya disebut. Dengan satu
sumbu waktu, baris [IGNORE] pada satu slave terlihat berdampingan dengan
[TX] POLL milik slave lain, sehingga penyaringan itu dapat dibuktikan langsung
alih-alih disimpulkan.

Modul ini memakai 115200 baud, berbeda dari Modul 01-04 yang memakai 9600.

    python3 week05_lora_master_slave/monitor_serial.py
    python3 week05_lora_master_slave/monitor_serial.py --log sesi1.txt
    python3 week05_lora_master_slave/monitor_serial.py --port S2=/dev/ttyUSB0
    python3 week05_lora_master_slave/monitor_serial.py --durasi 60      # berhenti sendiri

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

# Port bawaan mengikuti platformio.ini. Uno asli muncul sebagai /dev/ttyACM*,
# klon ber-bridge CH340 sebagai /dev/ttyUSB* — sesuaikan lewat --port.
DEFAULT_PORTS = [
    ("MASTER", "/dev/ttyACM0", "\033[32m"),  # hijau
    ("S1", "/dev/ttyACM1", "\033[36m"),      # cyan
    ("S2", "/dev/ttyACM2", "\033[35m"),      # magenta
]

# Pola yang dipanen dari baris serial untuk menyusun ringkasan
RE_CYCLE = re.compile(r"=== CYCLE (\d+)")
RE_DURASI = re.compile(r"Durasi siklus:\s*(\d+)")
RE_STAT = re.compile(r"S(\d+): OK=(\d+) \| FAIL=(\d+) \| Data:\s*(\d+)")
RE_POLL = re.compile(r"\[TX\] POLL:(\d+)")
RE_JAWAB = re.compile(r"\[RX\] S(\d+):DATA:(\d+)")
RE_GAGAL = re.compile(r"\[FAIL\] Slave (\d+)")
RE_IGNORE = re.compile(r"\[IGNORE\]")
RE_RSSI = re.compile(r"RSSI\s*:\s*(-?\d+)")
RE_SNR = re.compile(r"SNR\s*:\s*(-?[\d.]+)")
RESET = "\033[0m"
DIM = "\033[2m"

print_lock = threading.Lock()
counts = {}
# Bahan ringkasan akhir; diisi reader, dibaca sekali saat program berhenti
siklus = []        # nomor siklus yang terlihat di master
durasi = []        # lama tiap siklus, ms
stat = {}          # "1"/"2" -> (ok, fail, data) terakhir yang dilaporkan master
poll = {}          # nomor slave -> berapa kali dipanggil
jawab = {}         # nomor slave -> berapa kali menjawab
gagal = {}         # nomor slave -> berapa kali tidak merespons
abai = {}          # nama node -> berapa kali mencetak [IGNORE]
rssi_per, snr_per = {}, {}
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
    """Ambil kejadian siklus, polling, jawaban, dan penolakan dari satu baris.

    Penghitung diambil dari sisi master untuk keberhasilan, dan dari sisi slave
    untuk [IGNORE] - karena hanya slave yang tahu ia menerima panggilan milik
    node lain lalu membuangnya.
    """
    if name == "MASTER":
        if (m := RE_CYCLE.search(text)):
            siklus.append(int(m.group(1)))
        elif (m := RE_DURASI.search(text)):
            durasi.append(int(m.group(1)))
        elif (m := RE_STAT.search(text)):
            stat[m.group(1)] = tuple(int(x) for x in m.groups()[1:])
        elif (m := RE_POLL.search(text)):
            poll[m.group(1)] = poll.get(m.group(1), 0) + 1
        elif (m := RE_JAWAB.search(text)):
            jawab[m.group(1)] = jawab.get(m.group(1), 0) + 1
        elif (m := RE_GAGAL.search(text)):
            gagal[m.group(1)] = gagal.get(m.group(1), 0) + 1
    elif RE_IGNORE.search(text):
        abai[name] = abai.get(name, 0) + 1

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

    if not siklus:
        print("\nTidak ada siklus polling yang terbaca - periksa master.")
        return

    print(f"\n  Siklus polling : {len(siklus)}  (nomor {min(siklus)}..{max(siklus)})")
    if durasi:
        print(f"  Lama siklus min/maks/rata-rata : {min(durasi)} / {max(durasi)} / "
              f"{sum(durasi) / len(durasi):.0f} ms")

    for sid in sorted(set(list(poll) + list(jawab) + list(gagal))):
        p, j, g = poll.get(sid, 0), jawab.get(sid, 0), gagal.get(sid, 0)
        persen = j / p * 100 if p else 0
        print(f"\n  Slave {sid} : dipanggil {p}  menjawab {j}  gagal {g}"
              f"  -> keberhasilan {persen:.1f} %")
        if sid in stat:
            ok, fail, data = stat[sid]
            print(f"            penghitung master: OK={ok} FAIL={fail} Data={data}")

    for nama in counts:
        if nama in abai:
            print(f"\n  {nama} membuang {abai[nama]} panggilan milik node lain ([IGNORE])")
        r = rssi_per.get(nama)
        if r:
            print(f"  {nama} RSSI min/maks/rata-rata : {min(r)} / {max(r)} / "
                  f"{sum(r) / len(r):.1f} dBm")


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
