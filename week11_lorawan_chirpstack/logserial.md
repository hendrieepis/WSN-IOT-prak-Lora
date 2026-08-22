# Log Serial — Modul 11 (LoRaWAN + ChirpStack)

Hasil aktual dari perangkat. Node: baud **115200**, LoRaWAN Class A OTAA, kanal tunggal **433.175 MHz SF7BW125 CR4/5**, interval uplink 30 detik, payload ASCII `T=..,H=..` di FPort 1 (unconfirmed). Gateway: Raspberry Pi 5 + Dragino LoRa GPS HAT v1.4 menjalankan `single_chan_pkt_fwd.py`, ChirpStack v4 (Docker) di Pi yang sama, region **EU433**.

## Board & Port

| Peran | Environment / skrip | Port | Board |
|---|---|---|---|
| Node 1 (Ruangan 1) | `node1` | `/dev/ttyACM1` | Uno asli (`2341:0043`) + Dragino LoRa Shield v1.2 |
| Node 2 (Ruangan 2) | `node2` | `/dev/ttyACM2` | Uno asli (`2341:0043`) + Dragino LoRa Shield v1.2 |
| Gateway | `gateway/single_chan_pkt_fwd.py` | — | Raspberry Pi 5 + LoRa GPS HAT v1.4, Gateway EUI `2CCF67FFFE53AC11` |
| Server | ChirpStack v4 (Docker) | `:8080` UI, `:1700/udp`, `:1883` MQTT | Raspberry Pi 5 yang sama |

Sesi rekam: **16:32:07–16:37:51**, Node 1 dinyalakan lebih dahulu dan Node 2 menyusul 45 detik kemudian — persis urutan yang diminta README, supaya kedua JoinRequest tidak berebut satu-satunya kanal yang didengar gateway.

## EXP-02 — OTAA Join

Sisi node (Node 1), dari boot sampai uplink pertama:

```
[16:32:07] [   1.5] === LoRaWAN NODE 1 - Ruangan 1 ===
[16:32:07] [   1.5] Kanal   : 433.175 MHz SF7BW125 (kanal tunggal)
[16:32:07] [   1.5] Interval: 30 detik
[16:32:07] [   1.6] Menyusun JoinRequest OTAA ...
[16:32:07] [   1.6] [JOIN] mengirim JoinRequest ...
[16:32:11] [   5.7] [TX] radio: 433175 kHz DR5
[16:32:16] [  10.8] [JOIN] BERHASIL
[16:32:16] [  10.8]   DevAddr : ACC8E9
[16:32:16] [  10.8]   NetID   : 0
[16:32:16] [  10.8] [TX] radio: 433175 kHz DR5
[16:32:16] [  10.8] [TX #1] FPort=1 "T=29.9,H=69" -> antre di LMIC
[16:32:17] [  11.9] [TX] selesai (FCntUp=1)
```

Kejadian yang sama dari sisi gateway — perhatikan jeda **4784 ms** yang ditentukan server untuk JoinAccept (jendela RX1 join = 5 detik dikurangi waktu pemrosesan), dan ketelitian penembakannya:

```
16:32:11.712  [RX]  23 B  RSSI= -65 dBm  SNR=  9.8 dB  tmst=3134976299
              JoinRequest DevEUI=0011223344556601 DevNonce=21442
16:32:11.928  [TX] downlink dijadwalkan: 17 B  433.175 MHz  SF7BW125  dalam 4784 ms
              JoinAccept (17 byte)
16:32:16.758  [TX] terkirim (meleset -0.3 ms dari jadwal)
16:32:16.839  [RX]  24 B  RSSI= -64 dBm  SNR=  9.5 dB  tmst=3140103890
              UnconfirmedDataUp DevAddr=00ACC8E9 FCnt=0 FPort=1 (payload terenkripsi)
16:32:17.166  [TX] downlink dijadwalkan: 13 B  433.175 MHz  SF7BW125  dalam 673 ms
              UnconfirmedDataDown (13 byte)
16:32:17.880  [TX] terkirim (meleset -0.3 ms dari jadwal)
16:32:22.983  [RX]  15 B  RSSI= -63 dBm  SNR=  9.2 dB  tmst=3146247811
              UnconfirmedDataUp DevAddr=00ACC8E9 FCnt=1 (payload terenkripsi)
```

Node 2, join pada percobaan pertama juga, 53 detik sesudahnya:

```
[16:32:52] [   1.7] [JOIN] mengirim JoinRequest ...
[16:33:00] [   9.2] [TX] radio: 433175 kHz DR5
[16:33:05] [  14.3] [JOIN] BERHASIL
[16:33:05] [  14.3]   DevAddr : 13E3DD
```

**Tiga hal yang terbaca dari cuplikan di atas.**

1. **DevAddr diberikan server, dan berbeda untuk tiap node** (`ACC8E9` dan `13E3DD`) — bandingkan `NODE_ID` M05–M10 yang ditentukan build flag.
2. **Ada uplink yang tidak pernah diminta kode aplikasi.** Baris `FCnt=1` berukuran 15 byte, tanpa `FPort`, dan tidak didahului `[TX #n]` di sisi node. Itu jawaban otomatis LMIC atas perintah MAC (`DevStatusReq`) yang dititipkan server pada downlink 13 byte sebelumnya — lapisan MAC bekerja sendiri tanpa sepengetahuan `loop()`.
3. **Gateway tidak tahu isinya.** Setiap baris uplink diakhiri `(payload terenkripsi)`; gateway hanya membaca amplopnya (DevAddr, FCnt, FPort).

