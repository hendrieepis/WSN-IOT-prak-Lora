#!/usr/bin/env python3
"""Modul 11 - Single Channel LoRaWAN Gateway untuk Raspberry Pi 5 (SX1276).

Menjembatani udara dan ChirpStack: paket LoRa yang tertangkap SX1276 dibungkus
protokol Semtech UDP (GWMP v2) dan dikirim ke chirpstack-gateway-bridge di
port 1700; balasan downlink dari server ditembakkan kembali ke udara tepat
pada jendela RX perangkat.

Driver radionya adalah lanjutan langsung dari Modul06_rpi_lora_python/src/
receiver.py -- register yang sama, gaya yang sama. Yang ditambahkan hanyalah
apa yang membuat sebuah paket LoRa menjadi paket LoRaWAN:

    sync word 0x34   penanda jaringan publik LoRaWAN (0x12 = privat, M01-M10)
    explicit header  panjang payload ikut dikirim, sebab paket LoRaWAN
                     panjangnya berubah-ubah
    IQ terbalik      hanya untuk downlink -- lihat _stage_tx()
    CRC              aktif saat RX (uplink), mati saat TX (downlink)

SATU KANAL, SATU SF. Konsentrator gateway sungguhan (SX1301/SX1302) mendengar
8 kanal x seluruh SF sekaligus. SX1276 hanya punya satu modem: satu frekuensi,
satu spreading factor. Konsekuensinya harus disadari sejak awal -- lihat README
bagian 3: node WAJIB dikunci ke kanal dan DR yang sama dengan skrip ini.

    python3 single_chan_pkt_fwd.py                    # server di Pi ini juga
    python3 single_chan_pkt_fwd.py --server 192.168.1.45
    python3 single_chan_pkt_fwd.py --verbose          # cetak hex tiap paket

Pemetaan pin (Dragino LoRa GPS HAT - WiringPi -> BCM), sama seperti M06/M07:
    LoRa_NSS -> BCM 25    RESET -> BCM 17    DIO0 -> BCM 4

Prasyarat:
    sudo raspi-config           # Interface Options > SPI > Yes, lalu reboot
    pip3 install -r requirements.txt
"""

import argparse
import base64
import json
import os
import random
import select
import signal
import socket
import struct
import sys
import time
from datetime import datetime, timezone

import spidev
import RPi.GPIO as GPIO

# -- Pin (BCM) ----------------------------------------------------------------
NSS_PIN  = 25
RST_PIN  = 17
DIO0_PIN = 4

# -- Parameter radio: HARUS sama dengan node -----------------------------------
FREQUENCY_HZ = 433175000     # kanal 0 rencana EU433
SPREADING_FACTOR = 7         # SF7BW125 = DR5
BANDWIDTH_HZ = 125000
CODING_RATE = 5              # 4/5
TX_POWER_DBM = 17
LORAWAN_SYNC_WORD = 0x34     # jaringan publik. 0x12 dipakai M01-M10 (privat)
PREAMBLE_SYMBOLS = 8         # LoRaWAN mewajibkan 8

# -- Semtech UDP protocol (GWMP) ----------------------------------------------
PROTOCOL_VERSION = 2
PKT_PUSH_DATA = 0x00
PKT_PUSH_ACK  = 0x01
PKT_PULL_DATA = 0x02
PKT_PULL_RESP = 0x03
PKT_PULL_ACK  = 0x04
PKT_TX_ACK    = 0x05

KEEPALIVE_S = 5              # PULL_DATA: menjaga "lubang" NAT tetap terbuka
STAT_INTERVAL_S = 30

# Downlink dijadwalkan dari user space, bukan dari pencacah keras konsentrator.
# STAGE_LEAD_US    : berapa lama sebelum jadwal radio dilepas dari RX untuk
#                    diisi payload (selama itu gateway tuli -- sependek mungkin)
# TX_START_LEAD_US : kompensasi waktu tulis register OP_MODE + ramp-up PLL
STAGE_LEAD_US = 20000
TX_START_LEAD_US = 500

