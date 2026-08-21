```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
   MODUL 07 — Gateway Linux Menjadwalkan Node Arduino
              Varian -withCRC — CRC payload AKTIF

   Raspberry Pi + Arduino Uno · Advanced
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 07 dirancang untuk tiga pertemuan (3 × 50 menit) pada tingkat lanjut, dan menutup seluruh seri. Misinya memindahkan **master** Modul 05 dari Arduino Uno ke Raspberry Pi tanpa mengubah **satu baris pun** firmware slave — membentuk topologi gateway yang lazim di dunia nyata: satu komputer Linux yang menjadwalkan sekumpulan node mikrokontroler murah lewat radio, dikendalikan dari jarak jauh lewat SSH. Percobaan memakai satu Raspberry Pi bershield Dragino LoRa GPS HAT v1.4 sebagai master dan dua Arduino Uno bershield Dragino LoRa v1.2 sebagai slave, sama persis dengan perangkat keras slave Modul 05.

Modul ini adalah pertemuan dua kemampuan yang dibangun terpisah. Modul 05 membangun **penjadwalan**: pengalamatan aplikasi, round-robin, batas waktu per node, statistik terpisah. Modul 06 membangun **driver telanjang**: cara memegang register SX1276 langsung dari Python lewat `spidev` dan `RPi.GPIO`, dengan nama fungsi yang sengaja meniru API sandeepmistry (`beginPacket`, `endPacket`, `parsePacket`, `packetRssi`). Modul ini menggabungkan keduanya: `src/master.py` adalah penjadwal round-robin Modul 05, ditulis ulang di atas driver telanjang Modul 06. Kontrak datanya — `POLL:<id>` dan `S<id>:DATA:<n>` — tidak berubah sedikit pun, dan itulah yang membuat firmware slave dapat dipakai ulang tanpa modifikasi.

Prasyaratnya adalah M05 untuk logika penjadwalan dan M06 untuk driver telanjang. Yang dibangun di sini adalah pembuktian bahwa keduanya dapat disatukan lintas platform: master berganti dari C++/AVR ke Python/Linux, slave tidak menyadarinya sama sekali. Yang juga dibangun — dan tidak pernah muncul di modul-modul satu mesin sebelumnya — adalah **korelasi log lintas dua komputer independen**: master direkam di Raspberry Pi lewat SSH, slave direkam di laptop pengembang lewat USB, dan kedua rekaman tidak berbagi jam sama sekali. Isinya, bukan cap waktunya, yang membuktikan keduanya benar-benar saling bicara.

**Direktori ini adalah varian -withCRC dari Modul 07.** Modul 07 aslinya (`week07_rpi_master_slave/`) sengaja mematikan CRC payload di kedua sisi sebagai bahan ajar — paket yang rusak di udara lolos ke lapisan aplikasi dan salah didiagnosis sebagai "slave tidak merespon". Direktori ini menerapkan perbaikannya, yang di README asli tercatat sebagai tantangan **CH-2**: `LoRa.enableCrc()` ditambahkan di `src/slave/main.cpp`, dan bit yang sepadan (`REG_MODEM_CONFIG_2` bit 2) dinyalakan lewat `enableCrc()` baru di `src/master.py` serta `cek_radio.py`. Konsekuensinya, klaim "identik dengan slave M05" **tidak lagi berlaku secara harfiah** untuk firmware di direktori ini — satu baris fungsional berbeda, di luar komentar dan pesan pembuka. Bagian Percobaan dan `logserial.md` membandingkan perilaku sebelum/sesudah CRC dinyalakan.

**Peta modul LoRa (penutup seri)**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 01 | Tautan satu arah terbentuk; RSSI dan SNR terbaca |
| 02 | Penerimaan lewat interrupt — `loop()` tidak lagi menunggu |
| 03 | Dua arah bergantian di atas radio half-duplex |
| 04 | Setiap pengiriman diketahui hasilnya: ACK, timeout, statistik |
| 05 | Banyak node — hak bicara dijadwalkan agar tidak bertabrakan |
| 06 | Isi `LoRa.begin()` tidak pernah terlihat — register dipegang langsung |
| **07 (ini)** | **Penjadwal pindah ke gateway Linux; sisi node tidak berubah sama sekali** |

**Kontrak data lab ini.** Sama persis dengan Modul 05: perintah master berbentuk `POLL:<id>`, jawaban slave berbentuk `S<id>:DATA:<n>`. Tidak ada satu byte pun yang berubah di udara — yang berganti hanya bahasa dan platform yang menyusun serta membaca byte itu. Perbedaan halus satu-satunya ada di pesan pembuka Serial slave, yang sekarang menyebut `"Master (Raspberry Pi)"`.

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Membuktikan dengan `diff` seberapa kecil perubahan yang diperlukan pada firmware slave untuk menyalakan CRC payload, dan menjelaskan mengapa perubahan itu tetap membatalkan klaim "identik dengan M05".
2. Menerapkan ulang logika penjadwalan round-robin Modul 05 di atas driver SX1276 telanjang Modul 06, memakai `spidev` dan `RPi.GPIO`/`rpi-lgpio`.
3. Mengkorelasikan log dari dua mesin yang tidak berbagi jam — satu direkam lewat SSH di Raspberry Pi, satu lewat USB lokal — berdasarkan isi pesan, bukan cap waktu.
4. Menjelaskan mengapa menyalakan CRC payload di kedua sisi mengubah kelas kegagalan "payload rusak lolos ke aplikasi" menjadi "paket dibuang oleh radio sebelum sempat diproses", dan mengukur biayanya lewat waktu-di-udara.
5. Menelusuri anggaran waktu sesungguhnya di balik `POLL_TIMEOUT` — bagian siklus mana yang benar-benar dihitungnya — lalu memakainya untuk menjelaskan mengapa menyalakan CRC menggeser durasi siklus, bukan ambang kegagalannya.

**Kriteria keberhasilan**

- ☐ `master.py` berhasil memanggil kedua slave Uno bergiliran, dengan CRC payload **AKTIF** di kedua sisi — dibuktikan lewat `cek_radio.py` (`MODEM_CFG_2` bit 2 = 1) dan pesan `CRC payload: AKTIF` pada Serial Monitor slave.
- ☐ `cek_radio.py` membaca balik register SX1276 di Raspberry Pi dan hasilnya dibandingkan dengan konfigurasi yang dimaksud, termasuk bit CRC.
- ☐ Satu sesi log master (Raspberry Pi) dan log slave (laptop) dikorelasikan lewat isi pesan, bukan lewat waktu perekaman, dan menunjukkan nol baris `[WARN] Balasan tidak valid`.
- ☐ Durasi siklus dengan CRC aktif diukur dan dibandingkan terhadap baseline `week07_rpi_master_slave/logserial.md` (CRC mati) untuk mengukur biaya waktu-di-udara dari 2 byte CRC tambahan.

## 3 · Dasar Teori (secukupnya)

| Istilah | Definisi kerja di lab ini |
|---|---|
| Gateway | Node yang menjadwalkan jaringan radio dari komputer bertenaga penuh, terpisah dari node yang dijadwalkannya. Di sini: Raspberry Pi. |
| `spidev` | Antarmuka kernel Linux ke SPI perangkat keras — satu-satunya jalan bicara Python ke SX1276. |
| `RPi.GPIO` / `rpi-lgpio` | Kendali pin NSS/RESET dan pembacaan DIO0. Pi 5 memakai chip GPIO baru (RP1) yang butuh `rpi-lgpio` sebagai pengganti drop-in. |
| Jalankan lewat SSH | Master tidak punya layar sendiri; seluruh interaksi — unggah kode, jalankan, hentikan — dilakukan dari terminal jarak jauh. |
| CRC payload | Pemeriksaan keutuhan data oleh radio sendiri: 2 byte checksum ditambahkan ke tiap paket, diverifikasi otomatis oleh SX1276 penerima. **AKTIF** di kedua sisi pada varian ini (`LoRa.enableCrc()` di slave, `enableCrc()` di `master.py`) — bandingkan dengan `week07_rpi_master_slave/` (CRC mati) untuk melihat konsekuensinya. |
| Anggaran `POLL_TIMEOUT` | Bagian siklus yang benar-benar ditunggu batas waktu. TX `POLL` bersifat blocking dan selesai **sebelum** penghitung waktu mulai berjalan, sehingga anggarannya jauh lebih sempit dari dugaan naif. |
| Korelasi log lintas mesin | Membuktikan dua rekaman dari komputer berbeda menggambarkan peristiwa yang sama, memakai isi pesan (nomor urut, payload) sebagai pengikat karena keduanya tidak berbagi jam. |

**Mengapa firmware slave tidak perlu tahu siapa master-nya.** Slave hanya mendengar dua hal: `POLL:<id>` yang cocok dengan nomornya, dan segala sesuatu yang lain untuk diabaikan. Ia tidak pernah memeriksa dari mana `POLL` itu berasal, apalagi platform apa yang mengirimkannya. Selama pengirim baru menghasilkan bentuk gelombang yang identik — frekuensi, SF, BW, CR yang sama — SX1276 di sisi slave tidak dapat membedakan apakah lawan bicaranya Arduino atau Raspberry Pi. Inilah properti yang membuat pemindahan master menjadi mungkin tanpa sentuhan pada slave.

**Mengapa anggaran `POLL_TIMEOUT` lebih sempit dari dugaan.** Intuisi naif: batas waktu 500 ms harus menampung waktu udara `POLL` (±31 ms) **dan** waktu udara jawaban (±36–41 ms), sehingga ambang kegagalan diperkirakan baru muncul di atas 70-an ms. Kenyataannya, `transmit(pollMsg)` di `pollSlave()` bersifat blocking — ia baru kembali setelah `IRQ_TX_DONE` menyala, yaitu setelah `POLL` selesai mengudara. Penghitung waktu (`waitStart = time.monotonic()`) baru dimulai **sesudah** itu. Akibatnya jendela yang sebenarnya ditunggu hanya: pemrosesan di slave + waktu udara jawaban + deteksi RX di master — jauh lebih sempit dari intuisi awal. Bagian Percobaan mengukur persis di mana ambang itu berada. Angka-angka waktu udara di atas berasal dari sesi CRC **mati**; menyalakan CRC menambah 2 byte checksum ke setiap paket sehingga sedikit memperpanjang waktu udara kedua arah — pengukuran aktual pada varian ini ada di `logserial.md`.

**Sekuens yang diamati**

```
   Raspberry Pi (master)         Slave 1 (Uno)              Slave 2 (Uno)
     |                             |                           |
  "POLL:1" ---------------------> tiba                     tiba juga
  (TX blocking, ~31ms)       cocok -> jawab            tidak cocok -> [IGNORE]
     |  waitStart mulai DI SINI       |                           |
  tunggu <= POLL_TIMEOUT            |                           |
     |  <----------- "S1:DATA:12" -+                           |
  catat OK                                                     |
     |                                                         |
  "POLL:2" ------------------------------------------------> tiba
     |                        [IGNORE]                    cocok -> jawab
  tunggu <= POLL_TIMEOUT                                        |
     |  <-------------------------------------- "S2:DATA:12" --+
  catat OK, cetak statistik, jeda CYCLE_INTERVAL, ulangi siklus
