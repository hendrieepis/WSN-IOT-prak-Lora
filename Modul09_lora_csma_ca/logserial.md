# Log Serial — Modul 08 (CSMA/CA)

Hasil aktual dari perangkat, direkam **2026-08-23**. Baud **115200**, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm. Ketiga board di satu meja dengan jarak berbeda-beda — Node 1 lebih dekat ke gateway daripada Node 2 (lihat RSSI di bawah).

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Gateway | `gateway` | `/dev/ttyACM0` | Uno asli (`2341:0043`) |
| Node 1 | `node1` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |
| Node 2 | `node2` | `/dev/ttyACM2` | Uno asli (`2341:0043`) |

Ketiga aliran serial direkam bersamaan (tiga thread `pyserial`, satu per port), masing-masing sesi **180 detik** dihitung sejak perekaman dimulai — mencakup boot ketiga board. Parameter CSMA/CA memakai nilai bawaan modul: DIFS 30 ms, slot 20 ms, CW 4…64, `MAX_ATTEMPT` 5, ambang RSSI −95 dBm.

## Ringkasan keempat sesi

| Sesi | Carrier sense | Interval kirim | Dikirim node | Tiba di gateway | Hilang | `[GAP]` | `[WARN]` |
|---|---|---|---|---|---|---|---|
| EXP-02 | RSSI | 2000–5000 ms | 99 | 98 | 1 (1,0%) | 1 | 0 |
| EXP-03 | RSSI | 300–500 ms | 700 | 695 | 4 (0,6%) | 4 | 0 |
| EXP-04 | **mati** | 300–500 ms | 757 | 581 | **176 (23,2%)** | 102 | 37 |
| EXP-05 | CAD | 300–500 ms | 699 | 694 | 4 (0,6%) | 4 | 2 |

Perkiraan kehilangan dari lompatan `SEQ` di gateway (62 + 113 = 175 pada EXP-04) cocok dengan selisih kirim-terima yang sebenarnya (757 − 581 = 176) — selisih satu paket berasal dari paket terakhir yang belum sempat tercatat saat perekaman berhenti.

## Statistik akses kanal per node

| Sesi | Node | TX | `[CS]` sibuk | `[BACKOFF]` | `[FREEZE]` | `[DROP]` | CW maks | Tunda akses med / rata / maks (ms) |
|---|---|---|---|---|---|---|---|---|
| EXP-02 | 1 | 50 | 1 | 1 | 1 | 0 | 4 | 31 / 31,7 / 116 |
| EXP-02 | 2 | 49 | 2 | 2 | 2 | 0 | 4 | 32 / 34,3 / 87 |
| EXP-03 | 1 | 352 | 32 | 32 | 26 | 0 | 8 | 32 / 37,2 / 238 |
| EXP-03 | 2 | 348 | 67 | 67 | 46 | 0 | 16 | 44 / 46,1 / 257 |
| EXP-04 | 1 | 377 | 0 | 0 | 0 | 0 | — | 0 / 0 / 0 |
| EXP-04 | 2 | 380 | 0 | 0 | 0 | 0 | — | 0 / 0 / 0 |
| EXP-05 | 1 | 350 | 56 | 56 | 53 | 0 | 8 | 41 / 43,3 / 240 |
| EXP-05 | 2 | 349 | 51 | 51 | 43 | 0 | 16 | 39 / 41,3 / 299 |

`[DROP]` **nol di seluruh sesi**: bahkan pada beban tertinggi, lima percobaan selalu cukup untuk memperoleh kanal. Untuk memaksa `[DROP]` muncul, perkecil `MAX_ATTEMPT` atau tambah node ketiga (lihat CH-2).

## RSSI & SNR di gateway

| Sesi | Node 1 | Node 2 |
|---|---|---|
| EXP-02 | −44,3 dBm / 9,38 dB | −55,8 dBm / 9,63 dB |
| EXP-03 | −44,7 dBm / 9,77 dB | −54,5 dBm / 9,73 dB |
| EXP-04 | −43,3 dBm / **8,58 dB** | −54,0 dBm / 9,63 dB |
| EXP-05 | −44,5 dBm / 9,77 dB | −56,1 dBm / 9,85 dB |

