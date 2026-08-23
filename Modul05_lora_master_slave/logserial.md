# Log Serial — Modul 05 (Master-Slave 3 Node, Round-Robin Polling)

Hasil aktual dari perangkat. Baud **115200**, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `POLL_TIMEOUT` 500 ms. Ketiga board di satu meja, jarak ±30 cm.

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Master | `master` | `/dev/ttyACM0` | Uno asli (`2341:0043`) |
| Slave 1 | `slave1` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |
| Slave 2 | `slave2` | `/dev/ttyUSB0` | Uno klon, bridge CH340 (`1a86:7523`) |

Board ketiga pada pengujian ini adalah klon ber-bridge CH340 yang muncul sebagai `/dev/ttyUSB0`, bukan `/dev/ttyACM2` seperti tertulis di `platformio.ini`. Karena itu unggahan dan pemantauannya memakai `--upload-port /dev/ttyUSB0` dan `--port S2=/dev/ttyUSB0`.

Ketiga aliran serial direkam bersamaan memakai `monitor_serial.py`.

## EXP-01 — Slave Menyaring Panggilan

```
[   1.822] S1 | === LoRa SLAVE 1 ===
[   1.822] S1 | Init LoRa ... OK
[   1.822] S1 | Menunggu POLL:1 dari Master...
[   1.822] S1 | [RX] POLL:1 | RSSI: -62 dBm | SNR: 9.00 dB | RX#: 1
[   1.822] S1 | [TX] S1:DATA:1
[   1.822] S1 | [IGNORE] POLL:2
[   1.822] S1 | [IGNORE] S2:DATA:1
[   1.831] S2 | [RX] POLL:2 | RSSI: -62 dBm | SNR: 9.00 dB | RX#: 1
[   1.831] S2 | [TX] S2:DATA:1
[   2.432] S2 | [IGNORE] POLL:1
[   2.432] S2 | [IGNORE] S1:DATA:2
```

| Parameter | Hasil |
|---|---|
| Apakah Slave 1 menerima `POLL:2`? | **ya** — lalu dibuang |
| Baris `[IGNORE]` per siklus di tiap slave | **2** (`POLL` milik node lain + jawaban node lain) |
| Total `[IGNORE]` selama 40 detik | S1: 116, S2: 115 |
| Flash master / slave1 / slave2 | 29,6 % / 26,3 % / 26,3 % |

> **CHECKPOINT terpenuhi.** Setiap slave menerima panggilan untuk slave lain, lalu membuangnya. Yang menarik, slave juga membuang **jawaban** slave lain (`[IGNORE] S2:DATA:1`) — bukti bahwa di LoRa mentah setiap node mendengar seluruh lalu lintas, dan penyaringan sepenuhnya dikerjakan aplikasi.

## EXP-02 — Siklus Round-Robin (40 detik)

```
[   6.307] MASTER | === CYCLE 8 ===
[   6.307] MASTER | [TX] POLL:1
[   6.507] MASTER | [RX] S1:DATA:35 | RSSI: -58 dBm | SNR: 9.50 dB
[   6.507] MASTER | [TX] POLL:2
[   6.507] MASTER | [RX] S2:DATA:8 | RSSI: -56 dBm | SNR: 9.75 dB
[   6.507] MASTER | --- STATISTIK ---
[   6.507] MASTER | S1: OK=8 | FAIL=0 | Data: 35
[   6.507] MASTER | S2: OK=8 | FAIL=0 | Data: 8
[   6.507] MASTER | Durasi siklus: 148 ms
```

| Parameter | Hasil |
|---|---|
| Siklus selesai dalam 40 detik | **53** |
| Lama siklus min / maks / rata-rata | 147 / 154 / **152 ms** |
| Slave 1: dipanggil / menjawab / gagal | 53 / 52 / **0** |
| Slave 2: dipanggil / menjawab / gagal | 52 / 52 / **0** |
| RSSI di master (dari kedua slave) | −58 … −55, rata-rata −56,3 dBm |
| RSSI di S1 / S2 (dari master) | −62,0 / −61,8 dBm |
| SNR di seluruh node | ±9,0–9,8 dB |

Selisih satu jawaban pada Slave 1 berasal dari siklus terakhir yang terpotong saat perekaman berhenti, bukan paket hilang.

Lama siklus 152 ms terbagi menjadi dua giliran ±76 ms. Karena master menambahkan `CYCLE_INTERVAL` 500 ms di antara siklus, satu node terbaca ulang setiap ±650 ms.

