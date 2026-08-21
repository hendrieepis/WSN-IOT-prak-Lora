# Log Serial — Modul 07 (Gateway Linux Menjadwalkan Node Arduino)

Hasil aktual dari perangkat. Baud **115200**, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `POLL_TIMEOUT` 500 ms, `CYCLE_INTERVAL` 500 ms. Ketiga node di satu meja, jarak ±30 cm.

Pengujian ini adalah **pengujian perangkat keras pertama** untuk Modul 07. Bagian "Catatan verifikasi" pada README sebelumnya menyatakan konversi ini belum pernah dijalankan di perangkat nyata; sejak dokumen ini ditulis, pernyataan itu tidak berlaku lagi.

## Board & Port

| Peran | Environment / program | Port | Board |
|---|---|---|---|
| Master | `src/master.py` | — (lewat SSH) | Raspberry Pi 5B rev 1.0, BCM2712 + Dragino LoRa GPS HAT v1.4 |
| Slave 1 | `slave1` (`-DSLAVE_ID=1`) | `/dev/ttyACM0` | Uno asli (`2341:0043`) + Dragino Shield v1.2 |
| Slave 2 | `slave2` (`-DSLAVE_ID=2`) | `/dev/ttyACM1` | Uno asli (`2341:0043`) + Dragino Shield v1.2 |

Kedua Uno tertancap di laptop pengembang, sedangkan master dijalankan di Raspberry Pi lewat SSH. Inilah perbedaan praktis pertama dengan M05: **tiga node tidak lagi berada di satu komputer**, sehingga log master dan log slave direkam oleh dua mesin yang berbeda dan harus dicocokkan lewat isinya, bukan lewat cap waktu bersama.

Perangkat lunak Raspberry Pi: Raspberry Pi OS 13 (trixie), Python 3.13.5, `python3-spidev` 3.6, `python3-rpi-lgpio` 0.6. Paket `python3-rpi.gpio` **tidak** terpasang — pada Pi 5, `RPi.GPIO` disediakan oleh `rpi-lgpio`. Rinciannya di README bagian 5.

## Verifikasi radio sebelum percobaan

Nilai di bawah dibaca **balik dari register SX1276** setelah `loraBegin()` + konfigurasi, bukan disalin dari konstanta di source.

```
REG_VERSION   : 0x12   (0x12 = SX1276/77/78/79)
FRF register  : 0x6c 0x40 0x00  -> frf=7094272
FREKUENSI     : 433.000000 MHz   (target 433.000000, selisih +0.0 Hz)
MODEM_CFG_1   : 0x72 -> BW=125 kHz | CR=4/5 | header=explicit
MODEM_CFG_2   : 0x70 -> SF7 | CRC payload=MATI
PA_CONFIG     : 0x8f -> PA_BOOST, power=17 dBm
```

| Parameter | Nilai di chip | Sesuai README? |
|---|---|---|
| Frekuensi | **433,000000 MHz** (selisih 0,0 Hz) | ya |
| Spreading factor | SF7 | ya |
| Bandwidth | 125 kHz | ya |
| Coding rate | 4/5 | ya |
| Daya pancar | 17 dBm, PA_BOOST | ya |
| **CRC payload** | **MATI** | tidak disebut README — lihat bagian Temuan |

Skrip pembacanya ditinggalkan di Raspberry Pi sebagai `cek_radio.py` agar verifikasi ini dapat diulang kapan saja.

## EXP-01 — Siklus Pertama Lintas Platform

**Master (Raspberry Pi), siklus pertama**

```
=== LoRa MASTER-SLAVE 3 NODE ===
Init LoRa ... OK
Freq: 433 MHz
SF7 | BW: 125 kHz
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
Durasi siklus: 145 ms
========================================
```

**Slave 1 dan Slave 2 (cap waktu = detik sejak perekaman serial dimulai)**

```
   1.612  === LoRa SLAVE 1 ===          |     1.617  === LoRa SLAVE 2 ===
   1.634  Init LoRa ... OK              |     1.638  Init LoRa ... OK
   1.634  Freq: 433.00 MHz              |     1.638  Freq: 433.00 MHz
   1.637  Menunggu POLL:1 dari Master   |     1.642  Menunggu POLL:2 dari Master
                                        |
   4.320  [RX] POLL:1 | RSSI: -62 dBm | SNR: 8.00 dB | RX#: 1
   4.320  [TX] S1:DATA:1                |     4.316  [IGNORE] POLL:1
   4.389  [IGNORE] POLL:2               |     4.357  [IGNORE] S1:DATA:1
   4.426  [IGNORE] S2:DATA:1            |     4.391  [RX] POLL:2 | RSSI: -64 dBm | SNR: 9.00 dB | RX#: 1
                                        |     4.395  [TX] S2:DATA:1
```

