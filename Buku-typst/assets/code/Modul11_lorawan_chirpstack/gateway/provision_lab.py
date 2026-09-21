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
    python3 provision_lab.py --token ... --gateway-id ... --kelompok 2

DevEUI dan AppKey dihitung dari nomor kelompok dengan aturan yang sama persis
seperti src/node/lorawan_keys.h -- ubah salah satunya saja dan join akan gagal
dengan gejala paling menyesatkan: paket sampai, tetapi perangkat tidak pernah
ter-aktivasi.

Kelompok 1 memakai nama aplikasi dan perangkat tanpa akhiran, sama seperti
contoh di README; kelompok 2 dan 3 diberi akhiran -k2 / -k3 supaya ketiganya
bisa hidup berdampingan di satu server bila network server dipakai bersama.
"""

import argparse
import json
import sys
import urllib.error
import urllib.request

# Aturan penomoran yang sama dengan src/node/lorawan_keys.h:
#   DevEUI : 0011223344 55 KK NN   KK = 66/77/88 untuk kelompok 1/2/3
#   AppKey : KK 112233445566778899AABBCCDDEE FN   KK = 00/01/02, FN = F1/F2
RUANGAN = {
    1: ("Ruangan 1", "suhu 25-30 C, RH 60-75 %"),
    2: ("Ruangan 2", "suhu 28-35 C, RH 40-65 %"),
}
KANAL_HZ = {1: 433175000, 2: 433375000, 3: 433575000}
KANAL_KELOMPOK = {k: f"{hz / 1e6:.3f} MHz" for k, hz in KANAL_HZ.items()}


def daftar_node(kelompok):
    """Susun DevEUI, AppKey, dan nama untuk kedua node satu kelompok."""
    awalan = "" if kelompok == 1 else f"k{kelompok}-"
    hasil = []
    for node in (1, 2):
        ruang, rentang = RUANGAN[node]
        hasil.append({
            "name": f"{awalan}node{node}-{ruang.lower().replace(' ', '-')}",
            "dev_eui": f"001122334455{0x66 + (kelompok - 1) * 0x11:02x}{node:02x}",
            "app_key": f"{kelompok - 1:02x}112233445566778899aabbccddeef{node}",
            "desc": f"Arduino Uno + SX1276 - {ruang} ({rentang}), "
                    f"kelompok {kelompok}, {KANAL_KELOMPOK[kelompok]}",
        })
    return hasil


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
            # ChirpStack menolak objek kembar dengan beberapa cara berbeda:
            # 409, pesan "already exists", atau -- untuk gateway dengan EUI yang
            # sudah terdaftar -- 500 berisi pelanggaran unique constraint dari
            # PostgreSQL. Ketiganya berarti hal yang sama bagi skrip ini:
            # objeknya sudah ada, lanjut saja.
            if (e.code == 409 or "already exists" in detail
                    or "duplicate key" in detail):
                print(f"   (sudah ada, dilewati: {method} {path.split('?')[0]})")
                return None
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
    ap.add_argument("--kelompok", type=int, default=1, choices=(1, 2, 3),
                    help="nomor kelompok: menentukan DevEUI, AppKey, dan kanal "
                         "(bawaan: 1). HARUS sama dengan -DKELOMPOK di platformio.ini")
    ap.add_argument("--app-name", default=None,
                    help="nama aplikasi (bawaan: praktikum-wsn untuk kelompok 1, "
                         "praktikum-wsn-k<n> untuk kelompok lain)")
    ap.add_argument("--profile-name", default="uno-sx1276-eu433-otaa")
    args = ap.parse_args()

    if args.app_name is None:
        args.app_name = ("praktikum-wsn" if args.kelompok == 1
                         else f"praktikum-wsn-k{args.kelompok}")
    nodes = daftar_node(args.kelompok)

    api = API(args.api, args.token)
    print(f"Kelompok         : {args.kelompok}  (kanal {KANAL_KELOMPOK[args.kelompok]})")

    tenants = api.call("GET", "/api/tenants?limit=10")
    if not tenants or not tenants.get("result"):
        raise SystemExit("Tidak ada tenant di ChirpStack -- server baru dipasang?")
    tenant_id = tenants["result"][0]["id"]
    print(f"Tenant           : {tenants['result'][0]['name']} ({tenant_id})")

    gw_id = args.gateway_id.lower()
    api.call("POST", "/api/gateways", {"gateway": {
        "gatewayId": gw_id,
        "name": f"single-chan-pi5-k{args.kelompok}",
        "description": "Raspberry Pi 5 + Dragino LoRa GPS HAT (SX1276), "
                       f"{KANAL_KELOMPOK[args.kelompok]} SF7 - kelompok {args.kelompok}",
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
            "description": "Profil Modul 11 - kanal tunggal EU433 SF7BW125",
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

    for n in nodes:
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

    print("\nSelesai. Jalankan gateway pada kanal kelompok ini:")
    print(f"  python3 single_chan_pkt_fwd.py --freq {KANAL_HZ[args.kelompok]}")
    print("lalu pantau di web UI:")
    print("  Applications > " + args.app_name + " > Devices > <node> > Events")


if __name__ == "__main__":
    main()