Selisih ±11 dB antar node murni posisi fisik di meja. SNR Node 1 yang turun ~1,2 dB khusus di EXP-04 adalah jejak tabrakan: paket yang tetap berhasil didekode pun sebagian tercemar sinyal node lain.

## EXP-02 — Boot dan peristiwa backoff pertama

Cuplikan 1,5 detik pertama. Ketiga board menyala hampir bersamaan; kedua node melaporkan lantai derau sekitar −110 dBm. Perhatikan Node 2: pengukuran kalibrasinya sendiri sudah "tercemar" transmisi Node 1 (`maks -30 dBm`), lalu ia langsung mendeteksi kanal sibuk, mundur 2 slot, membekukan pencacahnya, dan baru mengirim 136 ms setelah paket Node 1 tiba.

```
[11:12:28.633] N1 | === LoRa CSMA/CA - NODE 1 ===
[11:12:28.649] N1 | Init LoRa ... OK
[11:12:28.653] N1 | Freq: 433.00 MHz
[11:12:28.658] N1 | Carrier sense: RSSI (ambang -95 dBm) | DIFS 30 ms | slot 20 ms | CW 4..64
[11:12:28.666] N1 | Peran: NODE (CSMA/CA) -- dengar dulu, mundur acak, baru kirim
[11:12:28.670] N1 | Tanpa ACK: node tahu kanal sepi, tetap tidak tahu paketnya sampai
[11:12:28.687] GW | === LoRa CSMA/CA - GATEWAY ===
[11:12:28.707] GW | Init LoRa ... OK
[11:12:28.707] GW | Freq: 433.00 MHz
[11:12:28.715] GW | Peran: GATEWAY (CSMA/CA) -- hanya mendengar, tanpa polling, tanpa ACK
[11:12:28.715] N2 | === LoRa CSMA/CA - NODE 2 ===
[11:12:28.718] GW | Menunggu paket dari Node 1 & Node 2...
[11:12:28.718] GW |
[11:12:28.735] N2 | Init LoRa ... OK
[11:12:28.735] N2 | Freq: 433.00 MHz
[11:12:28.743] N2 | Carrier sense: RSSI (ambang -95 dBm) | DIFS 30 ms | slot 20 ms | CW 4..64
[11:12:28.747] N2 | Peran: NODE (CSMA/CA) -- dengar dulu, mundur acak, baru kirim
[11:12:28.755] N2 | Tanpa ACK: node tahu kanal sepi, tetap tidak tahu paketnya sampai
[11:12:29.677] N1 | [KALIBRASI] lantai derau 200 sampel: min -117 | rata-rata -110 | maks -105 dBm
[11:12:29.685] N1 | [KALIBRASI] ambang terpakai sekarang: -95 dBm -- lihat EXP-01
[11:12:29.686] N1 |
[11:12:29.763] N2 | [KALIBRASI] lantai derau 200 sampel: min -118 | rata-rata -110 | maks -30 dBm
[11:12:29.767] N2 | [KALIBRASI] ambang terpakai sekarang: -95 dBm -- lihat EXP-01
[11:12:29.767] N2 |
[11:12:29.771] N2 | [CS] kanal SIBUK (RSSI -33 dBm)
[11:12:29.775] N2 | [BACKOFF] percobaan 1/5 | CW=4 | slot=2 -> 40 ms
[11:12:29.776] N1 | [TX] NODE=1,SEQ=0,T=27.1,H=70.5 | attempt=1 | tunda=31 ms
[11:12:29.779] GW | === PAKET DITERIMA ===
[11:12:29.779] N2 | [FREEZE] pencacah backoff dibekukan -- kanal terpakai
[11:12:29.780] GW |   Node    : 1
[11:12:29.780] GW |   SEQ     : 0
[11:12:29.783] N1 | [STAT] TX=1 | DROP=0 | kanal sibuk=0 | rata-rata tunda=31 ms
[11:12:29.784] GW |   Suhu    : 27.1 C
[11:12:29.784] GW |   Lembab  : 70.5 %
[11:12:29.784] GW |   RSSI    : -45 dBm
[11:12:29.784] N1 |
[11:12:29.788] GW |   SNR     : 9.25 dB
[11:12:29.792] GW |   Statistik Node 1: diterima=1 | perkiraan hilang=0
[11:12:29.796] GW |   Total diterima gateway: 1
[11:12:29.796] GW | =====================
[11:12:29.796] GW |
[11:12:29.915] GW | === PAKET DITERIMA ===
[11:12:29.915] GW |   Node    : 2
[11:12:29.915] N2 | [TX] NODE=2,SEQ=0,T=27.1,H=71.0 | attempt=2 | tunda=84 ms
[11:12:29.918] N2 | [STAT] TX=1 | DROP=0 | kanal sibuk=1 | rata-rata tunda=84 ms
[11:12:29.918] N2 |
[11:12:29.919] GW |   SEQ     : 0
[11:12:29.919] GW |   Suhu    : 27.1 C
[11:12:29.919] GW |   Lembab  : 71.0 %
[11:12:29.923] GW |   RSSI    : -55 dBm
[11:12:29.923] GW |   SNR     : 9.50 dB
[11:12:29.927] GW |   Selang  : 136 ms dari paket sebelumnya
[11:12:29.931] GW |   Statistik Node 2: diterima=1 | perkiraan hilang=0
[11:12:29.935] GW |   Total diterima gateway: 2
[11:12:29.935] GW | =====================
[11:12:29.935] GW |
```