| Parameter | Hasil |
|---|---|
| Pesan init master | `Init LoRa ... OK`, 433 MHz, SF7/BW 125 kHz |
| Pesan init slave 1 / slave 2 | keduanya `Init LoRa ... OK`, `Freq: 433.00 MHz` |
| Nomor siklus pertama yang lengkap | **1** — tidak ada `FAIL` sama sekali di siklus pembuka |
| RSSI master ← S1 | **−60 dBm** (SNR 14,2 dB) |
| RSSI master ← S2 | **−58 dBm** (SNR 14,2 dB) |
| Baris `[IGNORE]` | S1 mengabaikan `POLL:2`, S2 mengabaikan `POLL:1` — masing-masing 1 per siklus |
| Baris `[IGNORE]` tambahan | tiap slave juga mengabaikan **jawaban** slave lain (`S2:DATA:1` / `S1:DATA:1`) |

> **CHECKPOINT terpenuhi.** Ketiga node mencetak `OK`, dan tiap slave menampilkan tepat **satu** `[RX]` beserta **dua** `[IGNORE]` per siklus — satu untuk POLL milik node lain, satu untuk jawaban node lain. Urutan waktu di kedua slave saling mengunci: S2 mencatat `[IGNORE] POLL:1` pada 4.316 s, S1 mencatat `[RX] POLL:1` pada 4.320 s. Keduanya mendengar paket yang sama; hanya pemiliknya yang menjawab.

Perhatikan bahwa **master berganti platform tanpa slave mengetahuinya**. Firmware slave yang dipakai identik dengan M05:

```
$ diff week05_lora_master_slave/src/slave/main.cpp week07_rpi_master_slave/src/slave/main.cpp
2c2   <  LoRa Master-Slave 3 Node - ...     >  LoRa Master-Slave hybrid - ...
6,7c6,12   (blok komentar penjelas M07)
74c79,81   Serial.println("Menunggu POLL:1 dari Master...")
        ->  Serial.print("Menunggu POLL:"); Serial.print(SLAVE_ID);
            Serial.println(" dari Master (Raspberry Pi)...")
```

Tiga hunk, seluruhnya komentar dan satu pesan pembuka di `Serial`. Tidak satu byte pun dari yang mengudara berubah.

## EXP-02 — Statistik dan Lama Siklus

Rekaman 50 detik dengan `src/master.py` apa adanya, sambil kedua port serial slave direkam bersamaan.

| Parameter | Hasil |
|---|---|
| Jumlah siklus dalam 50 detik | **76** (≈1,52 siklus/detik) |
| S1: OK / FAIL | 74 / **2** |
| S2: OK / FAIL | 75 / **1** |
| `Data:` terakhir S1 / S2 | 76 / 76 |
| `RX#` terakhir di slave 1 / slave 2 | **76 / 76** |
| Durasi siklus minimum | **144 ms** |
| Durasi siklus maksimum (siklus sehat) | **145 ms** |
| Durasi siklus rata-rata (siklus sehat) | **145,0 ms** |
| Durasi siklus saat satu poll gagal | **605 ms** |
| RSSI di master (dari S1 / S2) | −59,6 / −57,8 dBm |
| SNR di master (dari S1 / S2) | 14,09 / 14,19 dB |
| RSSI di S1 / S2 (dari master) | −64,8 / −64,0 dBm |
| SNR di S1 / S2 (dari master) | 8,63 / 8,88 dB |

**Buka abstraksinya.** Ketiga bilangan yang diminta README dapat dibandingkan langsung: pada siklus ke-76, master mencatat `S1: OK=74 | FAIL=2 | Data: 76`, sedangkan slave 1 mencatat `RX#: 76`. Artinya slave menerima **seluruh** 76 panggilan dan mengirim **seluruh** 76 jawaban, tetapi hanya 74 yang sampai utuh ke master. `Data:` melompat dari 74 ke 76 tanpa master pernah menerima nomor 75 — persis keadaan yang diramalkan CHECKPOINT EXP-02, dan didapat tanpa perlu menjauhkan slave. Penyebab dua jawaban yang hilang itu dibahas di bagian Temuan.

