// ============================================================================
// Modul 07B — Gateway Linux Menjadwalkan Node Arduino (varian CRC aktif)
// Sumber: Modul07b_rpi_master_slave_crc/README.md; listing kode dibaca langsung
//         dari salinan berkas sumber di
//         assets/code/Modul07b_rpi_master_slave_crc/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist
#import "../config.typ": edisi_buku

#chapter("Modul 07B — Varian CRC Payload Aktif", l: "bab:modul-07b")

#identitas-modul(
  "Modul 07B",
  [Move the Scheduler to Linux --- Varian `-withCRC`, CRC Payload Aktif],
  [Raspberry Pi + LoRa GPS HAT v1.4 dan 2 × Arduino Uno + LoRa Shield v1.2 ·
   topologi bintang, 3 node · polling terjadwal + CRC payload ·
   level Advanced · 3 × 50 menit ·
   folder kode `Modul07b_rpi_master_slave_crc`],
)

#pengantar([Gambaran Umum])[
Modul 07B adalah *varian `-withCRC` dari Modul 07*. Modul 07 aslinya sengaja
mematikan CRC payload di kedua sisi sebagai bahan ajar --- paket yang rusak di
udara lolos ke lapisan aplikasi dan salah didiagnosis sebagai "slave tidak
merespon". Modul ini menerapkan perbaikannya, yang pada Modul 07 tercatat
sebagai tantangan CH-2.
]

== Pendahuluan

Seluruh misi, topologi, dan kontrak data modul ini sama persis dengan
@bab:modul-07: `master.py` di Raspberry Pi menjadwalkan dua Arduino Uno lewat
`POLL:<id>` dan `S<id>:DATA:<n>`. Yang berbeda hanya satu keputusan:
`LoRa.enableCrc()` ditambahkan di `src/slave/main.cpp`, dan bit yang sepadan
(`REG_MODEM_CONFIG_2` bit 2) dinyalakan lewat fungsi `enableCrc()` baru di
`src/master.py` serta `cek_radio.py`.

Konsekuensinya, klaim "identik dengan slave M05" *tidak lagi berlaku secara
harfiah* untuk firmware di modul ini --- satu baris fungsional berbeda, di luar
komentar dan pesan pembuka. Bagian Percobaan dan `logserial.md` membandingkan
perilaku sebelum dan sesudah CRC dinyalakan.

Prasyaratnya adalah @bab:modul-07 seluruhnya. Pembaca yang belum mengerjakan
modul tersebut sebaiknya menyelesaikannya lebih dahulu, sebab modul ini hanya
bermakna sebagai pembanding: nilainya terletak pada selisih terhadap baseline
CRC-mati, bukan pada angkanya sendiri.

*Peta modul LoRa*

#tbl(
  table(
    columns: (auto, 1fr),
    align: (center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Fokus (yang ditumpuk di atas modul sebelumnya)]),
    [05], [Banyak node --- hak bicara dijadwalkan agar tidak bertabrakan],
    [06], [Isi `LoRa.begin()` tidak pernah terlihat --- register dipegang langsung],
    [07], [Penjadwal pindah ke gateway Linux; sisi node tidak berubah sama sekali],
    [*07B (ini)*], [*CRC payload dinyalakan --- paket rusak dibuang radio, bukan salah didiagnosis aplikasi*],
  ),
  [Kedudukan Modul 07B terhadap modul sebelumnya],
  "tbl:m07b-peta",
)

*Kontrak data lab ini.* Tidak berubah dari Modul 07: `POLL:<id>` dan
`S<id>:DATA:<n>`. Yang bertambah di udara hanyalah 2 byte checksum per paket,
yang ditambahkan dan diperiksa oleh SX1276 sendiri, bukan oleh aplikasi.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Menyalakan CRC payload dan mengukur akibatnya])[
  + Membuktikan dengan `diff` seberapa kecil perubahan yang diperlukan pada
    firmware slave untuk menyalakan CRC payload, dan menjelaskan mengapa
    perubahan itu tetap membatalkan klaim "identik dengan M05".
  + Menerapkan ulang logika penjadwalan round-robin Modul 05 di atas driver
    SX1276 telanjang Modul 06, memakai `spidev` dan `RPi.GPIO` atau
    `rpi-lgpio`.
  + Mengkorelasikan log dari dua mesin yang tidak berbagi jam --- satu direkam
    lewat SSH di Raspberry Pi, satu lewat USB lokal --- berdasarkan isi pesan,
    bukan cap waktu.
  + Menjelaskan mengapa menyalakan CRC payload di kedua sisi mengubah kelas
    kegagalan "payload rusak lolos ke aplikasi" menjadi "paket dibuang oleh
    radio sebelum sempat diproses", dan mengukur biayanya lewat waktu-di-udara.
  + Menelusuri anggaran waktu sesungguhnya di balik `POLL_TIMEOUT` --- bagian
    siklus mana yang benar-benar dihitungnya --- lalu memakainya untuk
    menjelaskan mengapa menyalakan CRC menggeser durasi siklus, bukan ambang
    kegagalannya.
]

*Kriteria keberhasilan*

#checklist((
  [`master.py` berhasil memanggil kedua slave Uno bergiliran, dengan CRC
   payload *AKTIF* di kedua sisi --- dibuktikan lewat `cek_radio.py`
   (`MODEM_CFG_2` bit 2 = 1) dan pesan `CRC payload: AKTIF` pada Serial Monitor
   slave.],
  [`cek_radio.py` membaca balik register SX1276 di Raspberry Pi dan hasilnya
   dibandingkan dengan konfigurasi yang dimaksud, termasuk bit CRC.],
  [Satu sesi log master (Raspberry Pi) dan log slave (laptop) dikorelasikan
   lewat isi pesan, bukan lewat waktu perekaman, dan menunjukkan nol baris
   `[WARN] Balasan tidak valid`.],
  [Durasi siklus dengan CRC aktif diukur dan dibandingkan terhadap baseline
   `Modul07_rpi_master_slave/logserial.md` (CRC mati) untuk mengukur biaya
   waktu-di-udara dari 2 byte CRC tambahan.],
))

== Dasar Teori (Secukupnya)

Seluruh istilah Modul 07 (@tbl:m07-istilah) tetap berlaku. Satu di antaranya
berubah isinya.

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja pada varian ini]),
    [CRC payload], [Pemeriksaan keutuhan data oleh radio sendiri: 2 byte checksum ditambahkan ke tiap paket, diverifikasi otomatis oleh SX1276 penerima. *AKTIF* di kedua sisi pada varian ini (`LoRa.enableCrc()` di slave, `enableCrc()` di `master.py`) --- bandingkan dengan Modul 07 (CRC mati) untuk melihat konsekuensinya.],
  ),
  [Istilah yang berubah pada Modul 07B],
  "tbl:m07b-istilah",
)

*Mengapa anggaran `POLL_TIMEOUT` lebih sempit dari dugaan.* Penjelasannya sama
dengan Modul 07: `transmit(pollMsg)` bersifat blocking, sehingga waktu udara
`POLL` sudah terbayar sebelum penghitung waktu mulai berjalan. Satu tambahan
berlaku di sini: angka waktu udara pada Modul 07 berasal dari sesi CRC *mati*;
menyalakan CRC menambah 2 byte checksum ke setiap paket sehingga sedikit
memperpanjang waktu udara kedua arah --- pengukuran aktual pada varian ini ada
di `logserial.md`.

== Topologi

Identik dengan Modul 07, termasuk pemetaan pin HAT (@tbl:m07-pin) dan peran
tiap node (@tbl:m07-topologi).

#diagram(```
                    RASPBERRY PI (di ruang server)
                 +-----------------------------+
                 |  Raspberry Pi 5 + LoRa GPS  |
                 |  HAT  --  src/master.py     |
                 |  CRC payload AKTIF          |
                 +--------------+--------------+
                 POLL:1         |         POLL:2
              /------------------+------------------\
             v                                       v
    +------------------+                    +------------------+
    | Arduino Uno      |                    | Arduino Uno      |
    | + LoRa Shield    |                    | + LoRa Shield    |
    |     SLAVE 1      |                    |     SLAVE 2      |
    | LoRa.enableCrc() |                    | LoRa.enableCrc() |
    | "S1:DATA:n"      |                    | "S2:DATA:n"      |
    +------------------+                    +------------------+
       env: slave1                             env: slave2
       (+1 baris fungsional dibanding M05/M07)
```.text)

== Alat yang Digunakan

Sama persis dengan Modul 07 (@tbl:m07-alat): satu Raspberry Pi 5 dengan Dragino
LoRa GPS HAT v1.4, dua Arduino Uno dengan Dragino LoRa Shield v1.2, tiga antena
SMA, dan akses SSH ke Raspberry Pi.

*Struktur proyek*

#diagram(```
Modul07b_rpi_master_slave_crc/
├── platformio.ini          ← hanya 2 environment: slave1, slave2
├── requirements.txt        ← spidev + RPi.GPIO (atau rpi-lgpio untuk Pi 5)
├── logserial.md            ← log referensi sesi verifikasi CRC
├── lora_monitor.py         ← dasbor 2 slave lokal + rekaman CSV (butuh `rich`)
├── cek_radio.py            ← baca balik register SX1276, termasuk bit CRC
├── upload_auto.py          ← deteksi port otomatis saat unggah slave
└── src/
    ├── master.py           ← penjadwal round-robin + enableCrc()
    └── slave/main.cpp      ← satu source untuk kedua slave, +LoRa.enableCrc()
