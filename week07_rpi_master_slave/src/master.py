#!/usr/bin/env python3
"""Modul 07 - Master round-robin di Raspberry Pi (Dragino LoRa GPS HAT, SX1276).

Padanan Python dari week05_lora_master_slave/src/master/main.cpp: memanggil
Slave 1 dan Slave 2 bergiliran dengan batas waktu 500 ms per slave, lalu
mencetak statistik per node. Bedanya, kedua slave tetap Arduino Uno bershield
Dragino v1.2 -- master pindah platform, kontrak payload tidak berubah.

    POLL:<id>          master -> slave
    S<id>:DATA:<n>     slave  -> master

Driver SX1276 ditulis langsung via spidev + RPi.GPIO tanpa library LoRa, jadi
nama fungsinya sengaja dibuat sama dengan API sandeepmistry di Arduino agar
kedua sisi dapat dibandingkan baris per baris.

Pemetaan pin (Dragino LoRa GPS HAT - WiringPi -> BCM):
    LoRa_NSS  -> WiringPi GPIO6  -> BCM GPIO 25
    RESET     -> WiringPi GPIO0  -> BCM GPIO 17
    DIO0      -> WiringPi GPIO7  -> BCM GPIO 4
    SCK       -> WiringPi GPIO14 -> BCM GPIO 11  (SPI0 CLK)
    MOSI      -> WiringPi GPIO12 -> BCM GPIO 10  (SPI0 MOSI)
    MISO      -> WiringPi GPIO13 -> BCM GPIO 9   (SPI0 MISO)

Parameter radio harus IDENTIK dengan kedua slave: 433 MHz, SF7, BW 125 kHz,
CR 4/5. Upload kedua slave lebih dahulu, baru jalankan master.

Prasyarat:
    sudo raspi-config           # Interface Options > SPI > Yes, lalu reboot
    pip3 install -r week07_rpi_master_slave/requirements.txt
"""

import argparse
import time
import sys
import spidev
import RPi.GPIO as GPIO

# ── Pin configuration (BCM numbering) ─────────────────────────────────────────
NSS_PIN  = 25   # LoRa_NSS  (WiringPi GPIO6  = BCM GPIO 25)
RST_PIN  = 17   # RESET     (WiringPi GPIO0  = BCM GPIO 17)
DIO0_PIN = 4    # DIO0      (WiringPi GPIO7  = BCM GPIO 4)

# ── LoRa parameters ───────────────────────────────────────────────────────────
FREQUENCY        = 433E6
BANDWIDTH         = 125E3
SPREADING_FACTOR  = 7
CODING_RATE       = 5
TX_POWER          = 17

POLL_TIMEOUT      = 500   # ms menunggu balasan tiap slave
CYCLE_INTERVAL    = 500   # ms jeda antar siklus
SLAVE_COUNT       = 2

# ── SX1276 Register Map ───────────────────────────────────────────────────────
REG_FIFO                = 0x00
REG_OP_MODE             = 0x01
REG_FRF_MSB             = 0x06
REG_FRF_MID             = 0x07
REG_FRF_LSB             = 0x08
REG_PA_CONFIG           = 0x09
REG_FIFO_ADDR_PTR       = 0x0D
REG_FIFO_TX_BASE_ADDR   = 0x0E
REG_FIFO_RX_BASE_ADDR   = 0x0F
REG_FIFO_RX_CURRENT_ADDR = 0x10
REG_IRQ_FLAGS           = 0x12
REG_RX_NB_BYTES         = 0x13
REG_PKT_RSSI_VALUE      = 0x1A
REG_PKT_SNR_VALUE       = 0x1B
REG_MODEM_CONFIG_1      = 0x1D
REG_MODEM_CONFIG_2      = 0x1E
REG_PREAMBLE_MSB        = 0x20
REG_PREAMBLE_LSB        = 0x21
REG_PAYLOAD_LENGTH      = 0x22
REG_VERSION             = 0x42

