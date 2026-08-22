# Log Serial — Modul 08B (ALOHA + ACK)

Hasil aktual dari perangkat. Baud **115200**, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `ACK_TIMEOUT` 2000 ms. Ketiga board di posisi sama seperti M08 (Node 1 lebih dekat ke gateway daripada Node 2). Interval kirim bawaan (2000–5000 ms acak), tidak diubah.

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Gateway | `gateway` | `/dev/ttyACM0` | Uno asli (`2341:0043`) |
| Node 1 | `node1` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |
| Node 2 | `node2` | `/dev/ttyACM2` | Uno asli (`2341:0043`) |

Ketiga aliran serial direkam bersamaan, jendela rekam 90 detik setelah ketiga board di-*upload* ulang dan *boot* bersih.

## EXP-01 — Siklus ACK Sehat, Dua Node

Siklus normal (paket sampai, ACK sampai, latensi round-trip ~60 ms):

```
[07:55:29.194] GW | === PAKET DITERIMA ===
[07:55:29.198] GW |   Node    : 2
[07:55:29.198] GW |   SEQ     : 1
[07:55:29.198] GW |   Ruang 1 : 26.3 C, 45 %
[07:55:29.202] GW |   Ruang 2 : 23.8 C, 80 %
[07:55:29.202] GW |   RSSI    : -61 dBm
[07:55:29.206] GW |   SNR     : 9.25 dB
[07:55:29.210] GW |   Statistik Node 2: diterima=1 | perkiraan hilang=0
[07:55:29.247] GW |   [TX] ACK=2,SEQ=1
[07:55:29.251] GW | =====================
[07:55:29.819] N1 | [TX] NODE=1,SEQ=1,R1T=25.9,R1H=74,R2T=26.9,R2H=59
[07:55:29.881] N1 | [OK] ACK diterima | OK: 1 | FAIL: 1
```

| Parameter | Hasil (90 detik, bukan 10 siklus — lihat catatan) |
|---|---|
| `OK`/`FAIL` Node 1 | **22 / 2** (24 percobaan) |
| `OK`/`FAIL` Node 2 | **19 / 2** (21 percobaan tercatat lengkap) |
| Tingkat keberhasilan Node 1 / Node 2 | **91,7% / 90,5%** |
| Latensi ACK round-trip (TX → OK) Node 1 / Node 2 | **rata-rata 60 ms / 59 ms** (min 57, maks 65 ms) |
| RSSI/SNR arah DATA (di gateway) — Node 1 / Node 2 | **-46,3 dBm / 9,84 dB — -59,5 dBm / 9,60 dB** |

> **CHECKPOINT sebagian terpenuhi.** `FAIL` tidak nol: masing-masing node mengalami 2 kegagalan dalam 90 detik — satu di antaranya adalah tabrakan nyata yang berhasil direkam langsung (lihat EXP-02 di bawah). Ini konsisten dengan M08: pada jarak dan interval yang sama, tabrakan tetap mungkin terjadi walau jarang.

## Temuan Tambahan A — Tabrakan Nyata Tertangkap Langsung

(Bukan EXP-02 versi README — itu perbandingan sistematis M08 vs M08B pada interval dipersempit, belum dijalankan. Ini adalah tabrakan yang kebetulan terekam pada sesi EXP-01 di atas.)

Pada sesi ini, Node 1 dan Node 2 kebetulan mengirim `SEQ=5` hampir bersamaan (selisih ~90 ms — dalam *vulnerable period*). Log berikut menunjukkan efeknya di kedua sisi:

