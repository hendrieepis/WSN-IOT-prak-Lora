/*
  LoRa Sender + LED Notif - Dragino LoRa Shield v1.2 + Arduino Uno
  Diadaptasi dari: 02a-sender-uart-LEDNotif (Heltec HTITTracker SX1262)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: sender

  Pin Mapping Dragino Shield:
    NSS/CS -> D10  (R9 0-ohm populated)
    DIO0   -> D2
    RST    -> D9
    SCK    -> D13 / ICSP, MOSI -> D11, MISO -> D12

  LED:
    LED_BUILTIN (D13) = built-in LED Arduino, tapi shared dengan SPI SCK.
    LED akan berkedip saat SPI aktif — untuk notifikasi setelah TX selesai, OK.
    Ganti LED_PIN ke D3 jika ingin LED eksternal tanpa gangguan SPI.
*/

#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>

#define NSS_PIN    10
#define RST_PIN     9
#define DIO0_PIN    2

#define FREQUENCY        920E6
#define BANDWIDTH        125E3
#define SPREADING_FACTOR 7
#define CODING_RATE      5
#define TX_POWER         17

#define LED_PIN  LED_BUILTIN  // D13. Ganti ke 3 untuk LED eksternal di D3.

int counter = 0;

void setup() {
  Serial.begin(9600);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  Serial.println(F("=== LoRa SENDER (Dragino) ==="));
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

  Serial.println(F("OK"));
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.print(F(" MHz | "));
  Serial.print(F("BW: ")); Serial.print(BANDWIDTH / 1E3); Serial.print(F(" kHz | "));
  Serial.print(F("SF")); Serial.print(SPREADING_FACTOR); Serial.print(F(" | "));
  Serial.print(F("Power: ")); Serial.print(TX_POWER); Serial.println(F(" dBm"));
  Serial.println(F("Mulai kirim tiap 2 detik...\n"));
}

void loop() {
  String msg = "Hello #" + String(counter);

  Serial.print(F("[TX] Kirim: \""));
  Serial.print(msg);
  Serial.print(F("\" ... "));

  LoRa.beginPacket();
  LoRa.print(msg);
  LoRa.endPacket();         // blocking — SPI aktif sampai sini

  // LED blink setelah TX selesai (SPI sudah idle)
  digitalWrite(LED_PIN, HIGH);
  delay(150);
  digitalWrite(LED_PIN, LOW);

  Serial.println(F("OK"));
  counter++;

  delay(1850);              // total interval ~2 detik
}