**Asimetri arah yang tidak terduga.** SNR arah slave → master adalah 14,1 dB, sedangkan arah master → slave hanya 8,6–8,9 dB — selisih tetap sekitar **5,3 dB** yang bertahan di seluruh rekaman. Kedua arah memakai daya pancar 17 dBm yang sama. Yang berbeda hanyalah papan pembawanya: LoRa GPS HAT di sisi Pi, Shield v1.2 di sisi Uno. Angka ini tidak terlihat dari terminal master saja, karena master hanya melaporkan arah yang diterimanya; ia baru muncul setelah kedua sisi direkam bersamaan.

### Lama siklus jauh lebih rapat daripada dugaan README

README memperkirakan master Linux akan memperlihatkan **jitter penjadwalan** yang tidak ada padanannya di Arduino. Pada Raspberry Pi 5 dugaan itu **tidak terkonfirmasi**:

| Ukuran | Master Raspberry Pi 5 (modul ini) | Master Arduino Uno (M05, `logserial.md`) |
|---|---|---|
| Durasi siklus minimum | **144 ms** | 147 ms |
| Durasi siklus maksimum | **145 ms** | 154 ms |
| Durasi siklus rata-rata | **145,0 ms** | 152 ms |
| Sebaran (maks − min) | **1 ms** | 7 ms |

Master Linux justru **lebih rapat** sebarannya daripada master Arduino, dan sedikit lebih cepat. Pengukuran kedua, diambil dari sisi node memakai `lora_monitor.py` (jarak antar `POLL` yang diterima slave, jadi sudah termasuk `CYCLE_INTERVAL` 500 ms):

| Ukuran | Nilai |
|---|---|
| Periode siklus minimum | 642 ms |
| Periode siklus rata-rata | 645,2 ms |
| Periode siklus maksimum | 648 ms |
| Sebaran | **6 ms** (n = 112) |

Kedua pengukuran sepakat. Penjelasan yang masuk akal: Pi 5 berinti empat pada beban hampir nol, sehingga proses Python praktis tidak pernah benar-benar berebut CPU; dan `POLL_TIMEOUT` 500 ms sedemikian longgar dibanding waktu tanggap sebenarnya (±45 ms, lihat EXP-04) sehingga penundaan beberapa milidetik tidak pernah mengubah hasil. Sebaran ini bukan bantahan terhadap teori di README — jitter tetap ada secara prinsip — melainkan bukti bahwa pada beban serendah ini besarnya tidak terukur oleh alat yang dipakai modul ini.

## EXP-04 — Menekan Batas Waktu Sampai Rusak

`POLL_TIMEOUT` diturunkan bertahap, tiap nilai dijalankan **60 detik**. Nilai diberikan lewat environment ke salinan `master.py`, sehingga `src/master.py` tidak pernah diubah.

| `POLL_TIMEOUT` (ms) | Siklus | Poll berhasil | Poll gagal | Gagal (%) | Durasi siklus rata-rata (ms) |
|---|---|---|---|---|---|
| 500 (baku) | 92 | 184 | 0 | **0,0 %** | 156 |
| 250 | 92 | 184 | 0 | **0,0 %** | 156 |
| 150 | 92 | 184 | 0 | **0,0 %** | 156 |
| 100 | 92 | 184 | 0 | **0,0 %** | 156 |
| 60 | 92 | 184 | 0 | **0,0 %** | 156 |
| 55 | 92 | 183 | 1 | 0,5 % | 156 |
| 50 | 92 | 184 | 0 | **0,0 %** | 156 |
| 45 | 92 | 181 | 3 | 1,6 % | 156 |
| **40** | 93 | **0** | **186** | **100 %** | 146 |

**Ambangnya adalah tebing, bukan lereng** — persis seperti diramalkan CHECKPOINT EXP-04. Di 45 ms sistem masih berhasil 98,4 %; di 40 ms keberhasilan jatuh ke **nol mutlak**, bukan memburuk perlahan. Zona 45–55 ms adalah pinggiran tebing: sebagian jawaban mulai tersenggol batas waktu, tetapi mayoritas masih lolos.

Pengulangan tiga kali pada dua nilai penentu (Pengukuran C):

