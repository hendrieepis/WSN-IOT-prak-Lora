```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
   MODUL 05 — Master-Slave 3 Node (Round-Robin Polling)

   Arduino Uno + Dragino LoRa Shield v1.2 · Advanced
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 05 dirancang untuk tiga pertemuan (3 × 50 menit) pada tingkat lanjut. Misinya menambah jumlah node menjadi tiga tanpa membiarkan mereka saling menimpa di udara: satu master memanggil tiap slave bergiliran, dan slave hanya bersuara ketika namanya disebut. Percobaan memakai tiga Arduino Uno bershield Dragino LoRa v1.2, diamati melalui tiga Serial Monitor pada 115200 baud.

Empat modul sebelumnya selalu melibatkan tepat dua board, sehingga tidak pernah ada pertanyaan siapa yang boleh bicara. Begitu node ketiga hadir, masalah baru muncul seketika: radio LoRa tidak memiliki alamat, tidak memiliki mekanisme penghindaran tabrakan, dan tidak dapat mendengar ketika sedang memancar. Bila dua slave menjawab bersamaan, kedua paket bertabrakan dan **tidak satu pun** yang dapat dipecahkan master — kegagalan yang bahkan tidak terlihat sebagai kesalahan, hanya sebagai sunyi. Modul ini menyelesaikannya dengan cara paling tua dan paling mudah dibuktikan: penjadwalan terpusat, tempat hak bicara diberikan satu per satu oleh master.

Prasyaratnya adalah M03 untuk percakapan dua arah dan penanda identitas pada payload, serta M04 untuk penungguan berbatas waktu dan statistik keberhasilan. Yang dibangun di sini adalah pengalamatan di lapisan aplikasi (`POLL:1`, `S1:DATA:n`), penjadwalan round-robin, penyaringan paket yang bukan miliknya, batas waktu per node, serta statistik per node yang terpisah. Pola master-slave ini adalah bentuk paling sederhana dari penjadwalan medium yang pada jaringan sungguhan dikerjakan lapisan MAC.

**Peta modul LoRa (penutup seri)**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 01 | Tautan satu arah terbentuk; RSSI dan SNR terbaca |
| 02 | Penerimaan lewat interrupt — `loop()` tidak lagi menunggu |
| 03 | Dua arah bergantian di atas radio half-duplex |
| 04 | Setiap pengiriman diketahui hasilnya: ACK, timeout, statistik |
| **05 (ini)** | **Banyak node — hak bicara dijadwalkan agar tidak bertabrakan** |

**Kontrak data lab ini.** Perintah master berbentuk `POLL:<id>` dan jawaban slave berbentuk `S<id>:DATA:<n>`. Nomor id mengikat keduanya, sedangkan `n` adalah penghitung lokal slave yang **naik hanya setelah pengiriman benar-benar dilakukan** — sehingga angka itu mewakili jumlah jawaban yang sungguh dikirim, bukan jumlah niat mengirim. Perbedaan halus ini menjadi bahan analisis tersendiri.

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Menjelaskan mengapa tabrakan paket pasti terjadi pada LoRa mentah bila beberapa node bicara tanpa penjadwalan, dan mengapa tabrakan itu tidak terlihat sebagai pesan kesalahan.
2. Menerapkan pengalamatan di lapisan aplikasi ketika lapisan radio tidak menyediakannya.
3. Membangun penjadwalan round-robin dengan batas waktu per node, dan menjelaskan pengaruh nilai batas waktu terhadap lama siklus.
4. Mengukur keberhasilan dan waktu tanggap **per node**, bukan gabungan, lalu menjelaskan penyebab perbedaannya.
5. Menjelaskan batas skala pendekatan master-slave dan memperkirakan titik ketika pendekatan itu tidak lagi memadai.

**Kriteria keberhasilan**

- ☐ Master menyelesaikan siklus penuh: memanggil Slave 1 lalu Slave 2 bergantian tanpa henti.
- ☐ Setiap slave hanya menjawab panggilan bernomor dirinya, dan mencetak `[IGNORE]` untuk yang lain.
- ☐ Statistik `OK` dan `FAIL` tercatat terpisah untuk tiap slave.
- ☐ Ketika satu slave dimatikan, master tetap melayani slave lainnya dan mencatat kegagalan pada slave yang hilang.
- ☐ Lama siklus terukur dan dijelaskan penyusunnya.

## 3 · Dasar Teori (secukupnya)

| Istilah | Definisi kerja di lab ini |
|---|---|
| Master | Node yang menjadwalkan, memanggil tiap slave bergiliran. Hanya ada satu. |
| Slave | Node yang diam sampai dipanggil, lalu menjawab tepat satu kali. |
| Round-robin | Penjadwalan bergilir merata: 1, 2, 1, 2, … tanpa prioritas. |
| Tabrakan | Dua paket mengudara bersamaan sehingga saling merusak; penerima tidak menerima apa pun. |
| Masalah hidden node | Dua slave yang saling tidak terdengar tetap dapat bertabrakan di posisi master. Penjadwalan terpusat menghindarinya. |
| Batas waktu polling | Lama master menunggu jawaban sebelum menyatakan slave tidak merespons (500 ms pada modul ini). |
| Lama siklus | Waktu satu putaran penuh memanggil seluruh slave. Menentukan seberapa sering tiap node terbaca. |

**Mengapa penjadwalan lebih dahulu, bukan pengalamatan lebih dahulu.** Memberi nomor pada tiap node menyelesaikan persoalan "pesan ini untuk siapa", tetapi tidak menyelesaikan "siapa yang boleh bicara sekarang". Seandainya kedua slave dibiarkan mengirim sendiri secara berkala, penomoran tetap tidak menolong: dua paket yang bertabrakan di udara rusak sebelum sempat dibaca nomornya. Karena itu master memberi hak bicara satu per satu, dan nomor node hanya dipakai untuk memastikan jawaban yang tiba berasal dari node yang sedang dipanggil.

**Mengapa lama siklus penting.** Master menunggu paling lama 500 ms untuk tiap slave. Bila kedua slave menjawab cepat, satu siklus selesai dalam ratusan milidetik; bila keduanya mati, siklus memakan sekitar satu detik penuh hanya untuk menunggu kesunyian. Dengan sepuluh slave, satu node yang mati memperlambat pembacaan seluruh node lain — sifat yang perlu diperhitungkan sebelum jumlah node ditambah.

**Sekuens yang diamati**

```
   Master                       Slave 1                     Slave 2
     |                             |                           |
  "POLL:1" ---------------------> tiba                     tiba juga
     |                        cocok -> jawab            tidak cocok -> [IGNORE]
  tunggu <= 500 ms                 |                           |
     |  <----------- "S1:DATA:12" -+                           |
  catat OK                                                     |
     |                                                         |
  "POLL:2" ------------------------------------------------> tiba
     |                        [IGNORE]                    cocok -> jawab
  tunggu <= 500 ms                                             |
     |  <-------------------------------------- "S2:DATA:12" --+
  catat OK, cetak statistik, jeda 500 ms, ulangi siklus
