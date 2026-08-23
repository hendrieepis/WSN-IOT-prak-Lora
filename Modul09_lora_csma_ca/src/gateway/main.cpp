/*
  LoRa CSMA/CA - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: gateway

  Gateway di modul ini SENGAJA pasif. Ia bukan master: tidak memanggil node,
  tidak membagi giliran, tidak mengirim SYNC, dan belum membalas ACK. Seluruh
  keputusan "kapan boleh bicara" ada di node, dan gateway hanya menyaksikan
  hasilnya. Yang dikerjakan gateway hanya tiga hal:

    1. mendengar terus-menerus (interrupt DIO0 + flag, tanpa blocking),
    2. mencatat isi paket beserta RSSI/SNR-nya,
    3. memperkirakan paket hilang dari lompatan nomor urut SEQ.

  Karena tidak ada balasan apa pun, arah radio di sini satu arah penuh --
  yang berarti gateway tidak pernah ikut membuat kanal sibuk. Inilah yang
  membuat pengamatan CSMA/CA di modul ini bersih: setiap kali sebuah node
  melaporkan "kanal sibuk", yang ia dengar pasti node satunya.

  Payload  : "NODE=<id>,SEQ=<n>,T=<suhu>,H=<lembab>"
  Balasan  : tidak ada

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

unsigned long rxTotal = 0;
unsigned long rxCount[NODE_COUNT + 1] = {0};
long lastSeq[NODE_COUNT + 1];
unsigned long lostEst[NODE_COUNT + 1] = {0};
unsigned long lastRxTime = 0;

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

  Serial.println(F("=== LoRa CSMA/CA - GATEWAY ==="));
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
  Serial.println(F("Peran: GATEWAY (CSMA/CA) -- hanya mendengar, tanpa polling, tanpa ACK"));
  Serial.println(F("Menunggu paket dari Node 1 & Node 2...\n"));
}

void loop() {
  updateLED();

  if (!rxFlag) return;
  rxFlag = false;

  unsigned long now = millis();

  String received = "";
  while (LoRa.available()) {
    received += (char)LoRa.read();
  }

  if (!received.startsWith("NODE=")) {
    // Paket yang tetap lolos header tetapi isinya kacau biasanya sisa tabrakan
    // atau interferensi -- dicetak apa adanya supaya bisa dihitung praktikan.
    Serial.print(F("[WARN] Paket tak dikenal (mungkin sisa tabrakan): "));
    Serial.println(received);
    LoRa.receive();
    return;
  }

  String fNode = getField(received, "NODE");
  String fSeq  = getField(received, "SEQ");
  String fT    = getField(received, "T");
  String fH    = getField(received, "H");

  // Paket yang rusak di udara kadang masih menyisakan awalan "NODE=" utuh
  // sementara sisanya hancur. Tanpa pemeriksaan ini, field yang hilang dibaca
  // toInt() sebagai 0 -- dan SEQ palsu bernilai 0 membuat perkiraan kehilangan
  // meledak ratusan paket pada paket berikutnya yang sah. Satu paket rusak
  // tidak boleh merusak seluruh statistik sesi.
  if (fNode.length() == 0 || fSeq.length() == 0 ||
      fT.length()    == 0 || fH.length()   == 0) {
    Serial.print(F("[WARN] Paket cacat (field tidak lengkap): "));
    Serial.println(received);
    LoRa.receive();
    return;
  }

  int   nodeId = fNode.toInt();
  long  seq    = fSeq.toInt();
  float suhu   = fT.toFloat();
  float lembab = fH.toFloat();

  triggerLED();
  rxTotal++;

  Serial.println(F("=== PAKET DITERIMA ==="));
  Serial.print(F("  Node    : ")); Serial.println(nodeId);
  Serial.print(F("  SEQ     : ")); Serial.println(seq);
  Serial.print(F("  Suhu    : ")); Serial.print(suhu, 1);   Serial.println(F(" C"));
  Serial.print(F("  Lembab  : ")); Serial.print(lembab, 1); Serial.println(F(" %"));
  Serial.print(F("  RSSI    : ")); Serial.print(LoRa.packetRssi()); Serial.println(F(" dBm"));
  Serial.print(F("  SNR     : ")); Serial.print(LoRa.packetSnr()); Serial.println(F(" dB"));

  // Selang antar-kedatangan: pada kanal yang benar-benar diatur CSMA/CA, dua
  // paket tidak pernah tiba nyaris bersamaan -- yang datang belakangan
  // seharusnya sudah menunggu lebih dulu di sisi node.
  if (lastRxTime > 0) {
    Serial.print(F("  Selang  : ")); Serial.print(now - lastRxTime);
    Serial.println(F(" ms dari paket sebelumnya"));
  }
  lastRxTime = now;

  if (nodeId >= 1 && nodeId <= NODE_COUNT) {
    rxCount[nodeId]++;

    if (lastSeq[nodeId] >= 0) {
      long gap = seq - lastSeq[nodeId] - 1;
      if (gap > 0) {
        lostEst[nodeId] += gap;
        Serial.print(F("  [GAP] SEQ meloncat "));
        Serial.print(gap);
        Serial.println(F(" -- paket dibuang node atau bertabrakan"));
      }
    }
    lastSeq[nodeId] = seq;

    Serial.print(F("  Statistik Node ")); Serial.print(nodeId);
    Serial.print(F(": diterima=")); Serial.print(rxCount[nodeId]);
    Serial.print(F(" | perkiraan hilang=")); Serial.println(lostEst[nodeId]);
  }

  Serial.print(F("  Total diterima gateway: ")); Serial.println(rxTotal);
  Serial.println(F("=====================\n"));

  LoRa.receive();
}
