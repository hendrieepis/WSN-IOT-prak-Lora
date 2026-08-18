#!/usr/bin/env python3
"""
LoRa Master-Slave Monitor Dashboard
====================================
Full-terminal live dashboard untuk monitoring komunikasi
LoRa Master <-> Slave 1 <-> Slave 2

Kompatibel: Windows (PowerShell / Windows Terminal) & Linux/Mac

Kebutuhan:
  pip install pyserial rich

Cara pakai:
  python lora_monitor.py                               # default COM8/9/10 @ 9600
  python lora_monitor.py --master COM3 --s1 COM4 --s2 COM5 --baud 115200
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
DEFAULT_MASTER_PORT = "COM3"
DEFAULT_S1_PORT     = "COM4"
DEFAULT_S2_PORT     = "COM5"
DEFAULT_BAUD        = 115200
LOG_LINES           = 18
REFRESH_HZ          = 4
FAIL_STREAK_WARN    = 3
CYCLE_SLOW_MS       = 900

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
class MasterState:
    port:           str  = DEFAULT_MASTER_PORT
    connected:      bool = False
    cycle:          int  = 0
    last_cycle_ms:  int  = 0
    s1_ok:          int  = 0
    s1_fail:        int  = 0
    s1_data:        int  = 0
    s2_ok:          int  = 0
    s2_fail:        int  = 0
    s2_data:        int  = 0
    s1_fail_streak: int  = 0
    s2_fail_streak: int  = 0
    last_s1_data:   int  = 0
    last_s2_data:   int  = 0
    raw_log: deque = field(default_factory=lambda: deque(maxlen=200))

@dataclass
class SlaveState:
    name:         str  = ""
    port:         str  = ""
    connected:    bool = False
    rx_count:     int  = 0
    data_counter: int  = 0
    raw_log: deque = field(default_factory=lambda: deque(maxlen=200))

class SharedState:
    def __init__(self):
        self.lock          = threading.Lock()
        self.master        = MasterState()
        self.s1            = SlaveState("SLAVE 1", DEFAULT_S1_PORT)
        self.s2            = SlaveState("SLAVE 2", DEFAULT_S2_PORT)
        self.anomalies     = deque(maxlen=60)
        self.csv_queue     = queue.Queue()
        self.running       = True
        self.session_start = datetime.now()

# ──────────────────────────────────────────────
# PARSERS
# ──────────────────────────────────────────────

def parse_master_line(line: str, st: MasterState, anomalies: deque):
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]

    m = re.search(r'CYCLE\s+(\d+)', line)
    if m:
        st.cycle = int(m.group(1))

    m = re.search(r'\[RX\]\s+S1:DATA:(\d+)', line)
    if m:
        v = int(m.group(1))
        if st.last_s1_data > 0 and v > st.last_s1_data + 1:
            anomalies.append(Anomaly(ts, "S1", "COUNTER_JUMP",
                f"S1:DATA loncat {st.last_s1_data} -> {v} (skip {v - st.last_s1_data - 1})"))
        st.last_s1_data   = v
        st.s1_data        = v
        st.s1_fail_streak = 0

    m = re.search(r'\[RX\]\s+S2:DATA:(\d+)', line)
    if m:
        v = int(m.group(1))
        if st.last_s2_data > 0 and v > st.last_s2_data + 1:
            anomalies.append(Anomaly(ts, "S2", "COUNTER_JUMP",
                f"S2:DATA loncat {st.last_s2_data} -> {v} (skip {v - st.last_s2_data - 1})"))
        st.last_s2_data   = v
        st.s2_data        = v
        st.s2_fail_streak = 0

    m = re.search(r'\[FAIL\]\s+Slave\s+(\d+)', line)
    if m:
        n = int(m.group(1))
        if n == 1:
            st.s1_fail        += 1
            st.s1_fail_streak += 1
            if st.s1_fail_streak >= FAIL_STREAK_WARN:
                anomalies.append(Anomaly(ts, "S1", "FAIL_STREAK",
                    f"S1 FAIL beruntun {st.s1_fail_streak}x"))
        else:
            st.s2_fail        += 1
            st.s2_fail_streak += 1
            if st.s2_fail_streak >= FAIL_STREAK_WARN:
                anomalies.append(Anomaly(ts, "S2", "FAIL_STREAK",
                    f"S2 FAIL beruntun {st.s2_fail_streak}x"))

    m = re.search(r'S1:\s*OK=(\d+)\s*\|\s*FAIL=(\d+)', line)
    if m:
        st.s1_ok = int(m.group(1)); st.s1_fail = int(m.group(2))

    m = re.search(r'S2:\s*OK=(\d+)\s*\|\s*FAIL=(\d+)', line)
    if m:
        st.s2_ok = int(m.group(1)); st.s2_fail = int(m.group(2))

    m = re.search(r'Durasi\s+siklus:\s*(\d+)', line)
    if m:
        ms = int(m.group(1))
        st.last_cycle_ms = ms
        if ms > CYCLE_SLOW_MS:
            anomalies.append(Anomaly(ts, "MASTER", "SLOW_CYCLE",
                f"Cycle {st.cycle} lambat: {ms}ms (> {CYCLE_SLOW_MS}ms)"))

def parse_slave_line(line: str, st: SlaveState):
    m = re.search(r'RX#:\s*(\d+)', line)
    if m:
        st.rx_count = int(m.group(1))
    m = re.search(r'\[TX\]\s+S\d+:DATA:(\d+)', line)
    if m:
        st.data_counter = int(m.group(1))

# ──────────────────────────────────────────────
# READER THREADS
# ──────────────────────────────────────────────

def reader_thread(port: str, baud: int, node_key: str,
                  shared: SharedState, is_master: bool):
    if is_master:
        state = shared.master
    elif node_key == "S1":
        state = shared.s1
    else:
        state = shared.s2

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
                            if is_master:
                                parse_master_line(line, state, shared.anomalies)
                            else:
                                parse_slave_line(line, state)
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

def log_line_style(line: str, is_master: bool) -> str:
    if '[FAIL]'   in line: return "red"
    if '[RX]'     in line: return "green" if is_master else "yellow"
    if '[TX]'     in line: return "yellow" if is_master else "green"
    if 'CYCLE'    in line: return "bold cyan"
    if '[IGNORE]' in line: return "dim"
    return "dim white"

def build_master_panel(st: MasterState) -> Panel:
    t = Text()
    t.append("\n")
    t.append(conn_badge(st.connected, st.port))
    t.append("\n\n")
    t.append("  Cycle        : ", style="dim")
    t.append(f"{st.cycle}\n", style="bold white")

    ms = st.last_cycle_ms
    t.append("  Dur. Cycle   : ", style="dim")
    t.append(f"{ms} ms", style="bold red" if ms > CYCLE_SLOW_MS else "bold green")
    if ms > CYCLE_SLOW_MS:
        t.append("  LAMBAT!", style="bold red")
    t.append("\n\n")

    # Slave 1 stats
    s1_tot = st.s1_ok + st.s1_fail
    s1_pct = (st.s1_ok / s1_tot * 100) if s1_tot else 0.0
    t.append("  Slave 1\n", style="bold cyan")
    t.append("  OK    : ", style="dim"); t.append(f"{st.s1_ok:>6}\n", style="bold green")
    t.append("  FAIL  : ", style="dim"); t.append(f"{st.s1_fail:>6}\n",
              style="bold red" if st.s1_fail else "dim")
    t.append("  Rate  : ", style="dim"); t.append(f"{s1_pct:>6.2f}%\n",
              style=pct_style(st.s1_ok, s1_tot))
    t.append("  Data  : ", style="dim"); t.append(f"{st.s1_data:>6}\n\n", style="white")

    # Slave 2 stats
    s2_tot = st.s2_ok + st.s2_fail
    s2_pct = (st.s2_ok / s2_tot * 100) if s2_tot else 0.0
    t.append("  Slave 2\n", style="bold cyan")
    t.append("  OK    : ", style="dim"); t.append(f"{st.s2_ok:>6}\n", style="bold green")
    t.append("  FAIL  : ", style="dim"); t.append(f"{st.s2_fail:>6}\n",
              style="bold red" if st.s2_fail else "dim")
    t.append("  Rate  : ", style="dim"); t.append(f"{s2_pct:>6.2f}%\n",
              style=pct_style(st.s2_ok, s2_tot))
    t.append("  Data  : ", style="dim"); t.append(f"{st.s2_data:>6}\n\n", style="white")

    t.append("  Raw Log\n", style="bold dim")
    t.append("  " + "─" * 30 + "\n", style="dim")
    for ts, line in list(st.raw_log)[-LOG_LINES:]:
        style = log_line_style(line, True)
        t.append(f"  {ts[-8:]}  {line[:36]}\n", style=style)

    return Panel(t, title="[bold cyan]MASTER[/]",
                 border_style="cyan", box=box.ROUNDED)

def build_slave_panel(st: SlaveState, label: str, color: str) -> Panel:
    t = Text()
    t.append("\n")
    t.append(conn_badge(st.connected, st.port))
    t.append("\n\n")
    t.append("  RX Count   : ", style="dim"); t.append(f"{st.rx_count:>6}\n", style="bold white")
    t.append("  TX Counter : ", style="dim"); t.append(f"{st.data_counter:>6}\n\n", style="bold green")

    t.append("  Raw Log\n", style="bold dim")
    t.append("  " + "─" * 30 + "\n", style="dim")
    for ts, line in list(st.raw_log)[-LOG_LINES:]:
        style = log_line_style(line, False)
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
        'COUNTER_JUMP': "bold yellow",
        'FAIL_STREAK':  "bold red",
        'SLOW_CYCLE':   "bold white on red",
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
        # snapshot biar tidak hold lock saat render
        ms = MasterState(
            port=shared.master.port, connected=shared.master.connected,
            cycle=shared.master.cycle, last_cycle_ms=shared.master.last_cycle_ms,
            s1_ok=shared.master.s1_ok, s1_fail=shared.master.s1_fail,
            s1_data=shared.master.s1_data,
            s2_ok=shared.master.s2_ok, s2_fail=shared.master.s2_fail,
            s2_data=shared.master.s2_data,
            raw_log=deque(shared.master.raw_log),
        )
        s1 = SlaveState(
            name=shared.s1.name, port=shared.s1.port,
            connected=shared.s1.connected,
            rx_count=shared.s1.rx_count, data_counter=shared.s1.data_counter,
            raw_log=deque(shared.s1.raw_log),
        )
        s2 = SlaveState(
            name=shared.s2.name, port=shared.s2.port,
            connected=shared.s2.connected,
            rx_count=shared.s2.rx_count, data_counter=shared.s2.data_counter,
            raw_log=deque(shared.s2.raw_log),
        )
        anom  = deque(shared.anomalies)
        t_start = shared.session_start

    node_row = Columns([
        build_master_panel(ms),
        build_slave_panel(s1, "SLAVE 1", "green"),
        build_slave_panel(s2, "SLAVE 2", "magenta"),
    ], equal=True, expand=True)

    return Group(node_row, build_anomaly_panel(anom, t_start, csv_path))

# ──────────────────────────────────────────────
# ENTRY POINT
# ──────────────────────────────────────────────

BANNER = """\
╔══════════════════════════════════════════════════════════════════════╗
║           LoRa Master-Slave Monitor — Evaluasi Praktikum            ║
║      Dragino LoRa Shield v1.2 · SX1276 · Arduino Uno · 920 MHz     ║
╚══════════════════════════════════════════════════════════════════════╝

  Tool ini membaca data serial dari 3 node LoRa secara bersamaan dan
  menampilkan dashboard real-time: statistik OK/FAIL per slave, durasi
  cycle, RSSI/SNR, deteksi anomali, serta logging CSV otomatis untuk
  analisis data penelitian.

  PENGGUNAAN:
    python lora_monitor.py [opsi...]

  OPSI:
    --master PORT   Port COM untuk node Master      (default: {master})
    --s1     PORT   Port COM untuk Slave 1          (default: {s1})
    --s2     PORT   Port COM untuk Slave 2          (default: {s2})
    --baud   N      Baud rate serial semua port     (default: {baud})
    --out    FILE   Nama file CSV output            (default: lora_session_YYYYMMDD_HHMMSS.csv)
    -h / --help     Tampilkan pesan bantuan ini

  CONTOH:
    python lora_monitor.py
        → Jalankan dengan port & baud rate default

    python lora_monitor.py --master COM3 --s1 COM4 --s2 COM5
        → Tentukan port secara eksplisit

    python lora_monitor.py --out data_jarak_10m.csv
        → Simpan log ke nama file tertentu

    python lora_monitor.py --master COM3 --s1 COM4 --s2 COM5 --baud 115200 --out hasil_uji.csv
        → Konfigurasi penuh untuk satu sesi eksperimen

  KONTROL DASHBOARD:
    Ctrl+C          Hentikan monitoring & simpan CSV

  CATATAN:
    • Pastikan semua board sudah di-upload firmware dengan baud {baud}
    • Upload Slave dulu, baru Master, sebelum menjalankan tool ini
    • File CSV tersimpan otomatis saat Ctrl+C ditekan