```.text)

== Kode Program

#sumber-kode("Modul07b_rpi_master_slave_crc",
  ("platformio.ini", "requirements.txt", "src/master.py",
   "src/slave/main.cpp", "cek_radio.py", "lora_monitor.py", "upload_auto.py"))

#kode-berkas("Modul07b_rpi_master_slave_crc/platformio.ini",
  [`platformio.ini` Modul 07B --- environment `slave1` dan `slave2`],
  "lst:m07b-ini",
  pecah: true,
)

#kode-berkas("Modul07b_rpi_master_slave_crc/requirements.txt",
  [`requirements.txt` Modul 07B --- paket Python sisi Raspberry Pi],
  "lst:m07b-req",
  bahasa: "text",
  pecah: true,
)

#kode-berkas("Modul07b_rpi_master_slave_crc/src/master.py",
  [`src/master.py` --- penjadwal round-robin dengan `enableCrc()`],
  "lst:m07b-master",
  pecah: true,
)

#kode-berkas("Modul07b_rpi_master_slave_crc/src/slave/main.cpp",
  [`src/slave/main.cpp` --- firmware slave dengan `LoRa.enableCrc()`],
  "lst:m07b-slave",
  pecah: true,
)

#kode-berkas("Modul07b_rpi_master_slave_crc/cek_radio.py",
  [`cek_radio.py` --- baca balik register SX1276 termasuk bit CRC],
  "lst:m07b-cek",
  pecah: true,
)

#kode-berkas("Modul07b_rpi_master_slave_crc/lora_monitor.py",
  [`lora_monitor.py` --- dasbor dua slave lokal dengan perekaman CSV],
  "lst:m07b-monitor",
  pecah: true,
)

#kode-berkas("Modul07b_rpi_master_slave_crc/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah slave],
  "lst:m07b-upload",
  pecah: true,
)

== Build, Flash, dan Menjalankan

#keluaran("pio run -d Modul07b_rpi_master_slave_crc -e slave1 -t upload
pio run -d Modul07b_rpi_master_slave_crc -e slave2 -t upload")

*Menyiapkan Raspberry Pi*

#keluaran("ssh pi@<alamat-ip-pi>
sudo raspi-config                                    # Interface Options > SPI > Yes, lalu reboot
ls /dev/spi*                                         # harus muncul spidev0.0

pip3 install -r Modul07b_rpi_master_slave_crc/requirements.txt")

*Menjalankan master* --- kedua slave lebih dahulu, baru master.

#keluaran("ssh pi@<alamat-ip-pi>
cd ~/Documents/WSN-IOT-prak-Lora/Modul07b_rpi_master_slave_crc/src
python3 -u master.py            # -u penting bila keluarannya dipipa/direkam")

*Memantau kedua slave dari laptop*

#keluaran("pip install pyserial rich
python3 lora_monitor.py --s1 /dev/ttyACM0 --s2 /dev/ttyACM1
python3 lora_monitor.py --s1 /dev/ttyACM0 --s2 /dev/ttyACM1 --out sesi1.csv")

*Memverifikasi radio sebelum percobaan*

#keluaran("ssh pi@<alamat-ip-pi>
cd ~/Documents/WSN-IOT-prak-Lora/Modul07b_rpi_master_slave_crc
python3 cek_radio.py")

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada HAT dan kedua shield.],
  [SPI aktif di Raspberry Pi --- `ls /dev/spi*` menampilkan `spidev0.0`.],
  [`spidev` dan `RPi.GPIO` (atau `rpi-lgpio` pada Pi 5) sudah terpasang di Pi.],
  [`cek_radio.py` dijalankan lebih dahulu dan menunjukkan
   `MODEM_CFG_2 : 0x74`.],
  [Baseline Modul 07 (CRC mati) sudah dikerjakan dan angkanya tersedia untuk
   pembanding.],
  [Label fisik ditempel: SLAVE 1, SLAVE 2.],
))

== Percobaan

=== EXP-01 --- Siklus Pertama dengan CRC Aktif

Unggah kedua slave, jalankan `cek_radio.py`, lalu jalankan `master.py` dan
amati siklus pertama pada kedua sisi.

*Expected output --- master (Raspberry Pi)*

#keluaran("=== LoRa MASTER-SLAVE 3 NODE ===
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
========================================")

*Expected output --- slave (banner Serial Monitor, kedua Uno)*

#keluaran("=== LoRa SLAVE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
CRC payload: AKTIF
Menunggu POLL:1 dari Master (Raspberry Pi)...")

*Data capture*

#tbl(
  table(
    columns: (1.5fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Isi `MODEM_CFG_2` menurut `cek_radio.py` (SF, CRC)], [#isian],
    [Baris `CRC payload: AKTIF` muncul di Serial Monitor kedua slave?], [#isian],
    [Nomor siklus pertama yang lengkap tanpa `FAIL`], [#isian],
    [RSSI master dari S1 / S2 (dBm)], [#isian],
    [Jumlah `[IGNORE]` per siklus di tiap slave], [#isian],
  ),
  [Lembar pengamatan EXP-01],
  "tbl:m07b-exp01",
)

*Verifikasi kode* --- bandingkan `src/slave/main.cpp` di modul ini dengan
`Modul07_rpi_master_slave/src/slave/main.cpp` (varian tanpa CRC) memakai
`diff`. Jawab: baris apa saja yang berbeda, dan mengapa satu baris
`LoRa.enableCrc()` sudah cukup untuk mengubah keputusan hardware tentang paket
mana yang boleh naik ke `parsePacket()`?

#checkpoint[
  Ketiga node mencetak `OK` dan `CRC payload: AKTIF`, tiap slave menampilkan
  tepat satu `[RX]` dan dua `[IGNORE]` per siklus, dan `diff` menunjukkan hanya
  satu baris fungsional (`LoRa.enableCrc()` beserta satu baris cetak) yang
  berbeda dari varian tanpa CRC. Durasi siklus sedikit lebih panjang daripada
  baseline CRC-mati --- itu bukan regresi, melainkan biaya 2 byte checksum
  tambahan per paket.
]

=== EXP-02 --- Statistik dan Lama Siklus Lintas Mesin

Rekam bersamaan selama minimal 50 detik: terminal SSH master di Raspberry Pi,
dan kedua serial slave di laptop lewat `lora_monitor.py`.

*Expected output --- master*

#keluaran("========================================
=== CYCLE 40 ===
[TX] POLL:1
[RX] S1:DATA:40 | RSSI: -60 dBm | SNR: 14.0 dB
[TX] POLL:2
[RX] S2:DATA:40 | RSSI: -58 dBm | SNR: 14.1 dB
--- STATISTIK ---
S1: OK=40 | FAIL=0 | Data: 40
S2: OK=40 | FAIL=0 | Data: 40
Durasi siklus: 165 ms
========================================")

*Data capture*

#tbl(
  table(
    columns: (1.6fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Jumlah siklus dalam jendela rekaman], [#isian],
    [Durasi siklus min / maks / rata-rata saat sehat (ms)], [#isian],
    [Jumlah baris `[WARN] Balasan tidak valid` (harus 0 dengan CRC aktif)], [#isian],
    [`RX#` terakhir S1 / S2 vs `Data:` terakhir master --- harus *sama persis*], [#isian],
    [SNR arah slave#sym.arrow master vs master#sym.arrow slave --- simetris?], [#isian],
  ),
  [Lembar pengamatan EXP-02],
  "tbl:m07b-exp02",
)

#buka-abstraksi[
  Pada varian tanpa CRC (Modul 07), `OK` master kadang lebih kecil daripada
  `RX#` slave pada nomor yang sama, karena paket berpayload rusak lolos ke
  aplikasi dan gagal di-parse. Verifikasi pada sesi rekaman sendiri bahwa hal
  itu *tidak terjadi lagi* di sini --- `Data:` master harus mengikuti `RX#`
  slave nomor demi nomor tanpa selisih. Jelaskan, memakai isi `MODEM_CFG_2`
  dari `cek_radio.py`, mengapa kelas kegagalan itu sekarang tidak mungkin
  muncul.
]

#checkpoint[
  `Data:` master sama persis dengan `RX#` slave di setiap siklus yang `OK`, dan
  tidak ada satu pun baris `[WARN]` di seluruh sesi --- kontras langsung dengan
  `Modul07_rpi_master_slave/logserial.md`, yang mencatat sampai 0,74 % paket
  rusak lolos pada beberapa sesi. Durasi siklus sehat tetap sangat rapat
  (sebaran sekitar 1 ms pada Raspberry Pi 5), hanya bergeser lebih tinggi
  #sym.plus.minus 20 ms dari baseline CRC-mati karena 2 byte checksum tambahan
  di kedua arah.
]

=== EXP-03 --- Satu Node Hilang

Cabut kabel USB Slave 2 secara fisik selama `master.py` berjalan, tunggu
setidaknya 20 siklus, lalu pasang kembali.

#catatan[
  Mekanisme timeout dan pemulihan tidak berubah oleh CRC --- CRC hanya
  memfilter payload yang *diterima*, bukan payload yang tidak pernah datang.
  Expected output dan checkpoint di bawah diwariskan dari Modul 07 (CRC mati);
  keduanya *belum diuji ulang* secara khusus untuk varian ini pada sesi
  modifikasi CRC --- lihat `logserial.md` untuk status verifikasi terkini.
]

*Expected output --- master, tepat setelah kabel dicabut*

#keluaran("=== CYCLE 5 ===
[TX] POLL:1
[RX] S1:DATA:5 | RSSI: -70 dBm | SNR: 12.8 dB
[TX] POLL:2
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
S1: OK=5 | FAIL=0 | Data: 5
S2: OK=0 | FAIL=5 | Data: None
Durasi siklus: 605 ms")

*Data capture*

