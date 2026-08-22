#!/usr/bin/env python3
"""
LoRa Slotted ALOHA Monitor Dashboard
=============
Full-terminal live dashboard untuk monitoring komunikasi
LoRa Gateway <-> Node 1 & Node 2 (gateway menyiarkan SYNC, tiap node bicara pada slotnya sendiri)

Kompatibel: Windows (PowerShell / Windows Terminal) & Linux/Mac

Kebutuhan:
  pip install pyserial rich

Cara pakai:
  python lora_monitor.py                                    # port bawaan sesuai OS
  python lora_monitor.py --gateway /dev/ttyACM0 --n1 /dev/ttyACM1 --n2 /dev/ttyACM2
  python lora_monitor.py --out data_eksperimen.csv
"""

import threading
import queue
import csv
import time
import argparse
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
    from rich.table   import Table
    from rich.layout  import Layout
    from rich.panel   import Panel
    from rich.text    import Text
    from rich.console import Console, Group
    from rich.columns import Columns
    from rich         import box
except ImportError:
    print("ERROR: rich tidak terinstall. Jalankan: pip install pyserial rich")
    sys.exit(1)

# ──────────────────────────────────────────────
# KONFIGURASI
# ──────────────────────────────────────────────
# Port bawaan mengikuti sistem operasi. Di Linux/macOS, Uno asli muncul sebagai
# /dev/ttyACM* dan klon ber-bridge CH340 sebagai /dev/ttyUSB*; di Windows
# keduanya sama-sama COMx. Jalankan tools/deteksi_port.py untuk mengetahui port
# mana milik board yang mana, lalu berikan lewat --gateway/--n1/--n2.
if sys.platform.startswith("win"):
    DEFAULT_GW_PORT = "COM3"
    DEFAULT_N1_PORT = "COM4"
    DEFAULT_N2_PORT = "COM5"
else:
    DEFAULT_GW_PORT = "/dev/ttyACM0"
    DEFAULT_N1_PORT = "/dev/ttyACM1"
    DEFAULT_N2_PORT = "/dev/ttyACM2"
DEFAULT_BAUD     = 115200
LOG_LINES        = 16
REFRESH_HZ       = 4
GAP_WARN_STREAK  = 3
# Pure ALOHA (M08A) tidak punya ACK sama sekali -- node tidak pernah tahu
# apakah paketnya sampai, jadi baris OK/FAIL/Retry di panel node disembunyikan.
HAS_ACK          = True

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
class GatewayState:
    port:        str  = DEFAULT_GW_PORT
    connected:   bool = False
    rx_total:    int  = 0
    rx_n1:       int  = 0
    rx_n2:       int  = 0
    gap_n1:      int  = 0
    gap_n2:      int  = 0
    lost_n1:     int  = 0
    lost_n2:     int  = 0
    dup_n1:      int  = 0
    dup_n2:      int  = 0
    last_rssi:   int  = 0
    last_snr:    float = 0.0
    rssi_sum:    int  = 0
    snr_sum:     float = 0.0
    rssi_count:  int  = 0
    cycle:       int  = 0
    raw_log: deque = field(default_factory=lambda: deque(maxlen=300))

@dataclass
class NodeState:
    name:         str  = ""
    port:         str  = ""
    connected:    bool = False
    tx_count:     int  = 0
    ok_count:     int  = 0
    fail_count:   int  = 0
    retry_count:  int  = 0
    last_seq:     int  = -1
    raw_log: deque = field(default_factory=lambda: deque(maxlen=300))

class SharedState:
    def __init__(self):
        self.lock          = threading.Lock()
        self.gw            = GatewayState()
        self.n1            = NodeState("NODE 1", DEFAULT_N1_PORT)
        self.n2            = NodeState("NODE 2", DEFAULT_N2_PORT)
        self.anomalies     = deque(maxlen=60)
        self.csv_queue     = queue.Queue()
        self.running       = True
        self.session_start = datetime.now()

