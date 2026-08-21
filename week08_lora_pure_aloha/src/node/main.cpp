/*
  LoRa Pure ALOHA - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: node1 / node2

  Node membangkitkan data dummy suhu & kelembaban untuk dua ruangan, lalu
  mengirimkannya ke gateway KAPAN SAJA data itu siap -- tanpa mendengarkan
  kanal lebih dahulu, tanpa menunggu balasan, tanpa mengirim ulang. Inilah
  disiplin "Pure ALOHA": setiap node bebas berbicara, dan tabrakan adalah
  konsekuensi yang diterima, bukan dihindari.

  Payload  : "NODE=<id>,SEQ=<n>,R1T=<c>,R1H=<pct>,R2T=<c>,R2H=<pct>"
  Interval : acak SEND_INTERVAL_MIN..SEND_INTERVAL_MAX ms, sengaja tidak
             disamakan antar-node, meniru dua sumber data yang tidak
             saling tahu jadwal satu sama lain.

  Mekanisme:
    TX : blocking (endPacket) -- tidak ada RX sama sekali di modul ini
    Dummy sensor: random() di sekitar nilai dasar per ruangan

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
#define LED_PIN          LED_BUILTIN

#define FREQUENCY        433E6
#define BANDWIDTH        125E3
#define SPREADING_FACTOR 7
#define CODING_RATE      5
#define TX_POWER         17

// Nomor node datang dari build flag (-DNODE_ID=1 atau 2) di platformio.ini,
// sehingga kedua node memakai file source yang sama persis.
#ifndef NODE_ID
#define NODE_ID 1
#endif

#define SEND_INTERVAL_MIN 2000
#define SEND_INTERVAL_MAX 5000

// Ruangan 1 & Ruangan 2 dibedakan hanya lewat nilai dasar dummy-nya, supaya
// kedua ruangan terlihat berbeda di Serial Monitor walau datanya bukan hasil
// sensor sungguhan.
#define ROOM1_TEMP_BASE  27.0
#define ROOM1_HUM_BASE   60
#define ROOM2_TEMP_BASE  25.0
#define ROOM2_HUM_BASE   68

unsigned long seq = 0;
unsigned long txCount = 0;

void transmit(const String& msg) {
  LoRa.beginPacket();
  LoRa.print(msg);
  LoRa.endPacket();
}

// Dummy sensor: nilai dasar per ruangan +- jitter acak, dibulatkan 1 desimal
// untuk suhu. Bukan pembacaan sensor sungguhan -- lihat README modul ini.
float dummyTemp(float base) {
  return base + (random(-30, 31) / 10.0);   // +-3.0 C
}

int dummyHum(int base) {
  return base + random(-15, 16);            // +-15 %
}

void setup() {
  Serial.begin(115200);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  randomSeed(analogRead(A0));   // pin dibiarkan mengambang -> noise ADC sebagai seed

  Serial.print(F("=== LoRa PURE ALOHA - NODE "));
  Serial.print(NODE_ID);
  Serial.println(F(" ==="));
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
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.println(F("Peran: NODE (Pure ALOHA) -- kirim bebas, tanpa ACK, tanpa retry\n"));
}

void loop() {
  float r1t = dummyTemp(ROOM1_TEMP_BASE);
  int   r1h = dummyHum(ROOM1_HUM_BASE);
  float r2t = dummyTemp(ROOM2_TEMP_BASE);
  int   r2h = dummyHum(ROOM2_HUM_BASE);

  String payload = "NODE=" + String(NODE_ID) +
                    ",SEQ=" + String(seq) +
                    ",R1T=" + String(r1t, 1) +
                    ",R1H=" + String(r1h) +
                    ",R2T=" + String(r2t, 1) +
                    ",R2H=" + String(r2h);

  digitalWrite(LED_PIN, HIGH);
  transmit(payload);
  txCount++;
  digitalWrite(LED_PIN, LOW);

  Serial.print(F("[TX] ")); Serial.print(payload);
  Serial.print(F(" | total dikirim: ")); Serial.println(txCount);

  seq++;

  unsigned long interval = random(SEND_INTERVAL_MIN, SEND_INTERVAL_MAX + 1);
  delay(interval);
}