#tbl(
  table(
    columns: (1.5fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Pesan master saat Slave 2 tidak menjawab], [#isian],
    [Durasi siklus saat Slave 2 hilang (ms)], [#isian],
    [Apakah Slave 1 terpengaruh matinya Slave 2?], [#isian],
    [Berapa siklus sampai `OK` Slave 2 bertambah lagi setelah dipasang], [#isian],
    [`dataCounter` Slave 2 setelah dipasang kembali --- mulai dari berapa], [#isian],
  ),
  [Lembar pengamatan EXP-03],
  "tbl:m07b-exp03",
)

#checkpoint[
  Durasi siklus melonjak mendekati `POLL_TIMEOUT` penuh ditambah overhead,
  sementara Slave 1 sama sekali tidak terganggu. Begitu Slave 2 tersambung
  kembali, ia memulai `dataCounter` dari 1: bukti bahwa yang terjadi adalah
  reboot penuh, bukan sekadar port serial yang terputus.
]

=== EXP-04 --- Menekan Batas Waktu Sampai Rusak

Ubah `POLL_TIMEOUT` di *salinan* `master.py`, jalankan tiap nilai selama
60 detik, mulai dari 500 ms turun bertahap sampai keberhasilan jatuh ke nol.

#catatan[
  Dengan CRC aktif, waktu udara tiap paket sedikit lebih panjang (2 byte
  checksum tambahan di kedua arah), sehingga ambang tebing yang sebenarnya
  kemungkinan bergeser *lebih tinggi* dari titik 40--45 ms yang tercatat pada
  Modul 07 (CRC mati). Tabel di bawah dan checkpoint-nya diwariskan dari sesi
  CRC-mati sebagai titik acuan; *belum diukur ulang* untuk varian ini ---
  jalankan EXP-04 sendiri di sini untuk mendapati titik tebing yang baru.
]

*Data capture*

#tbl(
  table(
    columns: (auto, 1fr, 1fr, 1fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[`POLL_TIMEOUT` (ms)], th[Poll berhasil], th[Poll gagal], th[Gagal (%)]),
    [500 (baku)], [#isian], [], [],
    [100], [#isian], [], [],
    [60], [#isian], [], [],
    [50], [#isian], [], [],
    [45], [#isian], [], [],
    [40], [#isian], [], [],
  ),
  [Lembar pengamatan EXP-04 --- menekan batas waktu dengan CRC aktif],
  "tbl:m07b-exp04",
)

#checkpoint[
  Ambangnya tetap berupa tebing, bukan lereng. Bandingkan letaknya dengan hasil
  Modul 07: bila bergeser ke nilai yang lebih tinggi, jelaskan pergeseran itu
  memakai tambahan waktu udara dari 2 byte checksum.
]

=== Verifikasi Radio (Dijalankan Sebelum EXP-01)

#keluaran("REG_VERSION   : 0x12   (0x12 = SX1276/77/78/79)
FREKUENSI     : 433.000000 MHz   (target 433.000000, selisih +0.0 Hz)
MODEM_CFG_1   : 0x72 -> BW=125 kHz | CR=4/5 | header=explicit
MODEM_CFG_2   : 0x74 -> SF7 | CRC payload=AKTIF
PA_CONFIG     : 0x8f -> PA_BOOST, power=17 dBm")

#penting[
  *CRC payload aktif di kedua sisi.* `LoRa.enableCrc()` ditambahkan di
  `setup()` slave, dan `enableCrc()` --- fungsi baru di `master.py` yang
  menulis bit yang sama, `REG_MODEM_CONFIG_2` bit 2, persis seperti yang
  dilakukan `LoRa.enableCrc()` sandeepmistry --- dipanggil sebelum `master.py`
  mulai polling. Konsekuensinya: SX1276 penerima memverifikasi checksum 2-byte
  pada tiap paket dan membuang paket yang gagal *sebelum* `parsePacket()` atau
  `IRQ_RX_DONE` sempat menyerahkannya ke aplikasi. Paket berpayload rusak
  sekarang menghasilkan `[FAIL] tidak merespon` (timeout) alih-alih
  `[WARN] Balasan tidak valid` --- diagnosisnya benar secara radio (paket
  memang tidak sampai utuh), meski dari sisi statistik `OK` dan `FAIL` tetap
  tidak membedakan "slave diam" dari "jawaban dibuang radio".
]

=== Verifikasi Perangkat Keras (Log Referensi)

Sesi verifikasi CRC --- 21 Agustus 2026, satu Raspberry Pi 5 + LoRa GPS HAT
v1.4 (SSH) dan dua Arduino Uno + Dragino Shield v1.2 tertancap USB di laptop
pengembang (`/dev/ttyACM0`, `/dev/ttyACM1`), 433 MHz, jarak
#sym.plus.minus 30 cm. Log lengkap ada di `logserial.md`.

#tbl(
  table(
    columns: (1.3fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil terukur]),
    [`MODEM_CFG_2` menurut `cek_radio.py`], [*0x74* --- SF7, CRC payload *AKTIF* (sebelumnya 0x70 pada varian tanpa CRC)],
    [Banner `CRC payload: AKTIF` di Serial Monitor], [tampil pada kedua slave],
    [Siklus dalam sesi #sym.plus.minus 55 detik], [*83*, seluruhnya *OK* --- 0 `FAIL`, 0 `[WARN]`],
    [S1 / S2: OK / FAIL], [83/83 (100 %) / 83/83 (100 %)],
    [`RX#` slave vs `Data:` master pada siklus terakhir], [sama persis di kedua slave --- tidak ada payload rusak yang lolos maupun gagal parse],
    [Durasi siklus sehat min/maks/rata-rata], [*165 / 166 / 165,3 ms*],
    [Sebaran durasi siklus], [*1 ms* (n = 83) --- serapat sesi CRC-mati (144/145/145,0 ms), hanya bergeser *+20 ms* akibat 2 byte checksum per paket di kedua arah],
    [RSSI master dari S1 / S2], [#sym.minus 71,8 dBm (kisaran #sym.minus 83 … #sym.minus 68) / #sym.minus 65,0 dBm (kisaran #sym.minus 67 … #sym.minus 63)],
    [SNR master dari S1 / S2], [14,64 dB / 14,63 dB],
    [Baris `[IGNORE]` tak dikenal (payload rusak) di log kedua slave], [*0* dari 160 + 189 baris --- tidak satu pun keluar dari pola `POLL:<n>` atau `S<n>:DATA:<n>`],
  ),
  [Hasil verifikasi perangkat keras Modul 07B],
  "tbl:m07b-verifikasi",
)

#keluaran("Environment    Status    Flash
slave1         SUCCESS   26.6% (8.574 B)
slave2         SUCCESS   26.6% (8.574 B)")

Master tidak dikompilasi --- Python dijalankan langsung di Raspberry Pi. Kedua
slave berukuran identik (8.574 B, naik dari 8.522 B pada varian tanpa CRC ---
biaya `LoRa.enableCrc()` plus satu baris `Serial.println`), bukti keduanya
berasal dari source yang sama dan hanya berbeda `SLAVE_ID`.

#peringatan[
  *Cakupan pengujian sesi ini.* Yang diverifikasi langsung di perangkat: build,
  upload, register CRC di Pi (`cek_radio.py`), banner Serial kedua slave, dan
  satu sesi `master.py` penuh (gaya EXP-01 dan EXP-02) tanpa `[WARN]` maupun
  `[FAIL]` di luar transien awal. *EXP-03* (cabut kabel fisik) dan *EXP-04*
  (sapuan `POLL_TIMEOUT`) *tidak dijalankan ulang* pada sesi modifikasi CRC
  ini; angka di tabelnya tetap milik sesi CRC-mati sebelumnya dan perlu diukur
  ulang terpisah sebelum dipakai sebagai klaim untuk varian ini. Tidak satu pun
  paket rusak tertangkap secara langsung pada sesi 83 siklus ini untuk
  dibandingkan byte-per-byte dengan temuan Modul 07 --- wajar, karena kejadian
  itu sendiri sporadis (0,74 % pada sebagian sesi CRC-mati, 0,00 % pada sesi
  lain). Bukti bahwa CRC aktif berasal dari pembacaan register langsung dan
  dari nolnya `[WARN]` di seluruh sesi, bukan dari menangkap satu paket rusak
  yang difilter.
]

#catatan[
  *CH-2 pada modul dasar sudah diterapkan di sini.* Modul 07 mendaftar
  `LoRa.enableCrc()` di slave dan bit sepadan di master sebagai tantangan CH-2
  yang sengaja tidak diterapkan, karena menyentuh firmware slave akan
  membatalkan klaim "identik dengan M05" pada modul dasar. Modul ini adalah
  hasil penerapan CH-2 tersebut sebagai modul tersendiri. Rincian investigasi
  payload rusak pada varian tanpa CRC (pola byte, pengujian yang menyingkirkan
  SPI dan FIFO sebagai penyebab) tetap didokumentasikan di
  `Modul07_rpi_master_slave/logserial.md`, bagian "Temuan --- Payload rusak
  lolos karena CRC mati", sebagai bahan pembanding.
]

// Log serial lengkap dari Modul07b_rpi_master_slave_crc/logserial.md. Hanya dicetak pada
// edisi dosen agar tidak disalin mahasiswa sebagai hasil laporan
// (lihat config.typ).
#if edisi_buku == "dosen" [
  === Log Serial Terverifikasi

  Log serial lengkap hasil uji pada board nyata, bukan contoh. Bagian ini
  hanya dicetak pada edisi dosen.

  Hasil aktual dari perangkat. Baud *115200*, frekuensi *433 MHz*, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `POLL_TIMEOUT` 500 ms, `CYCLE_INTERVAL` 500 ms. Ketiga node di satu meja, jarak ±30 cm.

  Direktori ini adalah `Modul07b_rpi_master_slave_crc/`, salinan dari `Modul07_rpi_master_slave/` dengan `LoRa.enableCrc()` ditambahkan di slave dan `enableCrc()` di master. Sesi-sesi di bawah ini sampai dengan "Verifikasi ulang — 21 Agustus 2026" adalah *riwayat dari sebelum modifikasi CRC diterapkan* (CRC masih mati saat sesi-sesi itu direkam — persis kondisi `Modul07_rpi_master_slave/logserial.md`). Bagian *"Modifikasi CRC — 21 Agustus 2026"* di bawah, setelah bagian "Catatan pengambilan log", adalah sesi pertama dengan CRC *aktif* dan mendokumentasikan perubahan kode, build/upload, dan pengujian ulang di perangkat.

  Pengujian ini adalah *pengujian perangkat keras pertama* untuk Modul 07. Bagian "Catatan verifikasi" pada README sebelumnya menyatakan konversi ini belum pernah dijalankan di perangkat nyata; sejak dokumen ini ditulis, pernyataan itu tidak berlaku lagi.

  *Board & Port*

  #tbl(
    table(
      columns: (auto, auto, auto, 1fr),
      align: (left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Peran], th[Environment / program], th[Port], th[Board]),
      [Master], [`src/master.py`], [— (lewat SSH)], [Raspberry Pi 5B rev 1.0, BCM2712 + Dragino LoRa GPS HAT v1.4],
      [Slave 1], [`slave1` (`-DSLAVE_ID=1`)], [`/dev/ttyACM0`], [Uno asli (`2341:0043`) + Dragino Shield v1.2],
      [Slave 2], [`slave2` (`-DSLAVE_ID=2`)], [`/dev/ttyACM1`], [Uno asli (`2341:0043`) + Dragino Shield v1.2],
    ),
    [Log serial Modul 07B: Board & Port],
    "tbl:m07b-log-1",
  )

  Kedua Uno tertancap di laptop pengembang, sedangkan master dijalankan di Raspberry Pi lewat SSH. Inilah perbedaan praktis pertama dengan M05: *tiga node tidak lagi berada di satu komputer*, sehingga log master dan log slave direkam oleh dua mesin yang berbeda dan harus dicocokkan lewat isinya, bukan lewat cap waktu bersama.

  Perangkat lunak Raspberry Pi: Raspberry Pi OS 13 (trixie), Python 3.13.5, `python3-spidev` 3.6, `python3-rpi-lgpio` 0.6. Paket `python3-rpi.gpio` *tidak* terpasang — pada Pi 5, `RPi.GPIO` disediakan oleh `rpi-lgpio`. Rinciannya di README bagian 5.

  *Verifikasi radio sebelum percobaan*

  Nilai di bawah dibaca *balik dari register SX1276* setelah `loraBegin()` + konfigurasi, bukan disalin dari konstanta di source.

  #keluaran("REG_VERSION   : 0x12   (0x12 = SX1276/77/78/79)
FRF register  : 0x6c 0x40 0x00  -> frf=7094272
FREKUENSI     : 433.000000 MHz   (target 433.000000, selisih +0.0 Hz)
MODEM_CFG_1   : 0x72 -> BW=125 kHz | CR=4/5 | header=explicit
MODEM_CFG_2   : 0x70 -> SF7 | CRC payload=MATI
PA_CONFIG     : 0x8f -> PA_BOOST, power=17 dBm", pecah: true)

  #tbl(
    table(
      columns: (auto, auto, 1fr),
      align: (left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Nilai di chip], th[Sesuai README?]),
      [Frekuensi], [*433,000000 MHz* (selisih 0,0 Hz)], [ya],
      [Spreading factor], [SF7], [ya],
      [Bandwidth], [125 kHz], [ya],
      [Coding rate], [4/5], [ya],
      [Daya pancar], [17 dBm, PA\_BOOST], [ya],
      [*CRC payload*], [*MATI*], [tidak disebut README — lihat bagian Temuan],
    ),
    [Log serial Modul 07B: Verifikasi radio sebelum percobaan],
    "tbl:m07b-log-2",
  )

  Skrip pembacanya ditinggalkan di Raspberry Pi sebagai `cek_radio.py` agar verifikasi ini dapat diulang kapan saja.

  *EXP-01 — Siklus Pertama Lintas Platform*

  *Master (Raspberry Pi), siklus pertama*

  #keluaran("=== LoRa MASTER-SLAVE 3 NODE ===
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
========================================", pecah: true)

  *Slave 1 dan Slave 2 (cap waktu \= detik sejak perekaman serial dimulai)*

  #keluaran("   1.612  === LoRa SLAVE 1 ===          |     1.617  === LoRa SLAVE 2 ===
   1.634  Init LoRa ... OK              |     1.638  Init LoRa ... OK
   1.634  Freq: 433.00 MHz              |     1.638  Freq: 433.00 MHz
   1.637  Menunggu POLL:1 dari Master   |     1.642  Menunggu POLL:2 dari Master
                                        |
   4.320  [RX] POLL:1 | RSSI: -62 dBm | SNR: 8.00 dB | RX#: 1
   4.320  [TX] S1:DATA:1                |     4.316  [IGNORE] POLL:1
   4.389  [IGNORE] POLL:2               |     4.357  [IGNORE] S1:DATA:1
   4.426  [IGNORE] S2:DATA:1            |     4.391  [RX] POLL:2 | RSSI: -64 dBm | SNR: 9.00 dB | RX#: 1
                                        |     4.395  [TX] S2:DATA:1", pecah: true)

  #tbl(
    table(
      columns: (auto, 1fr),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Pesan init master], [`Init LoRa ... OK`, 433 MHz, SF7/BW 125 kHz],
      [Pesan init slave 1 / slave 2], [keduanya `Init LoRa ... OK`, `Freq: 433.00 MHz`],
      [Nomor siklus pertama yang lengkap], [*1* — tidak ada `FAIL` sama sekali di siklus pembuka],
      [RSSI master ← S1], [*−60 dBm* (SNR 14,2 dB)],
      [RSSI master ← S2], [*−58 dBm* (SNR 14,2 dB)],
      [Baris `[IGNORE]`], [S1 mengabaikan `POLL:2`, S2 mengabaikan `POLL:1` — masing-masing 1 per siklus],
      [Baris `[IGNORE]` tambahan], [tiap slave juga mengabaikan *jawaban* slave lain (`S2:DATA:1` / `S1:DATA:1`)],
    ),
    [Log serial Modul 07B: EXP-01 — Siklus Pertama Lintas Platform],
    "tbl:m07b-log-3",
  )

  *CHECKPOINT terpenuhi.* Ketiga node mencetak `OK`, dan tiap slave menampilkan tepat *satu* `[RX]` beserta *dua* `[IGNORE]` per siklus — satu untuk POLL milik node lain, satu untuk jawaban node lain. Urutan waktu di kedua slave saling mengunci: S2 mencatat `[IGNORE] POLL:1` pada 4.316 s, S1 mencatat `[RX] POLL:1` pada 4.320 s. Keduanya mendengar paket yang sama; hanya pemiliknya yang menjawab.

  Perhatikan bahwa *master berganti platform tanpa slave mengetahuinya*. Firmware slave yang dipakai identik dengan M05:

  #keluaran("$ diff Modul05_lora_master_slave/src/slave/main.cpp Modul07_rpi_master_slave/src/slave/main.cpp