# ── Operating modes ───────────────────────────────────────────────────────────
MODE_LONG_RANGE    = 0x80
MODE_SLEEP         = 0x00
MODE_STDBY         = 0x01
MODE_TX            = 0x03
MODE_RX_CONTINUOUS = 0x05

# ── IRQ flags ─────────────────────────────────────────────────────────────────
IRQ_RX_DONE        = 0x40
IRQ_TX_DONE        = 0x08
IRQ_CRC_ERROR      = 0x20

# ── PA config ─────────────────────────────────────────────────────────────────
PA_BOOST = 0x80

# ── SPI instance ──────────────────────────────────────────────────────────────
_spi = spidev.SpiDev()


# ══════════════════════════════════════════════════════════════════════════════
# Low-level SPI register access
# ══════════════════════════════════════════════════════════════════════════════
def _read_reg(addr):
    GPIO.output(NSS_PIN, GPIO.LOW)
    val = _spi.xfer2([addr & 0x7F, 0x00])[1]
    GPIO.output(NSS_PIN, GPIO.HIGH)
    return val


def _write_reg(addr, value):
    GPIO.output(NSS_PIN, GPIO.LOW)
    _spi.xfer2([addr | 0x80, value & 0xFF])
    GPIO.output(NSS_PIN, GPIO.HIGH)


# ══════════════════════════════════════════════════════════════════════════════
# LoRa mode & frequency
# ══════════════════════════════════════════════════════════════════════════════
def _set_mode(mode):
    _write_reg(REG_OP_MODE, MODE_LONG_RANGE | mode)


def _set_frequency(freq):
    frf = int(round(freq / 32e6 * (1 << 19)))
    _write_reg(REG_FRF_MSB, (frf >> 16) & 0xFF)
    _write_reg(REG_FRF_MID, (frf >> 8)  & 0xFF)
    _write_reg(REG_FRF_LSB,  frf        & 0xFF)


# ══════════════════════════════════════════════════════════════════════════════
# LoRa configuration (mirip API sandeepmistry)
# ══════════════════════════════════════════════════════════════════════════════
def setSpreadingFactor(sf):
    sf = max(6, min(12, sf))
    _write_reg(REG_MODEM_CONFIG_2,
               (_read_reg(REG_MODEM_CONFIG_2) & 0x0F) | ((sf << 4) & 0xF0))


def setSignalBandwidth(bw):
    bw_table = [7.8e3, 10.4e3, 15.6e3, 20.8e3, 31.25e3, 41.7e3, 62.5e3, 125e3, 250e3]
    idx = min(range(len(bw_table)), key=lambda i: abs(bw_table[i] - bw))
    _write_reg(REG_MODEM_CONFIG_1,
               (_read_reg(REG_MODEM_CONFIG_1) & 0x0F) | (idx << 4))


def setCodingRate4(denominator):
    cr = max(5, min(8, denominator)) - 4
    _write_reg(REG_MODEM_CONFIG_1,
               (_read_reg(REG_MODEM_CONFIG_1) & 0xF1) | (cr << 1))


def setTxPower(level):
    level = max(2, min(17, level))
    _write_reg(REG_PA_CONFIG, PA_BOOST | (level - 2))


# ══════════════════════════════════════════════════════════════════════════════
# TX functions (mirip LoRa.beginPacket / print / endPacket)
# ══════════════════════════════════════════════════════════════════════════════
def beginPacket():
    _set_mode(MODE_STDBY)
    _write_reg(REG_MODEM_CONFIG_1, _read_reg(REG_MODEM_CONFIG_1) & 0xFE)
    _write_reg(REG_FIFO_ADDR_PTR, 0x00)
    _write_reg(REG_PAYLOAD_LENGTH, 0x00)


def loraPrint(data):
    if isinstance(data, str):
        data = data.encode('ascii')
    current_len = _read_reg(REG_PAYLOAD_LENGTH)
    size = min(len(data), 255 - current_len)
    for byte in data[:size]:
        _write_reg(REG_FIFO, byte)
    _write_reg(REG_PAYLOAD_LENGTH, current_len + size)


