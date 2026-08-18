/*
  LoRa ACK Receiver - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: receiver

  Mekanisme:
    1. Tunggu paket "DATA:N" via interrupt DIO0 (non-blocking RX)
    2. Segera kirim "ACK:N" (TX blocking)
    3. Kembali ke RX mode

  Pin Mapping Dragino Shield v1.2:
    NSS/CS -> D10, DIO0 -> D2, RST -> D9
    SCK -> D13, MOSI -> D11, MISO -> D12
*/

#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>

#define NSS_PIN          10
#define RST_PIN           9
#define DIO0_PIN          2

#define FREQUENCY        920E6
#define BANDWIDTH        125E3
#define SPREADING_FACTOR 7
#define CODING_RATE      5
#define TX_POWER         17

#define LED_PIN      LED_BUILTIN  // D13. Ganti ke 3 untuk LED eksternal di D3.
#define LED_DURATION 200

int rxCount = 0;

unsigned long ledOnTime = 0;
bool ledActive = false;

volatile bool rxFlag = false;

void onReceive(int size) {
  if (size > 0) rxFlag = true;
}

void updateLED() {
  if (ledActive && (millis() - ledOnTime >= LED_DURATION)) {
    digitalWrite(LED_PIN, LOW);
    ledActive = false;
  }
}

void triggerLED() {
  digitalWrite(LED_PIN, HIGH);
  ledOnTime = millis();
  ledActive = true;
}

void setup() {
  Serial.begin(9600);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  Serial.println(F("=== LoRa ACK RECEIVER ==="));
  Serial.print(F("Init LoRa ... "));

  LoRa.setPins(NSS_PIN, RST_PIN, DIO0_PIN);
  if (!LoRa.begin(FREQUENCY)) {
    Serial.println(F("GAGAL! Cek shield/kabel."));
    while (true);
  }

  LoRa.setSpreadingFactor(SPREADING_FACTOR);
  LoRa.setSignalBandwidth(BANDWIDTH);
  LoRa.setCodingRate4(CODING_RATE);
  LoRa.setTxPower(TX_POWER);
  LoRa.onReceive(onReceive);
  LoRa.receive();   // langsung masuk RX mode

  Serial.println(F("OK"));
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.println(F("Menunggu paket DATA...\n"));
}

void loop() {
  updateLED();

  if (!rxFlag) return;
  rxFlag = false;

  String received = "";
  while (LoRa.available()) {
    received += (char)LoRa.read();
  }

  // Abaikan paket yang bukan format DATA:
  if (!received.startsWith("DATA:")) {
    Serial.print(F("[WARN] Abaikan paket: "));
    Serial.println(received);
    LoRa.receive();
    return;
  }

  float rssi = LoRa.packetRssi();
  float snr  = LoRa.packetSnr();
  rxCount++;
  triggerLED();

  Serial.println(F("=== PAKET DITERIMA ==="));
  Serial.print(F("  Data  : ")); Serial.println(received);
  Serial.print(F("  RSSI  : ")); Serial.print(rssi); Serial.println(F(" dBm"));
  Serial.print(F("  SNR   : ")); Serial.print(snr);  Serial.println(F(" dB"));
  Serial.print(F("  Total : ")); Serial.println(rxCount);
  Serial.println(F("====================="));

  // Kirim ACK (TX blocking)
  String ackMsg = "ACK:" + received.substring(5);
  Serial.print(F("[TX] ACK: "));
  Serial.println(ackMsg);

  LoRa.beginPacket();
  LoRa.print(ackMsg);
  LoRa.endPacket();   // blocking — pastikan ACK terkirim sempurna

  // Kembali ke RX mode
  LoRa.receive();
  Serial.println(F("[RX] Menunggu paket berikutnya...\n"));
}