```

## 4 · Topologi

```
                    RASPBERRY PI (di ruang server)
                 +----------------------------+
                 |  Raspberry Pi 5 + LoRa GPS  |
                 |  HAT  --  src/master.py     |
                 |  dijalankan lewat SSH        |
                 |  polling round-robin         |
                 +--------------+---------------+
                 POLL:1         |         POLL:2
              /------------------+------------------\
             v                                       v
    +------------------+                    +------------------+
    | Arduino Uno      |                    | Arduino Uno      |
    | + LoRa Shield    |                    | + LoRa Shield    |
    |     SLAVE 1      |                    |     SLAVE 2      |
    | jawab POLL:1     |                    | jawab POLL:2     |
    | "S1:DATA:n"      |                    | "S2:DATA:n"      |
    +------------------+                    +------------------+
       env: slave1                             env: slave2
       (identik dgn firmware M05, hanya beda pesan pembuka)
```

| Node | Environment / program | Build flag | Peran | Batas waktu |
|---|---|---|---|---|
| Master | `src/master.py` (Raspberry Pi, lewat SSH) | — | Memanggil bergiliran, mencatat statistik | 500 ms per slave |
| Slave 1 | `slave1` | `-DSLAVE_ID=1` | Menjawab `POLL:1` | — |
| Slave 2 | `slave2` | `-DSLAVE_ID=2` | Menjawab `POLL:2` | — |

Tidak ada environment PlatformIO untuk master — Python dijalankan langsung, tidak dikompilasi. `platformio.ini` di modul ini hanya memuat kedua environment slave. Kedua slave memakai **file source yang sama**, `src/slave/main.cpp`, identik dengan `week05_lora_master_slave/src/slave/main.cpp` kecuali komentar dan satu baris pesan pembuka Serial.

## 5 · Alat yang Digunakan

Modul ini menggabungkan dua platform: Raspberry Pi 5 dengan Dragino LoRa GPS HAT v1.4 sebagai master, dan dua Arduino Uno dengan Dragino LoRa Shield v1.2 sebagai slave — perangkat keras slave sama persis dengan Modul 05.

| No | Peralatan | Spesifikasi | Jumlah |
|---|---|---|---|
| 1 | Raspberry Pi | 2 / 3 / 4 / 5 — diuji pada **Pi 5** | 1 |
| 2 | Dragino LoRa GPS HAT | v1.4, SX1276, 433 MHz | 1 |
| 3 | Arduino Uno | ATmega328P | 2 |
| 4 | Dragino LoRa Shield | v1.2, SX1276, 433 MHz | 2 |
| 5 | Antena SMA | **wajib terpasang sebelum diberi daya**, di ketiga board | 3 |
| 6 | Kabel USB tipe B | ke kedua Uno | 2 |
| 7 | Akses jaringan ke Raspberry Pi | SSH, kunci terpasang lebih disarankan daripada kata sandi | 1 |

> **Baud slave 115200**, sama seperti Modul 05. Master tidak memakai Serial Monitor sama sekali — keluarannya langsung ke terminal SSH.

**Pemetaan pin HAT Raspberry Pi** (sisi master)

| LoRa GPS HAT | WiringPi | BCM GPIO | Padanan di shield Arduino |
|---|---|---|---|
| LoRa_NSS | GPIO6 | **25** | D10 |
| RESET | GPIO0 | **17** | D9 |
| DIO0 | GPIO7 | **4** | D2 |
| SCK / MOSI / MISO | GPIO14/12/13 | **11 / 10 / 9** | D13 / D11 / D12 |

Kolom **BCM** adalah yang dipakai `src/master.py` (`GPIO.setmode(GPIO.BCM)`). **NSS bukan CE0** — HAT memakai GPIO 25 biasa sebagai chip select, sehingga kode membuka SPI pada `(0, 0)` tetapi menggerakkan NSS sendiri di sekitar tiap transaksi, persis seperti driver Arduino menggerakkan D10. Rincian lengkap pemetaan pin ada di README utama bagian Perangkat Keras.

> **Raspberry Pi 5** memakai chip GPIO baru (RP1) yang tidak didukung `RPi.GPIO`. Pasang `rpi-lgpio` sebagai gantinya — nama modulnya sama (`import RPi.GPIO as GPIO`), sehingga tidak ada baris kode yang perlu diubah. Jangan memasang keduanya sekaligus. Lihat `requirements.txt`.

**Struktur proyek**

```
week07_rpi_master_slave-withCRC/
├── platformio.ini          ← hanya 2 environment: slave1, slave2
├── requirements.txt        ← spidev + RPi.GPIO (atau rpi-lgpio untuk Pi 5)
├── logserial.md            ← log referensi hasil uji perangkat, sangat lengkap
├── lora_monitor.py         ← dasbor 2 slave lokal + rekaman CSV (butuh `rich`)
├── cek_radio.py            ← baca balik register SX1276 di Raspberry Pi
└── src/
    ├── master.py           ← penjadwal round-robin, dijalankan DI Raspberry Pi
    └── slave/main.cpp      ← satu source untuk kedua slave, +LoRa.enableCrc() vs M05