2c2   <  LoRa Master-Slave 3 Node - ...     >  LoRa Master-Slave hybrid - ...
6,7c6,12   (blok komentar penjelas M07)
74c79,81   Serial.println(\"Menunggu POLL:1 dari Master...\")
        ->  Serial.print(\"Menunggu POLL:\"); Serial.print(SLAVE_ID);
            Serial.println(\" dari Master (Raspberry Pi)...\")", pecah: true)

  Tiga hunk, seluruhnya komentar dan satu pesan pembuka di `Serial`. Tidak satu byte pun dari yang mengudara berubah.

  *EXP-02 — Statistik dan Lama Siklus*

  Rekaman 50 detik dengan `src/master.py` apa adanya, sambil kedua port serial slave direkam bersamaan.

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Jumlah siklus dalam 50 detik], [*76* (≈1,52 siklus/detik)],
      [S1: OK / FAIL], [74 / *2*],
      [S2: OK / FAIL], [75 / *1*],
      [`Data:` terakhir S1 / S2], [76 / 76],
      [`RX#` terakhir di slave 1 / slave 2], [*76 / 76*],
      [Durasi siklus minimum], [*144 ms*],
      [Durasi siklus maksimum (siklus sehat)], [*145 ms*],
      [Durasi siklus rata-rata (siklus sehat)], [*145,0 ms*],
      [Durasi siklus saat satu poll gagal], [*605 ms*],
      [RSSI di master (dari S1 / S2)], [−59,6 / −57,8 dBm],
      [SNR di master (dari S1 / S2)], [14,09 / 14,19 dB],
      [RSSI di S1 / S2 (dari master)], [−64,8 / −64,0 dBm],
      [SNR di S1 / S2 (dari master)], [8,63 / 8,88 dB],
    ),
    [Log serial Modul 07B: EXP-02 — Statistik dan Lama Siklus],
    "tbl:m07b-log-4",
  )

  *Buka abstraksinya.* Ketiga bilangan yang diminta README dapat dibandingkan langsung: pada siklus ke-76, master mencatat `S1: OK=74 | FAIL=2 | Data: 76`, sedangkan slave 1 mencatat `RX#: 76`. Artinya slave menerima *seluruh* 76 panggilan dan mengirim *seluruh* 76 jawaban, tetapi hanya 74 yang sampai utuh ke master. `Data:` melompat dari 74 ke 76 tanpa master pernah menerima nomor 75 — persis keadaan yang diramalkan CHECKPOINT EXP-02, dan didapat tanpa perlu menjauhkan slave. Penyebab dua jawaban yang hilang itu dibahas di bagian Temuan.

  *Asimetri arah yang tidak terduga.* SNR arah slave → master adalah 14,1 dB, sedangkan arah master → slave hanya 8,6–8,9 dB — selisih tetap sekitar *5,3 dB* yang bertahan di seluruh rekaman. Kedua arah memakai daya pancar 17 dBm yang sama. Yang berbeda hanyalah papan pembawanya: LoRa GPS HAT di sisi Pi, Shield v1.2 di sisi Uno. Angka ini tidak terlihat dari terminal master saja, karena master hanya melaporkan arah yang diterimanya; ia baru muncul setelah kedua sisi direkam bersamaan.

  _Lama siklus jauh lebih rapat daripada dugaan README_

  README memperkirakan master Linux akan memperlihatkan *jitter penjadwalan* yang tidak ada padanannya di Arduino. Pada Raspberry Pi 5 dugaan itu *tidak terkonfirmasi*:

  #tbl(
    table(
      columns: (auto, auto, 1fr),
      align: (left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Ukuran], th[Master Raspberry Pi 5 (modul ini)], th[Master Arduino Uno (M05, `logserial.md`)]),
      [Durasi siklus minimum], [*144 ms*], [147 ms],
      [Durasi siklus maksimum], [*145 ms*], [154 ms],
      [Durasi siklus rata-rata], [*145,0 ms*], [152 ms],
      [Sebaran (maks − min)], [*1 ms*], [7 ms],
    ),
    [Log serial Modul 07B: Lama siklus jauh lebih rapat daripada dugaan README],
    "tbl:m07b-log-5",
  )

  Master Linux justru *lebih rapat* sebarannya daripada master Arduino, dan sedikit lebih cepat. Pengukuran kedua, diambil dari sisi node memakai `lora_monitor.py` (jarak antar `POLL` yang diterima slave, jadi sudah termasuk `CYCLE_INTERVAL` 500 ms):

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Ukuran], th[Nilai]),
      [Periode siklus minimum], [642 ms],
      [Periode siklus rata-rata], [645,2 ms],
      [Periode siklus maksimum], [648 ms],
      [Sebaran], [*6 ms* (n \= 112)],
    ),
    [Log serial Modul 07B: Lama siklus jauh lebih rapat daripada dugaan README],
    "tbl:m07b-log-6",
  )

  Kedua pengukuran sepakat. Penjelasan yang masuk akal: Pi 5 berinti empat pada beban hampir nol, sehingga proses Python praktis tidak pernah benar-benar berebut CPU; dan `POLL_TIMEOUT` 500 ms sedemikian longgar dibanding waktu tanggap sebenarnya (±45 ms, lihat EXP-04) sehingga penundaan beberapa milidetik tidak pernah mengubah hasil. Sebaran ini bukan bantahan terhadap teori di README — jitter tetap ada secara prinsip — melainkan bukti bahwa pada beban serendah ini besarnya tidak terukur oleh alat yang dipakai modul ini.

  *EXP-03 — Satu Node Hilang*

  Slave 2 dicabut kabel USB-nya sepenuhnya (bukan sekadar port serial ditutup — Uno bershield LoRa memakai daya dari USB, jadi mencabutnya mematikan seluruh node termasuk radionya) selama `master.py` berjalan, lalu dipasang kembali di tengah sesi. Slave 1 tetap dipantau lewat serial lokal selama percobaan berlangsung untuk memastikan node sehat tidak ikut terganggu.

  #keluaran("=== CYCLE 1 ===
