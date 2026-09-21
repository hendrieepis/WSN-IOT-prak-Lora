// ============================================================================
// Modul 07B — Gateway Linux Menjadwalkan Node Arduino (varian CRC aktif)
// Sumber: Modul07b_rpi_master_slave_crc/README.md; listing kode dibaca langsung
//         dari salinan berkas sumber di
//         assets/code/Modul07b_rpi_master_slave_crc/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist

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
