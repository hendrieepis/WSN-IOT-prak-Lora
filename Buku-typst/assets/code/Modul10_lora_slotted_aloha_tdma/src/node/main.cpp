/*
  LoRa Slotted ALOHA - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: node1 / node2

  Pengembangan dari M09, tapi mengganti "coba lagi dengan jeda acak" (backoff)
  dengan "bicara hanya pada jatah waktu sendiri" (slot). Gateway menyiarkan
  "SYNC=<cycle>" di awal tiap siklus; node memakai saat SYNC tiba sebagai
  referensi waktu bersama, lalu menghitung kapan gilirannya:

    txTime = waktuTerimaSync + slotIndex * SLOT_DURATION_MS + SLOT_GUARD_MS

  Dua mode pemilihan slot (SLOT_MODE_RANDOM di bawah):
    Mode B (default, 0) - Assigned : slotIndex = NODE_ID - 1, tetap selamanya
    Mode A (1)          - Random   : slotIndex diundi ulang tiap siklus

  Tidak ada lagi retry/backoff seperti M09 -- kalau satu siklus gagal, node
  tidak mengejarnya lagi; SYNC berikutnya membuka giliran baru dengan data
  yang lebih baru. Penjadwalan menggantikan peran retry sepenuhnya.

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

// Nomor node datang dari build flag (-DNODE_ID=1 atau 2) di platformio.ini,
// sehingga kedua node memakai file source yang sama persis.
#ifndef NODE_ID
#define NODE_ID 1
#endif

// SLOT_COUNT dan SLOT_DURATION_MS HARUS SAMA PERSIS dengan gateway/main.cpp
// -- keduanya tidak pernah dipertukarkan lewat radio, hanya disepakati lewat
// kode, persis seperti parameter radio (SF, BW, CR) yang juga tidak dikirim.
#ifndef SLOT_COUNT
#define SLOT_COUNT          2     // Node 1 -> slot 0 ("ganjil"), Node 2 -> slot 1 ("genap")
#endif
#define SLOT_DURATION_MS  800     // cukup untuk TX DATA + ACK + margin pada SF7
#define SLOT_GUARD_MS      50     // jeda kecil dari awal slot sebelum kirim

// 0 = Mode B (Assigned Slot, tanpa tabrakan bila SYNC benar)
// 1 = Mode A (Random Slot, masih bisa tabrakan bila dua node memilih slot sama)
// Ganti nilainya untuk EXP-02 lalu unggah ulang KEDUA node.
#ifndef SLOT_MODE_RANDOM
#define SLOT_MODE_RANDOM 0
#endif

#define ROOM1_TEMP_BASE  27.0
#define ROOM1_HUM_BASE   60
#define ROOM2_TEMP_BASE  25.0
#define ROOM2_HUM_BASE   68

unsigned long seq = 0;
unsigned long okCount = 0;
unsigned long failCount = 0;

volatile bool rxFlag = false;

void onPacket(int size) {
  if (size > 0) rxFlag = true;
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

// Blok sampai paket "SYNC=<cycle>" tiba. Paket lain (DATA/ACK milik siklus
// sebelumnya, atau milik node lain) dibaca lalu diabaikan -- radio LoRa tidak
// beralamat, sehingga node mendengar SEMUA lalu lintas, bukan hanya miliknya.
void waitForSync(unsigned long& syncTime, long& cycleNum) {
  LoRa.receive();
  unsigned long lastHeartbeat = millis();

  while (true) {
    if (rxFlag) {
      rxFlag = false;
      String msg = "";
      while (LoRa.available()) {
        msg += (char)LoRa.read();
      }

      if (msg.startsWith("SYNC=")) {
        cycleNum = msg.substring(5).toInt();
        syncTime = millis();
        return;
      }
      LoRa.receive();
    }

    if (millis() - lastHeartbeat > 3000) {
      Serial.println(F("[WAIT] Menunggu SYNC dari gateway..."));
      lastHeartbeat = millis();
    }
  }
}

void setup() {
  Serial.begin(115200);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  randomSeed(analogRead(A0));

  Serial.print(F("=== LoRa SLOTTED ALOHA - NODE "));
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
  LoRa.onReceive(onPacket);

  Serial.println(F("OK"));
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.print(F("Slot: ")); Serial.print(SLOT_COUNT);
  Serial.print(F(" x ")); Serial.print(SLOT_DURATION_MS); Serial.println(F(" ms"));
#if SLOT_MODE_RANDOM
  Serial.println(F("Mode : A (Random Slot) -- slot diundi tiap siklus"));
#else
  Serial.print(F("Mode : B (Assigned Slot) -- tetap di slot "));
  Serial.println(NODE_ID - 1);
#endif
  Serial.println(F("Menunggu SYNC pertama dari gateway...\n"));
}

void loop() {
  unsigned long syncTime;
  long cycleNum;
  waitForSync(syncTime, cycleNum);

#if SLOT_MODE_RANDOM
  int slotIndex = random(0, SLOT_COUNT);
#else
  int slotIndex = NODE_ID - 1;
#endif

  unsigned long txTime = syncTime + (unsigned long)slotIndex * SLOT_DURATION_MS + SLOT_GUARD_MS;
  while (millis() < txTime) { /* tunggu giliran slot */ }

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

  digitalWrite(LED_PIN, HIGH);
  transmit(payload);
  digitalWrite(LED_PIN, LOW);

  Serial.print(F("[TX] cycle=")); Serial.print(cycleNum);
  Serial.print(F(" slot=")); Serial.print(slotIndex);
  Serial.print(F(" | ")); Serial.println(payload);

  // Tunggu ACK hanya sampai batas AKHIR slot sendiri -- tidak boleh
  // menyerobot waktu slot node lain.
  unsigned long slotEnd = syncTime + (unsigned long)(slotIndex + 1) * SLOT_DURATION_MS;
  rxFlag = false;
  LoRa.receive();

  bool gotAck = false;
  while (millis() < slotEnd) {
    if (rxFlag) {
      rxFlag = false;
      String reply = "";
      while (LoRa.available()) {
        reply += (char)LoRa.read();
      }
      if (reply == expectedAck) {
        gotAck = true;
        break;
      }
      // Bukan ACK yang ditunggu (mis. SYNC/DATA node lain yang ikut
      // terdengar) -- abaikan, tetap tunggu sampai batas slot.
    }
  }

  if (gotAck) {
    okCount++;
    Serial.print(F("[OK] ACK diterima"));
  } else {
    failCount++;
    Serial.print(F("[FAIL] Tidak ada ACK dalam slot ini"));
  }
  Serial.print(F(" | OK: ")); Serial.print(okCount);
  Serial.print(F(" | FAIL: ")); Serial.println(failCount);
  Serial.println();

  seq++;
  // Tidak ada delay/backoff -- loop berikutnya langsung menunggu SYNC baru.
}