```

## 4 · Topologi

```
                        BOARD #1
                 +---------------------+
                 |     Arduino Uno     |
                 |   + LoRa Shield     |
                 |       MASTER        |
                 | polling round-robin |
                 +----------+----------+
                 POLL:1     |     POLL:2
              /-------------+-------------\
             v                             v
    +------------------+          +------------------+
    |   Arduino Uno    |          |   Arduino Uno    |
    | + LoRa Shield    |          | + LoRa Shield    |
    |     SLAVE 1      |          |     SLAVE 2      |
    | jawab POLL:1     |          | jawab POLL:2     |
    | "S1:DATA:n"      |          | "S2:DATA:n"      |
    +------------------+          +------------------+
       env: slave1                   env: slave2
```

| Node | Environment | Build flag | Peran | Batas waktu |
|---|---|---|---|---|
| Master | `master` | — | Memanggil bergiliran, mencatat statistik | 500 ms per slave |
| Slave 1 | `slave1` | `-DSLAVE_ID=1` | Menjawab `POLL:1` | — |
| Slave 2 | `slave2` | `-DSLAVE_ID=2` | Menjawab `POLL:2` | — |

Kedua slave memakai **file source yang sama**, `src/slave/main.cpp`; nomornya ditentukan build flag. Menambah slave ketiga berarti menambah satu environment dan menaikkan `SLAVE_COUNT` di master.

## 5 · Alat yang Digunakan

Modul ini dijalankan di atas Arduino Uno (ATmega328P) dengan Dragino LoRa Shield v1.2 (SX1276), memakai PlatformIO dan library LoRa karya sandeepmistry.

| No | Peralatan | Spesifikasi | Jumlah |
|---|---|---|---|
| 1 | Arduino Uno | ATmega328P | 3 |
| 2 | Dragino LoRa Shield | v1.2, SX1276, 433 MHz | 3 |
| 3 | Antena SMA | **wajib terpasang sebelum diberi daya** | 3 |
| 4 | Kabel USB tipe B | kabel data | 3 |
| 5 | PC/Laptop | PlatformIO Core/IDE, idealnya 3 port USB bebas | 1 |

> **Baud modul ini 115200**, berbeda dari M01–M04 yang memakai 9600. Serial Monitor yang masih tersetel 9600 akan menampilkan karakter acak — gejala yang sering disangka kerusakan perangkat.

**Struktur proyek**

```
week05_lora_master_slave/
├── platformio.ini              ← 3 environment; nomor slave lewat build flag
├── monitor_serial.py           ← pantau 3 node, ringkas siklus/keberhasilan/[IGNORE]
├── logserial.md                ← log referensi hasil uji perangkat
├── lora_monitor.py             ← dashboard tiga node dalam satu layar (butuh `rich`)
├── lora_session_20260516_071007.csv   ← contoh rekaman sesi (referensi)
└── src/
    ├── master/main.cpp         ← polling round-robin + statistik per node
    └── slave/main.cpp          ← satu source untuk kedua slave