# -- Register SX1276 -----------------------------------------------------------
REG_FIFO                 = 0x00
REG_OP_MODE              = 0x01
REG_FRF_MSB              = 0x06
REG_FRF_MID              = 0x07
REG_FRF_LSB              = 0x08
REG_PA_CONFIG            = 0x09
REG_LNA                  = 0x0C
REG_FIFO_ADDR_PTR        = 0x0D
REG_FIFO_TX_BASE_ADDR    = 0x0E
REG_FIFO_RX_BASE_ADDR    = 0x0F
REG_FIFO_RX_CURRENT_ADDR = 0x10
REG_IRQ_FLAGS_MASK       = 0x11
REG_IRQ_FLAGS            = 0x12
REG_RX_NB_BYTES          = 0x13
REG_PKT_SNR_VALUE        = 0x19
REG_PKT_RSSI_VALUE       = 0x1A
REG_MODEM_CONFIG_1       = 0x1D
REG_MODEM_CONFIG_2       = 0x1E
REG_PREAMBLE_MSB         = 0x20
REG_PREAMBLE_LSB         = 0x21
REG_PAYLOAD_LENGTH       = 0x22
REG_MAX_PAYLOAD_LENGTH   = 0x23
REG_MODEM_CONFIG_3       = 0x26
REG_DETECTION_OPTIMIZE   = 0x31
REG_INVERT_IQ            = 0x33
REG_DETECTION_THRESHOLD  = 0x37
REG_SYNC_WORD            = 0x39
REG_INVERT_IQ2           = 0x3B
REG_DIO_MAPPING_1        = 0x40
REG_VERSION              = 0x42
REG_PA_DAC               = 0x4D

MODE_LONG_RANGE    = 0x80
MODE_SLEEP         = 0x00
MODE_STDBY         = 0x01
MODE_TX            = 0x03
MODE_RX_CONTINUOUS = 0x05

IRQ_RX_TIMEOUT     = 0x80
IRQ_RX_DONE        = 0x40
IRQ_CRC_ERROR      = 0x20
IRQ_TX_DONE        = 0x08

PA_BOOST = 0x80

# Nilai register IQ. Uplink memakai IQ normal, downlink memakai IQ terbalik --
# begitulah LoRaWAN mencegah node saling mendengar sesama node, dan gateway
# mendengar gema sesama gateway.
IQ_NORMAL   = (0x27, 0x1D)
IQ_INVERTED = (0x66, 0x19)

_spi = spidev.SpiDev()

# Kanal RX gateway, diisi lora_begin(). Disimpan tersendiri karena downlink
# boleh memakai frekuensi dan SF yang BERBEDA (RX2 EU433 = 434.665 MHz SF12),
# dan sesudah TX radio harus dikembalikan ke kanal ini.
_rx_freq_hz = FREQUENCY_HZ
_rx_sf = SPREADING_FACTOR


# =============================================================================
# Lapisan SPI - identik dengan M06
# =============================================================================
def _read_reg(addr):
    GPIO.output(NSS_PIN, GPIO.LOW)
    val = _spi.xfer2([addr & 0x7F, 0x00])[1]
    GPIO.output(NSS_PIN, GPIO.HIGH)
    return val


def _write_reg(addr, value):
    GPIO.output(NSS_PIN, GPIO.LOW)
    _spi.xfer2([(addr | 0x80) & 0xFF, value & 0xFF])
    GPIO.output(NSS_PIN, GPIO.HIGH)


def _read_fifo(length):
    """Baca FIFO sekali jalan (burst) -- jauh lebih cepat daripada per byte."""
    GPIO.output(NSS_PIN, GPIO.LOW)
    data = _spi.xfer2([REG_FIFO & 0x7F] + [0x00] * length)[1:]
    GPIO.output(NSS_PIN, GPIO.HIGH)
    return bytes(data)


def _write_fifo(data):
    GPIO.output(NSS_PIN, GPIO.LOW)
    _spi.xfer2([REG_FIFO | 0x80] + list(data))
    GPIO.output(NSS_PIN, GPIO.HIGH)


