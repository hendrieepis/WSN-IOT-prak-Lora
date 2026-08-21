/*
  LoRa ALOHA + ACK + Random Backoff + Retry
  Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: node1 / node2

  Pengembangan langsung dari M08B: node tidak lagi menyerah pada [FAIL]
  pertama. Ketika ACK tidak tiba sebelum timeout, node menunggu selang
  ACAK (random backoff) lalu mengirim ULANG paket DATA yang SAMA -- SEQ
  tidak berubah selama retry, karena ini pengiriman ulang, bukan data baru.
  Data dummy dibangkitkan sekali per SEQ dan dipertahankan sepanjang seluruh
  percobaan retry-nya, persis seperti pembacaan sensor sungguhan yang tidak
  berubah hanya karena paketnya diulang.

  Payload  : "NODE=<id>,SEQ=<n>,R1T=<c>,R1H=<pct>,R2T=<c>,R2H=<pct>"
  Balasan  : "ACK=<id>,SEQ=<n>"

  Mengapa backoff acak, bukan jeda tetap: dua node yang bertabrakan lalu
  sama-sama menunggu jeda TETAP akan bertabrakan lagi pada retry pertama --
  keduanya tetap sinkron. Jeda ACAK memecah sinkronisasi kebetulan itu.

  Mekanisme:
    TX   : blocking (endPacket)
    RX   : interrupt DIO0 + flag, aktif selagi menunggu ACK
    Retry: maksimum MAX_RETRIES kali per SEQ, lalu menyerah permanen

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

#define MAX_RETRIES         3     // percobaan ulang setelah kiriman pertama
#define BACKOFF_MIN_MS     200
#define BACKOFF_MAX_MS    1500

#define ROOM1_TEMP_BASE  27.0
#define ROOM1_HUM_BASE   60
#define ROOM2_TEMP_BASE  25.0
#define ROOM2_HUM_BASE   68

unsigned long seq = 0;
unsigned long okCount = 0;
unsigned long failCount = 0;
unsigned long totalRetriesUsed = 0;

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

  Serial.print(F("=== LoRa ALOHA+ACK+RETRY - NODE "));
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
  Serial.print(F("ACK timeout: ")); Serial.print(ACK_TIMEOUT);
  Serial.print(F(" ms | Max retry: ")); Serial.print(MAX_RETRIES);
  Serial.print(F(" | Backoff: ")); Serial.print(BACKOFF_MIN_MS);
  Serial.print(F("-")); Serial.print(BACKOFF_MAX_MS); Serial.println(F(" ms"));
  Serial.println(F("Peran: NODE (ALOHA + ACK + Random Backoff + Retry)\n"));
}

void loop() {
  // Data dibangkitkan SEKALI per SEQ dan dipertahankan sepanjang retry --
  // paket yang diulang harus membawa pembacaan yang sama, bukan yang baru.
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
  String expectedAck = "ACK=" + String(NODE_ID) + ",SEQ=" + String(seq);

  bool gotAck = false;
  int attempt = 0;   // 0 = kiriman pertama, 1..MAX_RETRIES = nomor retry

  while (true) {
    if (attempt == 0) {
      Serial.print(F("[TX] ")); Serial.println(payload);
    } else {
      Serial.print(F("[RETRY ")); Serial.print(attempt); Serial.print(F("/"));
      Serial.print(MAX_RETRIES); Serial.print(F("] ")); Serial.println(payload);
    }

    digitalWrite(LED_PIN, HIGH);
    transmit(payload);
    digitalWrite(LED_PIN, LOW);

    ackFlag = false;
    LoRa.receive();

    unsigned long waitStart = millis();
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

    if (gotAck) break;
    if (attempt >= MAX_RETRIES) break;   // jatah retry habis, menyerah permanen

    attempt++;
    unsigned long backoff = random(BACKOFF_MIN_MS, BACKOFF_MAX_MS + 1);
    Serial.print(F("[BACKOFF] tunggu ")); Serial.print(backoff);
    Serial.println(F(" ms sebelum retry"));
    delay(backoff);
  }

  if (gotAck) {
    okCount++;
    totalRetriesUsed += attempt;
    Serial.print(F("[OK] SUCCESS setelah ")); Serial.print(attempt); Serial.print(F(" retry"));
  } else {
    failCount++;
    totalRetriesUsed += attempt;
    Serial.print(F("[FAIL] Gagal permanen setelah ")); Serial.print(MAX_RETRIES); Serial.print(F(" retry"));
  }
  Serial.print(F(" | OK: ")); Serial.print(okCount);
  Serial.print(F(" | FAIL: ")); Serial.print(failCount);
  Serial.print(F(" | Total retry terpakai: ")); Serial.println(totalRetriesUsed);
  Serial.println();

  seq++;

  unsigned long interval = random(SEND_INTERVAL_MIN, SEND_INTERVAL_MAX + 1);
  delay(interval);
}