| Percobaan ke- | Nilai terkecil yang masih andal (ms) | Nilai pertama yang sudah gagal (ms) |
|---|---|---|
| 1 | 60 (0 gagal dari 184) | 40 (186 gagal dari 186) |
| 2 | 60 (0 gagal dari 184) | 40 (186 gagal dari 186) |
| 3 | 60 (0 gagal dari 184) | 40 (186 gagal dari 186) |

Reproduksinya sempurna — tidak ada satu pun kejadian menyimpang di enam sesi.

### Mengapa 40 ms, bukan 77 ms

README memperkirakan ambangnya "hampir pasti jauh di atas" 77 ms, dengan alasan waktu udara `POLL:1` (±36 ms) ditambah waktu udara `S1:DATA:12` (±41 ms). Hasil pengukuran menunjukkan ambangnya justru **di bawah** angka itu, dan penyebabnya adalah kekeliruan dalam menyusun anggaran waktunya:

`POLL_TIMEOUT` **tidak pernah mencakup waktu udara POLL**. Di `pollSlave()`, `transmit(pollMsg)` bersifat blocking — ia baru kembali setelah `IRQ_TX_DONE` menyala, artinya paket POLL sudah selesai mengudara. Baru sesudah itu `waitStart = time.monotonic()` dijalankan. Jadi jendela batas waktu hanya menampung:

```
pemrosesan di slave  +  waktu udara jawaban (±41 ms)  +  deteksi RX_DONE di master
```

Yang tersisa memang ±41–45 ms, dan itulah sebabnya 45 ms berada di pinggiran sementara 40 ms memotong setiap jawaban tepat sebelum tiba. Angka 36 ms untuk POLL sudah "dibayar" di dalam `transmit()`, di luar penghitung waktu.

Konsekuensi praktisnya: `POLL_TIMEOUT` 500 ms adalah **11× lebih longgar** daripada yang dibutuhkan. Kelonggaran itulah yang membuat durasi siklus tidak pernah goyah — dan sekaligus yang membuat satu node mati menjadi sangat mahal, karena setiap node mati menagih 500 ms penuh setiap siklus.

## Temuan — Payload rusak lolos karena CRC mati

Selama pengujian, master beberapa kali mencetak `[WARN] Balasan tidak valid` lalu menghitungnya sebagai `[FAIL]`, padahal log serial slave membuktikan slave menerima POLL dan mengirim jawaban yang benar. Contoh byte mentahnya:

```
[WARN] Balasan tidak valid: S?:DATA:705 | ps=11 | raw=53 a1 3a 44 41 54 41 3a 37 30 35
                                                       ^^ seharusnya 0x31 ('1')
[WARN] Balasan tidak valid: S1:DATA?85  | ps=10 | raw=53 31 3a 44 41 54 41 9a 38 35
                                                                         ^^ seharusnya 0x3a (':')
```

**Frekuensi kejadian**

| Kelompok run | Paket diterima | Paket rusak | Rasio |
|---|---|---|---|
| 8 sesi pertama | 2288 | 17 | **0,74 %** |
| 4 sesi berikutnya | 1462 | 0 | **0,00 %** |

**Pola byte** — dari 13 paket rusak yang byte mentahnya sempat terekam:

| Sifat | Pengamatan |
|---|---|
| Byte rusak per paket | 1 byte (10 paket), 2 byte (3 paket) |
| Indeks byte yang rusak | indeks 1 (10×), indeks 7 (4×), indeks 8 (2×) |
| Indeks yang **tidak pernah** rusak | 0, 2, 3, 4, 5, 6 — yaitu `S`, `:`, dan `DATA` |
| Jumlah bit berbeda, pada byte yang nilai benarnya pasti | selalu **2 bit** (4 dari 4 kasus) |

**Yang sudah disingkirkan sebagai penyebab**

| Dugaan | Uji | Hasil |
|---|---|---|
| Jalur SPI tidak andal | `REG_VERSION` dibaca 40.000× pada 5 MHz dan 1 MHz | **0 error** di kedua kecepatan — SPI bersih saat idle |
| Modem menimpa FIFO saat dibaca | `MODE_STDBY` disisipkan sebelum baca FIFO, seperti `LoRa.parsePacket()` di Arduino | rasio **tidak berubah** (6 dari 354) |
| Byte rusak saat dibaca dari FIFO | isi FIFO dibaca **3× berturut-turut** lalu dibandingkan | **selalu identik**, termasuk pada paket rusak |
| Master membanjiri SPI saat demodulasi | `time.sleep(0.002)` disisipkan di loop tunggu | 0 dari 730 — **tetapi kontrol tanpa jeda juga 0 dari 732**, jadi tidak membuktikan apa pun |