```

**Build & flash** — **kedua slave lebih dahulu**, master belakangan.

```bash
pio run -d week05_lora_master_slave -e slave1 -t upload
pio run -d week05_lora_master_slave -e slave2 -t upload
pio run -d week05_lora_master_slave -e master -t upload -t monitor
```

**Memantau ketiga node sekaligus.** Tiga Serial Monitor terpisah menyulitkan penilaian urutan kejadian, karena tiap jendela memiliki sumbu waktunya sendiri. Tersedia dua alat.

`monitor_serial.py` — sama seperti Modul 01–04, tanpa pustaka tambahan, dan meringkas hasil ukur saat berhenti:

```bash
python3 week05_lora_master_slave/monitor_serial.py --baud 115200 --durasi 40
python3 week05_lora_master_slave/monitor_serial.py --baud 115200 --port S2=/dev/ttyUSB0
```

```
  Siklus polling : 53  (nomor 7..59)
  Lama siklus min/maks/rata-rata : 147 / 154 / 152 ms
  Slave 1 : dipanggil 53  menjawab 52  gagal 0  -> keberhasilan 98.1 %
  Slave 2 : dipanggil 52  menjawab 52  gagal 0  -> keberhasilan 100.0 %
  S1 membuang 116 panggilan milik node lain ([IGNORE])
  S2 membuang 115 panggilan milik node lain ([IGNORE])
