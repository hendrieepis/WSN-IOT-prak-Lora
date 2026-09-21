/*
  LoRa Sender - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: sender

  Pin mapping (hardwired on shield):
    NSS/CS -> D10  (R9 0-ohm populated)
    DIO0   -> D2
    RST    -> D9
    SCK    -> D13, MOSI -> D11, MISO -> D12 (ICSP header)

  Ganti FREQUENCY sesuai versi modul:
    433E6  -> 433 MHz
    868E6  -> 868 MHz (EU)
    915E6  -> 915 MHz (US/AS)
    923E6  -> 923 MHz (Indonesia AS923)
*/

#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>

#define NSS_PIN    10
#define RST_PIN     9
#define DIO0_PIN    2

#define FREQUENCY  433E6

int counter = 0;

void setup() {
  Serial.begin(9600);
  while (!Serial);

  Serial.println(F("=== LoRa SENDER ==="));
  Serial.print(F("Init LoRa ... "));

  LoRa.setPins(NSS_PIN, RST_PIN, DIO0_PIN);

  if (!LoRa.begin(FREQUENCY)) {
    Serial.println(F("GAGAL! Cek kabel/modul."));
    while (true);
  }

  LoRa.setSpreadingFactor(7);
  LoRa.setSignalBandwidth(125E3);
  LoRa.setCodingRate4(5);
  LoRa.setTxPower(17);

  Serial.println(F("OK"));
  Serial.print(F("Frekuensi : ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.println(F("SF=7, BW=125kHz, CR=4/5, Power=17dBm"));
  Serial.println(F("Kirim tiap 2 detik...\n"));
}

void loop() {
  String msg = "Hello LoRa #" + String(counter);

  Serial.print(F("[TX] \""));
  Serial.print(msg);
  Serial.print(F("\" ... "));

  LoRa.beginPacket();
  LoRa.print(msg);
  LoRa.endPacket();

  Serial.println(F("terkirim"));
  counter++;

  delay(2000);
}