```

**Build & flash slave** — dari laptop pengembang, seperti modul Arduino lain.

```bash
pio run -d week07_rpi_master_slave-withCRC -e slave1 -t upload
pio run -d week07_rpi_master_slave-withCRC -e slave2 -t upload
```

**Menyiapkan Raspberry Pi** — sekali per Pi.

```bash
ssh pi@<alamat-ip-pi>
sudo raspi-config                                    # Interface Options > SPI > Yes, lalu reboot
ls /dev/spi*                                         # harus muncul spidev0.0

pip3 install -r week07_rpi_master_slave-withCRC/requirements.txt
```

**Menjalankan master** — **kedua slave lebih dahulu**, baru master, dan master selalu di Raspberry Pi.

```bash
ssh pi@<alamat-ip-pi>
cd ~/Documents/WSN-IOT-prak-Lora/week07_rpi_master_slave-withCRC/src
python3 -u master.py            # -u penting bila keluarannya dipipa/direkam
```

`master.py` menerima `-h`/`--help` yang mencetak parameter radio tanpa menyentuh SPI/GPIO — aman dijalankan untuk memeriksa konfigurasi sebelum sesi sungguhan. Tidak ada opsi lain; seluruh parameter (frekuensi, SF, BW, `POLL_TIMEOUT`, `CYCLE_INTERVAL`) adalah konstanta di dalam berkas, sengaja dibuat sama dengan slave.

**Memantau kedua slave dari laptop.** Selagi master berjalan di Pi lewat SSH, kedua Uno tetap tersambung USB ke laptop pengembang. `lora_monitor.py` — dasbor dua node dengan perekaman CSV, memerlukan pustaka `rich`:

```bash
pip install pyserial rich
python3 lora_monitor.py --s1 /dev/ttyACM0 --s2 /dev/ttyACM1
python3 lora_monitor.py --s1 /dev/ttyACM0 --s2 /dev/ttyACM1 --out sesi1.csv
```

**Memverifikasi radio sebelum percobaan.** `cek_radio.py`, dijalankan di Raspberry Pi, membaca balik register SX1276 setelah `loraBegin()` + konfigurasi — bukan menyalin konstanta dari source, melainkan isi chip yang sesungguhnya:

```bash
ssh pi@<alamat-ip-pi>
cd ~/Documents/WSN-IOT-prak-Lora/week07_rpi_master_slave-withCRC
python3 cek_radio.py
```

**Pre-flight checklist**

- ☐ Antena terpasang pada HAT dan kedua shield.
- ☐ SPI aktif di Raspberry Pi — `ls /dev/spi*` menampilkan `spidev0.0`.
- ☐ `spidev` dan `RPi.GPIO` (atau `rpi-lgpio` pada Pi 5) sudah terpasang di Pi.
- ☐ `pio device list` dijalankan di laptop, kedua port Uno dicatat dan diisikan ke `platformio.ini`.
- ☐ SSH ke Raspberry Pi sudah teruji sebelum sesi dimulai — jangan mendiagnosis masalah jaringan di tengah sesi terjadwal.
- ☐ Label fisik ditempel: SLAVE 1, SLAVE 2. Master tidak perlu label — hanya ada satu Raspberry Pi.

## 6 · Percobaan

### EXP-01 — Siklus Pertama Lintas Platform

Unggah kedua slave, jalankan `cek_radio.py` untuk memastikan register chip sesuai, lalu jalankan `master.py` dan amati siklus pertama pada **kedua sisi**: terminal SSH di Raspberry Pi, dan serial kedua Uno di laptop.

**Expected output — master (Raspberry Pi)**

```
=== LoRa MASTER-SLAVE 3 NODE ===
Init LoRa ... OK
Freq: 433 MHz
SF7 | BW: 125 kHz
CRC payload: AKTIF
Peran: MASTER (Raspberry Pi + LoRa GPS HAT)
Slave: Dragino Shield Uno - S1 & S2