# =============================================================================
# Konfigurasi radio
# =============================================================================
def _set_mode(mode):
    _write_reg(REG_OP_MODE, MODE_LONG_RANGE | mode)


def _set_frequency(freq_hz):
    frf = int(round(freq_hz / 32e6 * (1 << 19)))
    _write_reg(REG_FRF_MSB, (frf >> 16) & 0xFF)
    _write_reg(REG_FRF_MID, (frf >> 8) & 0xFF)
    _write_reg(REG_FRF_LSB, frf & 0xFF)


def _set_spreading_factor(sf):
    sf = max(6, min(12, int(sf)))
    # SF11/SF12 pada BW125 wajib LowDataRateOptimize supaya simbol tidak melar
    ldro = 0x08 if sf >= 11 else 0x00
    _write_reg(REG_DETECTION_OPTIMIZE, 0xC5 if sf == 6 else 0xC3)
    _write_reg(REG_DETECTION_THRESHOLD, 0x0C if sf == 6 else 0x0A)
    _write_reg(REG_MODEM_CONFIG_3, ldro | 0x04)   # 0x04 = AGC otomatis
    _write_reg(REG_MODEM_CONFIG_2,
               (_read_reg(REG_MODEM_CONFIG_2) & 0x0F) | ((sf << 4) & 0xF0))


def _set_bandwidth(bw_hz):
    table = [7.8e3, 10.4e3, 15.6e3, 20.8e3, 31.25e3, 41.7e3, 62.5e3,
             125e3, 250e3, 500e3]
    idx = min(range(len(table)), key=lambda i: abs(table[i] - bw_hz))
    _write_reg(REG_MODEM_CONFIG_1,
               (_read_reg(REG_MODEM_CONFIG_1) & 0x0F) | (idx << 4))


def _set_coding_rate(denom):
    cr = max(5, min(8, int(denom))) - 4
    _write_reg(REG_MODEM_CONFIG_1,
               (_read_reg(REG_MODEM_CONFIG_1) & 0xF1) | (cr << 1))


def _set_explicit_header():
    """Header eksplisit: panjang payload ikut dikirim di dalam header.

    M01-M10 tidak pernah mempersoalkan ini karena panjang paketnya seragam.
    Paket LoRaWAN panjangnya berubah-ubah (JoinRequest 23 byte, uplink data
    bisa belasan sampai ratusan byte), jadi penerima harus diberi tahu.
    """
    _write_reg(REG_MODEM_CONFIG_1, _read_reg(REG_MODEM_CONFIG_1) & 0xFE)


def _set_crc(enabled):
    cfg = _read_reg(REG_MODEM_CONFIG_2)
    _write_reg(REG_MODEM_CONFIG_2, (cfg | 0x04) if enabled else (cfg & ~0x04))


def _set_invert_iq(inverted):
    reg33, reg3b = IQ_INVERTED if inverted else IQ_NORMAL
    _write_reg(REG_INVERT_IQ, reg33)
    _write_reg(REG_INVERT_IQ2, reg3b)


def _set_tx_power(dbm):
    dbm = max(2, min(17, int(dbm)))
    _write_reg(REG_PA_DAC, 0x84)                      # mode normal (bukan +20 dBm)
    _write_reg(REG_PA_CONFIG, PA_BOOST | (dbm - 2))   # HAT hanya punya PA_BOOST