```

`lora_monitor.py` — dasbor berwarna dengan perekaman CSV, memerlukan pustaka `rich`:

```bash
pip install pyserial rich
python3 lora_monitor.py --master /dev/ttyACM0 --s1 /dev/ttyACM1 --s2 /dev/ttyACM2 --baud 115200
python3 lora_monitor.py --master /dev/ttyACM0 --s1 /dev/ttyACM1 --s2 /dev/ttyACM2 --out sesi1.csv
```

Berkas `lora_session_20260516_071007.csv` adalah contoh keluarannya, berguna untuk melihat format kolom sebelum merekam sesi sendiri. Rekaman itu diambil dengan revisi firmware terdahulu, sehingga baris pembukanya masih mencetak nama port Windows (`Peran: MASTER (COM3)`) — firmware sekarang mencetak nama environment PlatformIO. Isi dan format kolomnya tetap sama.

**Pre-flight checklist**

- ☐ Antena terpasang pada ketiga shield.
- ☐ `pio device list` dijalankan, ketiga port dicatat dan diisikan ke `platformio.ini`.
- ☐ Serial Monitor **115200** baud disiapkan, bukan 9600.
- ☐ Label fisik ditempel pada board: MASTER, SLAVE 1, SLAVE 2.

## 6 · Percobaan

### EXP-01 — Slave Menyaring Panggilan

Nyalakan kedua slave lebih dahulu tanpa master, lalu nyalakan master dan amati Serial kedua slave.

**Expected output — Slave 1**

```
=== LoRa SLAVE 1 ===
Init LoRa ... OK
Menunggu POLL:1 dari Master...

[RX] POLL:1 | RSSI: -36 dBm | SNR: 9.75 dB | RX#: 1
[TX] S1:DATA:1
[IGNORE] POLL:2
```

**Data capture**

| Parameter | Hasil |
|---|---|
| Apakah Slave 1 menerima `POLL:2`? | |
| Apa yang dilakukannya terhadap paket itu? | |
| Jumlah `[IGNORE]` per siklus di tiap slave | |

> **CHECKPOINT** — Setiap slave **menerima** panggilan untuk slave lain, lalu membuangnya. Inilah bukti langsung bahwa LoRa tidak memiliki pengalamatan: penyaringan sepenuhnya dikerjakan aplikasi. Slave yang tidak pernah mencetak `[IGNORE]` berarti tidak mendengar panggilan sama sekali — periksa jarak dan antena.

### EXP-02 — Siklus Round-Robin

Amati master selama dua menit.

**Expected output — master**

```
========================================
=== CYCLE 4 ===
[TX] POLL:1
[RX] S1:DATA:4 | RSSI: -35 dBm | SNR: 9.50 dB
[TX] POLL:2
[RX] S2:DATA:4 | RSSI: -41 dBm | SNR: 9.25 dB
--- STATISTIK ---
S1: OK=4 | FAIL=0 | Data: 4
S2: OK=4 | FAIL=0 | Data: 4
Durasi siklus: 214 ms
========================================
```

**Data capture**

| Parameter | Hasil |
|---|---|
| Lama siklus saat kedua slave sehat (ms) | |
| Jumlah siklus per menit | |
| `OK` / `FAIL` Slave 1 setelah 2 menit | |
| `OK` / `FAIL` Slave 2 setelah 2 menit | |
| RSSI Slave 1 / Slave 2 (dBm) | |

**Buka abstraksinya** — di `src/slave/main.cpp`, `dataCounter++` sengaja diletakkan **sesudah** paket diterima tetapi **sebelum** `transmit()`, sementara komentarnya menjelaskan alasannya. Bandingkan dengan `rxCount++` yang naik lebih awal. Jawab: apa arti berbeda dari kedua penghitung itu, dan angka mana yang akan berbeda dengan `Data:` yang tercatat master ketika sebagian jawaban hilang di udara?

> **CHECKPOINT** — Nilai `Data:` di master harus mengikuti penghitung slave secara berurutan. Lompatan pada nilai itu berarti ada jawaban yang tidak sampai — catat, karena itulah bahan tabel pengukuran.

### EXP-03 — Satu Node Hilang

Uji ketahanan jadwal ketika salah satu slave menghilang.

| # | Skenario | Langkah | Yang diamati |
|---|---|---|---|
| 1 | Slave 2 mati | Cabut USB Slave 2 | pesan master, lama siklus, `FAIL` |
| 2 | Slave 2 kembali | Pasang lagi | berapa siklus sampai `OK` bertambah lagi |
| 3 | Kedua slave mati | Cabut keduanya | lama siklus saat sunyi total |
| 4 | Slave 1 dijauhkan | Bawa ke jarak 50 m | `FAIL` Slave 1 vs Slave 2 |

**Data capture**

| Parameter | Hasil |
|---|---|
| Pesan master saat slave tidak menjawab | |
| Lama siklus dengan satu slave mati (ms) | |
| Lama siklus dengan kedua slave mati (ms) | |
| Apakah Slave 1 terpengaruh oleh matinya Slave 2? | |
| Apakah pemulihan terjadi otomatis? | |

> **CHECKPOINT** — Skenario 3 memperlihatkan sifat penting penjadwalan terpusat: lama siklus **membengkak** menjadi sekitar jumlah seluruh batas waktu, karena master tetap menunggu setiap node yang sudah tidak ada. Catat angkanya — inilah dasar perhitungan batas skala pada bagian Analisis.

### EXP-04 — Tabrakan yang Disengaja

Percobaan ini memperlihatkan mengapa penjadwalan diperlukan. Ubah **kedua** slave agar menjawab panggilan mana pun, dengan mengganti pemeriksaan nomor:

```cpp
  // Sengaja dilumpuhkan untuk EXP-04: kedua slave menjawab semua panggilan
  // if (!received.equals("POLL:" + String(SLAVE_ID))) { ... return; }
