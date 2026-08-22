/*
  LoRaWAN Class A - Node OTAA
  Arduino Uno (ATmega328P) + Dragino LoRa Shield v1.2 (SX1276)
  Library : MCCI LoRaWAN LMIC 4.1.x
  Environment PlatformIO: node1 / node2

  Modul pertama di lab ini yang TIDAK mengirim byte mentah. Sembilan modul
  sebelumnya menaruh string apa adanya di udara ("NODE=1,SEQ=3,..."), dan semua
  yang menyerupai jaringan -- alamat, ACK, penjadwalan -- dibangun sendiri di
  lapisan aplikasi. Di sini pekerjaan itu diserahkan ke protokol: LMIC yang
  mengurus join, alamat perangkat (DevAddr), MIC, enkripsi payload, frame
  counter, dan dua jendela RX. Yang tersisa untuk kode ini hanyalah "kirim 11
  byte ini", persis seperti pada sensor komersial.

  Alur satu perangkat:

    OTAA join  : kirim JoinRequest (DevEUI + JoinEUI + MIC dari AppKey)
                 -> ChirpStack membalas JoinAccept di jendela RX1 (5 detik)
                 -> NwkSKey & AppSKey diturunkan di kedua sisi, DevAddr dipakai
    Uplink     : tiap TX_INTERVAL detik, "T=xx.x,H=xx" unconfirmed di FPort 1
    Downlink   : dicek otomatis di RX1/RX2 sesudah tiap uplink (Class A)

  Payload sengaja ASCII dan tanpa encoding apa pun ("T=27.4,H=68") supaya di
  ChirpStack terlihat langsung tanpa codec. Pengemasan biner yang hemat adalah
  bahan modul berikutnya, bukan modul ini.

  Dummy sensor dibedakan rentangnya per node, sehingga asal data langsung
  terbaca di layar ChirpStack tanpa perlu melihat DevEUI:

    Node 1 (Ruangan 1) : suhu 25-30 C, kelembapan 60-75 %
    Node 2 (Ruangan 2) : suhu 28-35 C, kelembapan 40-65 %

  KANAL TUNGGAL. Gateway modul ini hanya mendengar SATU frekuensi pada SATU
  spreading factor (433.175 MHz, SF7BW125). Karena itu seluruh rencana kanal
  LoRaWAN dilumpuhkan menjadi satu kanal saja -- lihat lockSingleChannel().

  Pin Mapping Dragino Shield v1.2 (sama seperti M01-M10, ditambah DIO1):
    NSS/CS -> D10, RST -> D9, DIO0 -> D2, DIO1 -> D6, DIO2 -> D7
    SCK -> D13, MOSI -> D11, MISO -> D12

  DIO1 WAJIB pada modul ini, dan inilah bedanya dengan M01-M10. Library
  sandeepmistry hanya perlu DIO0 (RxDone/TxDone). LMIC juga perlu DIO1, yaitu
  RxTimeout: sinyal "jendela RX sudah lewat, tidak ada apa-apa" -- tanpa itu
  LMIC tidak pernah tahu kapan harus menyerah menunggu downlink. Pada shield
  Dragino v1.2, DIO1 sudah tersambung ke D6 dari pabrik, tidak perlu kabel.
*/

#include <Arduino.h>
#include <lmic.h>
#include <hal/hal.h>
#include <SPI.h>

#include "lorawan_keys.h"

// ── Identitas node ────────────────────────────────────────────────────────────
#ifndef NODE_ID
#define NODE_ID 1
#endif

#if NODE_ID == 1
#define ROOM_NAME   "Ruangan 1"
#define T_MIN_X10   250     // 25.0 C
#define T_MAX_X10   300     // 30.0 C
#define H_MIN       60
#define H_MAX       75
#else
#define ROOM_NAME   "Ruangan 2"
#define T_MIN_X10   280     // 28.0 C
#define T_MAX_X10   350     // 35.0 C
#define H_MIN       40
#define H_MAX       65
#endif

