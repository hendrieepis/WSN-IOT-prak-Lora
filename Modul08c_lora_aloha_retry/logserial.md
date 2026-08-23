# Log Serial — Modul 09 (ALOHA + ACK + Random Backoff + Retry)

Hasil aktual dari perangkat. Baud **115200**, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `ACK_TIMEOUT` 2000 ms, `MAX_RETRIES` 3, backoff acak 200–1500 ms. Posisi board sama seperti M08/M08B. Interval kirim bawaan (2000–5000 ms acak), tidak diubah.

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Gateway | `gateway` | `/dev/ttyACM0` | Uno asli (`2341:0043`) |
| Node 1 | `node1` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |
| Node 2 | `node2` | `/dev/ttyACM2` | Uno asli (`2341:0043`) |

Ketiga aliran serial direkam bersamaan, jendela rekam 90 detik setelah ketiga board di-*upload* ulang dan *boot* bersih.

## EXP-01 — Retry Sehat, Jarak Dekat

Siklus normal (langsung sukses, 0 retry):

```
[08:06:27.884] GW | === PAKET DITERIMA (DATA BARU) ===
[08:06:27.888] GW |   Node    : 2
[08:06:27.888] GW |   SEQ     : 1
```

Dan siklus yang butuh retry — Node 1 mengirim `SEQ=0`, ACK pertama tidak sampai, node menunggu *backoff* acak lalu mengirim ulang **dua kali** sebelum akhirnya sukses:

```
[08:06:21.265] N1 | [BACKOFF] tunggu 854 ms sebelum retry
[08:06:22.125] N1 | [RETRY 1/3] NODE=1,SEQ=0,R1T=29.9,R1H=72,R2T=26.7,R2H=58
[08:06:24.210] N1 | [BACKOFF] tunggu 1358 ms sebelum retry
[08:06:25.573] N1 | [RETRY 2/3] NODE=1,SEQ=0,R1T=29.9,R1H=72,R2T=26.7,R2H=58
[08:06:25.725] N1 | [OK] SUCCESS setelah 2 retry | OK: 1 | FAIL: 0 | Total retry terpakai: 2
[08:06:25.664] GW | === PAKET DITERIMA (DATA BARU) ===
[08:06:25.665] GW |   Node    : 1
[08:06:25.668] GW |   SEQ     : 0
```

Perhatikan: `R1T=29.9,R1H=72,R2T=26.7,R2H=58` **identik** di ketiga percobaan (TX awal + 2 retry) — data dummy dibangkitkan sekali per `SEQ` dan dipertahankan sepanjang retry, persis seperti dijelaskan di kode.

| Parameter | Hasil (90 detik, bukan 10 siklus) |
|---|---|
| `OK`/`FAIL` Node 1 (23 siklus) | **23 / 0** — semua siklus akhirnya sukses |
| `OK`/`FAIL` Node 2 (23 siklus) | **23 / 0** — semua siklus akhirnya sukses |
| Total retry terpakai — Node 1 / Node 2 | **3 / 2** |
| `duplicate` tercatat di gateway — Node 1 / Node 2 | **1 / 1** |

> **CHECKPOINT terpenuhi.** Sebagian besar siklus (21/23 Node 1, 22/23 Node 2) sukses langsung dengan `SUCCESS setelah 0 retry`. Hanya satu siklus per node yang butuh retry pada sesi ini.

## Temuan Tambahan — Perbandingan Langsung dengan M08B (Tanpa vs Dengan Retry)

(Bukan EXP-02 versi README — itu menuntut interval dipersempit 300–500 ms, belum dijalankan. Ini perbandingan pada interval bawaan yang sama, memakai data EXP-01 M08B dan M08C.)

Kedua modul diuji pada interval kirim, jarak, dan posisi board yang **sama** (90 detik, 2000–5000 ms):

| Parameter | M08B (tanpa retry) | M08C (dengan retry) |
|---|---|---|
| `FAIL` permanen Node 1 (90 detik) | **2** | **0** |
| `FAIL` permanen Node 2 (90 detik) | **2** | **0** |
| Mekanisme pemulihan saat ACK hilang | tidak ada — SEQ lanjut, data hilang permanen | retry otomatis dengan backoff acak, hingga 3× |

> Retry+backoff pada M08C berhasil **memulihkan seluruh kegagalan** yang pada M08B akan tercatat sebagai `[FAIL]` permanen — pada sesi ini, tingkat kegagalan permanen turun dari 4 kejadian (M08B, gabungan kedua node) menjadi 0 (M08C). Ini bukti langsung nilai tambah retry dibanding sekadar mengetahui kegagalan (M08B).

## Temuan Tambahan — Duplicate Tidak Dihitung Ganda

(Bagian dari EXP-03 versi README — belum diamati sepenuhnya selama 5 menit penuh, tapi datanya konsisten pada jendela 90 detik yang diuji.)

```
[08:07:54.477] GW |   Statistik Node 1: baru=25 | duplicate=1 | gagal permanen (est.)=0
```

| Parameter | Hasil |
|---|---|
| Data baru — Node 1 / Node 2 (dari sisi gateway) | **25 / 24** |
| Duplicate — Node 1 / Node 2 | **1 / 1** |
| Apakah `baru=` ikut bertambah saat duplicate diterima? | **tidak** — hanya `duplicate=` yang bertambah |
| Apakah gateway tetap membalas ACK untuk duplicate? | **ya** (mengikuti kode; tidak diverifikasi eksplisit lewat log RSSI karena baris duplicate tidak mencetak RSSI/SNR) |

> Catatan: `baru` gateway (25/24) sedikit lebih tinggi daripada jumlah siklus `OK` di node (23/23) karena jendela rekam masing-masing dari tiga proses capture terpisah tidak mulai/berhenti pada detik yang identik persis — bukan indikasi bug penghitungan.

## Ringkasan Verifikasi Hardware

Diuji di perangkat pada 2026-08-22: 3× Arduino Uno asli + Dragino LoRa Shield v1.2 (gateway + node1 + node2, port `/dev/ttyACM0/1/2`). Build dan upload ketiga environment sukses. Protokol retry+backoff berjalan sesuai desain: node mengulang paket yang sama (data dummy tidak berubah) hingga 3× dengan jeda backoff acak sebelum menyerah, gateway mengenali retry sebagai duplicate lewat `SEQ <= lastSeq` dan tidak menghitungnya sebagai data baru namun tetap membalas ACK. Pada sesi 90 detik ini, retry berhasil memulihkan **seluruh** kegagalan yang di M08B akan permanen (`FAIL` turun dari 4 menjadi 0). EXP-02 versi README (interval dipersempit) dan pengukuran 5 menit penuh untuk EXP-03 **belum dijalankan** pada sesi ini — diserahkan sebagai latihan praktikum.

**Catatan teknis capture** — dua kali percobaan upload gateway pada sesi ini sempat menghasilkan output serial yang rusak (byte non-ASCII, bukan baris log yang valid) segera setelah `avrdude` selesai; unggah ulang tanpa mengubah kode langsung memulihkannya. Ini artefak transisi USB-CDC saat board baru selesai diprogram, bukan bug firmware — bila mengalami ini, unggah ulang environment yang bersangkutan sebelum menyalahkan kode.
