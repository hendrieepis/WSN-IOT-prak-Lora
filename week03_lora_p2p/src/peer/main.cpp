/*
  LoRa Peer-to-Peer (Ping-Pong) - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: devicea / deviceb

  Satu file ini di-upload ke DUA board.
  Peran dibedakan lewat environment PlatformIO, bukan dengan menyunting #define.

  Mekanisme:
    TX : blocking (endPacket) — sederhana dan andal di AVR
    RX : polling via LoRa.parsePacket() — tidak perlu ISR, bebas race condition
    Device A kirim ulang Ping tiap PING_INTERVAL ms jika tidak ada balasan (auto-recovery)

  Pin Mapping Dragino Shield v1.2:
    NSS/CS -> D10  (R9 0-ohm terpasang)
    DIO0   -> D2
    RST    -> D9
    SCK    -> D13, MOSI -> D11, MISO -> D12
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

#define LED_PIN       LED_BUILTIN  // D13. Ganti ke 3 untuk LED eksternal di D3.
#define PING_INTERVAL 5000         // ms — Device A kirim ulang Ping jika tidak ada balasan

// Peran board ditentukan build flag di platformio.ini:
//   [env:devicea] -> -DDEVICE_A  (initiator, memulai Ping)
//   [env:deviceb] -> (tanpa flag) responder, membalas tiap paket masuk
// Cara ini menggantikan penyuntingan #define secara manual, sehingga satu
// source dipakai kedua board tanpa risiko lupa mengembalikannya.

#ifdef DEVICE_A
  #define MY_NAME "DeviceA"
#else
  #define MY_NAME "DeviceB"
#endif

unsigned long lastTxMs = 0;

void transmit(const String& msg) {
  LoRa.beginPacket();
  LoRa.print(msg);
  LoRa.endPacket();  // blocking — selesai TX baru lanjut
}

void setup() {
  Serial.begin(9600);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  Serial.println(F("=== LoRa PEER-TO-PEER ==="));
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
  Serial.print(F("Freq  : ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.print(F("Peran : "));

#ifdef DEVICE_A
  Serial.println(F("INITIATOR (Device A, env devicea)"));
  Serial.println();
  delay(1000);  // beri Device B waktu siap
  transmit(MY_NAME ":Ping");
  lastTxMs = millis();
  Serial.println(F("[TX] DeviceA:Ping\n"));
#else
  Serial.println(F("RESPONDER  (Device B, env deviceb)"));
  Serial.println(F("Menunggu paket...\n"));
#endif
}

void loop() {
#ifdef DEVICE_A
  // Auto-recovery: kirim ulang Ping jika tidak ada balasan dalam PING_INTERVAL ms
  if (millis() - lastTxMs > PING_INTERVAL) {
    Serial.println(F("[RETRY] Tidak ada balasan, kirim ulang Ping..."));
    transmit(MY_NAME ":Ping");
    lastTxMs = millis();
    Serial.println(F("[TX] DeviceA:Ping\n"));
  }
#endif

  // Cek paket masuk — polling, tidak perlu ISR
  int ps = LoRa.parsePacket();
  if (ps == 0) return;

  String received = "";
  while (LoRa.available()) {
    received += (char)LoRa.read();
  }

  lastTxMs = millis();  // reset retry timer (Device A); diabaikan Device B

  digitalWrite(LED_PIN, HIGH);
  Serial.println(F("================================"));
  Serial.print(F("[RX] Pesan  : ")); Serial.println(received);
  Serial.print(F("[RX] RSSI   : ")); Serial.print(LoRa.packetRssi()); Serial.println(F(" dBm"));
  Serial.print(F("[RX] SNR    : ")); Serial.print(LoRa.packetSnr()); Serial.println(F(" dB"));
  Serial.println(F("================================"));
  digitalWrite(LED_PIN, LOW);

  delay(50);

  String reply = String(MY_NAME) + ":" +
                 (received.indexOf("Ping") >= 0 ? "Pong" : "Ping");

  transmit(reply);
  Serial.print(F("[TX] ")); Serial.println(reply);
  Serial.println();
}