// ── Parameter LoRaWAN ─────────────────────────────────────────────────────────
#define TX_INTERVAL   30    // detik antar-uplink (dihitung dari selesainya TX)
#define FPORT          1    // port aplikasi; 1-223 bebas dipakai aplikasi

// Kanal tunggal yang didengar gateway. HARUS sama persis dengan frekuensi
// yang dipakai gateway (--freq pada single_chan_pkt_fwd.py).
//
// Tiap kelompok memakai satu kanal wajib EU433 sendiri, supaya tiga meja di
// satu ruangan tidak saling menimpa. Nomornya datang dari -DKELOMPOK di
// platformio.ini, dan menggeser DevEUI/AppKey juga -- lihat lorawan_keys.h.
#ifndef KELOMPOK
#define KELOMPOK 1
#endif

#if KELOMPOK == 1
#define SC_FREQ_HZ    433175000UL
#define SC_FREQ_TXT   "433.175"
#elif KELOMPOK == 2
#define SC_FREQ_HZ    433375000UL
#define SC_FREQ_TXT   "433.375"
#elif KELOMPOK == 3
#define SC_FREQ_HZ    433575000UL
#define SC_FREQ_TXT   "433.575"
#else
#error "KELOMPOK harus 1, 2, atau 3 -- satu kanal EU433 untuk tiap kelompok"
#endif
#define SC_DR         DR_SF7        // SF7BW125 = DR5 pada rencana EU433/EU868

// Jendela RX2 menurut EU433. Gateway kanal tunggal tidak pernah memakainya
// (ChirpStack menjawab di RX1), tetapi nilai bawaan LMIC adalah RX2 EU868
// 869.525 MHz -- di luar band perangkat keras 433 MHz, jadi tetap dibetulkan.
#define SC_RX2_FREQ_HZ 434665000UL

// ── Pemetaan pin shield untuk LMIC ────────────────────────────────────────────
const lmic_pinmap lmic_pins = {
    .nss = 10,
    .rxtx = LMIC_UNUSED_PIN,   // shield tidak punya switch RX/TX terpisah
    .rst = 9,
    .dio = {2, 6, 7},          // DIO0 -> D2, DIO1 -> D6, DIO2 -> D7
    .rxtx_rx_active = 0,
    .rssi_cal = 10,
    .spi_freq = 1000000,
};

// ── Kunci OTAA: LMIC memanggil ketiga fungsi ini saat menyusun JoinRequest ────
void os_getArtEui(u1_t *buf) { memcpy_P(buf, APPEUI, 8); }
void os_getDevEui(u1_t *buf) { memcpy_P(buf, DEVEUI, 8); }
void os_getDevKey(u1_t *buf) { memcpy_P(buf, APPKEY, 16); }

static osjob_t sendjob;
static uint8_t payload[16];
static uint16_t txCount = 0;

