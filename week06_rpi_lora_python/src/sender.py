#!/usr/bin/env python3
"""Modul 06 - LoRa Sender di Raspberry Pi (Dragino LoRa GPS HAT, SX1276).

Padanan Python dari week01_lora_uart/src/sender/main.cpp. Perilakunya sama --
mengirim "Hello LoRa #n" setiap 2 detik -- tetapi tidak ada library LoRa di
bawahnya: setiap panggilan API di sini adalah tulisan langsung ke register
SX1276 lewat SPI, dan NSS dikendalikan manual karena HAT memakai GPIO 25,
bukan CE0 bawaan SPI.

Pemetaan pin (Dragino LoRa GPS HAT - WiringPi -> BCM):
    LoRa_NSS  -> WiringPi GPIO6  -> BCM GPIO 25
    RESET     -> WiringPi GPIO0  -> BCM GPIO 17
    DIO0      -> WiringPi GPIO7  -> BCM GPIO 4
    SCK       -> WiringPi GPIO14 -> BCM GPIO 11  (SPI0 CLK)
    MOSI      -> WiringPi GPIO12 -> BCM GPIO 10  (SPI0 MOSI)
    MISO      -> WiringPi GPIO13 -> BCM GPIO 9   (SPI0 MISO)

Ganti FREQUENCY sesuai versi modul HAT:
    433E6 -> 433 MHz   868E6 -> 868 MHz (EU)
    915E6 -> 915 MHz   923E6 -> 923 MHz (Indonesia AS923)

Prasyarat:
    sudo raspi-config           # Interface Options > SPI > Yes, lalu reboot
    pip3 install -r week06_rpi_lora_python/requirements.txt
"""

import time
import sys
import spidev
import RPi.GPIO as GPIO

# ── Pin configuration (BCM numbering) ─────────────────────────────────────────
NSS_PIN  = 25   # LoRa_NSS  (WiringPi GPIO6  = BCM GPIO 25)
RST_PIN  = 17   # RESET     (WiringPi GPIO0  = BCM GPIO 17)
DIO0_PIN = 4    # DIO0      (WiringPi GPIO7  = BCM GPIO 4)

# ── LoRa parameters ────────────────────────────────────────────────────────────
FREQUENCY = 433E6   # ganti: 868E6 / 915E6 / 923E6

# ── SX1276 Register Map ────────────────────────────────────────────────────────
REG_FIFO              = 0x00
REG_OP_MODE           = 0x01
REG_FRF_MSB           = 0x06
REG_FRF_MID           = 0x07
REG_FRF_LSB           = 0x08
REG_PA_CONFIG         = 0x09
REG_FIFO_ADDR_PTR     = 0x0D
REG_FIFO_TX_BASE_ADDR = 0x0E
REG_FIFO_RX_BASE_ADDR = 0x0F
REG_IRQ_FLAGS         = 0x12
REG_MODEM_CONFIG_1    = 0x1D
REG_MODEM_CONFIG_2    = 0x1E
REG_PREAMBLE_MSB      = 0x20
REG_PREAMBLE_LSB      = 0x21
REG_PAYLOAD_LENGTH    = 0x22
REG_VERSION           = 0x42

# Operating modes
MODE_LONG_RANGE = 0x80
MODE_SLEEP      = 0x00
MODE_STDBY      = 0x01
MODE_TX         = 0x03

# IRQ flags
IRQ_TX_DONE = 0x08

# PA config — pakai PA_BOOST untuk TxPower >= 2 dBm
PA_BOOST = 0x80

# ── SPI instance ───────────────────────────────────────────────────────────────
_spi = spidev.SpiDev()


# ── Low-level SPI helpers (NSS dikontrol manual karena HAT pakai GPIO 25) ──────
def _read_reg(addr):
    GPIO.output(NSS_PIN, GPIO.LOW)
    val = _spi.xfer2([addr & 0x7F, 0x00])[1]
    GPIO.output(NSS_PIN, GPIO.HIGH)
    return val


def _write_reg(addr, value):
    GPIO.output(NSS_PIN, GPIO.LOW)
    _spi.xfer2([addr | 0x80, value & 0xFF])
    GPIO.output(NSS_PIN, GPIO.HIGH)


# ── LoRa configuration (mirip API sandeepmistry) ───────────────────────────────
def _set_mode(mode):
    _write_reg(REG_OP_MODE, MODE_LONG_RANGE | mode)


def _set_frequency(freq):
    frf = int(round(freq / 32e6 * (1 << 19)))
    _write_reg(REG_FRF_MSB, (frf >> 16) & 0xFF)
    _write_reg(REG_FRF_MID, (frf >> 8)  & 0xFF)
    _write_reg(REG_FRF_LSB,  frf        & 0xFF)


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


# ── Packet TX (mirip LoRa.beginPacket / print / endPacket) ────────────────────
def beginPacket():
    _set_mode(MODE_STDBY)
    _write_reg(REG_MODEM_CONFIG_1, _read_reg(REG_MODEM_CONFIG_1) & 0xFE)  # explicit header
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
    _write_reg(REG_IRQ_FLAGS, IRQ_TX_DONE)   # clear flag


# ── Init & cleanup ─────────────────────────────────────────────────────────────
def loraBegin(frequency):
    # GPIO setup
    GPIO.setwarnings(False)
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(NSS_PIN,  GPIO.OUT, initial=GPIO.HIGH)
    GPIO.setup(RST_PIN,  GPIO.OUT, initial=GPIO.HIGH)
    GPIO.setup(DIO0_PIN, GPIO.IN)

    # SPI setup (bus 0, device 0 — hardware CE0 diabaikan, NSS dikontrol manual)
    _spi.open(0, 0)
    _spi.max_speed_hz = 5_000_000
    _spi.mode = 0b00

    # Hardware reset
    GPIO.output(RST_PIN, GPIO.LOW)
    time.sleep(0.01)
    GPIO.output(RST_PIN, GPIO.HIGH)
    time.sleep(0.01)

    # Verifikasi chip — SX1276/77/78/79 selalu return 0x12
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
# Main — identik dengan setup() + loop() di sender.ino
# ══════════════════════════════════════════════════════════════════════════════
print("=== LoRa SENDER ===")
print("Init LoRa ... ", end="", flush=True)

if not loraBegin(FREQUENCY):
    print("GAGAL! Cek kabel/modul.")
    print("Pastikan SPI aktif: sudo raspi-config > Interfacing Options > SPI")
    sys.exit(1)

setSpreadingFactor(7)
setSignalBandwidth(125e3)
setCodingRate4(5)
setTxPower(17)

print("OK")
print(f"Frekuensi : {FREQUENCY / 1e6:.0f} MHz")
print("SF=7, BW=125kHz, CR=4/5, Power=17dBm")
print("Kirim tiap 2 detik...\n")

counter = 0
try:
    while True:
        msg = f"Hello LoRa #{counter}"

        print(f'[TX] "{msg}" ... ', end="", flush=True)
        beginPacket()
        loraPrint(msg)
        endPacket()
        print("terkirim")

        counter += 1
        time.sleep(2)

except KeyboardInterrupt:
    print("\n\nProgram dihentikan oleh pengguna.")
finally:
    loraEnd()
    print("Menutup LoRa module...")