[TX] POLL:1
[FAIL] Slave 1 tidak merespon!
[TX] POLL:2
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
Durasi siklus: 1065 ms
========================================
=== CYCLE 2 ===
[TX] POLL:1
[RX] S1:DATA:1 | RSSI: -70 dBm | SNR: 12.8 dB
[TX] POLL:2
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
S1: OK=1 | FAIL=1 | Data: 1
S2: OK=0 | FAIL=2 | Data: None
Durasi siklus: 604 ms
...
=== CYCLE 28 ===
[TX] POLL:1
[RX] S1:DATA:27 | RSSI: -70 dBm | SNR: 13.0 dB
[TX] POLL:2
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
S1: OK=27 | FAIL=1 | Data: 27
S2: OK=0 | FAIL=27 | Data: None
Durasi siklus: 605 ms
=== CYCLE 29 ===
[TX] POLL:1
[RX] S1:DATA:28 | RSSI: -71 dBm | SNR: 12.8 dB
[TX] POLL:2
[RX] S2:DATA:1 | RSSI: -64 dBm | SNR: 13.8 dB
--- STATISTIK ---
S1: OK=28 | FAIL=1 | Data: 28
S2: OK=1 | FAIL=27 | Data: 1
Durasi siklus: 144 ms", pecah: true)

  #tbl(
    table(
      columns: (auto, 1fr),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Siklus 1 — kedua slave gagal (start-up master mendahului kesiapan radio)], [Durasi *1065 ms*, kira-kira dua `POLL_TIMEOUT` penuh],
      [Siklus 2–28 — Slave 2 hilang (27 siklus berturut-turut)], [Durasi stabil *604–606 ms*, rata-rata *621,4 ms*],
      [Siklus 29 — Slave 2 kembali], [Langsung `OK`, `S2:DATA:1` — `dataCounter` slave mulai dari 1 (bukti Uno benar-benar reboot, bukan cuma port serial terputus)],
      [Siklus 30 dst. — steady state], [Durasi kembali *144–145 ms*, rata-rata 144,8 ms],
      [Slave 1 selama Slave 2 hilang], [*OK di seluruh 27 siklus* — 79 baris `[TX] S1:DATA:n` lokal, `[IGNORE] POLL:2` 79× tanpa gangguan],
      [Pertambahan durasi akibat satu node mati], [*604,8 − 144,8 ≈ 460 ms*, ≈ `POLL_TIMEOUT` (500 ms) dikurangi waktu jawaban sehat],
      [Pemulihan], [*Seketika* — satu siklus setelah Slave 2 tersambung kembali, tanpa intervensi di sisi master],
    ),
    [Log serial Modul 07B: EXP-03 — Satu Node Hilang],
    "tbl:m07b-log-7",
  )

  *CHECKPOINT terpenuhi, dan sekarang dengan data sungguhan.* Catatan lama di bagian "Catatan pengambilan log" menyimpulkan pertambahan +460 ms hanya dari poll individual yang gagal sesekali, tanpa benar-benar mencabut node. Sesi ini mengonfirmasinya secara langsung: 27 siklus berturut-turut dengan Slave 2 mati, tidak satu pun memengaruhi Slave 1, dan durasi siklus melonjak persis sebesar satu `POLL_TIMEOUT` dikurangi waktu tanggap sehat (605 − 145 ≈ 460 ms) — sama seperti prediksi CHECKPOINT EXP-03 M05, dan sama dengan angka +459 ms yang tercatat di `Modul05_lora_master_slave/logserial.md` untuk skenario setara.

  *Siklus 1 (1065 ms) bukan anomali — konsisten dengan dua timeout penuh.* Master mulai polling sebelum Slave 1 (yang baru saja diunggah ulang) selesai boot, sehingga siklus pertama kehilangan *kedua* slave sekaligus: 2 × \~500 ms `POLL_TIMEOUT` plus overhead, hasilnya 1065 ms — persis nilai yang sudah tercatat sebagai temuan tersendiri di bagian ini sebelum EXP-03 pernah dijalankan langsung.

  *EXP-04 — Menekan Batas Waktu Sampai Rusak*

  `POLL_TIMEOUT` diturunkan bertahap, tiap nilai dijalankan *60 detik*. Nilai diberikan lewat environment ke salinan `master.py`, sehingga `src/master.py` tidak pernah diubah.

  #tbl(
    table(
      columns: (auto, auto, auto, auto, auto, 1fr),
      align: (left, left, left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[`POLL_TIMEOUT` (ms)], th[Siklus], th[Poll berhasil], th[Poll gagal], th[Gagal (%)], th[Durasi siklus rata-rata (ms)]),
      [500 (baku)], [92], [184], [0], [*0,0 %*], [156],
      [250], [92], [184], [0], [*0,0 %*], [156],
      [150], [92], [184], [0], [*0,0 %*], [156],
      [100], [92], [184], [0], [*0,0 %*], [156],
      [60], [92], [184], [0], [*0,0 %*], [156],
      [55], [92], [183], [1], [0,5 %], [156],
      [50], [92], [184], [0], [*0,0 %*], [156],
      [45], [92], [181], [3], [1,6 %], [156],
      [*40*], [93], [*0*], [*186*], [*100 %*], [146],
    ),
    [Log serial Modul 07B: EXP-04 — Menekan Batas Waktu Sampai Rusak],
    "tbl:m07b-log-8",
  )

  *Ambangnya adalah tebing, bukan lereng* — persis seperti diramalkan CHECKPOINT EXP-04. Di 45 ms sistem masih berhasil 98,4 %; di 40 ms keberhasilan jatuh ke *nol mutlak*, bukan memburuk perlahan. Zona 45–55 ms adalah pinggiran tebing: sebagian jawaban mulai tersenggol batas waktu, tetapi mayoritas masih lolos.

  Pengulangan tiga kali pada dua nilai penentu (Pengukuran C):

  #tbl(
    table(
      columns: (auto, 1fr, auto),
      align: (left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Percobaan ke-], th[Nilai terkecil yang masih andal (ms)], th[Nilai pertama yang sudah gagal (ms)]),
      [1], [60 (0 gagal dari 184)], [40 (186 gagal dari 186)],
      [2], [60 (0 gagal dari 184)], [40 (186 gagal dari 186)],
      [3], [60 (0 gagal dari 184)], [40 (186 gagal dari 186)],
    ),
    [Log serial Modul 07B: EXP-04 — Menekan Batas Waktu Sampai Rusak],
    "tbl:m07b-log-9",
  )

  Reproduksinya sempurna — tidak ada satu pun kejadian menyimpang di enam sesi.

  _Mengapa 40 ms, bukan 77 ms_

  README memperkirakan ambangnya "hampir pasti jauh di atas" 77 ms, dengan alasan waktu udara `POLL:1` (±36 ms) ditambah waktu udara `S1:DATA:12` (±41 ms). Hasil pengukuran menunjukkan ambangnya justru *di bawah* angka itu, dan penyebabnya adalah kekeliruan dalam menyusun anggaran waktunya:

  `POLL_TIMEOUT` *tidak pernah mencakup waktu udara POLL*. Di `pollSlave()`, `transmit(pollMsg)` bersifat blocking — ia baru kembali setelah `IRQ_TX_DONE` menyala, artinya paket POLL sudah selesai mengudara. Baru sesudah itu `waitStart = time.monotonic()` dijalankan. Jadi jendela batas waktu hanya menampung:

  #keluaran("pemrosesan di slave  +  waktu udara jawaban (±41 ms)  +  deteksi RX_DONE di master", pecah: true)

  Yang tersisa memang ±41–45 ms, dan itulah sebabnya 45 ms berada di pinggiran sementara 40 ms memotong setiap jawaban tepat sebelum tiba. Angka 36 ms untuk POLL sudah "dibayar" di dalam `transmit()`, di luar penghitung waktu.

  Konsekuensi praktisnya: `POLL_TIMEOUT` 500 ms adalah *11× lebih longgar* daripada yang dibutuhkan. Kelonggaran itulah yang membuat durasi siklus tidak pernah goyah — dan sekaligus yang membuat satu node mati menjadi sangat mahal, karena setiap node mati menagih 500 ms penuh setiap siklus.

  *Temuan — Payload rusak lolos karena CRC mati*

  Selama pengujian, master beberapa kali mencetak `[WARN] Balasan tidak valid` lalu menghitungnya sebagai `[FAIL]`, padahal log serial slave membuktikan slave menerima POLL dan mengirim jawaban yang benar. Contoh byte mentahnya:

  #keluaran("[WARN] Balasan tidak valid: S?:DATA:705 | ps=11 | raw=53 a1 3a 44 41 54 41 3a 37 30 35
                                                       ^^ seharusnya 0x31 ('1')