Pembacaan FIFO tiga kali yang selalu identik adalah uji penentunya: **byte rusak itu sudah berada di FIFO sebelum dibaca**. Jalur SPI tidak bersalah; kerusakan terjadi di udara atau di dalam demodulator.

**Mengapa kerusakan itu lolos sampai ke aplikasi.** `MODEM_CFG_2` menunjukkan CRC payload **mati**, di kedua sisi. `LoRa.begin()` milik sandeepmistry tidak mengaktifkan CRC kecuali diminta lewat `LoRa.enableCrc()`, dan `master.py` juga tidak menyalakannya. Akibatnya pemeriksaan `IRQ_CRC_ERROR` di `parsePacket()` **tidak akan pernah menyala** — bukan karena tidak ada paket cacat, melainkan karena radio tidak pernah diminta memeriksanya. Paket cacat naik utuh ke lapisan aplikasi, gagal di `reply.startswith("S1:DATA:")`, dan tercatat sebagai "slave tidak merespon" — diagnosis yang menunjuk ke arah yang salah sama sekali.

**Status.** Mekanisme yang membangkitkan kerusakan **belum diketahui**. Pola indeksnya (hanya 1, 7, 8) terlalu terpusat untuk galat bit acak, tetapi belum ada uji yang menjelaskannya. Fenomenanya juga tidak muncul terus-menerus: 17 kejadian di delapan sesi pertama, nol di empat sesi berikutnya dan di seluruh EXP-04 kecuali satu, tanpa perubahan perangkat keras apa pun di antaranya.

Perbaikan yang jelas — `LoRa.enableCrc()` di slave dan menyalakan bit 2 `REG_MODEM_CONFIG_2` di master — **tidak diterapkan**, karena menyentuh firmware slave dan dengan demikian membatalkan klaim utama modul ini bahwa slave identik dengan M05. Itu keputusan perancang modul, bukan keputusan penguji. Sebagai bahan praktikum, keadaan ini justru lebih berharga dibiarkan: ia memperlihatkan satu lapisan pelindung yang tidak dipasang, dan akibatnya terhadap diagnosis di lapisan atas.

## Verifikasi ulang — 21 Agustus 2026

Sesi verifikasi baru: kedua slave dibangun ulang dari `src/` saat ini dan diunggah ulang (`pio run -e slave1|slave2 -t upload`, keduanya SUCCESS, flash 8.522 B terverifikasi avrdude), master dijalankan langsung dari sumbernya di Raspberry Pi lewat SSH (`python3 -u src/master.py`, tanpa perubahan). Tujuannya memastikan konversi PlatformIO M07 masih berjalan seperti didokumentasikan di atas, bukan mengulang investigasi CRC.

**Board & Port sesi ini** — berbeda dari tabel "Board & Port" di atas karena hanya dua Uno yang tersambung ke laptop pengembang saat ini: Slave 1 di `/dev/ttyACM1`, Slave 2 di `/dev/ttyACM2` (bukan `ACM0`/`ACM1`). Ini contoh nyata alasan README menyuruh menjalankan `tools/deteksi_port.py` dan memakai `--upload-port` eksplisit alih-alih mengandalkan nilai contoh di `platformio.ini`.

```
=== CYCLE 3 ===
[TX] POLL:1
[RX] S1:DATA:47 | RSSI: -76 dBm | SNR: 13.0 dB
[TX] POLL:2
[WARN] Balasan tidak valid: S?:DATA:27
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
S1: OK=3 | FAIL=0 | Data: 47
S2: OK=2 | FAIL=1 | Data: None
Durasi siklus: 605 ms
```