========================================
=== CYCLE 1 ===
[TX] POLL:1
[RX] S1:DATA:1 | RSSI: -60 dBm | SNR: 14.2 dB
[TX] POLL:2
[RX] S2:DATA:1 | RSSI: -58 dBm | SNR: 14.2 dB
--- STATISTIK ---
S1: OK=1 | FAIL=0 | Data: 1
S2: OK=1 | FAIL=0 | Data: 1
Durasi siklus: 165 ms
========================================
```

**Expected output — slave (banner Serial Monitor, kedua Uno)**

```
=== LoRa SLAVE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
CRC payload: AKTIF
Menunggu POLL:1 dari Master (Raspberry Pi)...
```

**Data capture**

| Parameter | Hasil |
|---|---|
| Isi `MODEM_CFG_2` menurut `cek_radio.py` (SF, CRC) | |
| Baris `CRC payload: AKTIF` muncul di Serial Monitor kedua slave? | |
| Nomor siklus pertama yang lengkap tanpa `FAIL` | |
| RSSI master ← S1 / S2 (dBm) | |
| Jumlah `[IGNORE]` per siklus di tiap slave | |

**Verifikasi kode** — bandingkan `src/slave/main.cpp` di modul ini dengan `week07_rpi_master_slave/src/slave/main.cpp` (varian tanpa CRC) memakai `diff`. Jawab: baris apa saja yang berbeda, dan mengapa satu baris `LoRa.enableCrc()` sudah cukup untuk mengubah keputusan hardware tentang paket mana yang boleh naik ke `parsePacket()`?

> **CHECKPOINT** — Ketiga node mencetak `OK` dan `CRC payload: AKTIF`, tiap slave menampilkan tepat satu `[RX]` dan dua `[IGNORE]` per siklus (satu untuk `POLL` milik node lain, satu untuk jawaban node lain), dan `diff` menunjukkan hanya satu baris fungsional (`LoRa.enableCrc()` + satu baris cetak) yang berbeda dari varian tanpa CRC. Durasi siklus sedikit lebih panjang daripada baseline CRC-mati di `week07_rpi_master_slave/logserial.md` — itu bukan regresi, melainkan biaya 2 byte checksum tambahan per paket.

### EXP-02 — Statistik dan Lama Siklus Lintas Mesin

Rekam **bersamaan** selama minimal 50 detik: terminal SSH master di Raspberry Pi, dan kedua serial slave di laptop lewat `lora_monitor.py`. Dua rekaman ini berasal dari dua komputer yang **tidak berbagi jam** — korelasikan lewat nomor `Data:`/`RX#`, bukan cap waktu.