// ═════════════════════════════════════════════════════════════════════════════
// Kanal tunggal
// ═════════════════════════════════════════════════════════════════════════════
/*
  Rencana kanal EU868 bawaan LMIC punya tiga kanal wajib (868.1/868.3/868.5) dan
  menyebar uplink ke ketiganya secara acak. Di depan gateway kanal tunggal,
  dua dari tiga uplink akan hilang tanpa jejak -- gejala yang membingungkan
  karena tidak ada pesan galat sama sekali.

  Karena itu kanal 0 didefinisikan ulang ke 433.175 MHz dan kanal 1-8
  dimatikan, sehingga hanya ada satu kemungkinan frekuensi. Datarate juga
  dikunci di SF7 dan ADR dimatikan, supaya server tidak pernah memindahkan
  node ke SF lain yang tidak didengar gateway.

  Fungsi ini dipanggil TIGA KALI, dan ketiganya diperlukan:

    1. di setup()      -- keadaan awal
    2. di EV_JOINING   -- WAJIB. LMIC_startJoining() memanggil initJoinLoop()
                          yang MENGEMBALIKAN tabel kanal ke tiga kanal bawaan
                          EU868 (868.1/868.3/868.5). Tanpa pemanggilan ulang di
                          sini, node mengirim JoinRequest di 868 MHz dan gateway
                          tidak mendengar apa pun -- tanpa satu pun pesan galat.
    3. di EV_JOINED    -- JoinAccept boleh membawa daftar kanal tambahan
                          (CFList) yang otomatis dipasang LMIC.
*/
static void lockSingleChannel() {
    LMIC_setupChannel(0, SC_FREQ_HZ, DR_RANGE_MAP(DR_SF12, DR_SF7), BAND_CENTI);
    for (u1_t ch = 1; ch < 9; ch++) {
        LMIC_disableChannel(ch);
    }
    LMIC.dn2Freq = SC_RX2_FREQ_HZ;   // RX2 sesuai EU433, bukan bawaan EU868
    LMIC.dn2Dr = DR_SF12;
    LMIC_setAdrMode(0);          // server tidak boleh memindahkan DR
    LMIC_setLinkCheckMode(0);    // tanpa link check: hemat, dan tidak relevan di 1 kanal
    LMIC_setDrTxpow(SC_DR, 14);
}

// ═════════════════════════════════════════════════════════════════════════════
// Payload dummy
// ═════════════════════════════════════════════════════════════════════════════
static uint8_t buildPayload() {
    int t10 = random(T_MIN_X10, T_MAX_X10 + 1);   // suhu x10, supaya tanpa float
    int h   = random(H_MIN, H_MAX + 1);

    // Format sengaja seragam untuk kedua node: "T=27.4,H=68"
    char buf[16];
    snprintf(buf, sizeof(buf), "T=%d.%d,H=%d", t10 / 10, t10 % 10, h);

    uint8_t len = strlen(buf);
    memcpy(payload, buf, len);
    return len;
}

static void do_send(osjob_t *j) {
    if (LMIC.opmode & OP_TXRXPEND) {
        Serial.println(F("[TX] dilewati - masih ada TX/RX berjalan"));
        return;
    }

    uint8_t len = buildPayload();
    payload[len] = '\0';

    // Argumen terakhir 0 = unconfirmed uplink: node tidak menunggu ACK dari
    // server. Bandingkan dengan ACK buatan sendiri di M04/M08B -- di sini
    // confirmed uplink cukup diganti angka 1, dan seluruh mekanismenya sudah
    // disediakan protokol.
    LMIC_setTxData2(FPORT, payload, len, 0);

    txCount++;
    Serial.print(F("[TX #"));
    Serial.print(txCount);
    Serial.print(F("] FPort="));
    Serial.print(FPORT);
    Serial.print(F(" \""));
    Serial.print((char *)payload);
    Serial.println(F("\" -> antre di LMIC"));
}

