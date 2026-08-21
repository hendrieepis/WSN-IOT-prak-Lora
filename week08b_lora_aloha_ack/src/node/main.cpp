/*
  LoRa ALOHA + ACK - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: node1 / node2

  Pengembangan langsung dari M08 (Pure ALOHA): node masih mengirim data
  dummy dua ruangan kapan saja tanpa dengar-dahulu dan tanpa retry, TAPI kini
  menunggu balasan ACK dari gateway sebelum melanjutkan. Bedanya dengan M08
  hanya satu hal -- node akhirnya TAHU apakah paketnya sampai atau tidak.
  Belum ada kirim ulang otomatis; itu baru datang di M09.

  Payload  : "NODE=<id>,SEQ=<n>,R1T=<c>,R1H=<pct>,R2T=<c>,R2H=<pct>"
  Balasan  : "ACK=<id>,SEQ=<n>"  -- id & SEQ harus cocok persis dengan yang dikirim

  Mekanisme:
    TX   : blocking (endPacket)
    RX   : interrupt DIO0 + flag, hanya aktif selagi menunggu ACK
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
#define ACK_TIMEOUT        2000

#define ROOM1_TEMP_BASE  27.0
#define ROOM1_HUM_BASE   60
#define ROOM2_TEMP_BASE  25.0
#define ROOM2_HUM_BASE   68

unsigned long seq = 0;
unsigned long okCount = 0;
unsigned long failCount = 0;

volatile bool ackFlag = false;

void onAckReceived(int size) {
  if (size > 0) ackFlag = true;
}

void transmit(const String& msg) {
  LoRa.beginPacket();
  LoRa.print(msg);
  LoRa.endPacket();
}

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

  randomSeed(analogRead(A0));

  Serial.print(F("=== LoRa ALOHA+ACK - NODE "));
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
  LoRa.onReceive(onAckReceived);

  Serial.println(F("OK"));
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.print(F("ACK timeout: ")); Serial.print(ACK_TIMEOUT); Serial.println(F(" ms"));
  Serial.println(F("Peran: NODE (ALOHA + ACK) -- masih tanpa retry, lihat M09\n"));
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
  digitalWrite(LED_PIN, LOW);

  Serial.print(F("[TX] ")); Serial.println(payload);

  // --- Tunggu ACK ---
  String expectedAck = "ACK=" + String(NODE_ID) + ",SEQ=" + String(seq);
  ackFlag = false;
  LoRa.receive();

  unsigned long waitStart = millis();
  bool gotAck = false;

  while (millis() - waitStart < ACK_TIMEOUT) {
    if (ackFlag) {
      ackFlag = false;

      String reply = "";
      while (LoRa.available()) {
        reply += (char)LoRa.read();
      }

      if (reply == expectedAck) {
        gotAck = true;
        break;
      }
      Serial.print(F("[RX] WARN: balasan tak sesuai (")); Serial.print(reply);
      Serial.println(F("), tetap tunggu..."));
    }
  }

  if (gotAck) {
    okCount++;
    Serial.print(F("[OK] ACK diterima"));
  } else {
    failCount++;
    Serial.print(F("[FAIL] Tidak ada ACK"));
  }
  Serial.print(F(" | OK: ")); Serial.print(okCount);
  Serial.print(F(" | FAIL: ")); Serial.println(failCount);
  Serial.println();

  seq++;

  unsigned long interval = random(SEND_INTERVAL_MIN, SEND_INTERVAL_MAX + 1);
  delay(interval);
}