```
[07:55:44.196] N2 | [TX] NODE=2,SEQ=5,R1T=24.1,R1H=51,R2T=24.9,R2H=55
[07:55:44.286] N1 | [TX] NODE=1,SEQ=5,R1T=27.9,R1H=74,R2T=22.3,R2H=55
[07:55:44.295] N2 | [RX] WARN: balasan tak sesuai (NODE=1,SEQ=5,R1T=27.9,R1H=74,R2T=22.3,R2H=55), tetap tunggu...
[07:55:46.195] N2 | [FAIL] Tidak ada ACK | OK: 4 | FAIL: 2
[07:55:46.288] N1 | [FAIL] Tidak ada ACK | OK: 4 | FAIL: 2
[07:55:49.055] GW |   Ruang 2 : 27.6 C, 64 %
[07:55:49.055] GW |   RSSI    : -46 dBm
[07:55:49.059] GW |   SNR     : 10.00 dB
[07:55:49.062] GW |   [GAP] SEQ meloncat 1 -- indikasi tabrakan/paket hilang
[07:55:49.066] GW |   Statistik Node 1: diterima=5 | perkiraan hilang=1
```

Yang menarik: Node 2 sempat menerima **paket DATA milik Node 1** di jendela tunggu ACK-nya sendiri (`[RX] WARN: balasan tak sesuai`) — bukti langsung bahwa radio LoRa mentah tidak beralamat, semua node saling mendengar lalu lintas siapa pun. Kedua node akhirnya `[FAIL]` pada `SEQ=5` yang sama, dan gateway mencatat `[GAP]` pada Node 1 (SEQ meloncat dari 4 ke 6) — konsisten dengan paket Node 1 yang hilang akibat tabrakan ini.

| Parameter | Hasil |
|---|---|
| Total `[GAP]` gateway (90 detik) | **1** (Node 1, SEQ 4→6) |
| Total `[FAIL]` Node 1 / Node 2 (90 detik) | **2 / 2** |
| Selisih waktu TX kedua node saat tabrakan | **~90 ms** |

## Temuan Tambahan B — Ketidaksepakatan Node vs Gateway (DATA sampai, ACK hilang)

(Bukan EXP-03 versi README — itu uji mematikan gateway sesaat, belum dijalankan. Ini adalah data untuk Tabel B bagian Pengukuran README, dihitung dari sesi EXP-01 di atas.)

| Node | `OK` di node | `diterima` di gateway (akhir jendela) | Selisih | Tafsiran |
|---|---|---|---|---|
| Node 1 | 22 | 22 | **0** | Kedua `FAIL` Node 1 (boot-race SEQ=0 + tabrakan SEQ=5) memang DATA yang tidak pernah sampai — konsisten dengan `[GAP]` gateway. |
| Node 2 | 19 | 20 | **1** | Satu `FAIL` di Node 2 ternyata DATA-nya **sampai** di gateway (`diterima` gateway lebih tinggi dari `OK` node) — kemungkinan ACK balasannya yang hilang di jalur pulang, bukan DATA-nya di jalur pergi. |

> Baris Node 2 adalah bukti nyata dari poin analisis modul ini: `[FAIL]` di node **tidak selalu berarti** DATA hilang — bisa juga DATA sampai tapi ACK balasannya yang tidak pernah tiba kembali. Node tidak bisa membedakan kedua kasus ini hanya dari timeout-nya sendiri.

## Ringkasan Verifikasi Hardware

Diuji di perangkat pada 2026-08-22: 3× Arduino Uno asli + Dragino LoRa Shield v1.2 (gateway + node1 + node2, port `/dev/ttyACM0/1/2`). Build dan upload ketiga environment sukses. Protokol ALOHA+ACK berjalan sesuai desain: gateway membalas ACK untuk setiap paket valid yang diterima, kedua node menunggu ACK dengan timeout 2000 ms tanpa retry. Sesi 90 detik ini bahkan menangkap satu tabrakan nyata antara Node 1 dan Node 2, memberi bukti langsung untuk konsep *vulnerable period* dan perbedaan antara "DATA hilang" vs "ACK hilang". EXP-02 versi README (uji sistematis M08 vs M08B pada interval dipersempit) dan EXP-03 versi README (mematikan gateway sesaat) **belum dijalankan** pada sesi ini — diserahkan sebagai latihan praktikum.