## EXP-03 — Satu Node Hilang

Ketiadaan Slave 2 ditirukan dengan mengunggah **sketsa diam** (radio tidak pernah diinisialisasi), bukan mencabut USB.

| Parameter | Hasil |
|---|---|
| Lama siklus saat kedua slave sehat | **152 ms** |
| Lama siklus saat Slave 2 mati | **611 ms** (min 610, maks 612) |
| Pertambahan akibat satu node mati | **+459 ms** |
| `[FAIL] Slave 2 tidak merespon!` selama 14 detik | 11 |
| Apakah Slave 1 ikut terganggu? | **tidak** — `OK` Slave 1 terus bertambah |
| Lama siklus setelah Slave 2 kembali | 178 ms (kembali normal) |
| Pemulihan | otomatis, tanpa mereset master |

Pertambahan 459 ms mendekati `POLL_TIMEOUT` 500 ms dikurangi waktu yang biasanya dipakai jawaban yang sehat (±40 ms). Dengan kata lain, **master tetap membayar penuh waktu tunggu untuk node yang sudah tidak ada**. Lama siklus melipat **empat kali** hanya karena satu dari dua node mati — dan pelipatan itu memperlambat pembacaan node yang masih hidup.

Perkiraan lama siklus yang dapat diuji ulang:

```
lama siklus ≈ (jumlah node hidup × ±76 ms) + (jumlah node mati × 500 ms)
```

## EXP-04 — Tabrakan yang Disengaja

Penyaringan `POLL:<id>` dilumpuhkan pada **kedua** slave, sehingga keduanya menjawab setiap panggilan.

```
[  2.78] [TX] POLL:1
[  2.86] [WARN] Balasan tidak valid: S2:DATA:3
[  3.31] [FAIL] Slave 1 tidak merespon!
[  3.31] [TX] POLL:2
[  3.39] [RX] S2:DATA:4 | RSSI: -54 dBm | SNR: 1.25 dB
[  3.39] S1: OK=0 | FAIL=2 | Data: 0
[  3.39] S2: OK=2 | FAIL=0 | Data: 4
```

| Parameter | Penyaringan aktif | Penyaringan dilumpuhkan |
|---|---|---|
| Jawaban terbaca master (30 detik) | ±53 per node | 23 total |
| `[FAIL] tidak merespon` | 0 | **27** |
| `[WARN] Balasan tidak valid` | 0 | **24** |
| Lama siklus rata-rata | 152 ms | **643 ms** |
| **SNR di master** | **9,0–9,8 dB** | **1,25–1,75 dB** |
| Keberhasilan Slave 1 | 100 % | **0 %** (OK=0, FAIL=27) |

### Bacaan hasil

**Tabrakan tidak memunculkan pesan kesalahan dari radio.** Master tidak pernah mencetak "collision" atau semacamnya — yang terlihat hanya `[FAIL] tidak merespon` dan `[WARN] Balasan tidak valid`, dua pesan yang tampak seperti masalah lain sama sekali. Padahal kedua slave jelas-jelas mengirim setiap kali.

**SNR adalah petunjuk yang paling jujur.** Saat penyaringan aktif, SNR bertahan di 9–9,8 dB. Saat kedua slave memancar bersamaan, SNR anjlok ke 1,25–1,75 dB — sekitar **8 dB lebih buruk** — karena jawaban satu slave menjadi derau bagi jawaban slave lainnya. Inilah cara mendeteksi tabrakan dari sisi aplikasi tanpa dukungan radio, dan menjadi jawaban pertanyaan nomor 5 pada bagian Analisis.

**Satu node menang, satu node hilang sama sekali.** Master masih dapat memecahkan jawaban Slave 2 (efek *capture*: sinyal yang lebih kuat memenangkan penerima), sedangkan Slave 1 tidak pernah berhasil satu kali pun. Kegagalan tabrakan karena itu tidak merata — ia menghukum node yang lebih lemah, dan dari sisi master node itu tampak seperti mati.

**Penghitung master menjadi tidak bermakna.** Nilai `Data:` Slave 2 bertambah dua tiap siklus karena ia menjawab dua panggilan, sedangkan Slave 1 tertahan di 0. Statistik yang biasanya dipercaya justru menyesatkan ketika asumsi dasarnya — satu panggilan, satu penjawab — dilanggar.

## Sesi verifikasi ulang — 21 Agustus 2026

