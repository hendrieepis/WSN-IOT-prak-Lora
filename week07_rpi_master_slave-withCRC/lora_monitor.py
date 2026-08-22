#!/usr/bin/env python3
"""
LoRa Monitor Dashboard - Sisi Slave (Modul 07)
===============================================
Dashboard live untuk memantau KEDUA Arduino Uno slave dari komputer ini.

Bedanya dengan lora_monitor.py pada M05: di modul ini master adalah Raspberry
Pi, dan Pi tidak menyalurkan keluarannya lewat USB ke komputer ini. Jadi tidak
ada panel MASTER yang bisa dibaca langsung. Yang tersedia hanya dua port serial
slave -- dan ternyata itu sudah cukup untuk menyimpulkan hampir seluruh keadaan
master, karena setiap slave MENDENGAR seluruh lalu lintas di udara:

    [RX] POLL:1          <- perintah master untuk dirinya
    [IGNORE] POLL:2      <- perintah master untuk slave sebelah
    [IGNORE] S2:DATA:12  <- jawaban slave sebelah

Dari tiga jenis baris itu, monitor menurunkan:
  - periode siklus master, diukur dari jarak antar POLL yang diterima node
    (padanan "Durasi siklus" di master, dilihat dari tepi jaringan)
  - keadaan slave sebelah, dari ada/tidaknya jawaban setelah POLL-nya terdengar
  - RSSI/SNR arah master -> slave, yang TIDAK terlihat di terminal master
    (master hanya melaporkan arah sebaliknya, slave -> master)

Kebutuhan:
  pip install pyserial rich

Cara pakai:
  python3 lora_monitor.py                                   # port bawaan
  python3 lora_monitor.py --s1 /dev/ttyACM0 --s2 /dev/ttyACM1
  python3 lora_monitor.py --out data_eksperimen.csv

Jalankan tools/deteksi_port.py untuk mengetahui port mana milik board yang mana.
"""

import threading
import queue
import csv
import time
import argparse
import glob
import re
import os
import sys
from datetime import datetime
from collections import deque
from dataclasses import dataclass, field

try:
    import serial
except ImportError:
    print("ERROR: pyserial tidak terinstall. Jalankan: pip install pyserial rich")
    sys.exit(1)

try:
    from rich.live    import Live
    from rich.panel   import Panel
    from rich.text    import Text
    from rich.console import Console, Group
    from rich.table   import Table
    from rich         import box
except ImportError:
    print("ERROR: rich tidak terinstall. Jalankan: pip install pyserial rich")
    sys.exit(1)

# ──────────────────────────────────────────────
# KONFIGURASI
# ──────────────────────────────────────────────
# Port bawaan mengikuti sistem operasi. Di Linux/macOS, Uno asli muncul sebagai
# /dev/ttyACM* dan klon ber-bridge CH340 sebagai /dev/ttyUSB*; di Windows
# keduanya sama-sama COMx. Jalankan tools/deteksi_port.py lalu berikan lewat
# --s1/--s2 bila port di komputer Anda berbeda.
if sys.platform.startswith("win"):
    DEFAULT_S1_PORT = "COM4"
    DEFAULT_S2_PORT = "COM5"
else:
    DEFAULT_S1_PORT = "/dev/ttyACM0"
    DEFAULT_S2_PORT = "/dev/ttyACM1"
DEFAULT_BAUD     = 115200          # M07 memakai 115200, sama seperti M05
LOG_LINES        = 16
REFRESH_HZ       = 4
PERIODE_WINDOW   = 60              # jumlah periode terakhir untuk min/maks/rerata
MISS_WARN        = 2               # lompatan RX# yang dianggap POLL hilang
PASANGAN_WARN    = 3               # siklus berturut tanpa jawaban slave sebelah


def deteksi_port_aktif():
    """Port serial USB yang sedang tersambung, terurut nama device.

    Uno asli muncul sebagai /dev/ttyACM*, klon ber-bridge CH340/CP2102/FTDI
    sebagai /dev/ttyUSB* -- pola yang sama dipakai tools/deteksi_port.py.
    Dipanggil tiap program start supaya default s1/s2 selalu mengikuti apa
    yang benar-benar tersambung, bukan port tetap di atas.
    """
    if sys.platform.startswith("win"):
        return []  # deteksi berbasis /dev/tty* tidak berlaku di Windows (COMx)
    return sorted(glob.glob("/dev/ttyACM*") + glob.glob("/dev/ttyUSB*"))

