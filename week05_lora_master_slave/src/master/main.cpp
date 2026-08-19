/*
  LoRa Master-Slave 3 Node - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: master

  Topologi Master-Slave dengan 3 node:
    - 1 Master (COM3) : polling Slave 1 & Slave 2 secara bergantian
    - 2 Slave  (COM4, COM5) : hanya merespon saat dipanggil

  Mekanisme:
    TX : blocking (endPacket) — sederhana dan andal di AVR
    RX : polling via LoRa.parsePacket() — tidak perlu ISR

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

#define POLL_TIMEOUT     500
#define CYCLE_INTERVAL   500
#define SLAVE_COUNT      2

int cycle = 0;
int s1Ok = 0, s1Fail = 0, s1Data = 0;
int s2Ok = 0, s2Fail = 0, s2Data = 0;

unsigned long cycleStartMs = 0;

void transmit(const String& msg) {
  LoRa.beginPacket();
  LoRa.print(msg);
  LoRa.endPacket();
}

bool pollSlave(int slaveNum, int& dataOut, int& okCount, int& failCount) {
  String pollMsg = "POLL:" + String(slaveNum);
  Serial.print(F("[TX] ")); Serial.println(pollMsg);
  transmit(pollMsg);

  LoRa.receive();

  unsigned long waitStart = millis();
  while (millis() - waitStart < POLL_TIMEOUT) {
    int ps = LoRa.parsePacket();
    if (ps > 0) {
      String reply = "";
      while (LoRa.available()) {
        reply += (char)LoRa.read();
      }

      String prefix = "S" + String(slaveNum) + ":DATA:";
      if (reply.startsWith(prefix)) {
        dataOut = reply.substring(prefix.length()).toInt();
        okCount++;
        Serial.print(F("[RX] ")); Serial.print(reply);
        Serial.print(F(" | RSSI: ")); Serial.print(LoRa.packetRssi());
        Serial.print(F(" dBm | SNR: ")); Serial.print(LoRa.packetSnr());
        Serial.println(F(" dB"));
        return true;
      } else {
        Serial.print(F("[WARN] Balasan tidak valid: ")); Serial.println(reply);
      }
    }
  }

  failCount++;
  Serial.print(F("[FAIL] Slave ")); Serial.print(slaveNum);
  Serial.println(F(" tidak merespon!"));
  return false;
}

void setup() {
  Serial.begin(115200);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  Serial.println(F("=== LoRa MASTER-SLAVE 3 NODE ==="));
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
  Serial.print(F("SF")); Serial.print(SPREADING_FACTOR);
  Serial.print(F(" | BW: ")); Serial.print(BANDWIDTH / 1E3); Serial.println(F(" kHz"));
  Serial.println(F("Peran: MASTER (env master)"));
  Serial.println(F("Slave: env slave1 (S1) & slave2 (S2)"));
  Serial.println();
}

void loop() {
  cycle++;
  cycleStartMs = millis();

  Serial.println(F("========================================"));
  Serial.print(F("=== CYCLE ")); Serial.print(cycle);
  Serial.println(F(" ==="));

  // --- Poll Slave 1 ---
  digitalWrite(LED_PIN, HIGH);
  pollSlave(1, s1Data, s1Ok, s1Fail);
  digitalWrite(LED_PIN, LOW);

  // --- Poll Slave 2 ---
  digitalWrite(LED_PIN, HIGH);
  pollSlave(2, s2Data, s2Ok, s2Fail);
  digitalWrite(LED_PIN, LOW);

  // --- Statistik ---
  unsigned long duration = millis() - cycleStartMs;
  Serial.println(F("--- STATISTIK ---"));
  Serial.print(F("S1: OK=")); Serial.print(s1Ok);
  Serial.print(F(" | FAIL=")); Serial.print(s1Fail);
  Serial.print(F(" | Data: ")); Serial.println(s1Data);
  Serial.print(F("S2: OK=")); Serial.print(s2Ok);
  Serial.print(F(" | FAIL=")); Serial.print(s2Fail);
  Serial.print(F(" | Data: ")); Serial.println(s2Data);
  Serial.print(F("Durasi siklus: ")); Serial.print(duration); Serial.println(F(" ms"));
  Serial.println(F("========================================\n"));

  delay(CYCLE_INTERVAL);
}
