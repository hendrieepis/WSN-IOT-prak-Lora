/*
  LoRa Receiver - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: receiver

  Pin mapping (hardwired on shield):
    NSS/CS -> D10  (R9 0-ohm populated)
    DIO0   -> D2
    RST    -> D9
    SCK    -> D13, MOSI -> D11, MISO -> D12 (ICSP header)

  FREQUENCY harus sama persis dengan sender.
*/

#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>

#define NSS_PIN    10
#define RST_PIN     9
#define DIO0_PIN    2

#define FREQUENCY  433E6

void setup() {
  Serial.begin(9600);
  while (!Serial);

  Serial.println(F("=== LoRa RECEIVER ==="));
  Serial.print(F("Init LoRa ... "));

  LoRa.setPins(NSS_PIN, RST_PIN, DIO0_PIN);

  if (!LoRa.begin(FREQUENCY)) {
    Serial.println(F("GAGAL! Cek kabel/modul."));
    while (true);
  }

  LoRa.setSpreadingFactor(7);
  LoRa.setSignalBandwidth(125E3);
  LoRa.setCodingRate4(5);

  Serial.println(F("OK"));
  Serial.print(F("Frekuensi : ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.println(F("SF=7, BW=125kHz, CR=4/5"));
  Serial.println(F("Menunggu paket...\n"));
}

void loop() {
  int packetSize = LoRa.parsePacket();

  if (packetSize > 0) {
    String received = "";
    while (LoRa.available()) {
      received += (char)LoRa.read();
    }

    Serial.println(F("--- Paket Diterima ---"));
    Serial.print(F("  Data  : \""));
    Serial.print(received);
    Serial.println(F("\""));
    Serial.print(F("  RSSI  : "));
    Serial.print(LoRa.packetRssi());
    Serial.println(F(" dBm"));
    Serial.print(F("  SNR   : "));
    Serial.print(LoRa.packetSnr());
    Serial.println(F(" dB"));
    Serial.println();
  }
}