def endPacket():
    _set_mode(MODE_TX)
    while (_read_reg(REG_IRQ_FLAGS) & IRQ_TX_DONE) == 0:
        time.sleep(0.001)
    _write_reg(REG_IRQ_FLAGS, IRQ_TX_DONE)


def transmit(msg):
    beginPacket()
    loraPrint(msg)
    endPacket()


# ══════════════════════════════════════════════════════════════════════════════
# RX functions (mirip LoRa.parsePacket / available / read)
# ══════════════════════════════════════════════════════════════════════════════
def parsePacket():
    irq = _read_reg(REG_IRQ_FLAGS)
    if irq & IRQ_CRC_ERROR:
        _write_reg(REG_IRQ_FLAGS, IRQ_CRC_ERROR)
        return 0
    if (irq & IRQ_RX_DONE) == 0:
        return 0
    _write_reg(REG_IRQ_FLAGS, IRQ_RX_DONE)
    return _read_reg(REG_RX_NB_BYTES)


def loraAvailable():
    return _read_reg(REG_RX_NB_BYTES)


def loraRead():
    return _read_reg(REG_FIFO)


def packetRssi():
    rssi = _read_reg(REG_PKT_RSSI_VALUE)
    freq_mhz = FREQUENCY / 1e6
    if freq_mhz < 868:
        return rssi - 164
    else:
        return rssi - 157


def packetSnr():
    val = _read_reg(REG_PKT_SNR_VALUE)
    if val > 127:
        val = val - 256
    return val / 4.0


def startRx():
    _set_mode(MODE_RX_CONTINUOUS)


def initRxSequence():
    _write_reg(REG_FIFO_ADDR_PTR, _read_reg(REG_FIFO_RX_CURRENT_ADDR))


# ══════════════════════════════════════════════════════════════════════════════
# Init & cleanup
# ══════════════════════════════════════════════════════════════════════════════
def loraBegin(frequency):
    GPIO.setwarnings(False)
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(NSS_PIN,  GPIO.OUT, initial=GPIO.HIGH)
    GPIO.setup(RST_PIN,  GPIO.OUT, initial=GPIO.HIGH)
    GPIO.setup(DIO0_PIN, GPIO.IN)

    _spi.open(0, 0)
    _spi.max_speed_hz = 5_000_000
    _spi.mode = 0b00

    GPIO.output(RST_PIN, GPIO.LOW)
    time.sleep(0.01)
    GPIO.output(RST_PIN, GPIO.HIGH)
    time.sleep(0.01)

    version = _read_reg(REG_VERSION)
    if version != 0x12:
        return False

    _set_mode(MODE_SLEEP)
    _set_frequency(frequency)
    _write_reg(REG_FIFO_TX_BASE_ADDR, 0x00)
    _write_reg(REG_FIFO_RX_BASE_ADDR, 0x00)
    _set_mode(MODE_STDBY)
    return True


def loraEnd():
    _set_mode(MODE_SLEEP)
    _spi.close()
    GPIO.cleanup()


# ══════════════════════════════════════════════════════════════════════════════
# Master logic: poll slave (identik dengan pollSlave() di master.ino)
# ══════════════════════════════════════════════════════════════════════════════
def pollSlave(slaveNum, okRef, failRef):
    pollMsg = f"POLL:{slaveNum}"
    print(f"[TX] {pollMsg}")
    transmit(pollMsg)

    startRx()

    waitStart = time.monotonic()
    while (time.monotonic() - waitStart) * 1000 < POLL_TIMEOUT:
        ps = parsePacket()
        if ps > 0:
            initRxSequence()
            reply = bytes(loraRead() for _ in range(ps)).decode('ascii', errors='replace')

            prefix = f"S{slaveNum}:DATA:"
            if reply.startswith(prefix):
                try:
                    dataOut = int(reply[len(prefix):])
                except ValueError:
                    dataOut = 0
                okRef[0] += 1
                rssi = packetRssi()
                snr = packetSnr()
                print(f"[RX] {reply} | RSSI: {rssi:.0f} dBm | SNR: {snr:.1f} dB")
                return dataOut
            else:
                print(f"[WARN] Balasan tidak valid: {reply}")

    failRef[0] += 1
    print(f"[FAIL] Slave {slaveNum} tidak merespon!")
    return None