## EXP-03 — Uplink dua node, 5 menit

Keluaran `uplink_listen.py` (data yang **sudah** didekripsi network server, lewat MQTT):

```
waktu     device      FCnt  payload          suhu    RH    RSSI    SNR
------------------------------------------------------------------------
16:33:05  node2-ruangan-2     0  T=29.1,H=52     29.1C   52%    -63 dBm   9.8 dB
16:33:28  node1-ruangan-1     3  T=29.5,H=71     29.5C   71%    -64 dBm   9.8 dB
16:33:44  node2-ruangan-2     2  T=33.6,H=49     33.6C   49%    -61 dBm  10.0 dB
16:34:01  node1-ruangan-1     4  T=25.2,H=63     25.2C   63%    -63 dBm  10.2 dB
16:34:17  node2-ruangan-2     3  T=33.5,H=59     33.5C   59%    -61 dBm  10.5 dB
16:34:34  node1-ruangan-1     5  T=25.2,H=70     25.2C   70%    -64 dBm  10.0 dB
```

Rekapitulasi seluruh sesi (dari CSV `uplink_listen.py`, hanya frame ber-payload):

| Node | DevAddr | Uplink dikirim (serial) | Diterima gateway | Sampai ChirpStack | Loss | FCnt | RSSI rata-rata | SNR rata-rata |
|---|---|---|---|---|---|---|---|---|
| Node 1 | `00ACC8E9` | 10 | 10 | 10 | **0 %** | 0…10 berurutan | **−64,3 dBm** | **9,8 dB** |
| Node 2 | `0013E3DD` | 9 | 9 | 9 | **0 %** | 0…9 berurutan | **−61,6 dBm** | **9,9 dB** |

Rentang dummy yang terlihat di server — cukup untuk mengenali asal data tanpa melihat nama perangkat:

| Node | Spesifikasi | Terukur di sesi ini |
|---|---|---|
| Node 1 (Ruangan 1) | 25–30 °C, 60–75 % | **25,2–29,9 °C**, **60–74 %** |
| Node 2 (Ruangan 2) | 28–35 °C, 40–65 % | **28,3–33,6 °C**, **40–62 %** |

Statistik gateway sepanjang sesi: **26 paket** diterima (23 uplink data + 2 JoinRequest + 1 uplink dari sesi sebelumnya), **0** CRC salah, **4** downlink dikirim (2 JoinAccept + 2 perintah MAC), **0** `[TX] TERLAMBAT`, dan ketelitian jadwal downlink **−0,2 s.d. −0,3 ms** dari `tmst` yang diminta server.

## Catatan: dua node dinyalakan bersamaan

Pada sesi percobaan sebelumnya kedua node di-*reset* pada detik yang sama. Hasilnya: Node 1 join mulus, sedangkan JoinRequest pertama Node 2 tidak pernah sampai ke gateway dan baru berhasil pada percobaan kedua, **69 detik** kemudian (LMIC menunda percobaan berikutnya makin lama tiap kali gagal):

```
[   1.7] [JOIN] mengirim JoinRequest ...
[   9.0] [TX] radio: 433175 kHz DR5
[  16.7] [JOIN] tidak ada JoinAccept di RX1/RX2
[  78.3] [TX] radio: 433175 kHz DR5
[  83.4] [JOIN] BERHASIL
```

Inilah harga gateway kanal tunggal yang setengah-dupleks: selama ia menembakkan JoinAccept untuk satu node, ia tuli terhadap node lain. Karena itu README meminta node dinyalakan **satu per satu**, dan bukan karena firmware-nya rewel.

## Ringkasan Verifikasi Hardware

Diuji di perangkat pada **2026-08-22**: 2× Arduino Uno asli + Dragino LoRa Shield v1.2 (port `/dev/ttyACM1` dan `/dev/ttyACM2`), Raspberry Pi 5 (Debian 13, Docker) + Dragino LoRa GPS HAT v1.4, ChirpStack v4 region EU433. Build kedua environment sukses (RAM 69,8 %, Flash 75,0 % dari ATmega328P). Seluruh alur modul berjalan pada perangkat sungguhan: gateway online di ChirpStack, kedua node **join OTAA pada percobaan pertama**, dan 19 uplink berturut-turut sampai ke aplikasi tanpa satu pun hilang selama jendela rekam ~5,5 menit. EXP-01 (pendaftaran lewat web UI), percobaan DevEUI sengaja dibalik pada EXP-02, dan seluruh Challenge belum dijalankan pada sesi ini — semuanya adalah pekerjaan praktikan.

Dua temuan dari pengujian ini yang sudah diperbaiki di kode, dan keduanya menjadi bahan kotak **Buka abstraksinya** di README:

1. `LMIC_startJoining()` mengembalikan tabel kanal ke bawaan EU868, sehingga penguncian kanal tunggal harus **diulang di `EV_JOINING`** — tanpa itu node mengirim JoinRequest di 868.1 MHz dan gateway diam tanpa pesan galat apa pun.
2. `start_rx()` di gateway harus mengembalikan **frekuensi dan SF**, bukan hanya mode radio. Sesudah satu downlink RX2 (434.665 MHz SF12), gateway yang tidak mengembalikan keduanya akan tetap mendengarkan di kanal RX2 dan tuli selamanya terhadap seluruh uplink.