# ──────────────────────────────────────────────
# PARSERS
# ──────────────────────────────────────────────
# Semua regex dibuat agar aman dipakai lintas modul (M08A/M08B/M09/M10) --
# token yang tidak muncul pada suatu modul (mis. RETRY/SYNC) hanya tidak
# pernah cocok, tanpa memengaruhi parsing token lain.

RE_NODE_LINE   = re.compile(r'Node\s+:\s*(\d+)')
RE_SEQ_LINE    = re.compile(r'SEQ\s+:\s*(\d+)')
RE_RSSI_LINE   = re.compile(r'RSSI\s+:\s*(-?\d+)')
RE_SNR_LINE    = re.compile(r'SNR\s+:\s*(-?\d+\.?\d*)')
RE_GAP_LINE    = re.compile(r'\[GAP\] SEQ meloncat\s+(\d+)')
RE_STAT_LINE   = re.compile(r'Statistik Node\s+(\d+):\s*diterima=(\d+)\s*\|\s*perkiraan hilang=(\d+)')
RE_SYNC_TX     = re.compile(r'\[TX\]\s+SYNC=(\d+)')
RE_CYCLE_DONE  = re.compile(r'Cycle\s+(\d+)\s+selesai')
# M09: "Statistik Node X: baru=Y | duplicate=Z | gagal permanen (est.)=W"
RE_STAT_RETRY  = re.compile(r'Statistik Node\s+(\d+):\s*baru=(\d+)\s*\|\s*duplicate=(\d+)\s*\|\s*gagal permanen\s*\(est\.\)=(\d+)')
# M10: "--- Cycle N selesai | N1: diterima=Y hilang=Z  N2: diterima=Y hilang=Z ---"
RE_STAT_CYCLE  = re.compile(r'N(\d+):\s*diterima=(\d+)\s*hilang=(\d+)')

RE_NODE_TX     = re.compile(r'\[TX\].*NODE=(\d+),SEQ=(\d+)')
RE_NODE_RETRY  = re.compile(r'\[RETRY\s+(\d+)/(\d+)\]')
RE_NODE_OK     = re.compile(r'\[OK\]')
RE_NODE_FAIL   = re.compile(r'\[FAIL\]')

def parse_gateway_line(line: str, st: GatewayState, anomalies: deque):
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]

    if 'PAKET DITERIMA' in line:
        st.rx_total += 1

    m = RE_RSSI_LINE.search(line)
    if m:
        st.last_rssi = int(m.group(1))
        st.rssi_sum += st.last_rssi
        st.rssi_count += 1

    m = RE_SNR_LINE.search(line)
    if m:
        st.last_snr = float(m.group(1))
        st.snr_sum += st.last_snr

    m = RE_GAP_LINE.search(line)
    if m:
        gap = int(m.group(1))
        anomalies.append(Anomaly(ts, "GATEWAY", "GAP", f"SEQ meloncat {gap} -- indikasi tabrakan/paket hilang"))

    m = RE_STAT_LINE.search(line)
    if m:
        node_id, rx, lost = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if node_id == 1:
            st.rx_n1, st.lost_n1 = rx, lost
        elif node_id == 2:
            st.rx_n2, st.lost_n2 = rx, lost

    m = RE_STAT_RETRY.search(line)
    if m:
        node_id, rx, dup, lost = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
        if node_id == 1:
            st.rx_n1, st.dup_n1, st.lost_n1 = rx, dup, lost
        elif node_id == 2:
            st.rx_n2, st.dup_n2, st.lost_n2 = rx, dup, lost

    for node_id_s, rx_s, lost_s in RE_STAT_CYCLE.findall(line):
        node_id, rx, lost = int(node_id_s), int(rx_s), int(lost_s)
        if node_id == 1:
            st.rx_n1, st.lost_n1 = rx, lost
        elif node_id == 2:
            st.rx_n2, st.lost_n2 = rx, lost

    m = RE_SYNC_TX.search(line)
    if m:
        st.cycle = int(m.group(1))

    m = RE_CYCLE_DONE.search(line)
    if m:
        st.cycle = int(m.group(1))