Baris kuncinya:

```
[11:12:29.771] N2 | [CS] kanal SIBUK (RSSI -33 dBm)      <- telinga bekerja
[11:12:29.775] N2 | [BACKOFF] percobaan 1/5 | CW=4 | slot=2 -> 40 ms
[11:12:29.776] N1 | [TX] NODE=1,SEQ=0,... | attempt=1 | tunda=31 ms
[11:12:29.779] N2 | [FREEZE] pencacah backoff dibekukan  <- N1 masih mengudara
[11:12:29.915] N2 | [TX] NODE=2,SEQ=0,... | attempt=2 | tunda=84 ms
[11:12:29.927] GW |   Selang  : 136 ms dari paket sebelumnya
```

Tunda akses Node 1 = 31 ms, yaitu DIFS saja (kanal memang sepi). Tunda akses Node 2 = 84 ms: DIFS + backoff + waktu beku menunggu Node 1 selesai.

## EXP-03 — Beban tinggi: contention window melebar

Interval kirim dipersempit menjadi 300–500 ms pada kedua node. Cuplikan berikut memperlihatkan `CW` menggandakan diri 4 → 8 → 16 karena kanal ditemukan sibuk tiga kali berturut-turut, sampai akhirnya Node 2 memperoleh kanal pada percobaan ke-4 dengan tunda 155 ms:

```
[11:02:03.950] N2 | [BACKOFF] percobaan 1/5 | CW=4 | slot=0 -> 0 ms
[11:02:03.954] N2 | [CS] kanal SIBUK (RSSI -31 dBm)
[11:02:03.958] N2 | [BACKOFF] percobaan 2/5 | CW=8 | slot=0 -> 0 ms
[11:02:03.962] N2 | [CS] kanal SIBUK (RSSI -32 dBm)
[11:02:03.966] N2 | [BACKOFF] percobaan 3/5 | CW=16 | slot=3 -> 60 ms
[11:02:03.970] N2 | [FREEZE] pencacah backoff dibekukan -- kanal terpakai
[11:02:04.009] GW | === PAKET DITERIMA ===
[11:02:04.010] N1 | [TX] NODE=1,SEQ=231,T=29.1,H=67.5 | attempt=1 | tunda=31 ms
[11:02:04.013] GW |   Node    : 1
[11:02:04.013] GW |   SEQ     : 231
[11:02:04.014] GW |   Suhu    : 29.1 C
[11:02:04.014] N1 | [STAT] TX=232 | DROP=0 | kanal sibuk=19 | rata-rata tunda=37 ms
[11:02:04.014] N1 |
[11:02:04.018] GW |   Lembab  : 67.5 %
[11:02:04.018] GW |   RSSI    : -45 dBm
[11:02:04.021] GW |   SNR     : 9.75 dB
[11:02:04.026] GW |   Selang  : 409 ms dari paket sebelumnya
[11:02:04.030] GW |   Statistik Node 1: diterima=232 | perkiraan hilang=0
[11:02:04.030] GW |   Total diterima gateway: 457
[11:02:04.034] GW | =====================
[11:02:04.034] GW |
[11:02:04.166] N2 | [TX] NODE=2,SEQ=228,T=29.7,H=72.1 | attempt=4 | tunda=155 ms
[11:02:04.169] GW | === PAKET DITERIMA ===
[11:02:04.169] GW |   Node    : 2
[11:02:04.169] GW |   SEQ     : 228
[11:02:04.171] N2 | [STAT] TX=229 | DROP=0 | kanal sibuk=47 | rata-rata tunda=44 ms
[11:02:04.171] N2 |
[11:02:04.173] GW |   Suhu    : 29.7 C
[11:02:04.173] GW |   Lembab  : 72.1 %
[11:02:04.173] GW |   RSSI    : -55 dBm
[11:02:04.177] GW |   SNR     : 9.50 dB
[11:02:04.181] GW |   Selang  : 155 ms dari paket sebelumnya
[11:02:04.186] GW |   Statistik Node 2: diterima=226 | perkiraan hilang=3
[11:02:04.189] GW |   Total diterima gateway: 458
[11:02:04.189] GW | =====================
[11:02:04.190] GW |
```