# Bentuk payload yang sah menurut kontrak M05/M07. Apa pun di luar dua pola ini
# adalah byte yang rusak di udara. Varian -withCRC ini MENGAKTIFKAN CRC di kedua
# sisi (LoRa.enableCrc() di slave, enableCrc() di master.py), sehingga paket
# cacat semestinya sudah dibuang radio sebelum sempat terdengar di sini sama
# sekali -- baris RUSAK yang tetap muncul berarti sesuatu lolos dari filter
# CRC atau kerusakan terjadi setelah decode, layak diselidiki lebih lanjut.
RE_POLL_SAH  = re.compile(r'^POLL:\d+$')
RE_DATA_SAH  = re.compile(r'^S\d+:DATA:\d+$')


# ──────────────────────────────────────────────
# DATA STRUCTURES
# ──────────────────────────────────────────────

@dataclass
class Anomaly:
    ts:     str
    node:   str
    kind:   str
    detail: str


@dataclass
class SlaveState:
    name:         str  = ""
    port:         str  = ""
    slave_id:     int  = 0
    connected:    bool = False
    rx_count:     int  = 0     # RX# dari firmware: POLL untuk dirinya
    data_counter: int  = 0     # counter yang dikirim balik ke master
    last_rssi:    int  = 0
    last_snr:     float = 0.0
    rssi_min:     int  = 0
    rssi_max:     int  = 0
    ignore_poll:  int  = 0     # POLL milik slave sebelah yang ikut terdengar
    ignore_reply: int  = 0     # jawaban slave sebelah yang ikut terdengar
    rusak:        int  = 0     # payload yang tidak memenuhi kontrak
    miss:         int  = 0     # POLL untuk dirinya yang tidak sampai
    # periode antar POLL untuk dirinya = periode siklus master dari sisi node
    periode:      deque = field(default_factory=lambda: deque(maxlen=PERIODE_WINDOW))
    _t_poll:      float = 0.0
    # menunggu jawaban slave sebelah setelah POLL-nya terdengar
    _nunggu_pasangan: bool = False
    pasangan_sepi:    int  = 0
    raw_log: deque = field(default_factory=lambda: deque(maxlen=200))


class SharedState:
    def __init__(self):
        self.lock          = threading.Lock()
        self.s1            = SlaveState("SLAVE 1", DEFAULT_S1_PORT, 1)
        self.s2            = SlaveState("SLAVE 2", DEFAULT_S2_PORT, 2)
        self.anomalies     = deque(maxlen=60)
        self.csv_queue     = queue.Queue()
        self.running       = True
        self.session_start = datetime.now()


# ──────────────────────────────────────────────
# PARSER
# ──────────────────────────────────────────────