**Expected output — master**

```
========================================
=== CYCLE 40 ===
[TX] POLL:1
[RX] S1:DATA:40 | RSSI: -60 dBm | SNR: 14.0 dB
[TX] POLL:2
[RX] S2:DATA:40 | RSSI: -58 dBm | SNR: 14.1 dB
--- STATISTIK ---
S1: OK=40 | FAIL=0 | Data: 40
S2: OK=40 | FAIL=0 | Data: 40
Durasi siklus: 165 ms
========================================
```

**Data capture**

| Parameter | Hasil |
|---|---|
| Jumlah siklus dalam jendela rekaman | |
| Durasi siklus min / maks / rata-rata saat sehat (ms) | |
| Jumlah baris `[WARN] Balasan tidak valid` di seluruh sesi (harus 0 dengan CRC aktif) | |
| `RX#` terakhir slave 1 / slave 2 (dari log lokal) — bandingkan dengan `Data:` terakhir master, harus **sama persis** | |
| SNR arah slave→master vs arah master→slave — apakah simetris? | |

**Buka abstraksinya** — pada varian tanpa CRC (`week07_rpi_master_slave/`), `OK` master kadang lebih kecil daripada `RX#` slave pada nomor yang sama, karena paket berpayload rusak lolos ke aplikasi dan gagal di-parse. Verifikasi pada sesi rekamanmu bahwa hal itu **tidak terjadi lagi** di sini — `Data:` master harus mengikuti `RX#` slave nomor demi nomor tanpa selisih. Jelaskan, memakai isi `MODEM_CFG_2` dari `cek_radio.py`, mengapa kelas kegagalan itu sekarang tidak mungkin muncul.

> **CHECKPOINT** — `Data:` master sama persis dengan `RX#` slave di setiap siklus yang `OK`, dan tidak ada satu pun baris `[WARN]` di seluruh sesi — kontras langsung dengan `week07_rpi_master_slave/logserial.md`, yang mencatat sampai 0,74% paket rusak lolos pada beberapa sesi. Durasi siklus sehat tetap sangat rapat (sebaran sekitar 1 ms pada Raspberry Pi 5), hanya bergeser lebih tinggi ±20 ms dari baseline CRC-mati karena 2 byte checksum tambahan di kedua arah.

### EXP-03 — Satu Node Hilang

Cabut kabel USB Slave 2 **secara fisik** (bukan hanya menutup port serial — Uno bershield LoRa memakai daya dari USB, sehingga mencabutnya mematikan seluruh node termasuk radionya) selama `master.py` berjalan, tunggu setidaknya 20 siklus, lalu pasang kembali.

> Mekanisme timeout/pemulihan di bawah tidak berubah oleh CRC — CRC hanya memfilter payload yang **diterima**, bukan payload yang tidak pernah datang. Expected output dan CHECKPOINT ini diwariskan dari `week07_rpi_master_slave/` (CRC mati); belum diuji ulang secara khusus untuk varian ini pada sesi modifikasi CRC — lihat `logserial.md` untuk status verifikasi terkini.

**Expected output — master, tepat setelah kabel dicabut**

```
=== CYCLE 5 ===
[TX] POLL:1
[RX] S1:DATA:5 | RSSI: -70 dBm | SNR: 12.8 dB
[TX] POLL:2
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
S1: OK=5 | FAIL=0 | Data: 5
S2: OK=0 | FAIL=5 | Data: None
Durasi siklus: 605 ms
```

**Data capture**

| Parameter | Hasil |
|---|---|
| Pesan master saat Slave 2 tidak menjawab | |
| Durasi siklus saat Slave 2 hilang (ms) | |
| Apakah Slave 1 terpengaruh matinya Slave 2? (cek log lokal Slave 1) | |
| Berapa siklus sampai `OK` Slave 2 bertambah lagi setelah kabel dipasang | |
| `dataCounter` Slave 2 setelah dipasang kembali — mulai dari berapa, dan apa artinya | |

> **CHECKPOINT** — Durasi siklus melonjak dari kondisi sehat menjadi mendekati `POLL_TIMEOUT` penuh ditambah overhead, sementara Slave 1 sama sekali tidak terganggu — masih menjawab tiap `POLL:1` seperti biasa. Begitu Slave 2 tersambung kembali, ia memulai `dataCounter` dari 1: bukti bahwa yang terjadi adalah **reboot penuh**, bukan sekadar port serial yang terputus. Pemulihan di sisi master terjadi otomatis pada siklus berikutnya, tanpa intervensi apa pun.

### EXP-04 — Menekan Batas Waktu Sampai Rusak

Ambang kegagalan `POLL_TIMEOUT` naif diperkirakan di atas 70 ms (waktu udara `POLL` + waktu udara jawaban). Percobaan ini menunjukkan dugaan itu keliru. Ubah `POLL_TIMEOUT` di **salinan** `master.py` (jangan ubah `src/master.py` asli), jalankan tiap nilai selama 60 detik, mulai dari 500 ms turun bertahap sampai keberhasilan jatuh ke nol.