def parse_node_line(line: str, st: NodeState, node_label: str, anomalies: deque):
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]

    m = RE_NODE_TX.search(line)
    if m:
        seq = int(m.group(2))
        if st.last_seq >= 0 and seq == st.last_seq and '[RETRY' not in line:
            pass  # aman, tidak dipakai
        st.last_seq = seq
        if '[RETRY' not in line:
            st.tx_count += 1

    m = RE_NODE_RETRY.search(line)
    if m:
        st.retry_count += 1

    if RE_NODE_OK.search(line):
        st.ok_count += 1
    elif RE_NODE_FAIL.search(line):
        st.fail_count += 1
        if st.fail_count and st.fail_count % 5 == 0:
            anomalies.append(Anomaly(ts, node_label, "FAIL_COUNT",
                f"{node_label} sudah {st.fail_count}x gagal (tanpa ACK)"))

# ──────────────────────────────────────────────
# READER THREADS
# ──────────────────────────────────────────────

def reader_thread(port: str, baud: int, node_key: str,
                  shared: SharedState, role: str):
    if role == "GW":
        state = shared.gw
    elif node_key == "N1":
        state = shared.n1
    else:
        state = shared.n2

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
                            if role == "GW":
                                parse_gateway_line(line, state, shared.anomalies)
                            else:
                                parse_node_line(line, state, node_key, shared.anomalies)
                        shared.csv_queue.put({
                            'ts': ts, 'node': node_key, 'raw': line
                        })
                    except (serial.SerialException, OSError):
                        break
        except (serial.SerialException, OSError):
            with shared.lock:
                state.connected = False
            time.sleep(2)

def csv_writer_thread(shared: SharedState, filepath: str):
    with open(filepath, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=['timestamp', 'node', 'raw_line'])
        w.writeheader()
        while shared.running or not shared.csv_queue.empty():
            try:
                row = shared.csv_queue.get(timeout=0.5)
                w.writerow({'timestamp': row['ts'],
                            'node': row['node'],
                            'raw_line': row['raw']})
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

def pct_style(ok: int, total: int) -> str:
    if total == 0: return "dim"
    r = ok / total
    if r >= 0.97: return "bold green"
    if r >= 0.90: return "bold yellow"
    return "bold red"

def log_line_style(line: str) -> str:
    if '[FAIL]'    in line: return "red"
    if '[GAP]'     in line: return "bold red"
    if '[RETRY'    in line: return "bold yellow"
    if '[BACKOFF]' in line: return "yellow"
    if '[OK]'      in line: return "bold green"
    if '[TX]'      in line: return "cyan"
    if 'PAKET DITERIMA' in line: return "green"
    if '[WAIT]'    in line: return "dim"
    if '[WARN]'    in line: return "yellow"
    return "dim white"

