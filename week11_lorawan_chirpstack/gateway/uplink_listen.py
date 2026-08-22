#!/usr/bin/env python3
"""Modul 11 - dengarkan uplink dari ChirpStack lewat MQTT, tanpa membuka web UI.

Web UI ChirpStack sudah menampilkan semua ini, tetapi hanya satu perangkat per
layar. Skrip ini berlangganan seluruh aplikasi sekaligus, jadi uplink Node 1
dan Node 2 terlihat berselang-seling di satu terminal -- sekaligus memperlihatkan
bahwa integrasi MQTT-lah pintu keluar data LoRaWAN menuju aplikasi sungguhan.
Setiap baris juga dicatat ke CSV, seperti modul-modul sebelumnya.

    python3 uplink_listen.py                      # broker di Pi ini juga
    python3 uplink_listen.py --host 192.168.1.45
    python3 uplink_listen.py --csv sesi_praktikum.csv

Topik yang dilanggan (ChirpStack v4):
    application/+/device/+/event/up

Prasyarat: pip3 install paho-mqtt
"""

import argparse
import base64
import csv
import json
import re
import sys
from datetime import datetime

try:
    import paho.mqtt.client as mqtt
except ImportError:
    sys.exit("paho-mqtt belum terpasang:  pip3 install paho-mqtt")

# "T=27.4,H=68" -- format payload Modul 11, sengaja ASCII polos
POLA = re.compile(r"T=(-?\d+(?:\.\d+)?),H=(\d+(?:\.\d+)?)")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1", help="broker MQTT (bawaan: 127.0.0.1)")
    ap.add_argument("--port", type=int, default=1883)
    ap.add_argument("--csv", default=None,
                    help="berkas CSV keluaran (bawaan: lorawan_<tanggal>.csv)")
    args = ap.parse_args()

    nama_csv = args.csv or f"lorawan_{datetime.now():%Y%m%d_%H%M%S}.csv"
    berkas = open(nama_csv, "w", newline="")
    tulis = csv.writer(berkas)
    tulis.writerow(["waktu", "device", "dev_eui", "fcnt", "payload",
                    "suhu_c", "kelembapan_pct", "rssi_dbm", "snr_db"])

    print(f"Broker : {args.host}:{args.port}")
    print(f"Topik  : application/+/device/+/event/up")
    print(f"CSV    : {nama_csv}")
    print("Ctrl-C untuk berhenti.\n")
    print(f"{'waktu':8}  {'device':10} {'FCnt':>5}  {'payload':14} "
          f"{'suhu':>6} {'RH':>5}  {'RSSI':>6} {'SNR':>6}")
    print("-" * 72)

    def on_connect(client, userdata, flags, rc, properties=None):
        if rc != 0:
            print(f"Gagal terhubung ke broker (rc={rc})")
            return
        client.subscribe("application/+/device/+/event/up")

    def on_message(client, userdata, msg):
        try:
            ev = json.loads(msg.payload.decode())
        except ValueError:
            return

        info = ev.get("deviceInfo", {})
        nama = info.get("deviceName", "?")
        eui = info.get("devEui", "?")
        fcnt = ev.get("fCnt", 0)
        raw = base64.b64decode(ev.get("data", "")) if ev.get("data") else b""
        teks = raw.decode("ascii", errors="replace")

        rx = (ev.get("rxInfo") or [{}])[0]
        rssi = rx.get("rssi", 0)
        snr = rx.get("snr", 0.0)

        cocok = POLA.search(teks)
        suhu = cocok.group(1) if cocok else ""
        rh = cocok.group(2) if cocok else ""

        jam = datetime.now().strftime("%H:%M:%S")
        print(f"{jam}  {nama:10} {fcnt:5d}  {teks:14} "
              f"{suhu:>5}C {rh:>4}%  {rssi:5} dBm {snr:5.1f} dB")

        tulis.writerow([datetime.now().isoformat(timespec="seconds"), nama, eui,
                        fcnt, teks, suhu, rh, rssi, snr])
        berkas.flush()

    # paho-mqtt 2.x mewajibkan versi API callback disebutkan; 1.x belum mengenalnya.
    try:
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    except AttributeError:
        client = mqtt.Client()

    client.on_connect = on_connect
    client.on_message = on_message

    try:
        client.connect(args.host, args.port, 60)
    except OSError as e:
        sys.exit(f"Tidak bisa menghubungi broker {args.host}:{args.port} -- {e}\n"
                 f"Pastikan ChirpStack sudah berjalan (docker compose ps).")

    try:
        client.loop_forever()
    except KeyboardInterrupt:
        print(f"\n\nDihentikan. Log tersimpan di {nama_csv}")
    finally:
        berkas.close()


if __name__ == "__main__":
    main()