> Dengan CRC aktif, waktu udara tiap paket sedikit lebih panjang (2 byte checksum tambahan di kedua arah), sehingga ambang tebing yang sebenarnya kemungkinan bergeser **lebih tinggi** dari titik 40–45 ms yang tercatat di `week07_rpi_master_slave/logserial.md` (CRC mati). Tabel di bawah dan CHECKPOINT-nya diwariskan dari sesi CRC-mati sebagai titik acuan; belum diukur ulang untuk varian ini pada sesi modifikasi CRC — jalankan EXP-04 sendiri di sini untuk mendapati titik tebing yang baru.

**Expected output — pada nilai yang sudah terlalu kecil**

```
=== CYCLE 12 ===
[TX] POLL:1
[FAIL] Slave 1 tidak merespon!
[TX] POLL:2
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
S1: OK=0 | FAIL=12 | Data: None
S2: OK=0 | FAIL=12 | Data: None
```

**Data capture**

| `POLL_TIMEOUT` (ms) | Poll berhasil | Poll gagal | Gagal (%) |
|---|---|---|---|
| 500 (baku) | | | |
| 100 | | | |
| 60 | | | |
| 50 | | | |
| 45 | | | |
| 40 | | | |

> **CHECKPOINT** — Ambangnya adalah **tebing**, bukan lereng: keberhasilan bertahan tinggi sampai satu titik, lalu jatuh mendekati nol dalam rentang sempit beberapa milidetik. Titik itu jauh **lebih rendah** daripada dugaan naif 70-an ms, karena `transmit(pollMsg)` bersifat blocking dan waktu udara `POLL` sudah "dibayar" di dalamnya, sebelum penghitung waktu mulai berjalan — lihat kembali bagian Dasar Teori. Jelaskan letak tebing itu memakai anggaran waktu yang sesungguhnya, bukan anggaran naif.

### Verifikasi radio (dijalankan sebelum EXP-01)

`cek_radio.py` membaca balik register SX1276 di Raspberry Pi setelah `loraBegin()` + konfigurasi:

```
REG_VERSION   : 0x12   (0x12 = SX1276/77/78/79)
FREKUENSI     : 433.000000 MHz   (target 433.000000, selisih +0.0 Hz)
MODEM_CFG_1   : 0x72 -> BW=125 kHz | CR=4/5 | header=explicit
MODEM_CFG_2   : 0x74 -> SF7 | CRC payload=AKTIF
PA_CONFIG     : 0x8f -> PA_BOOST, power=17 dBm
```

**CRC payload aktif di kedua sisi.** `LoRa.enableCrc()` ditambahkan di `setup()` slave, dan `enableCrc()` (fungsi baru di `master.py`, menulis bit yang sama — `REG_MODEM_CONFIG_2` bit 2 — persis seperti yang dilakukan `LoRa.enableCrc()` sandeepmistry) dipanggil sebelum `master.py` mulai polling. Konsekuensinya: SX1276 penerima memverifikasi checksum 2-byte pada tiap paket dan membuang paket yang gagal **sebelum** `parsePacket()`/`IRQ_RX_DONE` sempat menyerahkannya ke aplikasi. Paket berpayload rusak sekarang menghasilkan `[FAIL] tidak merespon` (timeout) alih-alih `[WARN] Balasan tidak valid` — diagnosisnya benar secara radio (paket memang tidak sampai utuh), meski dari sisi statistik `OK`/`FAIL` tetap tidak membedakan "slave diam" dari "jawaban dibuang radio". Terverifikasi lewat pembacaan register langsung di Raspberry Pi (`cek_radio.py`, di atas) dan baris `CRC payload: AKTIF` pada boot banner kedua slave — lihat `logserial.md`.

### Verifikasi hardware (log referensi)

Sesi verifikasi CRC — 21 Agustus 2026, satu Raspberry Pi 5 + LoRa GPS HAT v1.4 (SSH `pi@192.168.1.45`) dan dua Arduino Uno + Dragino Shield v1.2 tertancap USB di laptop pengembang (`/dev/ttyACM0`, `/dev/ttyACM1`), 433 MHz, jarak ±30 cm. Log lengkap ada di `logserial.md`.

| Parameter | Hasil terukur |
|---|---|
| `MODEM_CFG_2` menurut `cek_radio.py` | **0x74** — SF7, CRC payload **AKTIF** (sebelumnya 0x70 pada varian tanpa CRC) |
| Banner `CRC payload: AKTIF` di Serial Monitor | tampil pada kedua slave |
| Siklus dalam sesi ±55 detik | **83**, seluruhnya **OK** — 0 `FAIL`, 0 `[WARN]` |
| S1 / S2: OK / FAIL | 83/83 (100%) / 83/83 (100%) |
| `RX#` slave vs `Data:` master pada siklus terakhir | sama persis di kedua slave — tidak ada payload rusak yang lolos maupun yang gagal parse |
| Durasi siklus sehat min/maks/rata-rata | **165 / 166 / 165,3 ms** |
| Sebaran durasi siklus | **1 ms** (n=83) — serapat sesi CRC-mati (144/145/145,0 ms, `week07_rpi_master_slave/logserial.md`), hanya bergeser **+20 ms** akibat 2 byte checksum tambahan per paket di kedua arah |
| RSSI master ← S1 / S2 | −71,8 dBm (kisaran −83..−68) / −65,0 dBm (kisaran −67..−63) |
| SNR master ← S1 / S2 | 14,64 dB / 14,63 dB |
| Baris `[IGNORE]` tak dikenal (payload rusak) di log lokal kedua slave | **0** dari 160+189 baris — tidak satu pun keluar dari pola `POLL:<n>` / `S<n>:DATA:<n>` |

```
Environment    Status    Flash
slave1         SUCCESS   26.6% (8.574 B)
slave2         SUCCESS   26.6% (8.574 B)
```