| Parameter | Hasil |
|---|---|
| Siklus dalam ±35 detik | **46** |
| Durasi siklus steady-state min/maks/rata-rata | 145 / 145 / **145,0 ms** (n=45, mengecualikan 1 timeout) |
| Slave 1: OK / FAIL | 46 / 0 → **100 %** |
| Slave 2: OK / FAIL | 45 / 1 → **97,8 %** |
| Penyebab satu-satunya FAIL | 1 byte payload rusak (`S1:DATA:27` → `S :DATA:27`), pola sama dengan temuan "Payload rusak lolos karena CRC mati" di atas |
| SNR balasan Slave 1 di master | rata-rata **13,2 dB** (n=46) |
| SNR balasan Slave 2 di master | rata-rata **13,3 dB** (n=45) |
| RSSI balasan Slave 1 / Slave 2 di master | −69,4 dBm / −65,8 dBm (sepadan, tidak ada node yang janggal) |

**Tidak ada anomali seperti pada M05.** Modul 05 sempat mencatat SNR Slave 2 anjlok ke ~1,2 dB akibat Slave 2 duduk terlalu dekat dengan master (near-field). Pada sesi M07 ini, SNR kedua slave hampir identik (13,2 vs 13,3 dB) dan RSSI keduanya wajar — tidak ada indikasi kejenuhan penerima di sisi mana pun.

**Tampilan Uno vs tampilan Raspberry Pi cocok satu sama lain.** Log slave lokal (dibaca langsung dari `/dev/ttyACM1` dan `/dev/ttyACM2`) menunjukkan `[TX] S1:DATA:n` dan `[TX] S2:DATA:n` yang nomornya berurutan dengan `[RX] S1:DATA:n`/`S2:DATA:n` pada log master di Raspberry Pi — mengonfirmasi kedua sisi memang saling bicara lewat radio, bukan kebetulan dua proses berjalan sendiri-sendiri.

**Catatan pelaksanaan.** Saat keluarannya dipipa lewat SSH (bukan TTY interaktif), Python membuffer stdout — memakai `timeout` untuk membatasi durasi lalu memutus prosesnya membuang isi buffer yang belum sempat di-flush. Jalankan dengan `python3 -u` saat keluarannya perlu direkam lewat pipa/redirect.

`master.py` sebelumnya tidak punya opsi `--help` — argumen apa pun diabaikan begitu saja dan sesi langsung berjalan, seperti yang terjadi saat pertama kali dicoba pada sesi ini. Sudah ditambahkan `argparse` dengan `-h`/`--help` yang mencetak parameter radio (frekuensi, SF, BW, `POLL_TIMEOUT`, `CYCLE_INTERVAL`) tanpa menyentuh SPI/GPIO, dan argumen tak dikenal sekarang ditolak dengan pesan `usage` alih-alih diam-diam diabaikan. Tidak ada opsi baru selain `-h`; perilaku tanpa argumen tidak berubah (diverifikasi ulang: 10 siklus bersih, 100 % OK).

## Catatan pengambilan log

- **EXP-03 belum dijalankan.** Percobaan itu menuntut kabel USB slave 2 dicabut secara fisik saat sistem berjalan, dan pengujian ini dikerjakan dari jarak jauh. Bagian dari perilakunya tetap teramati: setiap poll yang gagal menaikkan durasi siklus dari 145 ms menjadi **605 ms**, bertambah **+460 ms** — sesuai ramalan CHECKPOINT EXP-03 bahwa pertambahannya mendekati satu `POLL_TIMEOUT` dikurangi waktu jawaban sehat. Pada satu siklus yang **kedua** slave-nya gagal, durasinya 1065 ms, konsisten dengan dua batas waktu penuh.
- **Tabel jarak (Pengukuran B) belum terisi.** Seluruh percobaan dijalankan di satu meja pada jarak tetap ±30 cm.
- Kolom M05 pada tabel perbandingan lama siklus diisi dari `week05_lora_master_slave/logserial.md`, bukan dari pengukuran ulang pada sesi ini.
- Membuka port serial me-**reset** Arduino lewat DTR, sehingga `RX#` dan `dataCounter` slave kembali ke 1 sementara penghitung master terus berjalan. Bila kedua angka perlu sebanding, jalankan perekam serial lebih dahulu, baru master.
- Seluruh berkas diagnostik (`master_diagA/B/C/D.py`, `master_exp04.py`, `spi_stress.py`) sudah dihapus dari Raspberry Pi. Yang tersisa di sana hanya `src/master.py`, `requirements.txt`, dan `cek_radio.py`.
- `src/master.py`, `src/slave/main.cpp`, dan `platformio.ini` **tidak diubah sama sekali** selama pengujian ini.
