/*
  Kunci OTAA Modul 11 -- dipilih oleh build flag -DNODE_ID (platformio.ini).

  Tiga identitas yang dipakai LoRaWAN 1.0.x saat join OTAA:

    DevEUI  (8 byte)  identitas unik perangkat, seperti nomor seri
    JoinEUI (8 byte)  dulu bernama AppEUI -- identitas server join.
                      ChirpStack tidak memakainya untuk memilih perangkat,
                      jadi nol semua adalah nilai yang lazim di lab.
    AppKey  (16 byte) rahasia bersama. Dari kunci inilah NwkSKey dan AppSKey
                      diturunkan saat join berhasil. Nilai ini HARUS sama
                      persis dengan yang didaftarkan di ChirpStack.

  URUTAN BYTE ADALAH JEBAKAN UTAMA MODUL INI:

    DevEUI dan JoinEUI ditulis LSB-first (little endian) di sini, karena itulah
    yang diminta os_getDevEui()/os_getArtEui(). ChirpStack menampilkan keduanya
    MSB-first (seperti dibaca manusia). Jadi DevEUI yang di layar ChirpStack
    tertulis 0011223344556601 harus dibalik urutan bytenya menjadi
    { 0x01, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00 } di bawah.

    AppKey ditulis MSB-first -- TIDAK dibalik. Persis seperti di ChirpStack.

  Salah balik = MIC join request tidak cocok, dan gejalanya paling menyesatkan
  di seluruh modul ini: gateway tetap menerima paket, ChirpStack tetap mencatat
  frame masuk, tetapi perangkat tidak pernah join. Lihat README EXP-02.

  Nilai di bawah adalah kunci LAB -- boleh dipakai apa adanya. Untuk perangkat
  sungguhan, AppKey wajib acak dan tidak pernah masuk repository.
*/
#ifndef LORAWAN_KEYS_H
#define LORAWAN_KEYS_H

#include <Arduino.h>

#if NODE_ID == 1

// DevEUI di ChirpStack : 0011223344556601   (MSB, urutan baca manusia)
static const u1_t PROGMEM DEVEUI[8]  = { 0x01, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00 };
// JoinEUI di ChirpStack: 0000000000000000
static const u1_t PROGMEM APPEUI[8]  = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
// AppKey di ChirpStack : 00112233445566778899AABBCCDDEEF1  (MSB, tidak dibalik)
static const u1_t PROGMEM APPKEY[16] = { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                                         0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xF1 };

#elif NODE_ID == 2

// DevEUI di ChirpStack : 0011223344556602
static const u1_t PROGMEM DEVEUI[8]  = { 0x02, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00 };
// JoinEUI di ChirpStack: 0000000000000000
static const u1_t PROGMEM APPEUI[8]  = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
// AppKey di ChirpStack : 00112233445566778899AABBCCDDEEF2
static const u1_t PROGMEM APPKEY[16] = { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                                         0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xF2 };

#else
#error "NODE_ID harus 1 atau 2 -- diatur lewat build_flags di platformio.ini"
#endif

#endif  // LORAWAN_KEYS_H
