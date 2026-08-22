#!/usr/bin/env python3
"""Monitor pengirim dan penerima LoRa sekaligus untuk Modul 02.

Menampilkan kedua aliran serial dalam SATU jendela dengan timestamp bersama,
lalu meringkasnya saat berhenti: berapa paket dikirim, berapa yang tiba, dan
sebaran RSSI serta SNR-nya. Membandingkan nomor urut di dua jendela terpisah
jauh lebih sulit, karena tiap jendela punya sumbu waktunya sendiri.

Pada modul ini ringkasan tersebut dipakai untuk membuktikan keunggulan
penerimaan berbasis interrupt: jalankan monitor sambil `loop()` penerima
diberi pekerjaan tiruan (EXP-03), lalu bandingkan angka paket hilangnya
dengan penerima polling Modul 01 pada pekerjaan tiruan yang sama.

    python3 week02_lora_led_notif/monitor_serial.py
    python3 week02_lora_led_notif/monitor_serial.py --log sesi1.txt
    python3 week02_lora_led_notif/monitor_serial.py --port RX=/dev/ttyACM0
    python3 week02_lora_led_notif/monitor_serial.py --durasi 60      # berhenti sendiri

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

    port_bawaan = bangun_port_bawaan()
    if not port_bawaan and not args.port:
        sys.exit("Tidak ada port serial USB yang terdeteksi (/dev/ttyACM*, /dev/ttyUSB*).\n"
                  "Periksa kabel data (bukan charge-only) dan hak akses grup dialout,\n"
                  "atau jalankan tools/deteksi_port.py untuk diagnosis lebih lanjut,\n"
                  "atau tentukan port manual lewat --port TX=/dev/ttyUSB0 --port RX=/dev/ttyACM1")

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