Ketiga board diunggah ulang dari `src/` saat ini (`pio run -e slave1|slave2|master -t upload`, ketiganya SUCCESS, flash terverifikasi avrdude) lalu direkam 40 detik dengan reset serentak lewat DTR. Tujuannya memverifikasi bahwa ketiga node yang tersambung memang menjalankan firmware modul ini — bukan mengulang EXP-01–04 secara penuh.

**Board & Port saat ini** — berbeda dari tabel di atas: ketiga board sekarang Uno asli (`2341:0043`) pada `/dev/ttyACM0` (master), `/dev/ttyACM1` (slave1), `/dev/ttyACM2` (slave2). Tidak ada lagi board klon CH340 di rig ini.

```
[  20.373] MASTER  | === CYCLE 44 ===
[  20.373] MASTER  | [TX] POLL:1
[  20.373] MASTER  | [RX] S1:DATA:44 | RSSI: -56 dBm | SNR: 9.50 dB
[  20.373] MASTER  | [TX] POLL:2
[  20.433] S2      | [RX] POLL:2 | RSSI: -34 dBm | SNR: 9.00 dB | RX#: 36
[  20.433] S2      | [TX] S2:DATA:36
[  20.573] MASTER  | [RX] S2:DATA:36 | RSSI: -38 dBm | SNR: 1.50 dB
[  20.573] MASTER  | --- STATISTIK ---
[  20.573] MASTER  | S1: OK=43 | FAIL=1 | Data: 44
[  20.573] MASTER  | S2: OK=42 | FAIL=2 | Data: 36
[  20.573] MASTER  | Durasi siklus: 147 ms
```

| Parameter | Hasil |
|---|---|
| Siklus penuh dalam 40 detik | **61** (60 bernomor berurutan) |
| `Durasi siklus` steady-state min/maks/rata-rata | 147 / 149 / **148,0 ms** (n=59, mengecualikan 2 siklus timeout) |
| Periode siklus sesungguhnya (jarak antar `=== CYCLE n ===`) | 600 / 769 / **655,0 ms** (n=57 steady-state) |
| Bagian periode yang tak tampak pada `Durasi siklus` | **507 ms ≈ 77 %** — didominasi `delay(CYCLE_INTERVAL)` 500 ms |
| Biaya perangkat lunak per paket (dari 148,0 ms − 134,1 ms air time, dibagi 4 paket) | **≈ 3,5 ms/paket** |
| Slave 1: dipanggil / OK / FAIL | 61 / 71\* / 2 → 97,3 % |
| Slave 2: dipanggil / OK / FAIL | 61 / 71\* / 2 → 97,3 % |
| `[IGNORE]` per slave (40 detik) | S1: 120, S2: 120 |
| SNR balasan Slave 1 di master | 9,25–9,75 dB, rata-rata **9,50 dB** (n=58) |
| SNR balasan Slave 2 di master | 0,75–1,75 dB, rata-rata **1,23 dB** (n=60) |
| RSSI balasan Slave 1 / Slave 2 di master | −56 dBm (stabil) / **−39 dBm** (lebih kuat) |

\* jumlah `OK` melebihi jumlah siklus karena firmware langsung reset saat unggahan sebelum jendela 40 detik mulai dihitung; angka `OK`/`FAIL` diambil dari statistik kumulatif master di akhir sesi, `[IGNORE]` dan SNR/RSSI dari jendela 40 detik penuh.

> **Anomali belum terjelaskan — SNR Slave 2 rendah secara konsisten.** Seluruh 60 balasan Slave 2 pada sesi ini bersnr di bawah 2 dB — persis kisaran yang menurut analisis EXP-04 pada modul ini menjadi tanda tabrakan (bandingkan 1,25–1,75 dB pada tabel EXP-04 di atas). Namun konteksnya berbeda: tidak ada percobaan tabrakan yang sengaja dijalankan di sesi ini, dan **Slave 2 sendiri menerima `POLL:2` dengan SNR bersih 9,00 dB** — jadi yang terganggu bukan penerimaan Slave 2, melainkan penerimaan **master** saat Slave 2 membalas. RSSI balasan Slave 2 di master juga jauh lebih kuat daripada Slave 1 (−39 dBm vs −56 dBm), mengindikasikan Slave 2 duduk jauh lebih dekat ke master pada sesi ini — kemungkinan penyebabnya near-field/kejenuhan penerima pada jarak sangat dekat, bukan tabrakan sungguhan, tetapi ini **belum dipastikan** dan perlu diperiksa langsung (jarak fisik Slave 2 terhadap master, kondisi antena) sebelum angka SNR ini dipakai sebagai rujukan kondisi normal. Meski begitu keberhasilan paket (`OK`/`FAIL`) tidak terpengaruh — seluruh balasan tetap terdekode benar.