// ═════════════════════════════════════════════════════════════════════════════
// Event LMIC
// ═════════════════════════════════════════════════════════════════════════════
void onEvent(ev_t ev) {
    switch (ev) {
        case EV_JOINING:
            // initJoinLoop() baru saja mengembalikan tabel kanal ke bawaan
            // EU868 -- kunci ulang ke kanal tunggal 433.175 MHz.
            lockSingleChannel();
            Serial.println(F("[JOIN] mengirim JoinRequest ..."));
            break;

        case EV_JOINED: {
            u4_t netid = 0;
            devaddr_t devaddr = 0;
            u1_t nwkKey[16];
            u1_t artKey[16];
            LMIC_getSessionKeys(&netid, &devaddr, nwkKey, artKey);

            Serial.println(F("[JOIN] BERHASIL"));
            Serial.print(F("  DevAddr : "));
            Serial.println(devaddr, HEX);
            Serial.print(F("  NetID   : "));
            Serial.println(netid, HEX);

            // JoinAccept boleh membawa CFList -> kunci ulang ke satu kanal.
            lockSingleChannel();

            do_send(&sendjob);
            break;
        }

        case EV_JOIN_FAILED:
            Serial.println(F("[JOIN] GAGAL - LMIC akan mencoba lagi"));
            break;

        case EV_REJOIN_FAILED:
            Serial.println(F("[JOIN] rejoin gagal"));
            break;

        case EV_TXSTART:
            // Pengaman terakhir, tepat sebelum os_radio(RADIO_TX): LMIC sudah
            // selesai memilih kanal dan datarate, dan di sinilah keduanya
            // dipaksa kembali ke kanal tunggal gateway. Diperlukan karena
            // percobaan join berikutnya selalu menurunkan DR (SF7 -> SF8 ->
            // ... -> SF12), sementara gateway hanya mendengar SF7.
            LMIC.freq = SC_FREQ_HZ;
            if (LMIC.datarate != SC_DR) {
                LMIC.datarate = SC_DR;
                LMIC.rps = setCr(updr2rps(SC_DR), (cr_t)LMIC.errcr);
                LMIC.dndr = SC_DR;      // RX1 memakai DR yang sama dengan uplink
            }
            Serial.print(F("[TX] radio: "));
            Serial.print(LMIC.freq / 1000);
            Serial.print(F(" kHz DR"));
            Serial.println(LMIC.datarate);
            break;

        case EV_TXCOMPLETE:
            Serial.print(F("[TX] selesai (FCntUp="));
            Serial.print(LMIC.seqnoUp);
            Serial.println(F(")"));

            if (LMIC.txrxFlags & TXRX_ACK) {
                Serial.println(F("  ACK dari server diterima"));
            }
            if (LMIC.dataLen > 0) {
                Serial.print(F("  [RX] downlink "));
                Serial.print(LMIC.dataLen);
                Serial.print(F(" byte, RSSI="));
                Serial.print(LMIC.rssi);
                Serial.print(F(" dBm SNR="));
                Serial.println(LMIC.snr / 4);
            }

            os_setTimedCallback(&sendjob,
                                os_getTime() + sec2osticks(TX_INTERVAL),
                                do_send);
            break;

        case EV_JOIN_TXCOMPLETE:
            Serial.println(F("[JOIN] tidak ada JoinAccept di RX1/RX2"));
            break;

        default:
            Serial.print(F("[EV] "));
            Serial.println((unsigned)ev);
            break;
    }
}

// ═════════════════════════════════════════════════════════════════════════════
void setup() {
    Serial.begin(115200);
    while (!Serial && millis() < 3000) { }

    Serial.println();
    Serial.print(F("=== LoRaWAN NODE "));
    Serial.print(NODE_ID);
    Serial.print(F(" - " ROOM_NAME " (Kelompok "));
    Serial.print(KELOMPOK);
    Serial.println(F(") ==="));
    Serial.print(F("Kanal   : " SC_FREQ_TXT " MHz SF7BW125 (kanal tunggal)\r\nInterval: "));
    Serial.print(TX_INTERVAL);
    Serial.println(F(" detik"));

    // Seed acak dari pin analog mengambang -- cukup untuk dummy sensor, dan
    // membuat kedua node tidak menghasilkan deret angka yang identik.
    randomSeed(analogRead(A0) + NODE_ID * 977);

    os_init();
    LMIC_reset();

    // Toleransi jam. Jendela RX node dilebarkan 20% supaya tetap terbuka saat
    // downlink dari gateway Python datang beberapa milidetik lebih cepat atau
    // lambat dari jadwal. Konsentrator SX1301 asli tidak memerlukan ini;
    // gateway kanal tunggal yang menjadwalkan dari user space memerlukannya.
    LMIC_setClockError(MAX_CLOCK_ERROR * 20 / 100);

    lockSingleChannel();

    Serial.println(F("Menyusun JoinRequest OTAA ..."));
    LMIC_startJoining();
}

void loop() {
    os_runloop_once();
}