def lora_begin(freq_hz, sf, bw_hz, cr):
    global _rx_freq_hz, _rx_sf
    _rx_freq_hz, _rx_sf = freq_hz, sf

    GPIO.setwarnings(False)
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(NSS_PIN, GPIO.OUT, initial=GPIO.HIGH)
    GPIO.setup(RST_PIN, GPIO.OUT, initial=GPIO.HIGH)
    GPIO.setup(DIO0_PIN, GPIO.IN)

    _spi.open(0, 0)
    _spi.max_speed_hz = 5_000_000
    _spi.mode = 0b00

    GPIO.output(RST_PIN, GPIO.LOW)
    time.sleep(0.01)
    GPIO.output(RST_PIN, GPIO.HIGH)
    time.sleep(0.01)

    if _read_reg(REG_VERSION) != 0x12:
        return False

    _set_mode(MODE_SLEEP)               # berpindah ke modem LoRa hanya boleh saat SLEEP
    time.sleep(0.01)
    _set_frequency(freq_hz)
    _write_reg(REG_FIFO_TX_BASE_ADDR, 0x00)
    _write_reg(REG_FIFO_RX_BASE_ADDR, 0x00)
    _write_reg(REG_LNA, 0x23)           # LNA gain maksimum + boost
    _write_reg(REG_MAX_PAYLOAD_LENGTH, 0x80)
    _write_reg(REG_SYNC_WORD, LORAWAN_SYNC_WORD)
    _write_reg(REG_PREAMBLE_MSB, 0x00)
    _write_reg(REG_PREAMBLE_LSB, PREAMBLE_SYMBOLS)
    _set_mode(MODE_STDBY)

    _set_bandwidth(bw_hz)
    _set_coding_rate(cr)
    _set_spreading_factor(sf)
    _set_explicit_header()
    _set_tx_power(TX_POWER_DBM)
    return True


def start_rx():
    """Kembali mendengarkan uplink: kanal gateway, IQ normal, CRC, RX continuous.

    Frekuensi dan SF WAJIB ikut dikembalikan, bukan hanya mode. Downlink RX2
    memakai 434.665 MHz SF12, dan bila hanya mode yang diubah, gateway tetap
    mendengarkan di kanal RX2 itu sesudahnya -- tuli terhadap seluruh uplink,
    tanpa satu pun pesan galat. Gejalanya: semua berjalan normal sampai
    downlink RX2 yang pertama, lalu sunyi.
    """
    _set_mode(MODE_STDBY)
    _set_frequency(_rx_freq_hz)
    _set_spreading_factor(_rx_sf)
    _set_bandwidth(BANDWIDTH_HZ)
    _set_coding_rate(CODING_RATE)
    _set_explicit_header()
    _set_crc(True)
    _set_invert_iq(False)
    _write_reg(REG_DIO_MAPPING_1, 0x00)     # DIO0 = RxDone
    _write_reg(REG_IRQ_FLAGS, 0xFF)
    _write_reg(REG_FIFO_ADDR_PTR, 0x00)
    _set_mode(MODE_RX_CONTINUOUS)


def packet_rssi_snr():
    raw_snr = _read_reg(REG_PKT_SNR_VALUE)
    if raw_snr > 127:
        raw_snr -= 256
    snr = raw_snr / 4.0

    rssi = _read_reg(REG_PKT_RSSI_VALUE) - (164 if FREQUENCY_HZ < 868e6 else 157)
    if snr < 0:
        # Di bawah lantai derau, pembacaan register terlalu optimistis;
        # koreksi standar Semtech adalah menambahkan SNR-nya.
        rssi += snr
    return int(round(rssi)), snr


# =============================================================================
# Pembacaan amplop LoRaWAN (TANPA dekripsi)
# =============================================================================
MTYPE_NAMES = {
    0: "JoinRequest", 1: "JoinAccept", 2: "UnconfirmedDataUp",
    3: "UnconfirmedDataDown", 4: "ConfirmedDataUp", 5: "ConfirmedDataDown",
    6: "RFU", 7: "Proprietary",
}