[WARN] Balasan tidak valid: S1:DATA?85  | ps=10 | raw=53 31 3a 44 41 54 41 9a 38 35
                                                                         ^^ seharusnya 0x3a (':')", pecah: true)

  *Frekuensi kejadian*

  #tbl(
    table(
      columns: (1fr, auto, auto, auto),
      align: (left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Kelompok run], th[Paket diterima], th[Paket rusak], th[Rasio]),
      [8 sesi pertama], [2288], [17], [*0,74 %*],
      [4 sesi berikutnya], [1462], [0], [*0,00 %*],
    ),
    [Log serial Modul 07B: Temuan — Payload rusak lolos karena CRC mati],
    "tbl:m07b-log-10",
  )

  *Pola byte* — dari 13 paket rusak yang byte mentahnya sempat terekam:

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Sifat], th[Pengamatan]),
      [Byte rusak per paket], [1 byte (10 paket), 2 byte (3 paket)],
      [Indeks byte yang rusak], [indeks 1 (10×), indeks 7 (4×), indeks 8 (2×)],
      [Indeks yang *tidak pernah* rusak], [0, 2, 3, 4, 5, 6 — yaitu `S`, `:`, dan `DATA`],
      [Jumlah bit berbeda, pada byte yang nilai benarnya pasti], [selalu *2 bit* (4 dari 4 kasus)],
    ),
    [Log serial Modul 07B: Temuan — Payload rusak lolos karena CRC mati],
    "tbl:m07b-log-11",
  )

  *Yang sudah disingkirkan sebagai penyebab*

  #tbl(
    table(
      columns: (auto, auto, 1fr),
      align: (left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Dugaan], th[Uji], th[Hasil]),
      [Jalur SPI tidak andal], [`REG_VERSION` dibaca 40.000× pada 5 MHz dan 1 MHz], [*0 error* di kedua kecepatan — SPI bersih saat idle],
      [Modem menimpa FIFO saat dibaca], [`MODE_STDBY` disisipkan sebelum baca FIFO, seperti `LoRa.parsePacket()` di Arduino], [rasio *tidak berubah* (6 dari 354)],
      [Byte rusak saat dibaca dari FIFO], [isi FIFO dibaca *3× berturut-turut* lalu dibandingkan], [*selalu identik*, termasuk pada paket rusak],
      [Master membanjiri SPI saat demodulasi], [`time.sleep(0.002)` disisipkan di loop tunggu], [0 dari 730 — *tetapi kontrol tanpa jeda juga 0 dari 732*, jadi tidak membuktikan apa pun],
    ),
    [Log serial Modul 07B: Temuan — Payload rusak lolos karena CRC mati],
    "tbl:m07b-log-12",
  )

  Pembacaan FIFO tiga kali yang selalu identik adalah uji penentunya: *byte rusak itu sudah berada di FIFO sebelum dibaca*. Jalur SPI tidak bersalah; kerusakan terjadi di udara atau di dalam demodulator.

  *Mengapa kerusakan itu lolos sampai ke aplikasi.* `MODEM_CFG_2` menunjukkan CRC payload *mati*, di kedua sisi. `LoRa.begin()` milik sandeepmistry tidak mengaktifkan CRC kecuali diminta lewat `LoRa.enableCrc()`, dan `master.py` juga tidak menyalakannya. Akibatnya pemeriksaan `IRQ_CRC_ERROR` di `parsePacket()` *tidak akan pernah menyala* — bukan karena tidak ada paket cacat, melainkan karena radio tidak pernah diminta memeriksanya. Paket cacat naik utuh ke lapisan aplikasi, gagal di `reply.startswith("S1:DATA:")`, dan tercatat sebagai "slave tidak merespon" — diagnosis yang menunjuk ke arah yang salah sama sekali.

  *Status.* Mekanisme yang membangkitkan kerusakan *belum diketahui*. Pola indeksnya (hanya 1, 7, 8) terlalu terpusat untuk galat bit acak, tetapi belum ada uji yang menjelaskannya. Fenomenanya juga tidak muncul terus-menerus: 17 kejadian di delapan sesi pertama, nol di empat sesi berikutnya dan di seluruh EXP-04 kecuali satu, tanpa perubahan perangkat keras apa pun di antaranya.

  Perbaikan yang jelas — `LoRa.enableCrc()` di slave dan menyalakan bit 2 `REG_MODEM_CONFIG_2` di master — *tidak diterapkan*, karena menyentuh firmware slave dan dengan demikian membatalkan klaim utama modul ini bahwa slave identik dengan M05. Itu keputusan perancang modul, bukan keputusan penguji. Sebagai bahan praktikum, keadaan ini justru lebih berharga dibiarkan: ia memperlihatkan satu lapisan pelindung yang tidak dipasang, dan akibatnya terhadap diagnosis di lapisan atas.

  *Verifikasi ulang — 21 Agustus 2026*

  Sesi verifikasi baru: kedua slave dibangun ulang dari `src/` saat ini dan diunggah ulang (`pio run -e slave1|slave2 -t upload`, keduanya SUCCESS, flash 8.522 B terverifikasi avrdude), master dijalankan langsung dari sumbernya di Raspberry Pi lewat SSH (`python3 -u src/master.py`, tanpa perubahan). Tujuannya memastikan konversi PlatformIO M07 masih berjalan seperti didokumentasikan di atas, bukan mengulang investigasi CRC.

  *Board & Port sesi ini* — berbeda dari tabel "Board & Port" di atas karena hanya dua Uno yang tersambung ke laptop pengembang saat ini: Slave 1 di `/dev/ttyACM1`, Slave 2 di `/dev/ttyACM2` (bukan `ACM0`/`ACM1`). Ini contoh nyata alasan README menyuruh menjalankan `tools/deteksi_port.py` dan memakai `--upload-port` eksplisit alih-alih mengandalkan nilai contoh di `platformio.ini`.

  #keluaran("=== CYCLE 3 ===
[TX] POLL:1
[RX] S1:DATA:47 | RSSI: -76 dBm | SNR: 13.0 dB
[TX] POLL:2
[WARN] Balasan tidak valid: S?:DATA:27
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
S1: OK=3 | FAIL=0 | Data: 47
S2: OK=2 | FAIL=1 | Data: None
Durasi siklus: 605 ms", pecah: true)

  #tbl(
    table(
      columns: (auto, 1fr),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Siklus dalam ±35 detik], [*46*],
      [Durasi siklus steady-state min/maks/rata-rata], [145 / 145 / *145,0 ms* (n\=45, mengecualikan 1 timeout)],
      [Slave 1: OK / FAIL], [46 / 0 → *100 %*],
      [Slave 2: OK / FAIL], [45 / 1 → *97,8 %*],
      [Penyebab satu-satunya FAIL], [1 byte payload rusak (`S1:DATA:27` → `S :DATA:27`), pola sama dengan temuan "Payload rusak lolos karena CRC mati" di atas],
      [SNR balasan Slave 1 di master], [rata-rata *13,2 dB* (n\=46)],
      [SNR balasan Slave 2 di master], [rata-rata *13,3 dB* (n\=45)],
      [RSSI balasan Slave 1 / Slave 2 di master], [−69,4 dBm / −65,8 dBm (sepadan, tidak ada node yang janggal)],
    ),
    [Log serial Modul 07B: Verifikasi ulang — 21 Agustus 2026],
    "tbl:m07b-log-13",
  )

  *Tidak ada anomali seperti pada M05.* Modul 05 sempat mencatat SNR Slave 2 anjlok ke \~1,2 dB akibat Slave 2 duduk terlalu dekat dengan master (near-field). Pada sesi M07 ini, SNR kedua slave hampir identik (13,2 vs 13,3 dB) dan RSSI keduanya wajar — tidak ada indikasi kejenuhan penerima di sisi mana pun.

  *Tampilan Uno vs tampilan Raspberry Pi cocok satu sama lain.* Log slave lokal (dibaca langsung dari `/dev/ttyACM1` dan `/dev/ttyACM2`) menunjukkan `[TX] S1:DATA:n` dan `[TX] S2:DATA:n` yang nomornya berurutan dengan `[RX] S1:DATA:n`/`S2:DATA:n` pada log master di Raspberry Pi — mengonfirmasi kedua sisi memang saling bicara lewat radio, bukan kebetulan dua proses berjalan sendiri-sendiri.

  *Catatan pelaksanaan.* Saat keluarannya dipipa lewat SSH (bukan TTY interaktif), Python membuffer stdout — memakai `timeout` untuk membatasi durasi lalu memutus prosesnya membuang isi buffer yang belum sempat di-flush. Jalankan dengan `python3 -u` saat keluarannya perlu direkam lewat pipa/redirect.

  `master.py` sebelumnya tidak punya opsi `--help` — argumen apa pun diabaikan begitu saja dan sesi langsung berjalan, seperti yang terjadi saat pertama kali dicoba pada sesi ini. Sudah ditambahkan `argparse` dengan `-h`/`--help` yang mencetak parameter radio (frekuensi, SF, BW, `POLL_TIMEOUT`, `CYCLE_INTERVAL`) tanpa menyentuh SPI/GPIO, dan argumen tak dikenal sekarang ditolak dengan pesan `usage` alih-alih diam-diam diabaikan. Tidak ada opsi baru selain `-h`; perilaku tanpa argumen tidak berubah (diverifikasi ulang: 10 siklus bersih, 100 % OK).

  *Catatan pengambilan log*

  - *EXP-03 sudah dijalankan* pada sesi 21 Agustus 2026 (lihat bagian EXP-03 di atas) — kabel USB Slave 2 dicabut fisik dan dipasang kembali sementara operator hadir langsung di lokasi board, master tetap dijalankan dari jarak jauh lewat SSH.
  - *Tabel jarak (Pengukuran B) belum terisi.* Seluruh percobaan dijalankan di satu meja pada jarak tetap ±30 cm.
  - Kolom M05 pada tabel perbandingan lama siklus diisi dari `Modul05_lora_master_slave/logserial.md`, bukan dari pengukuran ulang pada sesi ini.
  - Membuka port serial me-*reset* Arduino lewat DTR, sehingga `RX#` dan `dataCounter` slave kembali ke 1 sementara penghitung master terus berjalan. Bila kedua angka perlu sebanding, jalankan perekam serial lebih dahulu, baru master.
  - Seluruh berkas diagnostik (`master_diagA/B/C/D.py`, `master_exp04.py`, `spi_stress.py`) sudah dihapus dari Raspberry Pi. Yang tersisa di sana hanya `src/master.py`, `requirements.txt`, dan `cek_radio.py`.
  - `src/master.py`, `src/slave/main.cpp`, dan `platformio.ini` *tidak diubah sama sekali* selama pengujian ini.

  *Modifikasi CRC — 21 Agustus 2026*

  Sesi ini menerapkan CH-2 dari README `Modul07_rpi_master_slave/` (menyalakan CRC payload di kedua sisi) sebagai modul tersendiri di direktori `-withCRC`. Raspberry Pi tetap `pi@192.168.1.45` lewat SSH; kedua Uno tertancap USB di laptop pengembang.

  *Perubahan kode*

  - `src/slave/main.cpp`: `LoRa.enableCrc();` ditambahkan di `setup()` setelah `LoRa.setTxPower()`, plus satu baris `Serial.println(F("CRC payload: AKTIF"));` pada banner boot. Komentar header disesuaikan untuk tidak lagi mengklaim identik-byte-untuk-byte dengan M05.
  - `src/master.py`: dua fungsi baru, `enableCrc()`/`disableCrc()`, menulis/membersihkan bit 2 `REG_MODEM_CONFIG_2` — persis padanan `LoRa.enableCrc()`/`disableCrc()` di pustaka sandeepmistry (dikonfirmasi lewat pembacaan `LoRa.cpp`: `writeRegister(REG_MODEM_CONFIG_2, readRegister(REG_MODEM_CONFIG_2) | 0x04)`). `enableCrc()` dipanggil di alur `__main__` setelah `setTxPower(TX_POWER)`, plus satu baris cetak `CRC payload: AKTIF` pada banner init.
  - `cek_radio.py`: awalnya *tidak* memanggil `M.enableCrc()` — skrip ini mengonfigurasi radio secara manual lewat pemanggilan fungsi satu-satu (`M.setSpreadingFactor`, dst.), bukan lewat `master.py` utuh, jadi luput saat `enableCrc()` pertama kali ditambahkan. Percobaan pertama pembacaan register masih menunjukkan `MODEM_CFG_2 : 0x70 -> CRC payload=MATI` meski kode slave dan `master.py` sudah benar. Ditambahkan `M.enableCrc()` di `cek_radio.py`, dan pembacaan ulang langsung menunjukkan `0x74 -> CRC payload=AKTIF`. Dicatat di sini karena ini contoh nyata kelas kegagalan "kode benar, tapi skrip verifikasinya sendiri belum diperbarui" — persis alasan bagian ini menuntut bukti pembacaan register, bukan sekadar membaca source.

  *Build & upload*

  #keluaran("Environment    Status    Duration
