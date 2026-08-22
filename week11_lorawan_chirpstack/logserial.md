# Log Serial — Modul 11 (LoRaWAN + ChirpStack)

Hasil aktual dari perangkat. Node: baud **115200**, LoRaWAN Class A OTAA, kanal tunggal **433.175 MHz SF7BW125 CR4/5** (kelompok 1), interval uplink 30 detik, payload ASCII `T=..,H=..` di FPort 1 (unconfirmed). Gateway: Raspberry Pi 5 + Dragino LoRa GPS HAT v1.4 menjalankan `single_chan_pkt_fwd.py`, ChirpStack v4 (Docker) di Pi yang sama, region **EU433**.

## Board & Port

| Peran | Environment / skrip | Port | Board |
|---|---|---|---|
| Node 1 (Ruangan 1) | `node1` | `/dev/ttyACM1` | Uno asli (`2341:0043`) + Dragino LoRa Shield v1.2 |
| Node 2 (Ruangan 2) | `node2` | `/dev/ttyACM2` | Uno asli (`2341:0043`) + Dragino LoRa Shield v1.2 |
| Gateway | `gateway/single_chan_pkt_fwd.py` | — | Raspberry Pi 5 + LoRa GPS HAT v1.4, Gateway EUI `2CCF67FFFE53AC11` |
| Server | ChirpStack v4 (Docker) | `:8080` UI, `:1700/udp`, `:1883` MQTT | Raspberry Pi 5 yang sama |

Sesi rekam: **17:18:38–17:24:18**, Node 1 dinyalakan lebih dahulu dan Node 2 menyusul 45 detik kemudian — persis urutan yang diminta README, supaya kedua JoinRequest tidak berebut satu-satunya kanal yang didengar gateway.

## EXP-02 — OTAA Join

Sisi node (Node 1), dari boot sampai uplink pertama:

```
[17:18:40] [   1.5] === LoRaWAN NODE 1 - Ruangan 1 (Kelompok 1) ===
[17:18:40] [   1.5] Kanal   : 433.175 MHz SF7BW125 (kanal tunggal)
[17:18:40] [   1.5] Interval: 30 detik
[17:18:40] [   1.6] Menyusun JoinRequest OTAA ...
[17:18:40] [   1.6] [JOIN] mengirim JoinRequest ...
[17:18:43] [   4.7] [TX] radio: 433175 kHz DR5
[17:18:48] [   9.8] [JOIN] BERHASIL
[17:18:48] [   9.8]   DevAddr : 1EBD973
[17:18:48] [   9.8]   NetID   : 0
[17:18:48] [   9.8] [TX] radio: 433175 kHz DR5
[17:18:48] [   9.8] [TX #1] FPort=1 "T=25.0,H=66" -> antre di LMIC
[17:18:49] [  10.9] [TX] selesai (FCntUp=1)
```

Kejadian yang sama dari sisi gateway — perhatikan jeda **4786 ms** yang ditentukan server untuk JoinAccept (jendela RX1 join = 5 detik dikurangi waktu pemrosesan), dan ketelitian penembakannya:

```
17:18:43.397  [RX]  23 B  RSSI= -66 dBm  SNR=  9.8 dB  tmst=1631694015
              JoinRequest DevEUI=0011223344556601 DevNonce=23600
17:18:43.611  [TX] downlink dijadwalkan: 17 B  433.175 MHz  SF7BW125  dalam 4786 ms
              JoinAccept (17 byte)
17:18:48.443  [TX] terkirim (meleset -0.2 ms dari jadwal)
17:18:48.524  [RX]  24 B  RSSI= -67 dBm  SNR= 10.0 dB  tmst=1636821687
              UnconfirmedDataUp DevAddr=01EBD973 FCnt=0 FPort=1 (payload terenkripsi)
17:18:48.853  [TX] downlink dijadwalkan: 13 B  433.175 MHz  SF7BW125  dalam 671 ms
              UnconfirmedDataDown (13 byte)
17:18:49.565  [TX] terkirim (meleset -0.2 ms dari jadwal)
17:18:54.669  [RX]  15 B  RSSI= -67 dBm  SNR=  9.5 dB  tmst=1642965879
              UnconfirmedDataUp DevAddr=01EBD973 FCnt=1 (payload terenkripsi)
```

Node 2, join pada percobaan pertama juga, 45 detik sesudahnya:

```
[17:19:25] [   1.7] [JOIN] mengirim JoinRequest ...
[17:19:26] [   3.1] [TX] radio: 433175 kHz DR5
[17:19:31] [   8.2] [JOIN] BERHASIL
[17:19:31] [   8.2]   DevAddr : 1DC98E3
```