```

Unggah ke kedua slave, amati master selama satu menit, lalu **kembalikan kodenya**.

**Data capture**

| Parameter | Hasil |
|---|---|
| Berapa jawaban yang berhasil dipecahkan master? | |
| Pesan apa yang muncul di master? | |
| Apakah master menerima campuran keduanya? | |

> **CHECKPOINT** — Sebagian besar siklus akan berakhir dengan `[FAIL]` atau `[WARN] Balasan tidak valid`, padahal kedua slave jelas-jelas mengirim. Tabrakan tidak menghasilkan pesan kesalahan dari radio — hanya kesunyian atau data rusak. Pengamatan ini adalah inti seluruh modul.

**Perhatikan kolom SNR.** Pada pengujian rujukan, SNR di master anjlok dari 9,0–9,8 dB menjadi **1,25–1,75 dB** begitu kedua slave menjawab bersamaan: jawaban satu slave menjadi derau bagi jawaban slave lainnya. Inilah cara paling langsung mendeteksi tabrakan dari sisi aplikasi, dan bahan jawaban pertanyaan nomor 5 pada bagian Analisis. Perhatikan pula bahwa kegagalannya **tidak merata** — Slave 2 tetap terbaca master sedangkan Slave 1 tidak pernah berhasil sama sekali, karena penerima memenangkan sinyal yang lebih kuat (*capture effect*). Dari sisi master, node yang kalah tampak seperti mati.

### Verifikasi hardware (log referensi)

Dijalankan pada tiga Arduino Uno bershield Dragino LoRa v1.2, 433 MHz, jarak ±30 cm. Log lengkap ada di `logserial.md`.

| Parameter | Hasil terukur |
|---|---|
| Siklus dalam 40 detik | **53** — lama siklus 147/154/**152 ms** |
| Keberhasilan kedua slave | **100 %**, 0 `FAIL` |
| `[IGNORE]` per slave per siklus | **2** — panggilan *dan* jawaban milik node lain |
| Lama siklus saat satu node mati | **611 ms** — melipat **4×** dari 152 ms |
| Pertambahan akibat satu node mati | +459 ms ≈ `POLL_TIMEOUT` |
| Apakah node sehat ikut terganggu? | tidak |
| **EXP-04 tabrakan: SNR di master** | **9,0–9,8 dB → 1,25–1,75 dB** |
| EXP-04: keberhasilan Slave 1 | 100 % → **0 %** (kalah *capture* dari Slave 2) |

```
Environment    Status    Flash
master         SUCCESS   29.7% (9574 B)
slave1         SUCCESS   26.3% (8492 B)
slave2         SUCCESS   26.3% (8492 B)
```

Master paling besar karena memuat penjadwal dan statistik dua node. Kedua slave berukuran sama persis — bukti bahwa keduanya berasal dari source yang sama dan hanya berbeda nilai `SLAVE_ID`.

**Verifikasi ulang — 21 Agustus 2026.** Ketiga board diunggah ulang dan direkam 40 detik pada konfigurasi port yang berbeda dari log di atas (ketiganya kini Uno asli, `ttyACM0/1/2`, bukan lagi klon CH340). Lama siklus steady-state **147–149 ms, rata-rata 148,0 ms** (n=59) — sejalan dengan sesi sebelumnya. Balasan Slave 2 pada sesi ini sempat menunjukkan **SNR rendah tak wajar** (rata-rata 1,23 dB, mirip tanda tabrakan pada tabel EXP-04) meski Slave 2 sendiri menerima `POLL:2` dengan bersih (9,00 dB) — gangguannya ada di penerimaan master, bukan di Slave 2.

**Anomali itu terselesaikan pada sesi lanjutan hari yang sama**, setelah bug banner startup diperbaiki (lihat catatan di bawah) dan kedua slave diunggah ulang: RSSI balasan Slave 2 turun dari −39 dBm menjadi **−61 dBm** — sepadan dengan Slave 1 (−65 dBm) — dan SNR-nya kembali normal, **rata-rata 9,34 dB** dari 60 balasan, tidak satu pun di bawah 5 dB. Dugaannya terkonfirmasi: pada sesi anomali, Slave 2 kemungkinan besar duduk terlalu dekat dengan master, menyebabkan penerima master jenuh (near-field), bukan tabrakan sungguhan. Rincian dan tabel perbandingan kedua sesi ada di `logserial.md`, bagian "Verifikasi anomali SNR — sesi lanjutan 21 Agustus 2026".

**Catatan perbaikan — banner yang berbohong.** Sebelum diperbaiki, `src/slave/main.cpp` mencetak `Serial.println(F("Menunggu POLL:1 dari Master...\n"))` sebagai literal tetap, tidak memakai `SLAVE_ID` — sehingga Slave 2 pun mencetak "menunggu POLL:1" di layarnya sendiri, padahal logika penyaringannya (`received.equals("POLL:" + String(SLAVE_ID))`) sudah benar sejak awal. Bug ini murni kosmetik — tidak memengaruhi jawaban maupun statistik — tapi cukup untuk menyesatkan siapa pun yang mendiagnosis dari banner saja. Baris itu sekarang `Serial.print(F("Menunggu POLL:")); Serial.print(SLAVE_ID);` — bukti bahwa dua baris kode yang tampak sepele pun bisa diam-diam salah selama tidak ada yang membandingkannya dengan `SLAVE_ID` sungguhan.

## 7 · Pengukuran

**A. Keberhasilan per node terhadap jarak** — kedua slave ditempatkan pada jarak sama, 30 siklus per baris.

| Jarak | RSSI S1 | RSSI S2 | OK/FAIL S1 | OK/FAIL S2 | Keberhasilan S1 (%) | Keberhasilan S2 (%) |
|---|---|---|---|---|---|---|
| 1 m | | | | | | |
| 25 m | | | | | | |
| 50 m | | | | | | |
| 100 m | | | | | | |

**B. Skenario asimetris** (wajib) — Slave 1 didekatkan, Slave 2 dijauhkan.

| Posisi S1 | Posisi S2 | Keberhasilan S1 (%) | Keberhasilan S2 (%) | Lama siklus (ms) | Kesimpulan |
|---|---|---|---|---|---|
| 1 m | 100 m | | | | |

**C. Lama siklus terhadap jumlah node yang hidup**

| Kondisi | Lama siklus (ms) | Siklus per menit |
|---|---|---|
| Kedua slave hidup | | |
| Satu slave mati | | |
| Kedua slave mati | | |

**D. Pengaruh batas waktu polling** — ubah `POLL_TIMEOUT` pada master, jarak tetap.

| `POLL_TIMEOUT` | Lama siklus (ms) | Keberhasilan S1 (%) | Keberhasilan S2 (%) |
|---|---|---|---|
| 200 ms | | | |
| 500 ms | | | |
| 1000 ms | | | |

## 8 · Analisis

1. Dari tabel C, berapa milidetik yang ditambahkan tiap node mati terhadap lama siklus? Susun rumus perkiraan lama siklus untuk `n` slave dengan `k` di antaranya mati.
2. Berdasarkan rumus tersebut, berapa jumlah slave maksimum bila setiap node harus terbaca minimal sekali setiap 5 detik pada kondisi terburuk? Sebutkan asumsinya.
3. Dari tabel D, apa akibat memperpendek batas waktu menjadi 200 ms? Kaitkan dengan waktu udara pada SF7 dan jelaskan mengapa nilai yang terlalu kecil menghasilkan kegagalan palsu.
4. Pada tabel B, apakah slave yang jauh menurunkan kualitas slave yang dekat? Bandingkan jawabannya dengan perilaku topologi bintang pada modul BLE multi-node, dan jelaskan sumber perbedaannya.
5. EXP-04 memperlihatkan tabrakan tidak menghasilkan pesan kesalahan. Sebutkan dua cara mendeteksi tabrakan dari sisi aplikasi, beserta keterbatasan masing-masing.
6. Pendekatan master-slave menjadwalkan hak bicara secara terpusat. Sebutkan dua kelemahan mendasarnya, lalu bandingkan dengan pendekatan lain seperti ALOHA atau LoRaWAN kelas A.

## 9 · Concept Check

1. Mengapa slave tetap menerima paket yang bukan miliknya, dan di lapisan mana penyaringan dilakukan?
2. Apa yang terjadi bila kedua slave menjawab bersamaan, dan mengapa hal itu tidak muncul sebagai pesan kesalahan?
3. Apa fungsi `POLL_TIMEOUT`, dan apa yang menentukan nilai terkecilnya yang masuk akal?
4. Mengapa `dataCounter` dinaikkan setelah paket diterima dan bukan pada saat pengiriman dinyatakan berhasil?
5. Mengapa kedua slave dapat memakai satu file source yang sama?
6. Mengapa modul ini memakai 115200 baud sementara modul sebelumnya 9600? Apa gejalanya bila Serial Monitor salah setel?

## 10 · Challenge (tugas modifikasi)

- **CH-1 — Slave ketiga.** Tambahkan `SLAVE_ID=3`: satu environment baru dan penyesuaian `SLAVE_COUNT` di master. Ukur pertambahan lama siklus dan bandingkan dengan rumus dari bagian Analisis.
- **CH-2 — Sensor sungguhan.** Ganti penghitung slave dengan pembacaan sensor pada A0, lalu kirimkan nilainya (`S1:DATA:512`). Bahas mengapa laju pembacaan kini dibatasi lama siklus master.
- **CH-3 — Perintah turun.** Tambahkan perintah `CMD:1:LED_ON` dari master, sehingga komunikasi tidak hanya mengambil data tetapi juga mengendalikan slave.
- **CH-4 — Jadwal adaptif.** Buat master melewati slave yang sudah gagal tiga kali berturut-turut, dan menengoknya kembali sekali setiap sepuluh siklus. Ukur perbaikan lama siklus saat satu node mati.
- **CH-5 — Rekam dan analisis.** Jalankan `lora_monitor.py --out sesi.csv` selama sepuluh menit, lalu olah CSV-nya untuk membuat grafik RSSI terhadap waktu bagi kedua slave.

## 11 · Laporan

**Deliverable**

1. Misi dan capaian pembelajaran
2. Dasar teori ringkas (tabrakan, penjadwalan terpusat, round-robin, batas waktu)
3. Konfigurasi — build flag nomor slave, `POLL_TIMEOUT`, format `POLL:n` dan `S<n>:DATA:m`
4. Hasil eksperimen — log serial ketiga board (EXP-01…04 beserta checkpoint), sebaiknya rekaman CSV dari `lora_monitor.py`
5. Data pengukuran — tabel A, B, C, dan D pada bagian Pengukuran
6. Analisis dan concept check, termasuk rumus perkiraan lama siklus
7. Challenge — minimal CH-1 dan CH-4
8. Kesimpulan yang disusun sendiri mengenai batas skala pendekatan master-slave pada LoRa mentah
