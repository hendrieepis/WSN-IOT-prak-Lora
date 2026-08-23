# Log Serial — Modul 08 (Pure ALOHA)

Hasil aktual dari perangkat. Baud **115200**, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm. Ketiga board di satu meja, jarak berbeda-beda (lihat RSSI di bawah — Node 1 lebih dekat ke gateway daripada Node 2). Interval kirim bawaan (2000–5000 ms acak) pada kedua node, tidak diubah.

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Gateway | `gateway` | `/dev/ttyACM0` | Uno asli (`2341:0043`) |
| Node 1 | `node1` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |
| Node 2 | `node2` | `/dev/ttyACM2` | Uno asli (`2341:0043`) |

Ketiga aliran serial direkam bersamaan (skrip capture terpisah 3 proses `pyserial`, satu per port), jendela rekam 90 detik setelah ketiga board selesai di-*upload* dan *boot*.

## EXP-01 — Dua Node Mengirim Bebas

Cuplikan 7 detik pertama sesi rekam, memperlihatkan boot Node 2, boot Gateway, lalu dua paket pertama yang tiba (Node 2 SEQ=1, Node 1 SEQ=1 — SEQ=0 kedua node terkirim sebelum jendela rekam mulai):

```
[07:42:53.243] N2 | === LoRa PURE ALOHA - NODE 2 ===
[07:42:53.259] N2 | Init LoRa ... OK
[07:42:53.259] N2 | Freq: 433.00 MHz
[07:42:53.267] N2 | Peran: NODE (Pure ALOHA) -- kirim bebas, tanpa ACK, tanpa retry
[07:42:53.357] N2 | [TX] NODE=2,SEQ=0,R1T=26.5,R1H=54,R2T=22.6,R2H=55 | total dikirim: 1
[07:42:54.004] GW | === LoRa PURE ALOHA - GATEWAY ===
[07:42:54.024] GW | Init LoRa ... OK
[07:42:54.024] GW | Freq: 433.00 MHz
[07:42:54.028] GW | Peran: GATEWAY (Pure ALOHA) -- hanya dengar, tidak pernah kirim ACK
[07:42:54.032] GW | Menunggu paket dari Node 1 & Node 2...
[07:42:56.147] N2 | [TX] NODE=2,SEQ=1,R1T=24.8,R1H=58,R2T=22.7,R2H=59 | total dikirim: 2
[07:42:56.150] GW | === PAKET DITERIMA ===
[07:42:56.150] GW |   Node    : 2
[07:42:56.154] GW |   SEQ     : 1
[07:42:56.154] GW |   Ruang 1 : 24.8 C, 58 %
[07:42:56.158] GW |   Ruang 2 : 22.7 C, 59 %
[07:42:56.158] GW |   RSSI    : -58 dBm
[07:42:56.162] GW |   SNR     : 9.50 dB
[07:42:56.166] GW |   Statistik Node 2: diterima=1 | perkiraan hilang=0
[07:42:56.166] GW | =====================
[07:42:56.936] GW | === PAKET DITERIMA ===
[07:42:56.936] GW |   Node    : 1
[07:42:56.940] GW |   SEQ     : 1
[07:42:56.940] GW |   Ruang 1 : 30.0 C, 45 %
[07:42:56.944] GW |   Ruang 2 : 24.8 C, 69 %
[07:42:56.944] GW |   RSSI    : -46 dBm
[07:42:56.945] GW |   SNR     : 9.75 dB
[07:42:56.952] GW |   Statistik Node 1: diterima=1 | perkiraan hilang=0
[07:42:56.953] GW | =====================
[07:42:59.158] N1 | [TX] NODE=1,SEQ=2,R1T=29.8,R1H=59,R2T=25.4,R2H=68 | total dikirim: 3
[07:42:59.160] GW | === PAKET DITERIMA ===
[07:42:59.160] GW |   Node    : 1
[07:42:59.164] GW |   SEQ     : 2
[07:42:59.164] GW |   Ruang 1 : 29.8 C, 59 %
[07:42:59.168] GW |   Ruang 2 : 25.4 C, 68 %
[07:42:59.168] GW |   RSSI    : -46 dBm
[07:42:59.172] GW |   SNR     : 11.00 dB
[07:42:59.176] GW |   Statistik Node 1: diterima=2 | perkiraan hilang=0
[07:42:59.176] GW | =====================
```

| Parameter | Hasil (90 detik, interval bawaan 2000–5000 ms) |
|---|---|
| Total paket diterima gateway | **51** |
| Node 1: diterima gateway / perkiraan hilang | **27 / 0** |
| Node 2: diterima gateway / perkiraan hilang | **24 / 0** |
| Jumlah `[GAP]` muncul | **0** (SEQ naik berurutan di kedua node sepanjang jendela rekam) |
| RSSI rata-rata — Node 1 (n=27) | **-45,9 dBm** (min -46, max -45) |
| RSSI rata-rata — Node 2 (n=24) | **-57,9 dBm** (min -59, max -57) |
| SNR rata-rata — Node 1 / Node 2 | **10,00 dB / 9,79 dB** |
| SNR & RSSI rata-rata gabungan (semua paket) | **-51,5 dBm / 9,90 dB** |

> **Catatan jarak.** Beda RSSI ±12 dB antara Node 1 dan Node 2 murni karena posisi fisik kedua board berbeda di meja pengujian saat sesi ini direkam, bukan karena protokol.

> Pada jarak dekat dan interval bawaan, **tidak ada satupun `[GAP]`** selama 90 detik / 51 paket. Ini konsisten dengan teori: pada beban rendah (G kecil), peluang dua paket saling tumpang tindih di udara sangat kecil meski Pure ALOHA tidak punya carrier-sense sama sekali. Memaksa tabrakan (EXP-02 di README) memerlukan mempersempit interval kirim kedua node dan diserahkan sebagai latihan praktikum — lihat catatan di README bagian Pengukuran.

## EXP-03 — Payload Dua Ruangan

```
[07:42:59.158] N1 | [TX] NODE=1,SEQ=2,R1T=29.8,R1H=59,R2T=25.4,R2H=68 | total dikirim: 3
```

| Parameter | Hasil |
|---|---|
| Jumlah field dalam satu payload | **6** (`NODE`, `SEQ`, `R1T`, `R1H`, `R2T`, `R2H`) |
| Apakah Ruang 1 dan Ruang 2 selalu tiba bersamaan (satu paket)? | **ya** — tidak pernah ada paket berisi hanya salah satu ruangan pada 51 paket yang diamati |
| Ukuran payload (contoh di atas) | **45 karakter** |

## Ringkasan Verifikasi Hardware

Diuji di perangkat pada 2026-08-22: 3× Arduino Uno asli + Dragino LoRa Shield v1.2, satu gateway + dua node, environment `gateway`/`node1`/`node2` sesuai `platformio.ini` bawaan (port `/dev/ttyACM0/1/2`, sudah cocok dengan hasil `deteksi_port.py` tanpa perlu diubah). Build dan upload ketiga environment sukses. Protokol Pure ALOHA berjalan sesuai desain: gateway hanya mendengar (tidak pernah TX), kedua node mengirim bebas dengan interval acak berbeda, dan pada beban rendah tidak terlihat kehilangan paket.