slave1         SUCCESS   00:00:00.592   Flash: 26.6% (8.574 B)
slave2         SUCCESS   00:00:00.615   Flash: 26.6% (8.574 B)", pecah: true)

  Naik dari 8.522 B (26,4%) pada varian tanpa CRC — biaya `LoRa.enableCrc()` plus satu baris `Serial.println` tambahan, 52 byte per slave. Upload lewat `avrdude` ke `/dev/ttyACM0` (slave1) dan `/dev/ttyACM1` (slave2, dikonfirmasi via `tools/deteksi_port.py` sebelum upload), keduanya `bytes written` dan `bytes verified` sama dengan ukuran hex — SUCCESS.

  *Verifikasi register di Raspberry Pi*

  `src/master.py`, `cek_radio.py`, dan `requirements.txt` disalin ke `~/Documents/WSN-IOT-prak-Lora/Modul07b_rpi_master_slave_crc/` di Pi lewat `scp`, lalu `cek_radio.py` dijalankan di sana:

  #keluaran("REG_VERSION   : 0x12   (0x12 = SX1276/77/78/79)
FRF register  : 0x6c 0x40 0x00  -> frf=7094272
FREKUENSI     : 433.000000 MHz   (target 433.000000, selisih +0.0 Hz)
MODEM_CFG_1   : 0x72 -> BW=125 kHz | CR=4/5 | header=explicit
MODEM_CFG_2   : 0x74 -> SF7 | CRC payload=AKTIF
PA_CONFIG     : 0x8f -> PA_BOOST, power=17 dBm", pecah: true)

  `MODEM_CFG_2` naik dari `0x70` ke `0x74` — persis bit 2 yang dinyalakan `enableCrc()`, tidak ada bit lain yang ikut berubah.

  *Banner Serial kedua slave* (dibaca dari `/dev/ttyACM0`/`/dev/ttyACM1` via `pyserial`, DTR ditoggle eksplisit untuk memicu reset dan menangkap banner boot penuh)

  #keluaran("=== LoRa SLAVE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
CRC payload: AKTIF
Menunggu POLL:1 dari Master (Raspberry Pi)...

=== LoRa SLAVE 2 ===
Init LoRa ... OK
Freq: 433.00 MHz
CRC payload: AKTIF
Menunggu POLL:2 dari Master (Raspberry Pi)...", pecah: true)

  *Uji fungsional — sesi bersih ±55 detik*

  Prosedur: logger `pyserial` dibuka lebih dulu di kedua port (memicu reset Uno lewat DTR), ditunggu 3,5 detik agar bootloader + `setup()` selesai, baru `python3 -u master.py` dijalankan di Pi lewat SSH selama 55 detik — meniru urutan EXP-01 (slave siap sebelum master mulai polling).

  #keluaran("=== LoRa MASTER-SLAVE 3 NODE ===
Init LoRa ... OK
Freq: 433 MHz
SF7 | BW: 125 kHz
CRC payload: AKTIF
Peran: MASTER (Raspberry Pi + LoRa GPS HAT)
Slave: Dragino Shield Uno - S1 & S2

========================================
=== CYCLE 1 ===
[TX] POLL:1
[RX] S1:DATA:1 | RSSI: -72 dBm | SNR: 14.8 dB
[TX] POLL:2
[RX] S2:DATA:38 | RSSI: -64 dBm | SNR: 14.5 dB
--- STATISTIK ---
S1: OK=1 | FAIL=0 | Data: 1
S2: OK=1 | FAIL=0 | Data: 38
Durasi siklus: 165 ms
========================================
...
--- STATISTIK ---
S1: OK=83 | FAIL=0 | Data: 83
S2: OK=83 | FAIL=0 | Data: 120
Durasi siklus: 166 ms", pecah: true)

  (`Data:` Slave 2 mulai dari 38, bukan 1 — `dataCounter` on-board-nya melanjutkan dari sesi uji coba sebelumnya di hari yang sama, bukan reboot penuh. Tidak memengaruhi validitas OK/FAIL karena keduanya dihitung per sesi master, bukan dari nilai absolut `Data:`.)

  #tbl(
    table(
      columns: (auto, 1fr),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Total siklus dalam ±55 detik], [*83*],
      [S1: OK / FAIL], [83 / 0 → *100 %*],
      [S2: OK / FAIL], [83 / 0 → *100 %*],
      [Baris `[WARN] Balasan tidak valid` di seluruh log master], [*0*],
      [Baris `[FAIL]` di seluruh log master], [*0*],
      [Durasi siklus min / maks / rata-rata], [*165 / 166 / 165,3 ms* (n\=83)],
      [Sebaran durasi siklus], [*1 ms* — sama rapatnya dengan sesi CRC-mati (144/145/145,0 ms), hanya bergeser *+20 ms*],
      [RSSI master ← S1], [rata-rata *−71,8 dBm* (kisaran −83..−68 dBm)],
      [RSSI master ← S2], [rata-rata *−65,0 dBm* (kisaran −67..−63 dBm)],
      [SNR master ← S1 / S2], [*14,64 dB* / *14,63 dB*],
      [`RX#` akhir slave 1 / slave 2 (log lokal)], [*83* / *120* — S1 cocok persis dengan `Data:` master (83); S2 juga cocok (120) setelah memperhitungkan offset awal 38],
      [Baris `[IGNORE]` di luar pola `POLL:<n>`/`S<n>:DATA:<n>` (log lokal, kedua slave)], [*0* dari 160 (S1) + 189 (S2) baris],
    ),
    [Log serial Modul 07B: Modifikasi CRC — 21 Agustus 2026],
    "tbl:m07b-log-14",
  )

  *Interpretasi.* Tidak ada satu pun payload rusak yang tertangkap secara langsung pada sesi 83-siklus ini untuk dibandingkan byte-per-byte dengan temuan "Payload rusak lolos karena CRC mati" di atas — konsisten dengan sifat sporadis fenomena itu (0,74% pada sebagian sesi CRC-mati, 0,00% pada sesi lain di bagian atas dokumen ini). Bukti bahwa proteksi CRC benar-benar aktif berasal dari tiga sumber independen: (1) pembacaan register langsung di Pi menunjukkan bit CRC menyala, (2) banner boot kedua slave mencetak `CRC payload: AKTIF`, dan (3) nol baris `[WARN]` di seluruh sesi — dengan CRC mati, sesi serupa pada sesi-sesi sebelumnya di dokumen ini rutin mencetak beberapa `[WARN]` per ratusan paket.

  *Kenaikan durasi siklus (+20 ms) dijelaskan secara fisik, bukan sebagai overhead pemrosesan.* SX1276 menambahkan 2 byte checksum ke payload saat `RxPayloadCrcOn` menyala, memperpanjang waktu-di-udara paket di kedua arah (`POLL` dan `S<id>:DATA:<n>`). Kenaikan ini konsisten di seluruh 83 siklus (hanya dua nilai: 165 ms × 56, 166 ms × 27) — bukan jitter, melainkan pergeseran baseline yang dapat diprediksi.

  *Uji coba awal (dibuang, tidak dipakai sebagai data resmi).* Sebelum sesi bersih di atas, dilakukan uji cepat ±25 detik tanpa jeda boot — logger serial dan `master.py` dimulai hampir bersamaan. Hasilnya: 37 siklus, S1 36 OK/1 FAIL (FAIL persis di CYCLE 1), S2 37/37 OK. `[FAIL]` tunggal itu adalah race kondisi start-up yang sudah didokumentasikan sebelumnya di bagian "Catatan pengambilan log" (membuka port serial me-reset Arduino lewat DTR) — bukan efek CRC — dan tidak muncul lagi setelah prosedur diperbaiki (tunggu boot sebelum start master) pada sesi resmi di atas.

  *Cakupan pengujian yang TIDAK dilakukan ulang sesi ini.* EXP-03 (cabut kabel fisik) dan EXP-04 (sapuan `POLL_TIMEOUT`) tidak dijalankan ulang — keduanya menuntut intervensi fisik berulang atau sesi 60 detik × banyak titik yang di luar cakupan verifikasi modifikasi CRC kali ini. Tabel EXP-03/EXP-04 di README tetap berisi angka dari sesi CRC-mati sebelumnya dan *belum divalidasi* untuk varian ini; kenaikan waktu-di-udara yang terukur di atas (+20 ms/siklus) memberi dugaan terarah bahwa ambang tebing EXP-04 akan bergeser sedikit lebih tinggi dari 40–45 ms, tetapi ini belum diukur langsung.
]