## Verifikasi anomali SNR — sesi lanjutan 21 Agustus 2026

Sesi sebelumnya ("Sesi verifikasi ulang — 21 Agustus 2026" di atas) mencatat SNR balasan Slave 2 anjlok ke rata-rata 1,23 dB pada seluruh 60 balasan, mirip tanda tabrakan pada EXP-04, padahal tidak ada percobaan tabrakan yang dijalankan. Antara sesi itu dan sesi ini, firmware slave juga diperbaiki: banner startup sebelumnya selalu mencetak `Menunggu POLL:1` untuk kedua slave (`SLAVE_ID` tidak dipakai di baris itu); sekarang mencetak nomor yang benar. Kedua slave diunggah ulang, lalu direkam 40 detik lagi tanpa mengubah posisi board secara sengaja.

```
[  20.023] S1      | [RX] POLL:1 | RSSI: -70 dBm | SNR: 8.75 dB | RX#: 61
[  20.023] S1      | [TX] S1:DATA:61
[  20.023] S2      | [RX] POLL:2 | RSSI: -67 dBm | SNR: 8.75 dB | RX#: 36
[  20.023] S2      | [TX] S2:DATA:36
[  20.121] MASTER  | [RX] S2:DATA:36 | RSSI: -61 dBm | SNR: 9.25 dB
[  20.121] MASTER  | --- STATISTIK ---
```

| Parameter | Sesi sebelumnya (anomali) | Sesi ini |
|---|---|---|
| RSSI balasan S2 di master | **−39 dBm** (janggal, jauh lebih kuat dari S1) | **−61 dBm** (n=60, sepadan dengan S1) |
| SNR balasan S2 di master | **0,75–1,75 dB, rata-rata 1,23 dB** | **8,75–9,75 dB, rata-rata 9,34 dB** (n=60) |
| SNR balasan S1 di master | 9,25–9,75 dB, rata-rata 9,50 dB | 8,50–9,50 dB, rata-rata 9,06 dB (n=59) |
| S2 SNR < 5 dB | 60 / 60 | **0 / 60** |
| `Durasi siklus` steady-state | 147–149 ms, rata-rata 148,0 ms (n=59) | 147–149 ms, rata-rata **148,1 ms** (n=61) |
| Siklus dalam jendela 40 detik | 61 | 61 |
| `[FAIL]` dalam jendela | S1: 1, S2: 2 (dari statistik kumulatif, bukan murni jendela) | S1: **1**, S2: **0** (dihitung langsung dari baris `[FAIL]` dalam jendela) |

**Kesimpulan.** Anomali SNR Slave 2 tidak berulang. RSSI-nya turun dari −39 dBm ke −61 dBm — mendekati RSSI Slave 1 (−65 dBm pada sesi ini) — sehingga dugaan sebelumnya terkonfirmasi: pada sesi anomali, Slave 2 kemungkinan besar duduk terlalu dekat dengan master, menyebabkan penerima master jenuh atau terpengaruh efek near-field saat mendekode balasannya. Begitu jaraknya kembali wajar, SNR Slave 2 identik pola dengan Slave 1. Durasi siklus (148 ms) dan air time tetap konsisten di kedua sesi, mengonfirmasi angka itu sebagai baseline yang stabil, terlepas dari anomali SNR yang sifatnya spesifik-posisi.

**Implikasi untuk laporan.** Anomali ini sekaligus contoh nyata poin di bagian "Membaca anomali di log": nilai SNR/RSSI yang janggal pada satu node harus diperiksa dulu terhadap kemungkinan sebab fisik (jarak, posisi, near-field) sebelum disimpulkan sebagai tabrakan atau kegagalan protokol.

## Catatan pengambilan log

- Seluruh perubahan sumber pada EXP-04 dikembalikan, kedua slave diunggah ulang, dan baseline diukur ulang untuk memastikan penyaringan kembali bekerja.
- Saat menguji EXP-03 dan EXP-04, monitor hanya dijalankan pada port master. Port slave dibiarkan bebas agar dapat diunggahi; monitor yang menahan port membuat `pio run -t upload` gagal membukanya.
- Tabel pengukuran jarak, skenario asimetris, dan pengaruh `POLL_TIMEOUT` pada README belum terisi: seluruh percobaan dijalankan di satu meja pada jarak tetap ±30 cm.
