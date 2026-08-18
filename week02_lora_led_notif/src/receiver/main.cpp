/*
  LoRa Receiver Non-Blocking + LED Notif - Dragino LoRa Shield v1.2 + Arduino Uno
  Diadaptasi dari: 02c_receiver_uart_nonblocking-LEDNotif (Heltec HTITTracker SX1262)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: receiver

  Interrupt-driven receive via DIO0 -> D2 (INT0 Arduino Uno).
  Loop() tidak terblokir — bisa kerjakan tugas lain sambil menunggu paket.

  Pin Mapping Dragino Shield:
    NSS/CS -> D10  (R9 0-ohm populated)
    DIO0   -> D2   (interrupt RX-done)
    RST    -> D9
    SCK    -> D13 / ICSP, MOSI -> D11, MISO -> D12

  LED:
    LED_BUILTIN (D13) shared dengan SPI SCK — nyala sebentar saat paket tiba.
    Ganti LED_PIN ke 3 untuk LED eksternal di D3 (tanpa gangguan SPI).
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

#define LED_PIN  LED_BUILTIN  // D13. Ganti ke 3 untuk LED eksternal di D3.

volatile bool rxFlag = false;

void onReceive(int packetSize) {
  if (packetSize > 0) rxFlag = true;
}

void setup() {
  Serial.begin(9600);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  Serial.println(F("=== LoRa RECEIVER (Dragino) ==="));
  Serial.print(F("Init LoRa ... "));

  LoRa.setPins(NSS_PIN, RST_PIN, DIO0_PIN);
  if (!LoRa.begin(FREQUENCY)) {
    Serial.println(F("GAGAL! Cek shield/kabel."));
    while (true);
  }

  LoRa.setSpreadingFactor(SPREADING_FACTOR);
  LoRa.setSignalBandwidth(BANDWIDTH);
  LoRa.setCodingRate4(CODING_RATE);

  LoRa.onReceive(onReceive);  // pasang callback ISR via DIO0 (D2)
  LoRa.receive();             // masuk mode receive kontinyu (non-blocking)

  Serial.println(F("OK"));
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.print(F(" MHz | "));
  Serial.print(F("BW: ")); Serial.print(BANDWIDTH / 1E3); Serial.print(F(" kHz | "));
  Serial.print(F("SF")); Serial.println(SPREADING_FACTOR);
  Serial.println(F("Menunggu paket (non-blocking)...\n"));
}

void loop() {
  if (rxFlag) {
    rxFlag = false;

    digitalWrite(LED_PIN, HIGH);  // LED nyala — paket diterima

    String received = "";
    while (LoRa.available()) {
      received += (char)LoRa.read();
    }

    Serial.println(F("================================"));
    Serial.print(F("[RX] Pesan : "));
    Serial.println(received);
    Serial.print(F("[RX] RSSI  : "));
    Serial.print(LoRa.packetRssi());
    Serial.println(F(" dBm"));
    Serial.print(F("[RX] SNR   : "));
    Serial.print(LoRa.packetSnr());
    Serial.println(F(" dB"));
    Serial.println(F("================================\n"));

    delay(200);                   // LED nyala 200ms
    digitalWrite(LED_PIN, LOW);

    LoRa.receive();               // kembali ke mode receive
  }

  // Di sini bisa tambah kode lain — loop tidak terblokir saat menunggu paket
}