def parse_slave_line(line: str, st: SlaveState, anomalies: deque) -> dict:
    """Perbarui state dari satu baris serial, kembalikan baris CSV terstruktur."""
    ts  = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    now = time.monotonic()
    row = {'event': 'LAIN', 'rssi': '', 'snr': '', 'rx': '', 'data': '',
           'periode_ms': '', 'detail': ''}

    # ── POLL untuk dirinya sendiri ───────────────────────────────────────────
    m = re.search(r'\[RX\]\s+POLL:(\d+)\s*\|\s*RSSI:\s*(-?\d+)\s*dBm\s*\|\s*'
                  r'SNR:\s*(-?[\d.]+)\s*dB\s*\|\s*RX#:\s*(\d+)', line)
    if m:
        rssi, snr, rx = int(m.group(2)), float(m.group(3)), int(m.group(4))

        # Jarak antar POLL = satu putaran penuh master. Diukur di sini, bukan
        # di master, sehingga sebaran yang terlihat sudah termasuk jitter
        # penjadwalan Linux + waktu udara -- persis yang ditanyakan EXP-02.
        if st._t_poll:
            periode = (now - st._t_poll) * 1000.0
            st.periode.append(periode)
            row['periode_ms'] = f"{periode:.0f}"
        st._t_poll = now

        if st.rx_count and rx > st.rx_count + 1:
            hilang = rx - st.rx_count - 1
            st.miss += hilang
            if hilang >= MISS_WARN:
                anomalies.append(Anomaly(ts, st.name, "POLL_HILANG",
                    f"RX# loncat {st.rx_count} -> {rx} ({hilang} POLL tidak sampai)"))

        st.rx_count  = rx
        st.last_rssi = rssi
        st.last_snr  = snr
        st.rssi_min  = rssi if not st.rssi_min else min(st.rssi_min, rssi)
        st.rssi_max  = rssi if not st.rssi_max else max(st.rssi_max, rssi)
        row.update(event='RX_POLL', rssi=rssi, snr=snr, rx=rx)
        return row

    # ── jawaban yang dikirim ke master ───────────────────────────────────────
    m = re.search(r'\[TX\]\s+S(\d+):DATA:(\d+)', line)
    if m:
        st.data_counter = int(m.group(2))
        row.update(event='TX_DATA', data=st.data_counter)
        return row

    # ── lalu lintas milik node lain yang ikut terdengar ──────────────────────
    m = re.search(r'\[IGNORE\]\s+(.*)$', line)
    if m:
        isi = m.group(1).strip()

        if RE_POLL_SAH.match(isi):
            st.ignore_poll += 1
            # master sedang memanggil slave sebelah; jawabannya ditunggu
            st._nunggu_pasangan = True
            row.update(event='IGNORE_POLL', detail=isi)
            return row

        if RE_DATA_SAH.match(isi):
            st.ignore_reply += 1
            if st._nunggu_pasangan:
                st._nunggu_pasangan = False
                st.pasangan_sepi    = 0
            row.update(event='IGNORE_REPLY', detail=isi)
            return row

        # Tidak cocok kontrak: byte rusak di udara. Inilah yang di terminal
        # master muncul sebagai "[WARN] Balasan tidak valid" lalu dihitung
        # sebagai FAIL, seolah slave tidak menjawab.
        st.rusak += 1
        anomalies.append(Anomaly(ts, st.name, "PAYLOAD_RUSAK",
            f"payload di luar kontrak: {isi!r}"))
        row.update(event='RUSAK', detail=isi)
        return row

    if 'Init LoRa' in line or '=== LoRa SLAVE' in line:
        row.update(event='INIT', detail=line.strip())
    return row


def tutup_siklus(st: SlaveState, anomalies: deque):
    """Dipanggil saat POLL untuk diri sendiri tiba: nilai siklus sebelumnya.

    Bila POLL slave sebelah sempat terdengar tetapi jawabannya tidak pernah
    muncul, slave sebelah sedang mati atau di luar jangkauan -- keadaan EXP-03.
    """
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    if st._nunggu_pasangan:
        st._nunggu_pasangan = False
        st.pasangan_sepi   += 1
        if st.pasangan_sepi == PASANGAN_WARN:
            lawan = 2 if st.slave_id == 1 else 1
            anomalies.append(Anomaly(ts, st.name, "PASANGAN_HILANG",
                f"POLL:{lawan} terdengar {PASANGAN_WARN}x tanpa jawaban - "
                f"slave {lawan} mati atau di luar jangkauan"))


# ──────────────────────────────────────────────
# READER THREADS
# ──────────────────────────────────────────────

def reader_thread(port: str, baud: int, node_key: str, shared: SharedState):
    state = shared.s1 if node_key == "S1" else shared.s2

    while shared.running:
        try:
            with serial.Serial(port, baud, timeout=1) as ser:
                with shared.lock:
                    state.connected = True
                while shared.running:
                    try:
                        raw = ser.readline()
                        if not raw:
                            continue
                        line = raw.decode('utf-8', errors='replace').rstrip()
                        if not line:
                            continue
                        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
                        with shared.lock:
                            state.raw_log.append((ts, line))
                            # siklus dinilai tepat sebelum POLL berikutnya diproses
                            if '[RX]' in line and 'POLL:' in line:
                                tutup_siklus(state, shared.anomalies)
                            row = parse_slave_line(line, state, shared.anomalies)
                        row.update(ts=ts, node=node_key, raw=line)
                        shared.csv_queue.put(row)
                    except (serial.SerialException, OSError):
                        break
        except (serial.SerialException, OSError):
            with shared.lock:
                state.connected = False
            time.sleep(2)


