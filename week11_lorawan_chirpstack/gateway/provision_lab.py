#!/usr/bin/env python3
"""Modul 11 - daftarkan gateway, device profile, aplikasi, dan kedua node ke
ChirpStack lewat REST API. Aman dijalankan berulang (yang sudah ada dilewati).

PRAKTIKAN TIDAK MEMAKAI SKRIP INI. Pendaftaran perangkat adalah inti EXP-01 dan
dikerjakan sendiri lewat web UI -- di situlah terlihat bahwa DevEUI/AppKey di
server harus cocok dengan yang tertanam di firmware. Skrip ini untuk asisten:
menyiapkan ulang lab dengan cepat, atau memastikan isi server memang sama
persis dengan yang tertulis di README ketika ada yang tidak jalan.

    # buat token dulu (sekali saja):
    cd ~/chirpstack-docker
    sudo docker compose exec chirpstack chirpstack -c /etc/chirpstack \
        create-api-key --name praktikum

    python3 provision_lab.py --token eyJ0eXAi... --gateway-id 2CCF67FFFE53AC11

Nilai DevEUI dan AppKey di bawah HARUS sama dengan src/node/lorawan_keys.h.
"""

import argparse
import json
import sys
import urllib.error
import urllib.request

# Sama persis dengan src/node/lorawan_keys.h (di sana ditulis terbalik untuk
# DevEUI, di sini ditulis seperti yang tampil di layar ChirpStack).
NODES = [
    {"name": "node1-ruangan-1", "dev_eui": "0011223344556601",
     "app_key": "00112233445566778899aabbccddeef1",
     "desc": "Arduino Uno + SX1276 - Ruangan 1 (suhu 25-30 C, RH 60-75 %)"},
    {"name": "node2-ruangan-2", "dev_eui": "0011223344556602",
     "app_key": "00112233445566778899aabbccddeef2",
     "desc": "Arduino Uno + SX1276 - Ruangan 2 (suhu 28-35 C, RH 40-65 %)"},
]

# Codec opsional: mengubah "T=27.4,H=68" menjadi objek JSON, supaya kolom
# "Object" di ChirpStack menampilkan angka yang sudah terbaca. Payload di
# udara tetap ASCII polos -- codec ini murni pekerjaan server.
CODEC_JS = """function decodeUplink(input) {
  var s = String.fromCharCode.apply(null, input.bytes);
  var m = s.match(/T=(-?\\d+(?:\\.\\d+)?),H=(\\d+(?:\\.\\d+)?)/);
  if (!m) { return { data: { raw: s } }; }
  return { data: { temperature: parseFloat(m[1]), humidity: parseFloat(m[2]), raw: s } };
}

function encodeDownlink(input) {
  return { bytes: [] };
}
"""


class API:
    def __init__(self, base, token):
        self.base = base.rstrip("/")
        self.token = token

    def call(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        req.add_header("Grpc-Metadata-Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                raw = r.read().decode()
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode()
            if e.code == 409 or "already exists" in detail:
                return None            # sudah ada -- dianggap sukses
            raise SystemExit(f"{method} {path} gagal ({e.code}): {detail}")
        except urllib.error.URLError as e:
            raise SystemExit(f"Tidak bisa menghubungi {self.base}: {e.reason}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--token", required=True, help="API key ChirpStack")
    ap.add_argument("--gateway-id", required=True,
                    help="EUI gateway, seperti yang dicetak single_chan_pkt_fwd.py")
    ap.add_argument("--api", default="http://127.0.0.1:8090",
                    help="alamat chirpstack-rest-api (bawaan: http://127.0.0.1:8090)")
    ap.add_argument("--app-name", default="praktikum-wsn")
    ap.add_argument("--profile-name", default="uno-sx1276-eu433-otaa")
    args = ap.parse_args()

    api = API(args.api, args.token)

    tenants = api.call("GET", "/api/tenants?limit=10")
    if not tenants or not tenants.get("result"):
        raise SystemExit("Tidak ada tenant di ChirpStack -- server baru dipasang?")
    tenant_id = tenants["result"][0]["id"]
    print(f"Tenant           : {tenants['result'][0]['name']} ({tenant_id})")

    gw_id = args.gateway_id.lower()
    api.call("POST", "/api/gateways", {"gateway": {
        "gatewayId": gw_id,
        "name": "single-chan-pi5",
        "description": "Raspberry Pi 5 + Dragino LoRa GPS HAT (SX1276), 433.175 MHz SF7",
        "tenantId": tenant_id,
        "statsInterval": 30,
        "location": {"latitude": 0, "longitude": 0, "altitude": 0},
    }})
    print(f"Gateway          : {gw_id}")

    # Device profile: EU433, LoRaWAN 1.0.3, OTAA, ADR dimatikan (kanal tunggal)
    profiles = api.call("GET", f"/api/device-profiles?limit=100&tenantId={tenant_id}")
    prof_id = next((p["id"] for p in profiles.get("result", [])
                    if p["name"] == args.profile_name), None)
    if prof_id is None:
        res = api.call("POST", "/api/device-profiles", {"deviceProfile": {
            "tenantId": tenant_id,
            "name": args.profile_name,
            "description": "Profil Modul 11 - kanal tunggal 433.175 MHz SF7BW125",
            "region": "EU433",
            "macVersion": "LORAWAN_1_0_3",
            "regParamsRevision": "A",
            "adrAlgorithmId": "default",
            "supportsOtaa": True,
            "uplinkInterval": 60,
            "deviceStatusReqInterval": 1,
            "flushQueueOnActivate": True,
            "payloadCodecRuntime": "JS",
            "payloadCodecScript": CODEC_JS,
        }})
        prof_id = res["id"]
    print(f"Device profile   : {args.profile_name} ({prof_id})")

    apps = api.call("GET", f"/api/applications?limit=100&tenantId={tenant_id}")
    app_id = next((a["id"] for a in apps.get("result", [])
                   if a["name"] == args.app_name), None)
    if app_id is None:
        res = api.call("POST", "/api/applications", {"application": {
            "tenantId": tenant_id,
            "name": args.app_name,
            "description": "Praktikum WSN/IoT - LoRaWAN Modul 11",
        }})
        app_id = res["id"]
    print(f"Application      : {args.app_name} ({app_id})")

    for n in NODES:
        api.call("POST", "/api/devices", {"device": {
            "devEui": n["dev_eui"],
            "name": n["name"],
            "description": n["desc"],
            "applicationId": app_id,
            "deviceProfileId": prof_id,
            "isDisabled": False,
            "skipFcntCheck": False,
        }})
        # LoRaWAN 1.0.x: AppKey disimpan ChirpStack di field nwkKey.
        api.call("POST", f"/api/devices/{n['dev_eui']}/keys", {"deviceKeys": {
            "devEui": n["dev_eui"],
            "nwkKey": n["app_key"],
        }})
        print(f"Device           : {n['name']}  DevEUI={n['dev_eui']}")

    print("\nSelesai. Nyalakan gateway lalu kedua node, dan pantau di web UI:")
    print("  Applications > " + args.app_name + " > Devices > <node> > Events")


if __name__ == "__main__":
    main()