**Tiga hal yang terbaca dari cuplikan di atas.**

1. **DevAddr diberikan server, dan berbeda untuk tiap node** (`01EBD973` dan `01DC98E3`) — bandingkan `NODE_ID` M05–M10 yang ditentukan build flag. Nilainya juga berganti setiap kali join diulang, jadi jangan heran bila berbeda dari sesi Anda.
2. **Ada uplink yang tidak pernah diminta kode aplikasi.** Baris `FCnt=1` berukuran 15 byte, tanpa `FPort`, dan tidak didahului `[TX #n]` di sisi node. Itu jawaban otomatis LMIC atas perintah MAC (`DevStatusReq`) yang dititipkan server pada downlink 13 byte sebelumnya — lapisan MAC bekerja sendiri tanpa sepengetahuan `loop()`.
3. **Gateway tidak tahu isinya.** Setiap baris uplink diakhiri `(payload terenkripsi)`; gateway hanya membaca amplopnya (DevAddr, FCnt, FPort).

## EXP-03 — Uplink dua node, 5 menit

Keluaran `uplink_listen.py` (data yang **sudah** didekripsi network server, lewat MQTT):

```
waktu     device      FCnt  payload          suhu    RH    RSSI    SNR
------------------------------------------------------------------------
17:18:48  node1-ruangan-1     0  T=25.0,H=66     25.0C   66%    -67 dBm  10.0 dB
17:19:32  node2-ruangan-2     0  T=32.1,H=47     32.1C   47%    -64 dBm  11.8 dB
17:20:00  node1-ruangan-1     3  T=26.0,H=61     26.0C   61%    -67 dBm   9.8 dB
17:20:11  node2-ruangan-2     2  T=33.7,H=44     33.7C   44%    -63 dBm   9.8 dB
```

Rekapitulasi jendela rekam (hanya frame ber-payload; frame MAC dihitung terpisah):

| Node | DevAddr | Uplink dikirim (serial) | Diterima gateway | Sampai ChirpStack | Loss | RSSI rata-rata | SNR rata-rata |
|---|---|---|---|---|---|---|---|
| Node 1 | `01EBD973` | 10 | 9 | 9 | **10 %** (FCnt 2 hilang) | **−66,1 dBm** | **9,7 dB** |
| Node 2 | `01DC98E3` | 9 | 9 | 9 | **0 %** | **−62,8 dBm** | **10,0 dB** |

Rentang dummy yang terlihat di server — cukup untuk mengenali asal data tanpa melihat nama perangkat:

| Node | Spesifikasi | Terukur di sesi ini |
|---|---|---|
| Node 1 (Ruangan 1) | 25–30 °C, 60–75 % | **25,0–28,5 °C**, **60–71 %** |
| Node 2 (Ruangan 2) | 28–35 °C, 40–65 % | **31,1–34,4 °C**, **40–65 %** |

Statistik gateway sepanjang sesi: **0** CRC salah, **0** `[TX] TERLAMBAT`, seluruh downlink meleset **−0,2 s.d. −0,4 ms** dari `tmst` yang diminta server.

## Satu uplink yang benar-benar hilang

FCnt Node 1 melompat dari 1 ke 3 — uplink `FCnt=2` tidak pernah sampai. Penyebabnya terbaca dengan mencocokkan cap waktu kedua log. Node 1 mulai memancar pada 17:19:27, kurang dari setengah detik sesudah gateway menyelesaikan penerimaan JoinRequest Node 2:

```
node 1 :  [17:19:27] [  48.7] [TX] radio: 433175 kHz DR5
          [17:19:27] [  48.7] [TX #2] FPort=1 "T=26.0,H=61" -> antre di LMIC

gateway:  17:19:26.825  [RX]  23 B  ...  JoinRequest DevEUI=0011223344556602
          17:19:27.039  [TX] downlink dijadwalkan: 17 B ... JoinAccept (17 byte)
          (tidak ada [RX] apa pun dari Node 1 di sini)
          17:19:31.871  [TX] terkirim (meleset -0.4 ms dari jadwal)
          17:20:00.071  [RX]  24 B  ...  DevAddr=01EBD973 FCnt=3 FPort=1
```

Node 1 mengirim tanpa tahu apa-apa, gateway tidak menerimanya, dan **tidak ada satu pun pesan galat di kedua sisi** — persis tabrakan senyap yang diukur di M08, kini pada jaringan yang sudah berprotokol. Yang berbeda dari M08 hanyalah akibatnya terlihat: `FCnt` yang melompat langsung menunjukkan ada frame yang hilang, tanpa perlu menghitung manual seperti dulu. Inilah bahan EXP-04.