def describe_phy(payload):
    """Ringkas isi header PHY, untuk memperlihatkan apa yang gateway TAHU.

    Gateway LoRaWAN adalah tukang pos: ia membaca amplop (jenis pesan, DevAddr,
    frame counter) tetapi TIDAK memegang AppSKey, sehingga isi payload tetap
    terenkripsi baginya. Inilah bukti praktis pemisahan peran gateway dan
    network server -- lihat README bagian 3.
    """
    if not payload:
        return "kosong"
    mtype = payload[0] >> 5
    name = MTYPE_NAMES.get(mtype, "?")

    if mtype == 0 and len(payload) >= 23:
        # JoinRequest: JoinEUI(8, LSB) DevEUI(8, LSB) DevNonce(2) MIC(4)
        deveui = payload[9:17][::-1].hex().upper()
        devnonce = int.from_bytes(payload[17:19], "little")
        return f"{name} DevEUI={deveui} DevNonce={devnonce}"

    if mtype in (2, 4) and len(payload) >= 12:
        devaddr = payload[1:5][::-1].hex().upper()
        fctrl = payload[5]
        fcnt = int.from_bytes(payload[6:8], "little")
        idx = 8 + (fctrl & 0x0F)          # lewati FOpts bila ada
        fport = payload[idx] if len(payload) > idx + 4 else None
        port_txt = f" FPort={fport}" if fport is not None else ""
        return f"{name} DevAddr={devaddr} FCnt={fcnt}{port_txt} (payload terenkripsi)"

    return f"{name} ({len(payload)} byte)"