Master tidak dikompilasi — Python dijalankan langsung di Raspberry Pi. Kedua slave berukuran identik (8.574 B, naik dari 8.522 B pada varian tanpa CRC — biaya `LoRa.enableCrc()` plus satu baris `Serial.println`), bukti keduanya berasal dari source yang sama dan hanya berbeda `SLAVE_ID`.

**Cakupan pengujian sesi ini.** Yang diverifikasi langsung di perangkat: build, upload, register CRC di Pi (`cek_radio.py`), banner Serial kedua slave, dan satu sesi `master.py` penuh (EXP-01/EXP-02 style) tanpa `[WARN]` maupun `[FAIL]` di luar transien awal. **EXP-03** (cabut kabel fisik) dan **EXP-04** (sapuan `POLL_TIMEOUT`) — yang tabelnya masih ada di bagian Percobaan di atas — **tidak dijalankan ulang** pada sesi modifikasi CRC ini; angka di tabelnya tetap milik sesi CRC-mati sebelumnya dan perlu diukur ulang terpisah sebelum dipakai sebagai klaim untuk varian ini. Tidak satu pun paket rusak tertangkap secara langsung pada sesi 83 siklus ini untuk dibandingkan byte-per-byte dengan temuan `week07_rpi_master_slave/logserial.md` — wajar, karena kejadian itu sendiri sporadis (0,74% pada sebagian sesi CRC-mati, 0,00% pada sesi lain). Bukti bahwa CRC aktif berasal dari pembacaan register langsung dan dari nolnya `[WARN]` di seluruh sesi, bukan dari menangkap satu paket rusak yang difilter.

**CH-2 pada modul dasar sudah diterapkan di sini.** README `week07_rpi_master_slave/` mendaftar `LoRa.enableCrc()` di slave dan bit sepadan di master sebagai tantangan CH-2 yang **sengaja tidak diterapkan**, karena menyentuh firmware slave akan membatalkan klaim "identik dengan M05" pada modul dasar. Direktori ini adalah hasil penerapan CH-2 tersebut sebagai modul tersendiri. Rincian investigasi payload rusak pada varian tanpa CRC (pola byte, pengujian yang menyingkirkan SPI dan FIFO sebagai penyebab) tetap didokumentasikan di `week07_rpi_master_slave/logserial.md`, bagian "Temuan — Payload rusak lolos karena CRC mati", sebagai bahan pembanding.

## 7 · Pengukuran

**A. Keberhasilan terhadap jarak** — kedua slave ditempatkan pada jarak sama dari Raspberry Pi, 30 siklus per baris.

| Jarak | RSSI S1 | RSSI S2 | OK/FAIL S1 | OK/FAIL S2 | Keberhasilan S1 (%) | Keberhasilan S2 (%) |
|---|---|---|---|---|---|---|
| 1 m | | | | | | |
| 25 m | | | | | | |
| 50 m | | | | | | |
| 100 m | | | | | | |

**B. Perbandingan platform master** — bandingkan langsung dengan `week05_lora_master_slave/logserial.md`.

| Ukuran | Master Raspberry Pi 5 (modul ini) | Master Arduino Uno (M05) |
|---|---|---|
| Durasi siklus minimum (ms) | | 147 |
| Durasi siklus maksimum (ms) | | 154 |
| Durasi siklus rata-rata (ms) | | 152 |
| Sebaran (maks − min, ms) | | 7 |

**C. Ambang `POLL_TIMEOUT`** — ulangi EXP-04 tiga kali pada dua titik: nilai terkecil yang masih 100 % andal, dan nilai terbesar yang sudah gagal total.

| Percobaan ke- | Nilai terkecil andal (ms) | Nilai pertama gagal total (ms) |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

**D. Rasio payload rusak yang lolos ke aplikasi** — hitung dari sesi gabungan EXP-02 dan EXP-04 milikmu sendiri, lalu bandingkan dengan tabel D pada `week07_rpi_master_slave/logserial.md` (CRC mati). Dengan CRC aktif, rasio ini seharusnya **0%** — paket rusak dibuang radio sebelum sempat menghasilkan `[WARN]`.

| Sesi | Paket diterima | Paket dengan `[WARN] Balasan tidak valid` | Rasio (%) |
|---|---|---|---|
| Referensi sesi ini (83 siklus, ±55 detik, 21 Agustus 2026) | 166 (83 S1 + 83 S2) | 0 | **0,0** |
| | | | |

## 8 · Analisis

1. Dari tabel B, sebutkan dua kemungkinan penyebab master Raspberry Pi memiliki sebaran durasi siklus lebih rapat daripada master Arduino, dan jelaskan mengapa `POLL_TIMEOUT` yang longgar (500 ms) membuat perbedaan itu tidak pernah terlihat pada durasi siklus akhir.
2. Dari tabel C, hitung anggaran waktu tunggu sesungguhnya (bukan naif) menggunakan waktu udara jawaban dari bagian Dasar Teori M05. Apakah nilai ambang yang kamu temukan cocok dengan hitungan itu? Jelaskan selisihnya bila ada.
3. Pada EXP-03, mengapa siklus pertama setelah master baru dinyalakan bisa mencatat **kedua** slave gagal sekaligus, dan berapa perkiraan durasinya dibandingkan satu slave gagal?
4. Bandingkan tabel D sesi ini (CRC aktif) dengan tabel D pada `week07_rpi_master_slave/logserial.md` (CRC mati, 0,74%/0,00% pada sesi berbeda). Rasio pada varian ini seharusnya turun ke nol — jelaskan mengapa CRC mengubah *kelas* kegagalannya, bukan menghilangkan kerusakan paket itu sendiri (paket yang sama tetap rusak di udara; yang berubah hanya siapa yang membuangnya dan kapan).
5. Dengan CRC aktif, `[WARN] Balasan tidak valid` semestinya tidak pernah muncul lagi — payload rusak sekarang tercatat sebagai `[FAIL]`, sama dengan slave yang benar-benar diam. Usulkan satu cara membedakan "slave diam" dari "jawaban dibuang karena CRC gagal" dari sisi statistik master saja, tanpa mematikan kembali CRC.
6. Bandingkan pekerjaan memindahkan master ke Raspberry Pi (modul ini) dengan pekerjaan memindahkan protokol seluruhnya ke LoRaWAN. Sebutkan satu keuntungan dan satu kerugian pendekatan "gateway custom" dibanding memakai protokol siap pakai.