Meski kanal diperebutkan sepanjang sesi, **tidak satu pun `[WARN]`** muncul di gateway: setiap paket yang berhasil naik ke udara tiba utuh dan terbaca penuh.

## EXP-04 — Telinga dimatikan (pembanding Pure ALOHA)

Kedua node dibangun dengan `-DCS_MODE=2`, interval tetap 300–500 ms. Tunda akses jatuh ke **0 ms** — dan konsekuensinya langsung terlihat di gateway. Cuplikan di bawah menangkap satu paket Node 2 yang bertabrakan di udara: awalannya masih utuh terbaca (`NODE=2,SEQ=1,T=28.`), sisanya hancur.

```
[10:56:40.865] N2 | [TX] NODE=2,SEQ=1,T=28.4,H=72.1 | attempt=1 | tunda=0 ms
[10:56:40.866] GW | [WARN] Paket cacat (field tidak lengkap): NODE=2,SEQ=1,T=28.t,??,a?2
[10:56:40.869] N2 | [STAT] TX=2 | DROP=0 | kanal sibuk=0 | rata-rata tunda=0 ms
[10:56:40.869] N2 |
[10:56:40.913] N1 | [TX] NODE=1,SEQ=1,T=30.4,H=72.0 | attempt=1 | tunda=0 ms
[10:56:40.917] N1 | [STAT] TX=2 | DROP=0 | kanal sibuk=0 | rata-rata tunda=0 ms
[10:56:40.917] N1 |
```

Sepanjang sesi ini gateway mencatat **102 `[GAP]` dan 37 paket cacat** — bandingkan dengan 4 `[GAP]` dan 0 cacat pada EXP-03 yang mengirim jumlah paket serupa.

Paket cacat semacam inilah yang memaksa gateway memeriksa kelengkapan field sebelum mempercayai isinya. Tanpa pemeriksaan itu, `SEQ` yang hilang dibaca sebagai `0` dan satu paket rusak saja sanggup merusak statistik seluruh sesi — pada percobaan pertama sebelum perbaikan, perkiraan kehilangan Node 2 melonjak ke **1177** padahal kenyataannya sekitar 30:

```
[10:54:09.727] GW |   Selang  : 387 ms dari paket sebelumnya
[10:54:09.735] GW |   [GAP] SEQ meloncat 272 -- paket dibuang node atau bertabrakan
[10:54:09.739] GW |   Statistik Node 2: diterima=233 | perkiraan hilang=1177
```

## EXP-05 — Carrier sense berbasis CAD

Kedua node dibangun dengan `-DCS_MODE=1`. Node tidak lagi memakai ambang dBm apa pun; SX1276 sendiri yang memutuskan ada-tidaknya simbol LoRa di kanal.

