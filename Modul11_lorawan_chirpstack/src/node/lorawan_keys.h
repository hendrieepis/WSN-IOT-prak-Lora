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

  NOMOR KELOMPOK IKUT MENENTUKAN KUNCI. Bila beberapa kelompok bekerja di satu
  ruangan, kunci yang sama persis di semua meja berbahaya: gateway kelompok
  sebelah ikut mendengar JoinRequest node Anda, dan karena AppKey-nya cocok,
  server mereka akan menjawabnya -- node Anda bisa join ke jaringan kelompok
  lain tanpa satu pun pesan galat. Karena itu -DKELOMPOK=<n> di platformio.ini
  menggeser dua byte:

    DevEUI : 0011223344 55 KK NN     KK = 66 (klp 1), 77 (klp 2), 88 (klp 3)
                                     NN = 01 (Node 1), 02 (Node 2)
    AppKey : KK 112233445566778899AABBCCDDEE FN
                                     KK = 00 (klp 1), 01 (klp 2), 02 (klp 3)
                                     FN = F1 (Node 1), F2 (Node 2)

  Kelompok 1 memakai nilai yang sama persis dengan contoh di README, sehingga
  seluruh tabel dan log di modul ini tetap berlaku apa adanya.
*/
#ifndef LORAWAN_KEYS_H
#define LORAWAN_KEYS_H

#include <Arduino.h>

#ifndef KELOMPOK
#define KELOMPOK 1
#endif

#if NODE_ID != 1 && NODE_ID != 2
#error "NODE_ID harus 1 atau 2 -- diatur lewat build_flags di platformio.ini"
#endif
#if KELOMPOK < 1 || KELOMPOK > 3
#error "KELOMPOK harus 1, 2, atau 3 -- satu kanal EU433 untuk tiap kelompok"
#endif

// Byte pembeda kelompok, dihitung compiler (bukan saat program berjalan).
#define EUI_BYTE_KELOMPOK  (0x66 + (KELOMPOK - 1) * 0x11)
#define KEY_BYTE_KELOMPOK  (KELOMPOK - 1)

// DevEUI di ChirpStack : 0011223344 55 <KK> <0N>   -- ditulis LSB-first di sini
static const u1_t PROGMEM DEVEUI[8]  = { NODE_ID, EUI_BYTE_KELOMPOK,
                                         0x55, 0x44, 0x33, 0x22, 0x11, 0x00 };

// JoinEUI di ChirpStack: 0000000000000000
static const u1_t PROGMEM APPEUI[8]  = { 0x00, 0x00, 0x00, 0x00,
                                         0x00, 0x00, 0x00, 0x00 };

// AppKey di ChirpStack : <KK> 112233445566778899AABBCCDDEE <FN>  -- MSB, tidak dibalik
static const u1_t PROGMEM APPKEY[16] = { KEY_BYTE_KELOMPOK, 0x11, 0x22, 0x33,
                                         0x44, 0x55, 0x66, 0x77,
                                         0x88, 0x99, 0xAA, 0xBB,
                                         0xCC, 0xDD, 0xEE, 0xF0 + NODE_ID };

#endif  // LORAWAN_KEYS_H