# =============================================================================
# Utilitas
# =============================================================================
def micros():
    """Pencacah mikrodetik 32-bit, meniru pencacah keras konsentrator.

    Nilai inilah yang dikirim sebagai 'tmst' dan yang dipakai server untuk
    menentukan kapan downlink harus mengudara (tmst uplink + 1 detik untuk
    RX1 data, + 5 detik untuk JoinAccept).
    """
    return (time.monotonic_ns() // 1000) & 0xFFFFFFFF


def us_until(target):
    """Selisih ke target, memperhitungkan pencacah yang berputar di 2^32."""
    return ((target - micros() + 0x80000000) & 0xFFFFFFFF) - 0x80000000


def datr_to_sf(datr):
    """'SF7BW125' -> 7"""
    try:
        return int(str(datr).upper().split("SF")[1].split("BW")[0])
    except (IndexError, ValueError):
        return SPREADING_FACTOR


def default_gateway_id():
    """EUI-64 dari MAC antarmuka jaringan, cara baku gateway sungguhan.

    MAC 48-bit disisipi FF:FE di tengah: b8:27:eb:12:34:56 -> b827ebfffe123456
    """
    for iface in ("eth0", "wlan0", "end0"):
        path = f"/sys/class/net/{iface}/address"
        if os.path.exists(path):
            with open(path) as f:
                mac = f.read().strip().replace(":", "")
            if len(mac) == 12:
                return (mac[:6] + "fffe" + mac[6:]).lower()
    return "0102030405060708"


def iso_now():
    """Cap waktu untuk rxpk: ISO 8601 'expanded', presisi milidetik."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def stat_time_now():
    """Cap waktu untuk pesan stat -- FORMATNYA BERBEDA dari rxpk, dan ini
    jebakan yang sunyi.

    chirpstack-gateway-bridge mengurai waktu di dalam stat dengan pola lama
    "2006-01-02 15:04:05 MST", bukan ISO 8601 seperti pada rxpk. Bila diberi
    ISO 8601, seluruh pesan stat ditolak dengan "could not handle packet" di
    log bridge -- sementara uplink tetap mengalir normal, sehingga satu-satunya
    gejala yang terlihat adalah gateway yang selamanya tampak OFFLINE di
    ChirpStack meski datanya jelas-jelas masuk.
    """
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S GMT")


def log(pesan):
    """Cetak dengan cap waktu lokal, supaya baris gateway bisa dicocokkan
    dengan Serial Monitor kedua node saat menyusun laporan."""
    print(f"{datetime.now():%H:%M:%S.%f}"[:-3] + f"  {pesan}", flush=True)


# =============================================================================
# Packet forwarder
# =============================================================================
class Forwarder:
    def __init__(self, args):
        self.args = args
        self.gw_id = bytes.fromhex(args.gateway_id)
        self.addr = (args.server, args.port)

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setblocking(False)

        self.last_pull = 0.0
        self.last_stat = 0.0
        self.pending_tx = None      # downlink yang sedang menunggu jadwalnya

        self.rx_nb = self.rx_ok = self.rx_fw = self.dw_nb = self.tx_nb = 0

    # -- UDP ------------------------------------------------------------------
    def _send(self, kind, payload=b"", with_eui=True):
        token = struct.pack("<H", random.getrandbits(16))
        pkt = bytes([PROTOCOL_VERSION]) + token + bytes([kind])
        pkt += (self.gw_id if with_eui else b"") + payload
        try:
            self.sock.sendto(pkt, self.addr)
        except OSError as e:
            log(f"[UDP] gagal kirim: {e}")

    def push_data(self, obj):
        self._send(PKT_PUSH_DATA, json.dumps(obj).encode())

    def pull_data(self):
        self._send(PKT_PULL_DATA)

    def tx_ack(self, token, error="NONE"):
        body = json.dumps({"txpk_ack": {"error": error}}).encode()
        pkt = bytes([PROTOCOL_VERSION]) + token + bytes([PKT_TX_ACK]) + self.gw_id + body
        try:
            self.sock.sendto(pkt, self.addr)
        except OSError:
            pass

    def send_stat(self):
        self.push_data({"stat": {
            "time": stat_time_now(), "lati": 0.0, "long": 0.0, "alti": 0,
            "rxnb": self.rx_nb, "rxok": self.rx_ok, "rxfw": self.rx_fw,
            "ackr": 100.0, "dwnb": self.dw_nb, "txnb": self.tx_nb,
        }})

    # -- Uplink ---------------------------------------------------------------
    def handle_rx(self, tmst):
        irq = _read_reg(REG_IRQ_FLAGS)
        _write_reg(REG_IRQ_FLAGS, 0xFF)
        self.rx_nb += 1

        if irq & IRQ_CRC_ERROR:
            log("[RX] CRC salah - paket dibuang (bukan paket kita, atau tabrakan)")
            return

        length = _read_reg(REG_RX_NB_BYTES)
        _write_reg(REG_FIFO_ADDR_PTR, _read_reg(REG_FIFO_RX_CURRENT_ADDR))
        payload = _read_fifo(length)
        rssi, snr = packet_rssi_snr()
        self.rx_ok += 1

        log(f"[RX] {len(payload):3d} B  RSSI={rssi:4d} dBm  SNR={snr:5.1f} dB  "
            f"tmst={tmst}\n              {describe_phy(payload)}")
        if self.args.verbose:
            print(f"              hex: {payload.hex().upper()}")

        self.push_data({"rxpk": [{
            "time": iso_now(),
            "tmst": tmst,
            "chan": 0,
            "rfch": 0,
            "freq": self.args.freq / 1e6,
            "stat": 1,
            "modu": "LORA",
            "datr": f"SF{self.args.sf}BW{int(BANDWIDTH_HZ / 1000)}",
            "codr": f"4/{CODING_RATE}",
            "rssi": rssi,
            "lsnr": round(snr, 1),
            "size": len(payload),
            "data": base64.b64encode(payload).decode(),
        }]})
        self.rx_fw += 1

    # -- Downlink -------------------------------------------------------------
    def handle_pull_resp(self, token, body):
        try:
            txpk = json.loads(body.decode())["txpk"]
        except (ValueError, KeyError, UnicodeDecodeError) as e:
            log(f"[TX] PULL_RESP tidak terbaca: {e}")
            self.tx_ack(token, "TX_FREQ")
            return

        data = base64.b64decode(txpk["data"])
        imme = txpk.get("imme", False)
        target = (micros() + 2000) & 0xFFFFFFFF if imme else int(txpk.get("tmst", micros())) & 0xFFFFFFFF

        if self.pending_tx is not None:
            log("[TX] masih ada downlink lain menunggu - yang ini ditolak")
            self.tx_ack(token, "COLLISION_PACKET")
            return

        delay_us = us_until(target)
        log(f"[TX] downlink dijadwalkan: {len(data)} B  {txpk.get('freq')} MHz  "
            f"{txpk.get('datr')}  dalam {delay_us / 1000:.0f} ms\n"
            f"              {describe_phy(data)}")

        if delay_us < STAGE_LEAD_US:
            # Terlambat: jendela RX node keburu lewat sebelum radio siap.
            log("[TX] TERLAMBAT - jadwal sudah lewat, downlink dibuang")
            self.tx_ack(token, "TOO_LATE")
            return

        self.pending_tx = {
            "data": data, "target": target, "token": token, "staged": False,
            "freq": int(float(txpk.get("freq", self.args.freq / 1e6)) * 1e6),
            "sf": datr_to_sf(txpk.get("datr", f"SF{self.args.sf}BW125")),
            "ncrc": txpk.get("ncrc", True),
        }

    def _stage_tx(self, tx):
        """Siapkan radio + isi FIFO lebih awal, supaya saat jadwalnya tiba yang
        tersisa hanya satu penulisan register: OP_MODE = TX."""
        _set_mode(MODE_STDBY)
        _write_reg(REG_IRQ_FLAGS, 0xFF)
        _set_frequency(tx["freq"])
        _set_spreading_factor(tx["sf"])
        _set_bandwidth(BANDWIDTH_HZ)
        _set_coding_rate(CODING_RATE)
        _set_explicit_header()
        _set_crc(not tx["ncrc"])       # downlink LoRaWAN tidak memakai CRC PHY
        _set_invert_iq(True)           # WAJIB: node hanya mendengar IQ terbalik
        _write_reg(REG_SYNC_WORD, LORAWAN_SYNC_WORD)
        _write_reg(REG_PREAMBLE_MSB, 0x00)
        _write_reg(REG_PREAMBLE_LSB, PREAMBLE_SYMBOLS)
        _set_tx_power(TX_POWER_DBM)
        _write_reg(REG_FIFO_TX_BASE_ADDR, 0x00)
        _write_reg(REG_FIFO_ADDR_PTR, 0x00)
        _write_fifo(tx["data"])
        _write_reg(REG_PAYLOAD_LENGTH, len(tx["data"]))
        _write_reg(REG_DIO_MAPPING_1, 0x40)   # DIO0 = TxDone
        tx["staged"] = True

    def _fire_tx(self, tx):
        _set_mode(MODE_TX)
        # Dicatat SEBELUM menunggu TxDone: sesudahnya, yang terukur bukan lagi
        # ketepatan jadwal melainkan lama paket mengudara.
        meleset_us = -us_until(tx["target"])
        t0 = time.monotonic()
        while not (_read_reg(REG_IRQ_FLAGS) & IRQ_TX_DONE):
            if time.monotonic() - t0 > 3:
                log("[TX] TxDone tidak pernah datang - radio dikembalikan ke RX")
                break
            time.sleep(0.0002)
        _write_reg(REG_IRQ_FLAGS, 0xFF)

        self.tx_nb += 1
        self.dw_nb += 1
        log(f"[TX] terkirim (meleset {meleset_us / 1000:+.1f} ms dari jadwal)")
        self.tx_ack(tx["token"])
        start_rx()

    # -- Loop utama -----------------------------------------------------------
    def run(self):
        print(f"Gateway EUI : {self.gw_id.hex().upper()}")
        print(f"Server      : {self.args.server}:{self.args.port} (Semtech UDP)")
        print(f"Kanal       : {self.args.freq / 1e6:.3f} MHz  SF{self.args.sf}BW125  CR4/{CODING_RATE}")
        print(f"Sync word   : 0x{LORAWAN_SYNC_WORD:02X} (LoRaWAN publik)")
        print("\nDaftarkan Gateway EUI di atas ke ChirpStack, lalu tunggu uplink.\n"
              "Ctrl-C untuk berhenti.\n")

        start_rx()
        self.pull_data()
        self.last_pull = self.last_stat = time.monotonic()

        while True:
            now = time.monotonic()

            # 1. Uplink dari udara. DIO0 naik saat RxDone; dibaca dengan polling
            #    cepat supaya cap waktunya sedekat mungkin dengan akhir paket.
            if self.pending_tx is None and GPIO.input(DIO0_PIN):
                self.handle_rx(micros())

            # 2. Downlink yang sudah dijadwalkan
            tx = self.pending_tx
            if tx is not None:
                sisa = us_until(tx["target"])
                if not tx["staged"] and sisa <= STAGE_LEAD_US:
                    self._stage_tx(tx)
                elif tx["staged"] and sisa <= TX_START_LEAD_US:
                    self._fire_tx(tx)
                    self.pending_tx = None

            # 3. Balasan dari server
            r, _, _ = select.select([self.sock], [], [], 0)
            if r:
                try:
                    pkt, _ = self.sock.recvfrom(2048)
                except OSError:
                    pkt = b""
                if len(pkt) >= 4:
                    kind = pkt[3]
                    if kind == PKT_PULL_RESP:
                        self.handle_pull_resp(pkt[1:3], pkt[4:])
                    elif kind in (PKT_PUSH_ACK, PKT_PULL_ACK) and self.args.verbose:
                        nama = "PUSH_ACK" if kind == PKT_PUSH_ACK else "PULL_ACK"
                        log(f"[UDP] {nama}")

            # 4. Pemeliharaan
            if now - self.last_pull >= KEEPALIVE_S:
                self.pull_data()
                self.last_pull = now
            if now - self.last_stat >= STAT_INTERVAL_S:
                self.send_stat()
                self.last_stat = now

            time.sleep(0.0002)


def main():
    global FREQUENCY_HZ

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--server", default="127.0.0.1",
                    help="alamat chirpstack-gateway-bridge (bawaan: 127.0.0.1)")
    ap.add_argument("--port", type=int, default=1700, help="port UDP (bawaan: 1700)")
    ap.add_argument("--freq", type=float, default=FREQUENCY_HZ,
                    help="frekuensi kanal dalam Hz (bawaan: 433175000)")
    ap.add_argument("--sf", type=int, default=SPREADING_FACTOR,
                    help="spreading factor (bawaan: 7)")
    ap.add_argument("--gateway-id", default=None,
                    help="EUI-64 gateway, 16 digit hex (bawaan: diturunkan dari MAC)")
    ap.add_argument("--verbose", action="store_true", help="cetak hex tiap paket")
    args = ap.parse_args()

    if args.gateway_id is None:
        args.gateway_id = default_gateway_id()
    args.gateway_id = args.gateway_id.replace(":", "").replace("-", "").lower()
    if len(args.gateway_id) != 16:
        sys.exit("Gateway ID harus 16 digit hex (EUI-64).")

    FREQUENCY_HZ = args.freq

    print("=== SINGLE CHANNEL LoRaWAN GATEWAY ===")
    print("Init SX1276 ... ", end="", flush=True)
    if not lora_begin(args.freq, args.sf, BANDWIDTH_HZ, CODING_RATE):
        print("GAGAL")
        print("REG_VERSION bukan 0x12. Periksa HAT terpasang rapat dan SPI aktif:")
        print("  sudo raspi-config > Interface Options > SPI > Yes")
        sys.exit(1)
    print("OK")

    # systemd menghentikan layanan dengan SIGTERM, bukan Ctrl-C. Tanpa baris
    # ini Python langsung keluar dan blok finally di bawah tidak pernah jalan --
    # radio ditinggal dalam mode RX dan pin GPIO tidak dilepas. Diubah menjadi
    # KeyboardInterrupt supaya keduanya berakhir lewat jalan yang sama.
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt))

    fwd = Forwarder(args)
    try:
        fwd.run()
    except KeyboardInterrupt:
        print("\n\nDihentikan.")
    finally:
        _set_mode(MODE_SLEEP)
        _spi.close()
        GPIO.cleanup()
        print("Radio dimatikan.")


if __name__ == "__main__":
    main()
