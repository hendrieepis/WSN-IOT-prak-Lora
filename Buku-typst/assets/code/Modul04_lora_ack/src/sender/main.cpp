/*
  LoRa ACK Sender - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: sender

  Mekanisme:
    1. Kirim "DATA:N" tiap 3 detik (TX blocking)
    2. Langsung masuk RX mode, tunggu "ACK:N" max ACK_TIMEOUT ms
    3. Catat statistik ACK OK / NO ACK ke Serial

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

#define FREQUENCY        433E6
#define BANDWIDTH        125E3
#define SPREADING_FACTOR 7
#define CODING_RATE      5
#define TX_POWER         17

#define LED_PIN      LED_BUILTIN  // D13. Ganti ke 3 untuk LED eksternal di D3.
#define LED_DURATION 200
#define ACK_TIMEOUT  3000

int counter = 0;
int ackOK   = 0;
int ackFail = 0;

unsigned long ledOnTime = 0;
bool ledActive = false;

volatile bool ackFlag = false;

void onAckReceived(int size) {
  if (size > 0) ackFlag = true;
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

  Serial.println(F("=== LoRa ACK SENDER ==="));
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
  LoRa.onReceive(onAckReceived);  // ISR untuk terima ACK

  Serial.println(F("OK"));
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.print(F(" MHz | "));
  Serial.print(F("SF")); Serial.print(SPREADING_FACTOR); Serial.print(F(" | "));
  Serial.print(F("ACK timeout: ")); Serial.print(ACK_TIMEOUT); Serial.println(F(" ms\n"));
}

void loop() {
  updateLED();

  // --- 1. Kirim DATA (TX blocking) ---
  String msg = "DATA:" + String(counter);
  Serial.print(F("[TX] Kirim: "));
  Serial.print(msg);
  Serial.print(F(" ... "));

  LoRa.beginPacket();
  LoRa.print(msg);
  LoRa.endPacket();   // blocking — selesai TX baru lanjut

  Serial.println(F("selesai"));

  // --- 2. Masuk RX, tunggu ACK ---
  String expectedACK = "ACK:" + String(counter);
  ackFlag = false;
  LoRa.receive();   // non-blocking RX via interrupt DIO0

  unsigned long waitStart = millis();
  bool gotACK = false;

  while (millis() - waitStart < ACK_TIMEOUT) {
    updateLED();

    if (ackFlag) {
      ackFlag = false;

      String reply = "";
      while (LoRa.available()) {
        reply += (char)LoRa.read();
      }

      Serial.print(F("[RX] Balasan: "));
      Serial.println(reply);

      if (reply == expectedACK) {
        gotACK = true;
        break;
      }

      // Paket datang tapi bukan ACK yang ditunggu — tetap tunggu
      Serial.println(F("[RX] WARN: bukan ACK yang diharapkan, tetap tunggu..."));
    }
  }

  // --- 3. Evaluasi hasil ---
  if (gotACK) {
    ackOK++;
    triggerLED();
    Serial.print(F("[OK] ACK diterima!"));
  } else {
    ackFail++;
    Serial.print(F("[FAIL] Tidak ada ACK!"));
  }

  Serial.print(F(" | OK: ")); Serial.print(ackOK);
  Serial.print(F(" | FAIL: ")); Serial.println(ackFail);
  Serial.println();

  counter++;
  delay(3000);
}