== Pengukuran

*A. Keberhasilan terhadap jarak* --- kedua slave ditempatkan pada jarak sama
dari Raspberry Pi, 30 siklus per baris.

#tbl(
  table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: (left, left, left, left, left, left, left),
    inset: (x: 0.4em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Jarak], th[RSSI S1], th[RSSI S2], th[OK/FAIL S1], th[OK/FAIL S2], th[Berhasil S1 (%)], th[Berhasil S2 (%)]),
    [1 m], [#isian], [], [], [], [], [],
    [25 m], [#isian], [], [], [], [], [],
    [50 m], [#isian], [], [], [], [], [],
    [100 m], [#isian], [], [], [], [], [],
  ),
  [Lembar pengukuran A --- keberhasilan terhadap jarak],
  "tbl:m07b-ukur-a",
)

*B. Perbandingan platform master dan biaya CRC*

#tbl(
  table(
    columns: (1.1fr, 1fr, 1fr, 1fr),
    align: (left, left, left, left),
    inset: (x: 0.5em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Ukuran], th[Modul ini (Pi 5, CRC aktif)], th[M07 (Pi 5, CRC mati)], th[M05 (Uno)]),
    [Durasi siklus minimum (ms)], [#isian], [144], [147],
    [Durasi siklus maksimum (ms)], [#isian], [145], [154],
    [Durasi siklus rata-rata (ms)], [#isian], [145,0], [152],
    [Sebaran (maks #sym.minus min, ms)], [#isian], [1], [7],
  ),
  [Lembar pengukuran B --- perbandingan platform master dan biaya CRC],
  "tbl:m07b-ukur-b",
)

*C. Ambang `POLL_TIMEOUT`* --- ulangi EXP-04 tiga kali pada dua titik.

#tbl(
  table(
    columns: (auto, 1.2fr, 1.2fr),
    align: (center + horizon, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Percobaan ke-], th[Nilai terkecil andal (ms)], th[Nilai pertama gagal total (ms)]),
    [1], [#isian], [],
    [2], [#isian], [],
    [3], [#isian], [],
  ),
  [Lembar pengukuran C --- ambang `POLL_TIMEOUT` dengan CRC aktif],
  "tbl:m07b-ukur-c",
)

*D. Rasio payload rusak yang lolos ke aplikasi* --- hitung dari sesi gabungan
EXP-02 dan EXP-04 sendiri, lalu bandingkan dengan lembar pengukuran D pada
Modul 07 (CRC mati). Dengan CRC aktif, rasio ini seharusnya *0 %* --- paket
rusak dibuang radio sebelum sempat menghasilkan `[WARN]`.

#tbl(
  table(
    columns: (1.3fr, 1fr, 1.2fr, auto),
    align: (left, left, left, left),
    inset: (x: 0.5em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Sesi], th[Paket diterima], th[Paket `[WARN]`], th[Rasio (%)]),
    [Sesi sendiri 1], [#isian], [], [],
    [Sesi sendiri 2], [#isian], [], [],
    [Referensi (83 siklus, #sym.plus.minus 55 s, 21 Agustus 2026)], [166 (83 S1 + 83 S2)], [0], [*0,0*],
  ),
  [Lembar pengukuran D --- rasio payload rusak yang lolos],
  "tbl:m07b-ukur-d",
)

== Analisis

+ Dari @tbl:m07b-ukur-b, sebutkan dua kemungkinan penyebab master Raspberry Pi
  memiliki sebaran durasi siklus lebih rapat daripada master Arduino, dan
  jelaskan mengapa `POLL_TIMEOUT` yang longgar (500 ms) membuat perbedaan itu
  tidak pernah terlihat pada durasi siklus akhir.
+ Dari @tbl:m07b-ukur-c, hitung anggaran waktu tunggu sesungguhnya (bukan naif)
  menggunakan waktu udara jawaban dari bagian Dasar Teori M05, ditambah waktu
  udara 2 byte checksum. Apakah nilai ambang yang ditemukan cocok dengan
  hitungan itu?
+ Pada EXP-03, mengapa siklus pertama setelah master baru dinyalakan bisa
  mencatat kedua slave gagal sekaligus, dan berapa perkiraan durasinya
  dibandingkan satu slave gagal?
+ Bandingkan @tbl:m07b-ukur-d (CRC aktif) dengan lembar pengukuran D pada
  Modul 07 (CRC mati, 0,74 % dan 0,00 % pada sesi berbeda). Rasio pada varian
  ini seharusnya turun ke nol --- jelaskan mengapa CRC mengubah _kelas_
  kegagalannya, bukan menghilangkan kerusakan paket itu sendiri (paket yang
  sama tetap rusak di udara; yang berubah hanya siapa yang membuangnya dan
  kapan).
+ Dengan CRC aktif, `[WARN] Balasan tidak valid` semestinya tidak pernah muncul
  lagi --- payload rusak sekarang tercatat sebagai `[FAIL]`, sama dengan slave
  yang benar-benar diam. Usulkan satu cara membedakan "slave diam" dari
  "jawaban dibuang karena CRC gagal" dari sisi statistik master saja, tanpa
  mematikan kembali CRC.
+ Bandingkan pekerjaan memindahkan master ke Raspberry Pi dengan pekerjaan
  memindahkan protokol seluruhnya ke LoRaWAN. Sebutkan satu keuntungan dan satu
  kerugian pendekatan "gateway custom" dibanding memakai protokol siap pakai.

== Concept Check

+ Mengapa firmware slave tidak perlu tahu bahwa masternya sekarang Raspberry
  Pi, bukan Arduino?
+ Sebutkan dua cara mengorelasikan log dari dua mesin yang tidak berbagi jam,
  selain nomor urut payload.
+ Mengapa `POLL_TIMEOUT` tidak menghitung waktu udara `POLL` itu sendiri?
  Fungsi mana di `master.py` yang menjadi penyebabnya?
+ Apa yang terjadi pada paket yang payload-nya rusak satu bit ketika CRC
  payload *aktif*, dan pada tahap mana paket itu dibuang --- sebelum atau
  sesudah `parsePacket()` mengembalikan nilai bukan nol?
+ Satu baris `LoRa.enableCrc()` di slave dan satu pemanggilan `enableCrc()` di
  master sudah cukup mengubah perilaku ini. Mengapa perbaikan sesederhana itu
  tetap dianggap "membatalkan klaim identik dengan M05" pada modul dasarnya?
+ Apa perbedaan mendasar antara "slave tidak menjawab" dan "jawaban dibuang
  karena CRC gagal" dari sudut pandang radio, dan mengapa master saat ini masih
  tidak membedakan keduanya dalam statistik `OK` dan `FAIL` meskipun `[WARN]`
  sudah tidak pernah muncul lagi?

== Challenge (Tugas Modifikasi)

#tujuan-prak(2, [Memperbesar jaringan dan mempertajam diagnosis])[
  / CH-1 --- Slave ketiga: Tambahkan Uno ketiga dengan `SLAVE_ID=3`, lalu ukur
    pertambahan lama siklus dan bandingkan dengan hasil CH-1 pada M05 dan M07.

  / CH-2 --- Sudah diterapkan: Tantangan CH-2 Modul 07 (menyalakan CRC) sudah
    diterapkan di modul ini --- lihat `src/slave/main.cpp` dan
    `src/master.py`/`cek_radio.py`. Trade-off-nya: klaim "identik dengan M05"
    tidak lagi berlaku secara harfiah untuk firmware slave, tetapi diagnosis
    kegagalan menjadi lebih jujur. Variasi lanjutan: ukur ulang
    @tbl:m07b-ukur-d dan EXP-04 di sini sendiri, karena keduanya belum diukur
    ulang pada sesi modifikasi ini.
]

#tujuan-prak(3, [Memanfaatkan informasi yang baru tersedia])[
  / CH-3 --- Bedakan "diam" dan "dibuang CRC": Ubah `pollSlave()` di
    `master.py` agar mencatat statistik terpisah untuk "tidak menjawab sama
    sekali" versus "menjawab tapi dibuang radio karena CRC gagal" --- pada
    varian ini `IRQ_CRC_ERROR` di `parsePacket()` sudah membedakan keduanya di
    level register, tinggal dipropagasikan ke statistik. Ukur apakah rasio
    keduanya berubah seiring durasi sesi.

  / CH-4 --- Jadwal adaptif lintas platform: Port ide CH-4 M05 ke `master.py`,
    lalu ukur perbaikan durasi siklus saat satu node mati.

  / CH-5 --- Korelasi RSSI lintas mesin: Jalankan
    `lora_monitor.py --out sesi.csv` di laptop bersamaan dengan `master.py` di
    Raspberry Pi selama sepuluh menit, gabungkan kedua rekaman berdasarkan
    nomor urut, lalu buat satu grafik RSSI dari kedua arah terhadap waktu.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- mengapa slave tidak perlu tahu platform master,
  anggaran waktu sesungguhnya `POLL_TIMEOUT`, konsekuensi CRC aktif dibanding
  CRC mati.
+ Bukti `diff` firmware slave terhadap varian Modul 07, beserta penjelasan
  mengapa satu baris itu cukup mengubah perilaku perangkat keras.
+ Hasil eksperimen --- keluaran terminal EXP-01 sampai EXP-04 dari kedua sisi
  beserta checkpoint, dan hasil `cek_radio.py`.
+ Data pengukuran --- @tbl:m07b-ukur-a sampai @tbl:m07b-ukur-d, disertai
  perbandingan eksplisit terhadap baseline Modul 07.
+ Analisis dan concept check, termasuk hitungan anggaran waktu `POLL_TIMEOUT`
  yang sudah memperhitungkan 2 byte checksum.
+ Challenge --- minimal CH-1 dan CH-3.
+ Kesimpulan yang disusun sendiri mengenai harga dan manfaat menyalakan CRC
  payload pada jaringan LoRa mentah.