def build_gateway_panel(st: GatewayState) -> Panel:
    t = Text()
    t.append("\n")
    t.append(conn_badge(st.connected, st.port))
    t.append("\n\n")

    t.append("  Total diterima : ", style="dim"); t.append(f"{st.rx_total}\n", style="bold white")
    if st.cycle:
        t.append("  Cycle terakhir : ", style="dim"); t.append(f"{st.cycle}\n", style="bold cyan")
    t.append("\n")

    dup_suffix1 = f" dup={st.dup_n1}" if st.dup_n1 else ""
    dup_suffix2 = f" dup={st.dup_n2}" if st.dup_n2 else ""
    t.append("  Node 1  ", style="bold cyan")
    t.append(f"diterima={st.rx_n1:<4} hilang={st.lost_n1}{dup_suffix1}\n", style="white")
    t.append("  Node 2  ", style="bold magenta")
    t.append(f"diterima={st.rx_n2:<4} hilang={st.lost_n2}{dup_suffix2}\n\n", style="white")

    rssi_avg = (st.rssi_sum / st.rssi_count) if st.rssi_count else 0.0
    snr_avg  = (st.snr_sum / st.rssi_count) if st.rssi_count else 0.0
    t.append("  RSSI terakhir  : ", style="dim"); t.append(f"{st.last_rssi} dBm\n", style="white")
    t.append("  SNR terakhir   : ", style="dim"); t.append(f"{st.last_snr:.2f} dB\n", style="white")
    t.append("  RSSI rata-rata : ", style="dim"); t.append(f"{rssi_avg:.1f} dBm\n", style="white")
    t.append("  SNR rata-rata  : ", style="dim"); t.append(f"{snr_avg:.2f} dB\n\n", style="white")

    t.append("  Raw Log\n", style="bold dim")
    t.append("  " + "─" * 30 + "\n", style="dim")
    for ts, line in list(st.raw_log)[-LOG_LINES:]:
        style = log_line_style(line)
        t.append(f"  {ts[-8:]}  {line[:40]}\n", style=style)

    return Panel(t, title="[bold cyan]GATEWAY[/]",
                 border_style="cyan", box=box.ROUNDED)