## Catatan: dua node dinyalakan bersamaan

Pada sesi percobaan lain kedua node di-*reset* pada detik yang sama. Hasilnya: Node 1 join mulus, sedangkan JoinRequest pertama Node 2 tidak pernah sampai ke gateway dan baru berhasil pada percobaan kedua, **69 detik** kemudian (LMIC menunda percobaan berikutnya makin lama tiap kali gagal):

```
[   1.7] [JOIN] mengirim JoinRequest ...
[   9.0] [TX] radio: 433175 kHz DR5
[  16.7] [JOIN] tidak ada JoinAccept di RX1/RX2
[  78.3] [TX] radio: 433175 kHz DR5
[  83.4] [JOIN] BERHASIL
```

Inilah harga gateway kanal tunggal yang setengah-dupleks: selama ia menembakkan JoinAccept untuk satu node, ia tuli terhadap node lain. Karena itu README meminta node dinyalakan **satu per satu**, dan bukan karena firmware-nya rewel.

## Uji skema multi-kelompok (Lampiran B)

Pembagian kanal per kelompok diuji dengan menjalankan kelompok 2 secara penuh: gateway dipindah ke 433.375 MHz (`--freq 433375000`), node di-flash dengan `-D KELOMPOK=2`.

```
node   :  === LoRaWAN NODE 2 - Ruangan 2 (Kelompok 2) ===
          Kanal   : 433.375 MHz SF7BW125 (kanal tunggal)
          [  76.3] [TX] radio: 433375 kHz DR5
          [  81.4] [JOIN] BERHASIL
          [  81.4]   DevAddr : D1C237

gateway:  17:12:27.838  [RX]  23 B  RSSI= -65 dBm  SNR=  9.5 dB
                        JoinRequest DevEUI=0011223344557702 DevNonce=12184
          17:12:28.055  [TX] downlink dijadwalkan: 17 B  433.375 MHz  SF7BW125  dalam 4783 ms
          17:12:32.884  [TX] terkirim (meleset -0.3 ms dari jadwal)
```

DevEUI bergeser sendiri ke `...7702` mengikuti nomor kelompok, dan uplink-nya masuk ke Application **`praktikum-wsn-k2`** yang terpisah dari `praktikum-wsn` milik kelompok 1 (diperiksa lewat API: `devAddr 00d1c237`, `fCntUp 4`). Join berhasil pada percobaan kedua; percobaan pertamanya tidak diterima node meski JoinAccept sudah ditembakkan tepat waktu — kejadian yang sesekali muncul juga pada kelompok 1, dan memang sifat gateway kanal tunggal.

## Ringkasan Verifikasi Hardware

Diuji di perangkat pada **2026-08-22**: 2× Arduino Uno asli + Dragino LoRa Shield v1.2 (port `/dev/ttyACM1` dan `/dev/ttyACM2`), Raspberry Pi 5 (Debian 13, Docker) + Dragino LoRa GPS HAT v1.4, ChirpStack v4 region EU433. Build kedua environment sukses (RAM 69,8 %, Flash 75,0 % dari ATmega328P). Seluruh alur modul berjalan pada perangkat sungguhan dengan kode yang persis seperti di repositori ini: gateway online di ChirpStack, kedua node **join OTAA pada percobaan pertama**, dan 18 dari 19 uplink sampai ke aplikasi selama jendela rekam 5,5 menit — satu yang hilang terdokumentasi di atas beserta penyebabnya. Skema multi-kelompok diuji terpisah untuk kelompok 2.

EXP-01 (pendaftaran lewat web UI), percobaan DevEUI sengaja dibalik pada EXP-02, kedua kotak **Buka abstraksinya**, dan seluruh Challenge belum dijalankan — semuanya adalah pekerjaan praktikan.

Dua temuan dari pengujian ini yang sudah diperbaiki di kode, dan keduanya menjadi bahan kotak **Buka abstraksinya** di README:

1. `LMIC_startJoining()` mengembalikan tabel kanal ke bawaan EU868, sehingga penguncian kanal tunggal harus **diulang di `EV_JOINING`** — tanpa itu node mengirim JoinRequest di 868.1 MHz dan gateway diam tanpa pesan galat apa pun.
2. `start_rx()` di gateway harus mengembalikan **frekuensi dan SF**, bukan hanya mode radio. Sesudah satu downlink RX2 (434.665 MHz SF12), gateway yang tidak mengembalikan keduanya akan tetap mendengarkan di kanal RX2 dan tuli selamanya terhadap seluruh uplink.
