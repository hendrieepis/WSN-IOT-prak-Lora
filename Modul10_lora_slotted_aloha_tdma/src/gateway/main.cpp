/*
  LoRa Slotted ALOHA - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: gateway

  Gateway kini punya peran baru dibanding M08/M08B/M09: ia bukan sekadar
  pendengar pasif, melainkan penentu waktu bersama. Tiap siklus dimulai
  dengan menyiarkan "SYNC=<cycle>", lalu gateway mendengarkan selama
  SLOT_COUNT x SLOT_DURATION_MS -- jendela waktu yang cukup untuk seluruh
  node mengirim pada slotnya masing-masing -- sebelum menyiarkan SYNC
  berikutnya. Tidak ada polling seperti M05; gateway tidak memanggil node
  satu per satu, ia hanya menjaga detak waktu, dan node sendiri yang tahu
  kapan gilirannya berdasarkan SYNC itu.

  Payload  : "NODE=<id>,SEQ=<n>,R1T=<c>,R1H=<pct>,R2T=<c>,R2H=<pct>"
  Balasan  : "ACK=<id>,SEQ=<n>"

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

#define LED_DURATION     150
#define NODE_COUNT       2   // Node 1 dan Node 2 -> indeks array 1..2

// HARUS SAMA PERSIS dengan src/node/main.cpp di kedua node. Nilainya datang
// dari [slot] count di platformio.ini supaya gateway dan kedua node tidak
// mungkin berbeda -- ketiganya membaca angka yang sama.
#ifndef SLOT_COUNT
#define SLOT_COUNT          2
#endif
#define SLOT_DURATION_MS  800

volatile bool rxFlag = false;

unsigned long ledOnTime = 0;
bool ledActive = false;

unsigned long cycleCount = 0;
unsigned long rxCount[NODE_COUNT + 1] = {0};
long lastSeq[NODE_COUNT + 1];
unsigned long lostEst[NODE_COUNT + 1] = {0};

void onPacket(int size) {
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

String getField(const String& data, const String& key) {
  String needle = key + "=";
  int start = data.indexOf(needle);
  if (start == -1) return "";
  start += needle.length();
  int end = data.indexOf(',', start);
  if (end == -1) end = data.length();
  return data.substring(start, end);
}

void broadcastSync() {
  String syncMsg = "SYNC=" + String(cycleCount);
  LoRa.beginPacket();
  LoRa.print(syncMsg);
  LoRa.endPacket();
  Serial.print(F("[TX] ")); Serial.println(syncMsg);
  LoRa.receive();
}

void setup() {
  Serial.begin(115200);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  for (int i = 0; i <= NODE_COUNT; i++) lastSeq[i] = -1;

  Serial.println(F("=== LoRa SLOTTED ALOHA - GATEWAY ==="));
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
  LoRa.onReceive(onPacket);

  Serial.println(F("OK"));
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.print(F("Slot: ")); Serial.print(SLOT_COUNT);
  Serial.print(F(" x ")); Serial.print(SLOT_DURATION_MS); Serial.println(F(" ms"));
  Serial.println(F("Peran: GATEWAY (Slotted ALOHA) -- siarkan SYNC, dengar tiap slot\n"));
}

void loop() {
  broadcastSync();

  unsigned long cycleStart = millis();
  unsigned long cycleEnd = cycleStart + (unsigned long)SLOT_COUNT * SLOT_DURATION_MS;

  while (millis() < cycleEnd) {
    updateLED();

    if (!rxFlag) continue;
    rxFlag = false;

    String received = "";
    while (LoRa.available()) {
      received += (char)LoRa.read();
    }

    if (!received.startsWith("NODE=")) {
      // Kemungkinan gema SYNC sendiri atau paket asing -- abaikan.
      LoRa.receive();
      continue;
    }

    int nodeId = getField(received, "NODE").toInt();
    long seq   = getField(received, "SEQ").toInt();
    float r1t  = getField(received, "R1T").toFloat();
    int   r1h  = getField(received, "R1H").toInt();
    float r2t  = getField(received, "R2T").toFloat();
    int   r2h  = getField(received, "R2H").toInt();

    int slotObserved = (millis() - cycleStart) / SLOT_DURATION_MS;

    triggerLED();

    Serial.println(F("=== PAKET DITERIMA ==="));
    Serial.print(F("  Node    : ")); Serial.println(nodeId);
    Serial.print(F("  Slot    : ")); Serial.println(slotObserved);
    Serial.print(F("  SEQ     : ")); Serial.println(seq);
    Serial.print(F("  Ruang 1 : ")); Serial.print(r1t, 1); Serial.print(F(" C, "));
    Serial.print(r1h); Serial.println(F(" %"));
    Serial.print(F("  Ruang 2 : ")); Serial.print(r2t, 1); Serial.print(F(" C, "));
    Serial.print(r2h); Serial.println(F(" %"));
    Serial.print(F("  RSSI    : ")); Serial.print(LoRa.packetRssi()); Serial.println(F(" dBm"));
    Serial.print(F("  SNR     : ")); Serial.print(LoRa.packetSnr()); Serial.println(F(" dB"));

    if (nodeId >= 1 && nodeId <= NODE_COUNT) {
      rxCount[nodeId]++;

      if (lastSeq[nodeId] >= 0) {
        long gap = seq - lastSeq[nodeId] - 1;
        if (gap > 0) {
          // Tidak ada retry di M10 -- satu SEQ yang gagal berarti hilang
          // permanen untuk siklus itu, bukan sekadar tabrakan sesaat.
          lostEst[nodeId] += gap;
          Serial.print(F("  [GAP] SEQ meloncat ")); Serial.print(gap);
          Serial.println(F(" -- data hilang pada siklus tersebut (mis. tabrakan slot)"));
        }
      }
      lastSeq[nodeId] = seq;
    }

    // Balas ACK, lalu kembali dengarkan sisa slot / siklus.
    String ack = "ACK=" + String(nodeId) + ",SEQ=" + String(seq);
    LoRa.beginPacket();
    LoRa.print(ack);
    LoRa.endPacket();
    Serial.print(F("  [TX] ")); Serial.println(ack);
    Serial.println(F("=====================\n"));

    LoRa.receive();
  }

  Serial.print(F("--- Cycle ")); Serial.print(cycleCount); Serial.print(F(" selesai | "));
  for (int i = 1; i <= NODE_COUNT; i++) {
    Serial.print(F("N")); Serial.print(i);
    Serial.print(F(": diterima=")); Serial.print(rxCount[i]);
    Serial.print(F(" hilang=")); Serial.print(lostEst[i]);
    Serial.print(F("  "));
  }
  Serial.println(F("---\n"));

  cycleCount++;
}