def build_node_panel(st: NodeState, label: str, color: str) -> Panel:
    t = Text()
    t.append("\n")
    t.append(conn_badge(st.connected, st.port))
    t.append("\n\n")

    t.append("  TX terkirim  : ", style="dim"); t.append(f"{st.tx_count:>6}\n", style="bold white")
    t.append("  SEQ terakhir : ", style="dim"); t.append(f"{st.last_seq:>6}\n\n", style="white")

    if HAS_ACK:
        tot = st.ok_count + st.fail_count
        pct = (st.ok_count / tot * 100) if tot else 0.0
        t.append("  OK    : ", style="dim"); t.append(f"{st.ok_count:>6}\n", style="bold green")
        t.append("  FAIL  : ", style="dim"); t.append(f"{st.fail_count:>6}\n",
                  style="bold red" if st.fail_count else "dim")
        if tot:
            t.append("  Rate  : ", style="dim"); t.append(f"{pct:>6.2f}%\n", style=pct_style(st.ok_count, tot))
        t.append("  Retry : ", style="dim"); t.append(f"{st.retry_count:>6}\n\n",
                  style="yellow" if st.retry_count else "dim")
    else:
        t.append("  (Pure ALOHA -- tanpa ACK, node tidak pernah tahu\n", style="dim")
        t.append("   apakah paketnya sampai. Lihat panel GATEWAY untuk\n", style="dim")
        t.append("   statistik diterima/hilang per node.)\n\n", style="dim")

    t.append("  Raw Log\n", style="bold dim")
    t.append("  " + "─" * 30 + "\n", style="dim")
    for ts, line in list(st.raw_log)[-LOG_LINES:]:
        style = log_line_style(line)
        t.append(f"  {ts[-8:]}  {line[:36]}\n", style=style)

    return Panel(t, title=f"[bold {color}]{label}[/]",
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
    t.append(f"   Ctrl+C untuk keluar\n\n", style="dim")

    kind_style = {
        'GAP':        "bold red",
        'FAIL_COUNT': "bold yellow",
    }
    anom_list = list(anomalies)
    if not anom_list:
        t.append("  Tidak ada anomali terdeteksi", style="bold green")
    else:
        for a in reversed(anom_list[-5:]):
            style = kind_style.get(a.kind, "white")
            t.append(f"  [{a.ts}] ", style="dim")
            t.append(f"[{a.node}] ", style="bold white")
            t.append(f"{a.kind}: ", style=style)
            t.append(f"{a.detail}\n", style="white")

    return Panel(t, title="[bold red]ANOMALI DETECTOR[/]",
                 border_style="red", box=box.ROUNDED)

# ──────────────────────────────────────────────
# LAYOUT BUILDER
# ──────────────────────────────────────────────

def build_layout(shared: SharedState, csv_path: str):
    with shared.lock:
        gw = GatewayState(
            port=shared.gw.port, connected=shared.gw.connected,
            rx_total=shared.gw.rx_total, rx_n1=shared.gw.rx_n1, rx_n2=shared.gw.rx_n2,
            gap_n1=shared.gw.gap_n1, gap_n2=shared.gw.gap_n2,
            lost_n1=shared.gw.lost_n1, lost_n2=shared.gw.lost_n2,
            dup_n1=shared.gw.dup_n1, dup_n2=shared.gw.dup_n2,
            last_rssi=shared.gw.last_rssi, last_snr=shared.gw.last_snr,
            rssi_sum=shared.gw.rssi_sum, snr_sum=shared.gw.snr_sum,
            rssi_count=shared.gw.rssi_count, cycle=shared.gw.cycle,
            raw_log=deque(shared.gw.raw_log),
        )
        n1 = NodeState(
            name=shared.n1.name, port=shared.n1.port, connected=shared.n1.connected,
            tx_count=shared.n1.tx_count, ok_count=shared.n1.ok_count,
            fail_count=shared.n1.fail_count, retry_count=shared.n1.retry_count,
            last_seq=shared.n1.last_seq,
            raw_log=deque(shared.n1.raw_log),
        )
        n2 = NodeState(
            name=shared.n2.name, port=shared.n2.port, connected=shared.n2.connected,
            tx_count=shared.n2.tx_count, ok_count=shared.n2.ok_count,
            fail_count=shared.n2.fail_count, retry_count=shared.n2.retry_count,
            last_seq=shared.n2.last_seq,
            raw_log=deque(shared.n2.raw_log),
        )
        anom  = deque(shared.anomalies)
        t_start = shared.session_start

    node_row = Columns([
        build_gateway_panel(gw),
        build_node_panel(n1, "NODE 1", "green"),
        build_node_panel(n2, "NODE 2", "magenta"),
    ], equal=True, expand=True)

    return Group(node_row, build_anomaly_panel(anom, t_start, csv_path))

# ──────────────────────────────────────────────
# ENTRY POINT
# ──────────────────────────────────────────────

BANNER = """\
╔══════════════════════════════════════════════════════════════════════╗
║        LoRa SLOTTED ALOHA Monitor — Evaluasi Praktikum        ║
║      Dragino LoRa Shield v1.2 · SX1276 · Arduino Uno · 433 MHz     ║
╚══════════════════════════════════════════════════════════════════════╝

  Tool ini membaca data serial dari 3 board LoRa (Gateway, Node 1, Node 2)
  secara bersamaan dan menampilkan dashboard real-time: statistik
  diterima/OK/FAIL/SLOT, RSSI/SNR, deteksi anomali (GAP/FAIL beruntun),
  serta logging CSV otomatis untuk analisis data penelitian.

  PENGGUNAAN:
    python lora_monitor.py [opsi...]

  OPSI:
    --gateway PORT  Port COM untuk Gateway              (default: {gw})
    --n1      PORT  Port COM untuk Node 1                (default: {n1})
    --n2      PORT  Port COM untuk Node 2                (default: {n2})
    --baud    N     Baud rate serial semua port          (default: {baud})
    --out     FILE  Nama file CSV output                 (default: lora_session_YYYYMMDD_HHMMSS.csv)
    -h / --help     Tampilkan pesan bantuan ini

  CONTOH:
    python lora_monitor.py
        -> Jalankan dengan port & baud rate default

    python lora_monitor.py --gateway /dev/ttyACM0 --n1 /dev/ttyACM1 --n2 /dev/ttyACM2
        -> Tentukan port secara eksplisit (Windows: COM3, COM4, COM5)

    python lora_monitor.py --out data_jarak_10m.csv
        -> Simpan log ke nama file tertentu

  KONTROL DASHBOARD:
    Ctrl+C          Hentikan monitoring & simpan CSV

  CATATAN:
    * Pastikan semua board sudah di-upload firmware dengan baud {baud}
    * Upload Gateway dulu, baru Node 1 dan Node 2, sebelum menjalankan tool ini
    * File CSV tersimpan otomatis saat Ctrl+C ditekan
""".format(
    gw=DEFAULT_GW_PORT,
    n1=DEFAULT_N1_PORT,
    n2=DEFAULT_N2_PORT,
    baud=DEFAULT_BAUD,
)

def parse_args():
    p = argparse.ArgumentParser(
        description="LoRa Slotted ALOHA Monitor Dashboard -- tool evaluasi praktikum LoRa.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Contoh penggunaan:\n"
            f"  python lora_monitor.py\n"
            f"  python lora_monitor.py --gateway /dev/ttyACM0 --n1 /dev/ttyACM1 --n2 /dev/ttyACM2\n"
            f"  python lora_monitor.py --out data_eksperimen.csv\n"
        ),
    )
    p.add_argument('--gateway', default=DEFAULT_GW_PORT,
                   metavar='PORT', help=f'Port COM Gateway (default: {DEFAULT_GW_PORT})')
    p.add_argument('--n1',      default=DEFAULT_N1_PORT,
                   metavar='PORT', help=f'Port COM Node 1 (default: {DEFAULT_N1_PORT})')
    p.add_argument('--n2',      default=DEFAULT_N2_PORT,
                   metavar='PORT', help=f'Port COM Node 2 (default: {DEFAULT_N2_PORT})')
    p.add_argument('--baud',    default=DEFAULT_BAUD, type=int,
                   metavar='N',    help=f'Baud rate serial (default: {DEFAULT_BAUD})')
    p.add_argument('--out',     default=None,
                   metavar='FILE', help='Nama file CSV output (default: auto timestamp)')
    return p, p.parse_args()