```
[11:09:12.395] N1 | [CS] kanal SIBUK (CAD mendeteksi sinyal LoRa)
[11:09:12.400] N1 | [BACKOFF] percobaan 1/5 | CW=4 | slot=1 -> 20 ms
[11:09:12.407] N1 | [FREEZE] pencacah backoff dibekukan -- kanal terpakai
[11:09:12.419] GW | === PAKET DITERIMA ===
[11:09:12.422] N2 | [TX] NODE=2,SEQ=19,T=31.4,H=65.2 | attempt=1 | tunda=31 ms
[11:09:12.423] GW |   Node    : 2
[11:09:12.423] GW |   SEQ     : 19
[11:09:12.423] GW |   Suhu    : 31.4 C
[11:09:12.426] N2 | [STAT] TX=20 | DROP=0 | kanal sibuk=5 | rata-rata tunda=46 ms
[11:09:12.426] N2 |
[11:09:12.427] GW |   Lembab  : 65.2 %
[11:09:12.427] GW |   RSSI    : -56 dBm
[11:09:12.431] GW |   SNR     : 9.75 dB
[11:09:12.435] GW |   Selang  : 412 ms dari paket sebelumnya
[11:09:12.439] GW |   Statistik Node 2: diterima=20 | perkiraan hilang=0
[11:09:12.439] GW |   Total diterima gateway: 39
[11:09:12.443] GW | =====================
[11:09:12.443] GW |
[11:09:12.537] GW | === PAKET DITERIMA ===
[11:09:12.538] GW |   Node    : 1
[11:09:12.538] GW |   SEQ     : 19
[11:09:12.538] N1 | [TX] NODE=1,SEQ=19,T=30.0,H=65.7 | attempt=2 | tunda=79 ms
[11:09:12.542] GW |   Suhu    : 30.0 C
[11:09:12.542] GW |   Lembab  : 65.7 %
[11:09:12.542] N1 | [STAT] TX=20 | DROP=0 | kanal sibuk=1 | rata-rata tunda=32 ms
[11:09:12.542] N1 |
[11:09:12.546] GW |   RSSI    : -44 dBm
[11:09:12.546] GW |   SNR     : 9.50 dB
[11:09:12.550] GW |   Selang  : 116 ms dari paket sebelumnya
[11:09:12.554] GW |   Statistik Node 1: diterima=20 | perkiraan hilang=0
[11:09:12.559] GW |   Total diterima gateway: 40
[11:09:12.559] GW | =====================
[11:09:12.559] GW |
```

Hasil akhirnya setara RSSI (694 vs 695 paket tiba, sama-sama 4 hilang), tetapi CAD **melaporkan kanal sibuk lebih sering**: 107 kali berbanding 99 kali pada beban yang sama persis. Ini konsisten dengan sifat CAD yang mengenali sinyal LoRa sampai di bawah lantai derau, sementara ambang RSSI −95 dBm melewatkan sinyal lemah.

Satu catatan penting untuk yang mengutak-atik mode ini: pada percobaan pertama, CAD sama sekali tidak pernah mendeteksi apa pun (`[CS] kanal SIBUK` = 0) **dan** merusak transmisi node itu sendiri — 103 dari 440 paket tiba dalam keadaan cacat. Dua sebabnya, keduanya sudah diperbaiki di kode sekarang:

1. **CAD harus dimasuki dari STANDBY.** Perintah CAD yang dikirim selagi modem masih di RX kontinu tidak pernah dijalankan; `CadDone` tidak pernah naik dan setiap pemeriksaan hanya berakhir di timeout 50 ms (terlihat dari tunda akses yang konstan 50 ms).
2. **`isTransmitting()` di library menganggap mode CAD sebagai "sedang TX".** Fungsi itu menguji `(RegOpMode & 0x03) == 0x03`, dan mode CAD bernilai `0x07` lolos uji tersebut. Bila modem kebetulan masih berada di CAD saat `beginPacket()` dipanggil, `beginPacket()` gagal diam-diam tanpa me-reset FIFO — dan yang naik ke udara adalah sampah. Karena itu `LoRa.idle()` dipanggil sebelum `beginPacket()`.

Kedua jebakan itu tidak akan pernah terlihat dari dokumentasi library, sebab library ini memang tidak menyediakan CAD sama sekali.
