/*
  LoRa CSMA/CA - Dragino LoRa Shield v1.2 + Arduino Uno (ATmega328P)
  Library : LoRa by sandeepmistry v0.8.x
  Environment PlatformIO: node1 / node2

  Node membawa satu sensor suhu & kelembaban dan mengirim datanya ke gateway
  KAPAN SAJA ia mau -- tidak ada master, tidak ada polling, tidak ada giliran
  yang dibagikan siapa pun. Satu-satunya aturan yang dipatuhi node adalah
  aturan yang ia jalankan sendiri: DENGARKAN KANAL DULU, dan kalau ada yang
  sedang memakai udara, MUNDUR SEJENAK secara acak sebelum mencoba lagi.

  Itulah CSMA/CA:
    CS (Carrier Sense)      -> radio masuk mode dengar, kanal diperiksa
    MA (Multiple Access)    -> banyak node berbagi satu frekuensi
    CA (Collision Avoidance)-> kalau sibuk: backoff acak, bukan langsung kirim

  Belum ada ACK pada modul ini. Node tahu kanal sedang sepi saat ia mengirim,
  tetapi tetap tidak tahu apakah paketnya benar-benar sampai -- itu urusan
  modul berikutnya.

  Payload  : "NODE=<id>,SEQ=<n>,T=<suhu>,H=<lembab>"
  Balasan  : tidak ada

  Dua cara mendengar kanal, dipilih lewat build flag CS_MODE:
    CS_MODE=0  RSSI  -> radio ditahan di RX kontinu, RegRssiValue dibaca
                        berulang; kanal dianggap terpakai bila RSSI melewati
                        ambang RSSI_THRESHOLD.
    CS_MODE=1  CAD   -> SX1276 disuruh masuk mode Channel Activity Detection,
                        yang mengkorelasikan simbol LoRa dan bisa mengenali
                        sinyal LoRa bahkan di bawah lantai derau. Ditulis
                        dengan akses register langsung (lihat M06), sebab
                        library sandeepmistry tidak menyediakan CAD.

  Mekanisme:
    TX   : blocking (endPacket), hanya setelah kanal dinyatakan bebas
    RX   : tidak ada callback -- node ini murni pengirim. Radio tetap
           ditahan di mode RX bukan untuk membaca paket, melainkan supaya
           penerimanya hidup dan kanal bisa didengar.

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

// Cara mendengar kanal, diatur dari platformio.ini:
//   0 = RSSI, 1 = CAD, 2 = telinga dimatikan (pembanding Pure ALOHA, EXP-04)
#ifndef CS_MODE
#define CS_MODE 0
#endif

// ---------------------------------------------------------------------------
// Parameter CSMA/CA
// ---------------------------------------------------------------------------
// Waktu udara satu paket modul ini (SF7, BW125 kHz, CR4/5, ~26 byte) sekitar
// 60-70 ms. Seluruh angka di bawah dipilih relatif terhadap angka itu:
// DIFS cukup panjang untuk mengambil beberapa sampel, satu slot backoff cukup
// panjang untuk membedakan kanal yang benar-benar bebas dari sela antar-simbol.
#define RSSI_THRESHOLD   -95   // dBm; di atas nilai ini kanal dianggap terpakai
#define RSSI_SAMPLE_MS     2   // jarak antar sampel RSSI
#define DIFS_MS           30   // kanal harus bebas selama ini sebelum boleh TX
#define SLOT_MS           20   // panjang satu slot backoff
#define CW_MIN             4   // contention window awal (jumlah slot)
#define CW_MAX            64   // batas atas contention window
#define MAX_ATTEMPT        5   // sesudah ini paket dibuang, tidak dipaksakan
#define FREEZE_TIMEOUT   2000  // batas menunggu kanal bebas saat backoff beku
#define CAD_TIMEOUT_MS    50   // jaring pengaman bila CadDone tidak pernah naik

// Bisa ditimpa dari platformio.ini (-DSEND_INTERVAL_MIN=300 dst.) supaya
// EXP-03 cukup mengganti build flag, tanpa mengedit file ini.
#ifndef SEND_INTERVAL_MIN
#define SEND_INTERVAL_MIN 2000
#endif
#ifndef SEND_INTERVAL_MAX
#define SEND_INTERVAL_MAX 5000
#endif

// Nilai dasar sensor dibedakan antar node supaya mudah dikenali di gateway.
#if NODE_ID == 1
#define TEMP_BASE        28.0
#define HUM_BASE         70.0
#else
#define TEMP_BASE        29.0
#define HUM_BASE         68.0
#endif

// --- Register SX1276 yang dipakai mode CAD (datasheet SX1276/77/78/79) ---
#define REG_OP_MODE           0x01
#define REG_IRQ_FLAGS         0x12
#define MODE_LONG_RANGE_MODE  0x80
#define MODE_CAD              0x07
#define IRQ_CAD_DONE_MASK     0x04
#define IRQ_CAD_DETECTED_MASK 0x01

unsigned long seq        = 0;
unsigned long txCount    = 0;   // paket yang benar-benar naik ke udara
unsigned long dropCount  = 0;   // paket yang dibuang karena kanal tak kunjung bebas
unsigned long busyCount  = 0;   // berapa kali kanal ketahuan sedang terpakai
unsigned long delaySum   = 0;   // total tunda akses kanal (ms), untuk rata-rata
int  lastSenseRssi       = 0;   // RSSI terakhir yang terbaca saat menyensor

// ---------------------------------------------------------------------------
// Akses register langsung -- dipakai mode CAD saja
// ---------------------------------------------------------------------------
// Bus SPI yang sama dipakai bergantian dengan library. Aman karena node ini
// tidak memasang interrupt DIO0 sama sekali, jadi tidak ada pembacaan register
// yang menyela di tengah transaksi ini.
uint8_t regBaca(uint8_t alamat) {
  SPI.beginTransaction(SPISettings(8E6, MSBFIRST, SPI_MODE0));
  digitalWrite(NSS_PIN, LOW);
  SPI.transfer(alamat & 0x7F);            // bit 7 = 0 -> baca
  uint8_t nilai = SPI.transfer(0x00);
  digitalWrite(NSS_PIN, HIGH);
  SPI.endTransaction();
  return nilai;
}

void regTulis(uint8_t alamat, uint8_t nilai) {
  SPI.beginTransaction(SPISettings(8E6, MSBFIRST, SPI_MODE0));
  digitalWrite(NSS_PIN, LOW);
  SPI.transfer(alamat | 0x80);            // bit 7 = 1 -> tulis
  SPI.transfer(nilai);
  digitalWrite(NSS_PIN, HIGH);
  SPI.endTransaction();
}

// ---------------------------------------------------------------------------
// Carrier sense: satu pemeriksaan kanal
// ---------------------------------------------------------------------------
#if CS_MODE == 1
// CAD: radio diminta menganalisis kanal selama beberapa simbol, lalu melapor
// lewat dua flag -- CadDone (analisis selesai) dan CadDetected (ada sinyal
// LoRa di sana). Sesudah itu radio harus dikembalikan sendiri ke mode RX.
bool kanalTerpakai() {
  // CAD harus dimasuki dari STANDBY. Perintah CAD yang dikirim selagi modem
  // masih di RX kontinu tidak pernah dijalankan: CadDone tidak akan pernah
  // naik dan pemeriksaan ini hanya berakhir di timeout.
  LoRa.idle();
  regTulis(REG_IRQ_FLAGS, 0xFF);                                // bersihkan flag lama
  regTulis(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_CAD);       // mulai CAD

  unsigned long t0 = millis();
  uint8_t flags = 0;
  do {
    flags = regBaca(REG_IRQ_FLAGS);
  } while (!(flags & IRQ_CAD_DONE_MASK) && (millis() - t0 < CAD_TIMEOUT_MS));

  regTulis(REG_IRQ_FLAGS, 0xFF);
  LoRa.receive();                                               // kembali mendengar

  return (flags & IRQ_CAD_DETECTED_MASK) != 0;
}
#elif CS_MODE == 2
// Telinga dimatikan -- node mengirim buta. Ini bukan CSMA/CA lagi melainkan
// Pure ALOHA, dan hanya ada di sini sebagai PEMBANDING untuk EXP-04: berapa
// sebenarnya harga yang dibayar carrier sense, dan apa yang dibeli dengannya.
bool kanalTerpakai() {
  return false;
}
#else
// RSSI: radio sudah ditahan di RX kontinu, jadi RegRssiValue selalu berisi
// kekuatan sinyal kanal saat ini. Tidak ada paket yang perlu didekode --
// yang diperlukan hanya jawaban "ada energi di frekuensi ini atau tidak".
bool kanalTerpakai() {
  lastSenseRssi = LoRa.rssi();
  return lastSenseRssi > RSSI_THRESHOLD;
}
#endif

// Kanal harus bebas SELAMA satu rentang penuh, bukan sekadar bebas pada satu
// sampel. Satu sampel saja terlalu mudah tertipu sela antar-simbol.
bool kanalBebasSelama(unsigned long durasiMs) {
#if CS_MODE == 2
  (void)durasiMs;      // tanpa carrier sense: berangkat saja, tanpa menunggu
  return true;
#else
  unsigned long t0 = millis();
  while (millis() - t0 < durasiMs) {
    if (kanalTerpakai()) return false;
#if CS_MODE == 0
    delay(RSSI_SAMPLE_MS);
#endif
  }
  return true;
#endif
}

void tungguKanalBebas() {
  unsigned long t0 = millis();
  while (kanalTerpakai() && (millis() - t0 < FREEZE_TIMEOUT)) {
    delay(RSSI_SAMPLE_MS);
  }
}

// ---------------------------------------------------------------------------
// Backoff: hitung mundur slot, DIBEKUKAN selagi kanal terpakai
// ---------------------------------------------------------------------------
// Inilah inti "CA". Pencacah tidak berkurang selama ada yang sedang mengirim,
// sehingga node yang sudah lama menunggu tidak kehilangan antreannya ketika
// tetangganya bicara panjang -- persis perilaku DCF pada 802.11.
void hitungMundurSlot(int slot) {
  while (slot > 0) {
    if (kanalBebasSelama(SLOT_MS)) {
      slot--;
    } else {
      Serial.println(F("[FREEZE] pencacah backoff dibekukan -- kanal terpakai"));
      tungguKanalBebas();
    }
  }
}

// ---------------------------------------------------------------------------
// Satu siklus pengiriman CSMA/CA
// ---------------------------------------------------------------------------
bool kirimCSMA(const String& payload) {
  unsigned long tSiap = millis();     // saat data siap, mulai menghitung tunda akses
  int cw = CW_MIN;

  for (int attempt = 1; attempt <= MAX_ATTEMPT; attempt++) {
    if (kanalBebasSelama(DIFS_MS)) {
      // Tunda akses dihitung SAMPAI SINI saja -- sampai kanal diperoleh.
      // Waktu udara paket bukan bagian dari tunda akses: itu harga transmisi,
      // bukan harga menunggu giliran.
      unsigned long tunda = millis() - tSiap;

      // Wajib sebelum beginPacket() bila CAD dipakai: isTransmitting() di
      // library menguji (RegOpMode & 0x03) == 0x03, dan mode CAD (0x07) lolos
      // uji itu. Bila modem kebetulan masih di CAD, beginPacket() diam-diam
      // gagal, FIFO tidak di-reset, dan yang naik ke udara adalah sampah.
      LoRa.idle();

      digitalWrite(LED_PIN, HIGH);
      LoRa.beginPacket();
      LoRa.print(payload);
      LoRa.endPacket();               // blocking sampai paket habis dikirim
      digitalWrite(LED_PIN, LOW);
      LoRa.receive();                 // langsung mendengar lagi

      txCount++;
      delaySum += tunda;

      Serial.print(F("[TX] "));      Serial.print(payload);
      Serial.print(F(" | attempt=")); Serial.print(attempt);
      Serial.print(F(" | tunda="));   Serial.print(tunda);
      Serial.println(F(" ms"));
      return true;
    }

    busyCount++;
    Serial.print(F("[CS] kanal SIBUK"));
#if CS_MODE == 0
    Serial.print(F(" (RSSI ")); Serial.print(lastSenseRssi); Serial.print(F(" dBm)"));
#elif CS_MODE == 1
    Serial.print(F(" (CAD mendeteksi sinyal LoRa)"));
#endif
    Serial.println();

    int slot = random(0, cw);         // 0 .. cw-1 slot
    Serial.print(F("[BACKOFF] percobaan ")); Serial.print(attempt);
    Serial.print(F("/"));                    Serial.print(MAX_ATTEMPT);
    Serial.print(F(" | CW="));               Serial.print(cw);
    Serial.print(F(" | slot="));             Serial.print(slot);
    Serial.print(F(" -> "));                 Serial.print((long)slot * SLOT_MS);
    Serial.println(F(" ms"));

    hitungMundurSlot(slot);

    cw *= 2;                          // contention window melebar tiap kegagalan
    if (cw > CW_MAX) cw = CW_MAX;
  }

  dropCount++;
  Serial.print(F("[DROP] SEQ=")); Serial.print(seq);
  Serial.print(F(" dibuang -- kanal tetap sibuk setelah "));
  Serial.print(MAX_ATTEMPT); Serial.println(F(" percobaan"));
  return false;
}

// ---------------------------------------------------------------------------
// Sensor
// ---------------------------------------------------------------------------
// Data masih dibangkitkan (dummy) supaya modul bisa dijalankan tanpa sensor
// fisik. Untuk memakai DHT22 sungguhan, cukup GANTI ISI FUNGSI INI -- tidak
// ada baris lain di file ini yang perlu diubah, sebab seluruh mekanisme
// CSMA/CA tidak peduli dari mana angkanya datang.
void bacaSensor(float& suhu, float& lembab) {
  suhu   = TEMP_BASE + (random(-30, 31) / 10.0);   // +-3.0 C
  lembab = HUM_BASE  + (random(-50, 51) / 10.0);   // +-5.0 %
}

// ---------------------------------------------------------------------------
// Kalibrasi: seperti apa kanal ini ketika tidak ada siapa-siapa?
// ---------------------------------------------------------------------------
// Dipanggil sekali saat menyala, selagi node lain (mudah-mudahan) belum
// mengirim apa-apa. Angka inilah bahan EXP-01: ambang kanal-sibuk yang masuk
// akal ada di antara lantai derau ini dan RSSI node tetangga saat mengirim.
void laporLantaiDerau() {
  const int JUMLAH_SAMPEL = 200;
  int minimum =  0;
  int maksimum = -200;
  long jumlah = 0;

  for (int i = 0; i < JUMLAH_SAMPEL; i++) {
    int r = LoRa.rssi();
    if (r < minimum)  minimum  = r;
    if (r > maksimum) maksimum = r;
    jumlah += r;
    delay(5);
  }

  Serial.print(F("[KALIBRASI] lantai derau ")); Serial.print(JUMLAH_SAMPEL);
  Serial.print(F(" sampel: min ")); Serial.print(minimum);
  Serial.print(F(" | rata-rata ")); Serial.print((int)(jumlah / JUMLAH_SAMPEL));
  Serial.print(F(" | maks ")); Serial.print(maksimum);
  Serial.println(F(" dBm"));
#if CS_MODE == 0
  Serial.print(F("[KALIBRASI] ambang terpakai sekarang: "));
  Serial.print(RSSI_THRESHOLD); Serial.println(F(" dBm -- lihat EXP-01"));
#elif CS_MODE == 1
  Serial.println(F("[KALIBRASI] mode CAD: angka di atas hanya rujukan, CAD tidak memakai ambang"));
#else
  Serial.println(F("[KALIBRASI] carrier sense MATI: angka di atas tidak dipakai sama sekali"));
#endif
}

void setup() {
  Serial.begin(115200);
  while (!Serial);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  randomSeed(analogRead(A0) + NODE_ID);

  Serial.print(F("=== LoRa CSMA/CA - NODE "));
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

  // Tidak ada LoRa.onReceive() di sini: node ini tidak pernah membaca paket.
  // Radio ditahan di RX kontinu semata-mata supaya kanal bisa didengar.
  LoRa.receive();

  Serial.println(F("OK"));
  Serial.print(F("Freq: ")); Serial.print(FREQUENCY / 1E6); Serial.println(F(" MHz"));
  Serial.print(F("Carrier sense: "));
#if CS_MODE == 0
  Serial.print(F("RSSI (ambang ")); Serial.print(RSSI_THRESHOLD); Serial.print(F(" dBm)"));
#elif CS_MODE == 1
  Serial.print(F("CAD (Channel Activity Detection)"));
#else
  Serial.print(F("MATI -- kirim buta (Pure ALOHA, pembanding EXP-04)"));
#endif
  Serial.print(F(" | DIFS ")); Serial.print(DIFS_MS);
  Serial.print(F(" ms | slot ")); Serial.print(SLOT_MS);
  Serial.print(F(" ms | CW ")); Serial.print(CW_MIN);
  Serial.print(F("..")); Serial.println(CW_MAX);
  Serial.println(F("Peran: NODE (CSMA/CA) -- dengar dulu, mundur acak, baru kirim"));
  Serial.println(F("Tanpa ACK: node tahu kanal sepi, tetap tidak tahu paketnya sampai"));

  laporLantaiDerau();
  Serial.println();
}

void loop() {
  float suhu, lembab;
  bacaSensor(suhu, lembab);

  String payload = "NODE=" + String(NODE_ID) +
                    ",SEQ=" + String(seq) +
                    ",T="   + String(suhu, 1) +
                    ",H="   + String(lembab, 1);

  kirimCSMA(payload);

  unsigned long rataTunda = txCount ? (delaySum / txCount) : 0;
  Serial.print(F("[STAT] TX="));            Serial.print(txCount);
  Serial.print(F(" | DROP="));              Serial.print(dropCount);
  Serial.print(F(" | kanal sibuk="));       Serial.print(busyCount);
  Serial.print(F(" | rata-rata tunda="));   Serial.print(rataTunda);
  Serial.println(F(" ms"));
  Serial.println();

  seq++;   // naik untuk setiap data yang DIHASILKAN, termasuk yang dibuang,
           // supaya gateway melihat lubang SEQ pada paket yang tidak terkirim

  delay(random(SEND_INTERVAL_MIN, SEND_INTERVAL_MAX + 1));
}
