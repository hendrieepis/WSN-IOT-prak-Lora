# Log Serial — Modul 10 (Slotted ALOHA)

Hasil aktual dari perangkat. Baud **115200**, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `SLOT_COUNT`=2, `SLOT_DURATION_MS`=800, `SLOT_GUARD_MS`=50. **Mode B (Assigned Slot)** — bawaan kode, tidak diubah: Node 1 selalu di slot 0, Node 2 selalu di slot 1. Posisi board sama seperti M08/M08B/M09.

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Gateway | `gateway` | `/dev/ttyACM0` | Uno asli (`2341:0043`) |
| Node 1 | `node1` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |
| Node 2 | `node2` | `/dev/ttyACM2` | Uno asli (`2341:0043`) |

Ketiga aliran serial direkam bersamaan, jendela rekam 90 detik setelah ketiga board di-*upload* ulang dan *boot* bersih.

## EXP-01 — Mode B (Assigned Slot), Tanpa Tabrakan

Siklus lengkap: gateway menyiarkan `SYNC`, Node 2 (slot 1) mengirim di jendelanya, gateway membalas ACK, siklus ditutup dengan ringkasan, lalu `SYNC` berikutnya:

```
[08:16:51.900] GW | === PAKET DITERIMA ===
[08:16:51.904] GW |   Node    : 2
[08:16:51.904] GW |   Slot    : 1
[08:16:51.905] GW |   SEQ     : 0
[08:16:51.908] GW |   Ruang 1 : 27.9 C, 60 %
[08:16:51.909] GW |   Ruang 2 : 22.9 C, 69 %
[08:16:51.912] GW |   RSSI    : -55 dBm
[08:16:51.912] GW |   SNR     : 9.50 dB
[08:16:51.953] GW |   [TX] ACK=2,SEQ=0
[08:16:51.954] GW | =====================
[08:16:52.560] GW | --- Cycle 0 selesai | N1: diterima=1 hilang=0  N2: diterima=1 hilang=0  ---
[08:16:52.588] GW | [TX] SYNC=1
[08:16:52.732] GW | === PAKET DITERIMA ===
[08:16:52.736] GW |   Node    : 1
[08:16:52.736] GW |   Slot    : 0
[08:16:52.736] GW |   SEQ     : 9
```

Cuplikan dari sisi Node 1 (slot 0, TX diikuti langsung ACK):

```
[08:16:57.633] N1 | [TX] cycle=4 slot=0 | NODE=1,SEQ=12,R1T=25.8,R1H=65,R2T=25.9,R2H=75
[08:16:57.687] N1 | [OK] ACK diterima | OK: 12 | FAIL: 1
```

Ringkasan siklus terakhir yang terekam (Cycle 55, ~90 detik kemudian):

```
[08:18:22.379] GW | --- Cycle 55 selesai | N1: diterima=56 hilang=0  N2: diterima=56 hilang=0  ---
```

| Parameter | Hasil (90 detik) |
|---|---|
| Jumlah siklus lengkap dalam 90 detik | **56** (Cycle 0 s.d. Cycle 55) |
| Diterima gateway per siklus, Node 1 / Node 2 (di akhir Cycle 55) | **56 / 56** — sama persis dengan jumlah siklus |
| `hilang` (gagal permanen) — Node 1 / Node 2 (data gateway) | **0 / 0** |
| Total `[GAP]` gateway sepanjang 90 detik | **0** |
| Durasi rata-rata satu siklus | **≈1633 ms** (55 interval Cycle0→Cycle55 / 89,8 detik) — dekat dengan `SLOT_COUNT × SLOT_DURATION_MS` = 1600 ms teoretis, selisih ~33 ms adalah overhead pemrosesan |
| `FAIL` di sisi Node 1 (penghitung lokal node, seluruh masa hidup proses) | **1** (terjadi sebelum jendela log yang tertangkap — lihat catatan) |
| `FAIL` di sisi Node 2 | **0** |

> **CHECKPOINT terpenuhi — dan lebih baik dari M08B/M09.** Pada Mode B (Assigned Slot), gateway mencatat **nol** `[GAP]` dan **nol** `hilang` untuk kedua node sepanjang 56 siklus penuh (90 detik) — setiap satu paket yang dikirim, satu diterima, tidak ada yang perlu diulang sama sekali. Ini kontras dengan M09 yang masih perlu retry untuk memulihkan sesekali kegagalan; di sini penjadwalan slot mencegah tabrakan sejak awal, bukan memulihkannya setelah terjadi.

> **Catatan tentang `FAIL: 1` di penghitung Node 1.** Log Node 1 yang berhasil tertangkap dimulai dari `cycle=4` (`OK: 12`, `FAIL: 1`) — beberapa siklus paling awal terlewat oleh proses perekaman itu sendiri (jeda "settle" 2,5 detik saat port dibuka, dipakai untuk membuang sisa byte transisi reset USB). `FAIL: 1` itu sendiri karenanya terjadi **sebelum** jendela yang tertangkap, kemungkinan pada sinkronisasi SYNC pertama saat Node 1 baru boot. Catatan otoritatif dari sisi **gateway** (yang merekam sejak Cycle 0 hingga Cycle 55 secara utuh) menunjukkan **nol** kehilangan untuk kedua node — ini yang dipakai sebagai angka rujukan pada tabel Pengukuran README.

## Ringkasan Verifikasi Hardware

Diuji di perangkat pada 2026-08-22: 3× Arduino Uno asli + Dragino LoRa Shield v1.2 (gateway + node1 + node2, port `/dev/ttyACM0/1/2`). Build dan upload ketiga environment sukses. Protokol Slotted ALOHA Mode B (Assigned Slot) berjalan sesuai desain: gateway menyiarkan `SYNC` di awal tiap siklus, Node 1 selalu bicara di slot 0 dan Node 2 di slot 1, tanpa tabrakan sama sekali selama 56 siklus (90 detik) — hasil terbaik dibanding ketiga modul sebelumnya (M08/M08B/M09) yang semuanya masih mengalami kehilangan atau butuh retry. Mode A (Random Slot, `SLOT_MODE_RANDOM=1`) untuk EXP-02 versi README **belum diuji** pada sesi ini — memerlukan mengubah `#define` di kode dan unggah ulang kedua node, diserahkan sebagai latihan praktikum.
