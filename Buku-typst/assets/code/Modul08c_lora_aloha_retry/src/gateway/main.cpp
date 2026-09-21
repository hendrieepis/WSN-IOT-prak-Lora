/*
  LoRa ALOHA + ACK + Random Backoff + Retry
  Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: gateway

  Pengembangan langsung dari M08B: karena node sekarang mengirim ULANG
  paket yang ACK-nya hilang, gateway bisa menerima SEQ yang SAMA lebih dari
  sekali -- bukan data baru, melainkan retry akibat ACK sebelumnya tidak
  sampai ke node. Gateway membedakan keduanya lewat lastSeq per node: SEQ
  yang sama dengan yang terakhir SUDAH diproses berarti duplicate, dicetak
  sebagai [DUP] dan TIDAK dihitung sebagai data baru -- tetapi tetap dibalas
  ACK, sebab justru itulah yang membuat node akhirnya berhasil.

  Payload  : "NODE=<id>,SEQ=<n>,R1T=<c>,R1H=<pct>,R2T=<c>,R2H=<pct>"
  Balasan  : "ACK=<id>,SEQ=<n>"

  Mekanisme:
    RX : interrupt DIO0 + flag (non-blocking)
    TX : blocking (endPacket), langsung setelah RX selesai diproses,
         dikirim untuk data baru MAUPUN duplicate

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

volatile bool rxFlag = false;

unsigned long ledOnTime = 0;
bool ledActive = false;

unsigned long rxCount[NODE_COUNT + 1] = {0};   // data BARU (bukan duplicate) yang diterima
unsigned long dupCount[NODE_COUNT + 1] = {0};  // retry yang dikenali sebagai duplicate
long lastSeq[NODE_COUNT + 1];                  // SEQ terakhir yang sudah diproses sebagai data baru
unsigned long lostEst[NODE_COUNT + 1] = {0};   // gagal permanen (semua retry habis)

void onReceive(int size) {
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

void setup() {
  Serial.begin(115200);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  for (int i = 0; i <= NODE_COUNT; i++) lastSeq[i] = -1;

  Serial.println(F("=== LoRa ALOHA+ACK+RETRY - GATEWAY ==="));
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
  LoRa.onReceive(onReceive);
  LoRa.receive();

  Serial.println(F("OK"));
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.println(F("Peran: GATEWAY (ALOHA + ACK + Retry) -- kenali duplicate lewat SEQ"));
  Serial.println(F("Menunggu paket dari Node 1 & Node 2...\n"));
}

void loop() {
  updateLED();

  if (!rxFlag) return;
  rxFlag = false;

  String received = "";
  while (LoRa.available()) {
    received += (char)LoRa.read();
  }

  if (!received.startsWith("NODE=")) {
    Serial.print(F("[WARN] Paket tak dikenal (mungkin sisa tabrakan): "));
    Serial.println(received);
    LoRa.receive();
    return;
  }

  int nodeId = getField(received, "NODE").toInt();
  long seq   = getField(received, "SEQ").toInt();
  float r1t  = getField(received, "R1T").toFloat();
  int   r1h  = getField(received, "R1H").toInt();
  float r2t  = getField(received, "R2T").toFloat();
  int   r2h  = getField(received, "R2H").toInt();

  triggerLED();

  bool validNode = (nodeId >= 1 && nodeId <= NODE_COUNT);
  bool isDuplicate = validNode && (lastSeq[nodeId] >= 0) && (seq <= lastSeq[nodeId]);

  if (isDuplicate) {
    dupCount[nodeId]++;
    Serial.println(F("=== PAKET DITERIMA (DUPLICATE) ==="));
    Serial.print(F("  Node    : ")); Serial.println(nodeId);
    Serial.print(F("  SEQ     : ")); Serial.print(seq);
    Serial.println(F("  -- sudah pernah diproses, ini retry akibat ACK sebelumnya hilang"));
    Serial.print(F("  Duplicate ke- ")); Serial.print(dupCount[nodeId]);
    Serial.print(F(" untuk Node ")); Serial.println(nodeId);
  } else {
    Serial.println(F("=== PAKET DITERIMA (DATA BARU) ==="));
    Serial.print(F("  Node    : ")); Serial.println(nodeId);
    Serial.print(F("  SEQ     : ")); Serial.println(seq);
    Serial.print(F("  Ruang 1 : ")); Serial.print(r1t, 1); Serial.print(F(" C, "));
    Serial.print(r1h); Serial.println(F(" %"));
    Serial.print(F("  Ruang 2 : ")); Serial.print(r2t, 1); Serial.print(F(" C, "));
    Serial.print(r2h); Serial.println(F(" %"));
    Serial.print(F("  RSSI    : ")); Serial.print(LoRa.packetRssi()); Serial.println(F(" dBm"));
    Serial.print(F("  SNR     : ")); Serial.print(LoRa.packetSnr()); Serial.println(F(" dB"));

    if (validNode) {
      rxCount[nodeId]++;

      if (lastSeq[nodeId] >= 0) {
        long gap = seq - lastSeq[nodeId] - 1;
        if (gap > 0) {
          // Retry M09 membuat ini jauh lebih jarang daripada [GAP] M08/M08B --
          // hanya muncul kalau SELURUH percobaan retry untuk satu SEQ gagal.
          lostEst[nodeId] += gap;
          Serial.print(F("  [GAP] SEQ meloncat ")); Serial.print(gap);
          Serial.println(F(" -- gagal permanen (retry habis), bukan sekadar tabrakan sesaat"));
        }
      }
      lastSeq[nodeId] = seq;

      Serial.print(F("  Statistik Node ")); Serial.print(nodeId);
      Serial.print(F(": baru=")); Serial.print(rxCount[nodeId]);
      Serial.print(F(" | duplicate=")); Serial.print(dupCount[nodeId]);
      Serial.print(F(" | gagal permanen (est.)=")); Serial.println(lostEst[nodeId]);
    }
  }

  // ACK dibalas untuk DATA BARU maupun DUPLICATE -- retry hanya berhenti
  // kalau node akhirnya menerima ACK, tidak peduli ini percobaan keberapa.
  if (validNode) {
    String ack = "ACK=" + String(nodeId) + ",SEQ=" + String(seq);
    LoRa.beginPacket();
    LoRa.print(ack);
    LoRa.endPacket();
    Serial.print(F("  [TX] ")); Serial.println(ack);
  }
  Serial.println(F("=====================\n"));

  LoRa.receive();
}