def csv_writer_thread(shared: SharedState, filepath: str):
    kolom = ['timestamp', 'node', 'event', 'rssi_dbm', 'snr_db',
             'rx_count', 'data', 'periode_ms', 'detail', 'raw_line']
    with open(filepath, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=kolom)
        w.writeheader()
        while shared.running or not shared.csv_queue.empty():
            try:
                r = shared.csv_queue.get(timeout=0.5)
                w.writerow({'timestamp': r['ts'],    'node':       r['node'],
                            'event':     r['event'], 'rssi_dbm':   r['rssi'],
                            'snr_db':    r['snr'],   'rx_count':   r['rx'],
                            'data':      r['data'],  'periode_ms': r['periode_ms'],
                            'detail':    r['detail'],'raw_line':   r['raw']})
                f.flush()
            except queue.Empty:
                continue


# ──────────────────────────────────────────────
# RICH RENDERERS
# ──────────────────────────────────────────────

def conn_badge(connected: bool, port: str) -> Text:
    if connected:
        return Text(f" CONNECTED: {port} ", style="bold black on green")
    return Text(f" DISCONNECTED: {port} ", style="bold white on red")


def log_line_style(line: str) -> str:
    if '[RX]'     in line: return "green"
    if '[TX]'     in line: return "yellow"
    if '[IGNORE]' in line: return "dim"
    if 'GAGAL'    in line: return "bold red"
    if '==='      in line: return "bold cyan"
    return "dim white"


def build_slave_panel(st: SlaveState, color: str) -> Panel:
    t = Text()
    t.append("\n")
    t.append(conn_badge(st.connected, st.port))
    t.append("\n\n")

    t.append("  POLL diterima  : ", style="dim")
    t.append(f"{st.rx_count:>7}\n", style="bold white")
    t.append("  Jawaban dikirim: ", style="dim")
    t.append(f"{st.data_counter:>7}\n", style="bold green")
    t.append("  POLL hilang    : ", style="dim")
    t.append(f"{st.miss:>7}\n", style="bold red" if st.miss else "dim")
    t.append("  Payload rusak  : ", style="dim")
    t.append(f"{st.rusak:>7}\n\n", style="bold red" if st.rusak else "dim")

    # Arah master -> slave. Terminal master hanya melaporkan arah sebaliknya,
    # jadi angka ini tidak ada duanya di tempat lain.
    t.append("  Master -> node\n", style="bold cyan")
    t.append("  RSSI  : ", style="dim")
    t.append(f"{st.last_rssi:>6} dBm\n", style="bold white")
    t.append("  rentang: ", style="dim")
    t.append(f"{st.rssi_min}..{st.rssi_max} dBm\n" if st.rssi_min else "-\n",
             style="white")
    t.append("  SNR   : ", style="dim")
    t.append(f"{st.last_snr:>6.2f} dB\n\n", style="bold white")

    t.append("  Periode siklus\n", style="bold cyan")
    if st.periode:
        p = list(st.periode)
        rata = sum(p) / len(p)
        t.append("  min/rata/maks: ", style="dim")
        t.append(f"{min(p):.0f} / {rata:.0f} / {max(p):.0f} ms\n", style="bold white")
        t.append("  sebaran : ", style="dim")
        t.append(f"{max(p) - min(p):.0f} ms\n\n", style="bold yellow")
    else:
        t.append("  menunggu POLL kedua...\n\n", style="dim")

    t.append("  Terdengar dari node lain\n", style="bold cyan")
    t.append("  POLL / jawaban: ", style="dim")
    t.append(f"{st.ignore_poll} / {st.ignore_reply}\n\n", style="white")

    t.append("  Raw Log\n", style="bold dim")
    t.append("  " + "─" * 34 + "\n", style="dim")
    for ts, line in list(st.raw_log)[-LOG_LINES:]:
        t.append(f"  {ts[3:]}  {line[:40]}\n", style=log_line_style(line))

    return Panel(t, title=f"[bold {color}]{st.name}[/]",
                 border_style=color, box=box.ROUNDED)