def main():
    p, args = parse_args()
    no_args = len(sys.argv) == 1

    console = Console()

    if no_args:
        console.print(BANNER)
        console.print(
            f"[dim]Tidak ada argumen -> menggunakan default: "
            f"Gateway=[yellow]{args.gateway}[/] "
            f"N1=[green]{args.n1}[/] "
            f"N2=[magenta]{args.n2}[/] "
            f"Baud=[white]{args.baud}[/][/dim]\n"
        )

    shared = SharedState()
    shared.gw.port = args.gateway
    shared.n1.port = args.n1
    shared.n2.port = args.n2

    ts_str   = shared.session_start.strftime("%Y%m%d_%H%M%S")
    csv_path = args.out or f"lora_session_{ts_str}.csv"

    if not no_args:
        console.print("\n[bold cyan]LoRa Monitor Dashboard[/]")
        console.print(f"  Gateway : [yellow]{args.gateway}[/]")
        console.print(f"  Node 1  : [green]{args.n1}[/]")
        console.print(f"  Node 2  : [magenta]{args.n2}[/]")
        console.print(f"  Baud    : [white]{args.baud}[/]")

    console.print(f"  CSV     : [dim]{csv_path}[/]")
    console.print("\nTekan [bold]Enter[/] untuk mulai dashboard, [bold]Ctrl+C[/] untuk batal...\n")
    try:
        input()
    except KeyboardInterrupt:
        return

    threads = [
        threading.Thread(target=reader_thread,
            args=(args.gateway, args.baud, "GW", shared, "GW"),
            daemon=True, name="reader-gateway"),
        threading.Thread(target=reader_thread,
            args=(args.n1, args.baud, "N1", shared, "NODE"),
            daemon=True, name="reader-n1"),
        threading.Thread(target=reader_thread,
            args=(args.n2, args.baud, "N2", shared, "NODE"),
            daemon=True, name="reader-n2"),
        threading.Thread(target=csv_writer_thread,
            args=(shared, csv_path),
            daemon=True, name="csv-writer"),
    ]
    for t in threads:
        t.start()

    try:
        with Live(build_layout(shared, csv_path),
                  console=console,
                  refresh_per_second=REFRESH_HZ,
                  screen=True) as live:
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