""".format(
    master=DEFAULT_MASTER_PORT,
    s1=DEFAULT_S1_PORT,
    s2=DEFAULT_S2_PORT,
    baud=DEFAULT_BAUD,
)

def parse_args():
    p = argparse.ArgumentParser(
        description="LoRa Master-Slave Monitor Dashboard — tool evaluasi praktikum LoRa.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Contoh penggunaan:\n"
            f"  python lora_monitor.py\n"
            f"  python lora_monitor.py --master COM3 --s1 COM4 --s2 COM5\n"
            f"  python lora_monitor.py --out data_eksperimen.csv\n"
            f"  python lora_monitor.py --master COM3 --s1 COM4 --s2 COM5 --baud 115200 --out hasil.csv\n"
        ),
    )
    p.add_argument('--master', default=DEFAULT_MASTER_PORT,
                   metavar='PORT', help=f'Port COM node Master (default: {DEFAULT_MASTER_PORT})')
    p.add_argument('--s1',    default=DEFAULT_S1_PORT,
                   metavar='PORT', help=f'Port COM Slave 1 (default: {DEFAULT_S1_PORT})')
    p.add_argument('--s2',    default=DEFAULT_S2_PORT,
                   metavar='PORT', help=f'Port COM Slave 2 (default: {DEFAULT_S2_PORT})')
    p.add_argument('--baud',  default=DEFAULT_BAUD, type=int,
                   metavar='N',    help=f'Baud rate serial (default: {DEFAULT_BAUD})')
    p.add_argument('--out',   default=None,
                   metavar='FILE', help='Nama file CSV output (default: auto timestamp)')
    return p, p.parse_args()

def main():
    p, args = parse_args()
    no_args = len(sys.argv) == 1

    console = Console()

    if no_args:
        console.print(BANNER)
        console.print(
            f"[dim]Tidak ada argumen → menggunakan default: "
            f"Master=[yellow]{args.master}[/] "
            f"S1=[green]{args.s1}[/] "
            f"S2=[magenta]{args.s2}[/] "
            f"Baud=[white]{args.baud}[/][/dim]\n"
        )

    shared = SharedState()
    shared.master.port = args.master
    shared.s1.port     = args.s1
    shared.s2.port     = args.s2

    ts_str   = shared.session_start.strftime("%Y%m%d_%H%M%S")
    csv_path = args.out or f"lora_session_{ts_str}.csv"

    if not no_args:
        console.print("\n[bold cyan]LoRa Monitor Dashboard[/]")
        console.print(f"  Master : [yellow]{args.master}[/]")
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
        threading.Thread(target=reader_thread,
            args=(args.master, args.baud, "MASTER", shared, True),
            daemon=True, name="reader-master"),
        threading.Thread(target=reader_thread,
            args=(args.s1, args.baud, "S1", shared, False),
            daemon=True, name="reader-s1"),
        threading.Thread(target=reader_thread,
            args=(args.s2, args.baud, "S2", shared, False),
            daemon=True, name="reader-s2"),
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
