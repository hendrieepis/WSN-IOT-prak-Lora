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

    python3 Modul05_lora_master_slave/monitor_serial.py
    python3 Modul05_lora_master_slave/monitor_serial.py --log sesi1.txt
    python3 Modul05_lora_master_slave/monitor_serial.py --port S2=/dev/ttyUSB0
    python3 Modul05_lora_master_slave/monitor_serial.py --durasi 60      # berhenti sendiri

Butuh pyserial (`pip install pyserial`; sudah ikut terpasang bersama PlatformIO).
Hentikan dengan Ctrl-C, atau pakai `--durasi` agar berhenti otomatis.

PORT OTOMATIS. Port MASTER/S1/S2 tidak lagi ditulis tetap di kode: setiap
kali dijalankan, skrip memindai /dev/ttyACM* dan /dev/ttyUSB* yang sedang
aktif dan memakai yang benar-benar tersambung, urut sesuai nama device. Ini
penting karena nama port bisa berubah tiap kali board dicabut-pasang atau
board asli/klon bercampur (lihat tools/deteksi_port.py). Bila urutan
otomatisnya keliru, timpa lewat --port, mis. --port MASTER=/dev/ttyACM1.

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
import glob
import re
import signal
import sys
import threading
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial belum terpasang. Jalankan: pip install pyserial")

# Nama peran bawaan (urutan) dan warna yang dipasangkan ke port yang
# terdeteksi aktif, bukan ke nama /dev tertentu — lihat deteksi_port_aktif().
NAMA_PERAN_BAWAAN = ["MASTER", "S1", "S2"]
PALET_WARNA = ["\033[32m", "\033[36m", "\033[35m", "\033[33m", "\033[34m"]


def deteksi_port_aktif():
    """Kumpulkan port serial USB yang sedang tersambung, terurut nama device.

    Uno asli muncul sebagai /dev/ttyACM*, klon ber-bridge CH340/CP2102/FTDI
    sebagai /dev/ttyUSB* — pola yang sama dipakai tools/deteksi_port.py.
    Dipanggil ulang tiap program start supaya daftarnya selalu mengikuti apa
    yang benar-benar tersambung saat itu, bukan port tetap di kode.
    """
    return sorted(glob.glob("/dev/ttyACM*") + glob.glob("/dev/ttyUSB*"))


def bangun_port_bawaan():
    """Pasangkan tiap port aktif ke nama peran (MASTER, S1, S2, lalu P4, ...)."""
    hasil = []
    for i, dev in enumerate(deteksi_port_aktif()):
        nama = NAMA_PERAN_BAWAAN[i] if i < len(NAMA_PERAN_BAWAAN) else f"P{i + 1}"
        warna = PALET_WARNA[i % len(PALET_WARNA)]
        hasil.append((nama, dev, warna))
    return hasil

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
                    help="ganti port MASTER/S1/S2, mis. S2=/dev/ttyACM0; boleh diulang")
    # Modul ini memakai 115200, sesuai Serial.begin() di src/ dan monitor_speed
    # di platformio.ini. Modul 01-04 memakai 9600.
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--durasi", type=float, metavar="DETIK",
                    help="berhenti otomatis setelah sekian detik (mis. --durasi 60)")
    ap.add_argument("--log", metavar="FILE", help="simpan juga ke file teks")
    ap.add_argument("--no-color", action="store_true")
    args = ap.parse_args()

    port_bawaan = bangun_port_bawaan()
    if not port_bawaan and not args.port:
        sys.exit("Tidak ada port serial USB yang terdeteksi (/dev/ttyACM*, /dev/ttyUSB*).\n"
                  "Periksa kabel data (bukan charge-only) dan hak akses grup dialout,\n"
                  "atau jalankan tools/deteksi_port.py untuk diagnosis lebih lanjut,\n"
                  "atau tentukan port manual lewat --port MASTER=/dev/ttyACM0 --port S1=/dev/ttyACM1 --port S2=/dev/ttyACM2")

    dipakai = port_bawaan[:len(NAMA_PERAN_BAWAAN)]
    sisa = port_bawaan[len(NAMA_PERAN_BAWAAN):]
    print(f"Port aktif terdeteksi: {', '.join(p for _, p, _ in port_bawaan)}"
          if port_bawaan else "Tidak ada port aktif terdeteksi otomatis — memakai --port saja.")
    for nama, port, _ in dipakai:
        print(f"  -> {nama} = {port}")
    if sisa:
        print(f"  (tidak dipakai: {', '.join(p for _, p, _ in sisa)}"
              f" — pakai --port NAMA=/dev/... untuk memakainya)")

    ports = {name: (port, color) for name, port, color in dipakai}
    for item in args.port or []:
        if "=" not in item:
            sys.exit(f"format --port salah: {item!r} (harus NAMA=/dev/ttyXXX)")
        name, port = item.split("=", 1)
        _, color = ports.get(name.upper(), (None, "\033[35m"))
        ports[name.upper()] = (port, color)

    if not ports:
        sys.exit("Tidak ada port untuk dipantau — tentukan lewat --port NAMA=/dev/ttyXXX")

    use_color = not args.no_color and sys.stdout.isatty()
    logfile = open(args.log, "w") if args.log else None

    # SIGTERM (mis. dijalankan lewat `timeout 30 ...`) cukup menyalakan flag
    # `stop` yang sama dipakai reader thread, BUKAN melempar exception --
    # melempar exception dari signal handler bisa mendarat di tengah blok
    # `finally` (mis. saat t.join() atau ringkasan() berjalan) dan menyebabkan
    # crash tak tertangkap alih-alih mencetak ringkasan dengan rapi.
    signal.signal(signal.SIGTERM, lambda *_: stop.set())

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
        while any(t.is_alive() for t in threads) and not stop.is_set():
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