# ══════════════════════════════════════════════════════════════════════════════
# Main (identik dengan setup() + loop() di master.ino)
# ══════════════════════════════════════════════════════════════════════════════
def build_arg_parser():
    parser = argparse.ArgumentParser(
        prog="master.py",
        description=(
            "Master round-robin M07 (Raspberry Pi + Dragino LoRa GPS HAT). "
            "Memanggil Slave 1 lalu Slave 2 bergiliran tanpa henti, mencetak "
            "statistik OK/FAIL per node setiap siklus. Tidak ada opsi lain -- "
            "seluruh parameter (frekuensi, SF, BW, timeout) ditetapkan sebagai "
            "konstanta di berkas ini agar tetap identik dengan slave M05."
        ),
        epilog=(
            f"Parameter radio: {FREQUENCY / 1e6:.0f} MHz, SF{SPREADING_FACTOR}, "
            f"BW {BANDWIDTH / 1e3:.0f} kHz, CR 4/5, {TX_POWER} dBm. "
            f"POLL_TIMEOUT={POLL_TIMEOUT} ms, CYCLE_INTERVAL={CYCLE_INTERVAL} ms. "
            "Hentikan dengan Ctrl-C."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    return parser


if __name__ == '__main__':
    build_arg_parser().parse_args()

    cycle = 0
    s1Ok = [0]; s1Fail = [0]; s1Data = 0
    s2Ok = [0]; s2Fail = [0]; s2Data = 0

    print("=== LoRa MASTER-SLAVE 3 NODE ===")
    print("Init LoRa ... ", end="", flush=True)

    if not loraBegin(FREQUENCY):
        print("GAGAL! Cek kabel/modul.")
        print("Pastikan SPI aktif: sudo raspi-config > Interfacing Options > SPI")
        sys.exit(1)

    setSpreadingFactor(SPREADING_FACTOR)
    setSignalBandwidth(BANDWIDTH)
    setCodingRate4(CODING_RATE)
    setTxPower(TX_POWER)

    print("OK")
    print(f"Freq: {FREQUENCY / 1e6:.0f} MHz")
    print(f"SF{SPREADING_FACTOR} | BW: {BANDWIDTH / 1e3:.0f} kHz")
    print("Peran: MASTER (Raspberry Pi + LoRa GPS HAT)")
    print("Slave: Dragino Shield Uno - S1 & S2\n")

    try:
        while True:
            cycle += 1
            cycleStartMs = time.monotonic()

            print("=" * 40)
            print(f"=== CYCLE {cycle} ===")

            # --- Poll Slave 1 ---
            s1Data = pollSlave(1, s1Ok, s1Fail)

            # --- Poll Slave 2 ---
            s2Data = pollSlave(2, s2Ok, s2Fail)

            # --- Statistik ---
            duration = (time.monotonic() - cycleStartMs) * 1000
            print("--- STATISTIK ---")
            print(f"S1: OK={s1Ok[0]} | FAIL={s1Fail[0]} | Data: {s1Data}")
            print(f"S2: OK={s2Ok[0]} | FAIL={s2Fail[0]} | Data: {s2Data}")
            print(f"Durasi siklus: {duration:.0f} ms")
            print("=" * 40 + "\n")

            time.sleep(CYCLE_INTERVAL / 1000.0)

    except KeyboardInterrupt:
        print("\nProgram dihentikan oleh pengguna.")
    finally:
        loraEnd()
        print("Menutup LoRa module...")
