#!/usr/bin/env python3
"""Monitor pengirim dan penerima LoRa sekaligus untuk Modul 04.

Menampilkan kedua aliran serial dalam SATU jendela dengan timestamp bersama,
lalu meringkasnya saat berhenti: berapa DATA dikirim, berapa yang berbalas ACK,
berapa yang kehabisan waktu, dan berapa lama satu putaran DATA-ACK memakan
waktu.

Ringkasan ini menghitung ulang keberhasilan dari **kedua sisi**: berapa DATA
yang benar-benar tiba di penerima, dan berapa ACK yang benar-benar kembali ke
pengirim. Selisih keduanya adalah ketidaksepakatan yang dibahas pada tabel B
bagian Pengukuran - keadaan ketika penerima merasa berhasil sedangkan pengirim
mencatat gagal karena ACK-nya yang hilang.

    python3 Modul04_lora_ack/monitor_serial.py
    python3 Modul04_lora_ack/monitor_serial.py --log sesi1.txt
    python3 Modul04_lora_ack/monitor_serial.py --port RX=/dev/ttyACM0
    python3 Modul04_lora_ack/monitor_serial.py --durasi 60      # berhenti sendiri

Butuh pyserial (`pip install pyserial`; sudah ikut terpasang bersama PlatformIO).
Hentikan dengan Ctrl-C, atau pakai `--durasi` agar berhenti otomatis.

PORT OTOMATIS. Port TX/RX tidak lagi ditulis tetap di kode: setiap kali
dijalankan, skrip memindai /dev/ttyACM* dan /dev/ttyUSB* yang sedang aktif
dan memakai yang benar-benar tersambung, urut sesuai nama device. Ini
penting karena nama port bisa berubah tiap kali board dicabut-pasang atau
board asli/klon bercampur (lihat tools/deteksi_port.py). Bila urutan
otomatisnya keliru (mis. board TX ternyata terdeteksi sebagai RX), timpa
lewat --port, mis. --port TX=/dev/ttyUSB0 --port RX=/dev/ttyACM1.

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
NAMA_PERAN_BAWAAN = ["TX", "RX"]
PALET_WARNA = ["\033[33m", "\033[36m", "\033[35m", "\033[32m", "\033[34m"]


def deteksi_port_aktif():
    """Kumpulkan port serial USB yang sedang tersambung, terurut nama device.

    Uno asli muncul sebagai /dev/ttyACM*, klon ber-bridge CH340/CP2102/FTDI
    sebagai /dev/ttyUSB* — pola yang sama dipakai tools/deteksi_port.py.
    Dipanggil ulang tiap program start supaya daftarnya selalu mengikuti apa
    yang benar-benar tersambung saat itu, bukan port tetap di kode.
    """
    return sorted(glob.glob("/dev/ttyACM*") + glob.glob("/dev/ttyUSB*"))


def bangun_port_bawaan():
    """Pasangkan tiap port aktif ke nama peran (TX, RX, lalu P3, P4, ...)."""
    hasil = []
    for i, dev in enumerate(deteksi_port_aktif()):
        nama = NAMA_PERAN_BAWAAN[i] if i < len(NAMA_PERAN_BAWAAN) else f"P{i + 1}"
        warna = PALET_WARNA[i % len(PALET_WARNA)]
        hasil.append((nama, dev, warna))
    return hasil

# Pola yang dipanen dari baris serial untuk menyusun ringkasan
RE_KIRIM = re.compile(r"\[TX\] Kirim:\s*DATA:(\d+)")     # pengirim: DATA keluar
RE_TIBA = re.compile(r"Data\s*:\s*DATA:(\d+)")            # penerima: DATA masuk
RE_ACK_KIRIM = re.compile(r"\[TX\] ACK:\s*ACK:(\d+)")     # penerima: ACK dibalas
RE_ACK_TIBA = re.compile(r"\[RX\] Balasan:\s*ACK:(\d+)")  # pengirim: ACK kembali
RE_OK = re.compile(r"\[OK\]")
RE_FAIL = re.compile(r"\[FAIL\]")
RE_RSSI = re.compile(r"RSSI\s*:\s*(-?[\d.]+)")
RE_SNR = re.compile(r"SNR\s*:\s*(-?[\d.]+)")
RESET = "\033[0m"
DIM = "\033[2m"

print_lock = threading.Lock()
counts = {}
# Bahan ringkasan akhir; diisi reader, dibaca sekali saat program berhenti
data_kirim, data_tiba = set(), set()   # nomor DATA di sisi pengirim / penerima
ack_kirim, ack_tiba = set(), set()     # nomor ACK di sisi penerima / pengirim
jml_ok, jml_fail = [0], [0]            # penghitung [OK] dan [FAIL] di pengirim
rtt = []                               # DATA keluar -> ACK kembali, detik
waktu_kirim = {}                       # nomor DATA -> saat dikirim
daftar_rssi, daftar_snr = [], []
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
    """Ambil kejadian DATA, ACK, OK/FAIL, RSSI, dan SNR dari sebuah baris.

    Nomor dipanen dari empat titik berbeda - DATA keluar, DATA tiba, ACK
    dibalas, ACK kembali - sehingga dapat dibedakan mana yang hilang: paket
    datanya, atau justru balasannya.
    """
    if (m := RE_KIRIM.search(text)):
        n = int(m.group(1)); data_kirim.add(n); waktu_kirim[n] = time.time()
    elif (m := RE_TIBA.search(text)):
        data_tiba.add(int(m.group(1)))
    elif (m := RE_ACK_KIRIM.search(text)):
        ack_kirim.add(int(m.group(1)))
    elif (m := RE_ACK_TIBA.search(text)):
        n = int(m.group(1)); ack_tiba.add(n)
        if n in waktu_kirim:
            rtt.append(time.time() - waktu_kirim.pop(n))
    elif RE_OK.search(text):
        jml_ok[0] += 1
    elif RE_FAIL.search(text):
        jml_fail[0] += 1

    if name != "TX":
        if (m := RE_RSSI.search(text)):
            daftar_rssi.append(float(m.group(1)))
        if (m := RE_SNR.search(text)):
            daftar_snr.append(float(m.group(1)))


def ringkasan():
    """Cetak hasil ukur tautan: loss, RSSI, dan SNR."""
    print("\n" + "-" * 60)
    print(f"Durasi: {time.time() - t0:.1f} s")
    for nama in counts:
        print(f"  {nama:<7} : {counts.get(nama, 0)} baris")

    if not data_kirim:
        print("\nTidak ada DATA yang terbaca - periksa tautan.")
        return

    print(f"\n  DATA dikirim pengirim  : {len(data_kirim)}"
          f"  (nomor {min(data_kirim)}..{max(data_kirim)})")
    print(f"  DATA tiba di penerima  : {len(data_tiba & data_kirim)}")
    print(f"  ACK dibalas penerima   : {len(ack_kirim & data_kirim)}")
    print(f"  ACK kembali ke pengirim: {len(ack_tiba & data_kirim)}")

    # Dua jenis kegagalan yang berbeda akibatnya, sengaja dipisah: DATA yang
    # tidak pernah tiba, dan DATA yang tiba tetapi ACK-nya hilang di jalan.
    data_hilang = sorted(data_kirim - data_tiba)
    ack_hilang = sorted((data_tiba & data_kirim) - ack_tiba)
    n = len(data_kirim)
    print(f"\n  DATA hilang            : {len(data_hilang)} ({len(data_hilang) / n * 100:.1f} %)")
    print(f"  DATA tiba tapi ACK hilang: {len(ack_hilang)} ({len(ack_hilang) / n * 100:.1f} %)")
    print(f"  Keberhasilan menurut pengirim : "
          f"{len(ack_tiba & data_kirim) / n * 100:.1f} %")
    print(f"  Keberhasilan menurut penerima : "
          f"{len(data_tiba & data_kirim) / n * 100:.1f} %")
    if jml_ok[0] or jml_fail[0]:
        print(f"  Penghitung firmware    : OK {jml_ok[0]} / FAIL {jml_fail[0]}")

    if rtt:
        print(f"\n  Waktu DATA->ACK min/maks/rata-rata : "
              f"{min(rtt) * 1000:.0f} / {max(rtt) * 1000:.0f} / "
              f"{sum(rtt) / len(rtt) * 1000:.0f} ms")
    if daftar_rssi:
        print(f"  RSSI  min/maks/rata-rata : {min(daftar_rssi):.0f} / {max(daftar_rssi):.0f} / "
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

    port_bawaan = bangun_port_bawaan()
    if not port_bawaan and not args.port:
        sys.exit("Tidak ada port serial USB yang terdeteksi (/dev/ttyACM*, /dev/ttyUSB*).\n"
                  "Periksa kabel data (bukan charge-only) dan hak akses grup dialout,\n"
                  "atau jalankan tools/deteksi_port.py untuk diagnosis lebih lanjut,\n"
                  "atau tentukan port manual lewat --port TX=/dev/ttyACM0 --port RX=/dev/ttyACM1")

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