## 9 · Concept Check

1. Mengapa firmware slave tidak perlu tahu bahwa masternya sekarang Raspberry Pi, bukan Arduino?
2. Sebutkan dua cara mengorelasikan log dari dua mesin yang tidak berbagi jam, selain nomor urut payload.
3. Kenapa `POLL_TIMEOUT` tidak menghitung waktu udara `POLL` itu sendiri? Fungsi mana di `master.py` yang menjadi penyebabnya?
4. Apa yang terjadi pada paket yang payload-nya rusak satu bit ketika CRC payload **aktif**, dan pada tahap mana paket itu dibuang — sebelum atau sesudah `parsePacket()` mengembalikan nilai bukan nol?
5. Satu baris `LoRa.enableCrc()` di slave dan satu pemanggilan `enableCrc()` di master sudah cukup mengubah perilaku ini. Mengapa perbaikan sesederhana itu tetap dianggap "membatalkan klaim identik dengan M05" pada modul dasarnya?
6. Apa perbedaan mendasar antara "slave tidak menjawab" dan "jawaban dibuang karena CRC gagal" dari sudut pandang radio, dan mengapa master saat ini masih tidak membedakan keduanya dalam statistik `OK`/`FAIL` meskipun `[WARN]` sudah tidak pernah muncul lagi?

## 10 · Challenge (tugas modifikasi)

- **CH-1 — Slave ketiga.** Tambahkan Uno ketiga dengan `SLAVE_ID=3`: satu environment PlatformIO baru, dan penyesuaian `SLAVE_COUNT` serta pemanggilan `pollSlave(3, ...)` di `master.py`. Ukur pertambahan lama siklus dan bandingkan dengan hasil CH-1 pada M05.
- ~~**CH-2 — Nyalakan CRC.**~~ **Sudah diterapkan pada direktori ini** — lihat `src/slave/main.cpp` (`LoRa.enableCrc()`) dan `src/master.py`/`cek_radio.py` (`enableCrc()`). Trade-off-nya: klaim "identik dengan M05" tidak lagi berlaku secara harfiah untuk firmware slave (satu baris fungsional berbeda), tetapi diagnosis kegagalan jadi lebih jujur — `[WARN]` tidak pernah muncul lagi. Variasi lanjutan: ukur ulang tabel D dan EXP-04 di sini sendiri (belum diukur ulang pada sesi modifikasi ini, lihat catatan di bagian Verifikasi hardware).
- **CH-3 — Bedakan "diam" dan "dibuang CRC".** Ubah `pollSlave()` di `master.py` agar mencatat statistik terpisah untuk "tidak menjawab sama sekali" versus "menjawab tapi dibuang radio karena CRC gagal" — pada varian ini `IRQ_CRC_ERROR` di `parsePacket()` sudah membedakan keduanya di level register, tinggal dipropagasikan ke statistik. Ukur apakah rasio keduanya berubah seiring durasi sesi.
- **CH-4 — Jadwal adaptif lintas platform.** Port ide CH-4 M05 (lewati slave yang gagal tiga kali berturut-turut, tengok kembali tiap sepuluh siklus) ke `master.py`. Ukur perbaikan durasi siklus saat satu node mati, bandingkan dengan hasil EXP-03.
- **CH-5 — Korelasi RSSI lintas mesin.** Jalankan `lora_monitor.py --out sesi.csv` di laptop bersamaan dengan `master.py` di Raspberry Pi selama sepuluh menit. Gabungkan kedua rekaman berdasarkan nomor urut, lalu buat satu grafik RSSI dari kedua arah (slave→master dan master→slave) terhadap waktu.

## 11 · Laporan

**Deliverable**

1. Misi dan capaian pembelajaran
2. Dasar teori ringkas — mengapa slave tidak perlu tahu platform master, anggaran waktu sesungguhnya `POLL_TIMEOUT`, konsekuensi CRC aktif vs mati
3. Bukti `diff` bahwa firmware slave hanya berbeda satu baris fungsional (`LoRa.enableCrc()`) dari `week07_rpi_master_slave/src/slave/main.cpp`
4. Hasil eksperimen — keluaran terminal EXP-01…04 dari **kedua sisi** (master di Raspberry Pi, slave di laptop) beserta checkpoint, dan hasil `cek_radio.py` (harus menunjukkan `MODEM_CFG_2` bit CRC = AKTIF)
5. Data pengukuran — tabel A, B, C, dan D pada bagian Pengukuran
6. Analisis dan concept check, termasuk hitungan anggaran waktu `POLL_TIMEOUT`
7. Challenge — minimal CH-1 dan CH-3
8. Kesimpulan yang disusun sendiri mengenai apa yang berubah dan apa yang tidak berubah ketika penjadwal jaringan LoRa dipindahkan dari mikrokontroler ke gateway Linux