def build_anomaly_panel(anomalies: deque, session_start: datetime,
                        csv_path: str) -> Panel:
    elapsed = datetime.now() - session_start
    h = int(elapsed.total_seconds() // 3600)
    m = int((elapsed.total_seconds() % 3600) // 60)
    s = int(elapsed.total_seconds() % 60)

    t = Text()
    t.append(f"  Session: {h:02d}:{m:02d}:{s:02d}", style="dim")
    t.append(f"   CSV: {os.path.basename(csv_path)}", style="dim")
    t.append("   Ctrl+C untuk keluar\n\n", style="dim")

    kind_style = {
        'POLL_HILANG':     "bold yellow",
        'PAYLOAD_RUSAK':   "bold white on red",
        'PASANGAN_HILANG': "bold red",
    }
    anom_list = list(anomalies)
    if not anom_list:
        t.append("  Tidak ada anomali terdeteksi", style="bold green")
    else:
        for a in reversed(anom_list[-5:]):
            t.append(f"  [{a.ts}] ", style="dim")
            t.append(f"[{a.node}] ", style="bold white")
            t.append(f"{a.kind}: ", style=kind_style.get(a.kind, "white"))
            t.append(f"{a.detail}\n", style="white")

    return Panel(t, title="[bold red]ANOMALI DETECTOR[/]",
                 border_style="red", box=box.ROUNDED)


# ──────────────────────────────────────────────
# LAYOUT BUILDER
# ──────────────────────────────────────────────

def build_layout(shared: SharedState, csv_path: str):
    with shared.lock:
        # snapshot biar tidak menahan lock saat render
        snap = []
        for src in (shared.s1, shared.s2):
            snap.append(SlaveState(
                name=src.name, port=src.port, slave_id=src.slave_id,
                connected=src.connected, rx_count=src.rx_count,
                data_counter=src.data_counter, last_rssi=src.last_rssi,
                last_snr=src.last_snr, rssi_min=src.rssi_min,
                rssi_max=src.rssi_max, ignore_poll=src.ignore_poll,
                ignore_reply=src.ignore_reply, rusak=src.rusak, miss=src.miss,
                periode=deque(src.periode), raw_log=deque(src.raw_log),
            ))
        anom    = deque(shared.anomalies)
        t_start = shared.session_start

    # Grid dua kolom berbagi rata: dengan hanya dua panel, Columns membiarkan
    # keduanya selebar isinya saja dan separuh terminal terbuang.
    node_row = Table.grid(expand=True)
    node_row.add_column(ratio=1)
    node_row.add_column(ratio=1)
    node_row.add_row(build_slave_panel(snap[0], "green"),
                     build_slave_panel(snap[1], "magenta"))

    return Group(node_row, build_anomaly_panel(anom, t_start, csv_path))


# ──────────────────────────────────────────────
# ENTRY POINT
# ──────────────────────────────────────────────

BANNER = """\
╔══════════════════════════════════════════════════════════════════════╗
║        LoRa Monitor Dashboard - Sisi Slave (Modul 07)               ║
║   Dragino LoRa Shield v1.2 · SX1276 · Arduino Uno · 433 MHz         ║
╚══════════════════════════════════════════════════════════════════════╝

  Master modul ini adalah Raspberry Pi, jadi terminalnya tidak lewat USB
  ke komputer ini. Monitor membaca kedua slave saja - dan menyimpulkan
  keadaan master dari lalu lintas yang ikut terdengar oleh node.

  PENGGUNAAN:
    python3 lora_monitor.py [opsi...]

  OPSI:
    --s1   PORT   Port serial Slave 1              (default: {s1})
    --s2   PORT   Port serial Slave 2              (default: {s2})
    --baud N      Baud rate serial kedua port      (default: {baud})
    --out  FILE   Nama file CSV output             (default: lora_slaves_YYYYMMDD_HHMMSS.csv)
    -h / --help   Tampilkan pesan bantuan ini

  CONTOH:
    python3 lora_monitor.py
        -> Jalankan dengan port & baud rate default

    python3 lora_monitor.py --s1 /dev/ttyACM0 --s2 /dev/ttyACM1
        -> Tentukan port secara eksplisit (Windows: COM4, COM5)

    python3 lora_monitor.py --out data_jarak_10m.csv
        -> Simpan log ke nama file tertentu

  KONTROL DASHBOARD:
    Ctrl+C        Hentikan monitoring & simpan CSV

  CATATAN:
    • Kedua slave harus sudah di-upload firmware dengan baud {baud}
    • Jalankan tools/deteksi_port.py bila ragu port mana milik board mana
    • Tutup Serial Monitor PlatformIO dulu - satu port hanya boleh dibuka
      oleh satu program
    • Master di Raspberry Pi dijalankan terpisah:
      python3 week07_rpi_master_slave/src/master.py
""".format(s1=DEFAULT_S1_PORT, s2=DEFAULT_S2_PORT, baud=DEFAULT_BAUD)


def parse_args(port_aktif):
    s1_default = port_aktif[0] if len(port_aktif) > 0 else DEFAULT_S1_PORT
    s2_default = port_aktif[1] if len(port_aktif) > 1 else DEFAULT_S2_PORT

    p = argparse.ArgumentParser(
        description="LoRa Monitor Dashboard sisi slave - tool pemantauan praktikum M07.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Contoh penggunaan:\n"
            "  python3 lora_monitor.py\n"
            "  python3 lora_monitor.py --s1 /dev/ttyACM0 --s2 /dev/ttyACM1\n"
            "  python3 lora_monitor.py --out data_eksperimen.csv\n"
        ),
    )
    p.add_argument('--s1',   default=s1_default, metavar='PORT',
                   help=f'Port serial Slave 1 (default: {s1_default}, dari deteksi port aktif)')
    p.add_argument('--s2',   default=s2_default, metavar='PORT',
                   help=f'Port serial Slave 2 (default: {s2_default}, dari deteksi port aktif)')
    p.add_argument('--baud', default=DEFAULT_BAUD, type=int, metavar='N',
                   help=f'Baud rate serial (default: {DEFAULT_BAUD})')
    p.add_argument('--out',  default=None, metavar='FILE',
                   help='Nama file CSV output (default: auto timestamp)')
    return p.parse_args()


def main():
    port_aktif = deteksi_port_aktif()
    args    = parse_args(port_aktif)
    no_args = len(sys.argv) == 1
    console = Console()

    if no_args:
        console.print(BANNER)

    console.print(
        f"[dim]Port aktif terdeteksi: {', '.join(port_aktif) if port_aktif else '(tidak ada -- memakai default tetap)'}[/]"
    )
    console.print(
        f"[dim]Dipakai -> "
        f"S1=[green]{args.s1}[/] S2=[magenta]{args.s2}[/] "
        f"Baud=[white]{args.baud}[/][/dim]\n"
    )

    shared = SharedState()
    shared.s1.port = args.s1
    shared.s2.port = args.s2

    ts_str   = shared.session_start.strftime("%Y%m%d_%H%M%S")
    csv_path = args.out or f"lora_slaves_{ts_str}.csv"

    if not no_args:
        console.print("\n[bold cyan]LoRa Monitor Dashboard - Sisi Slave[/]")
        console.print(f"  Slave1 : [green]{args.s1}[/]")
        console.print(f"  Slave2 : [magenta]{args.s2}[/]")
        console.print(f"  Baud   : [white]{args.baud}[/]")

    console.print(f"  CSV    : [dim]{csv_path}[/]")
    console.print("\nTekan [bold]Enter[/] untuk mulai dashboard, [bold]Ctrl+C[/] untuk batal...\n")
    try:
        input()
    except KeyboardInterrupt:
        return

    threads = [
        threading.Thread(target=reader_thread, args=(args.s1, args.baud, "S1", shared),
                         daemon=True, name="reader-s1"),
        threading.Thread(target=reader_thread, args=(args.s2, args.baud, "S2", shared),
                         daemon=True, name="reader-s2"),
        threading.Thread(target=csv_writer_thread, args=(shared, csv_path),
                         daemon=True, name="csv-writer"),
    ]
    for t in threads:
        t.start()

    try:
        with Live(build_layout(shared, csv_path), console=console,
                  refresh_per_second=REFRESH_HZ, screen=True) as live:
            while True:
                time.sleep(1.0 / REFRESH_HZ)
                live.update(build_layout(shared, csv_path))
    except KeyboardInterrupt:
        pass
    finally:
        shared.running = False
        time.sleep(0.6)
        console.print(f"\n[green]Session selesai.[/] Data di: [bold]{csv_path}[/]")


if __name__ == "__main__":
    main()
