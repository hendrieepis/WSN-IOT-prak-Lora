// ============================================================================
// Modul 07 — Gateway Linux Menjadwalkan Node Arduino
// Sumber: Modul07_rpi_master_slave/README.md; listing kode dibaca langsung dari
//         salinan berkas sumber di assets/code/Modul07_rpi_master_slave/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist
#import "../config.typ": edisi_buku

#chapter("Modul 07 — Gateway Linux Menjadwalkan Node Arduino", l: "bab:modul-07")

#identitas-modul(
  "Modul 07",
  [Move the Scheduler to Linux --- Gateway Linux Menjadwalkan Node Arduino],
  [Raspberry Pi + LoRa GPS HAT v1.4 dan 2 × Arduino Uno + LoRa Shield v1.2 ·
   topologi bintang, 3 node · polling terjadwal · level Advanced ·
   3 × 50 menit · folder kode `Modul07_rpi_master_slave`],
)

#pengantar([Gambaran Umum])[
Modul 07 dirancang untuk tiga pertemuan (3 × 50 menit) pada tingkat lanjut, dan
menutup arc pertama. Misinya memindahkan *master* Modul 05 dari Arduino Uno ke
Raspberry Pi tanpa mengubah *satu baris pun* firmware slave --- membentuk
topologi gateway yang lazim di dunia nyata: satu komputer Linux yang
menjadwalkan sekumpulan node mikrokontroler murah lewat radio, dikendalikan
dari jarak jauh lewat SSH.
]

== Pendahuluan

Percobaan memakai satu Raspberry Pi bershield Dragino LoRa GPS HAT v1.4 sebagai
master dan dua Arduino Uno bershield Dragino LoRa v1.2 sebagai slave, sama
persis dengan perangkat keras slave Modul 05.

Modul ini adalah pertemuan dua kemampuan yang dibangun terpisah. Modul 05
membangun *penjadwalan*: pengalamatan aplikasi, round-robin, batas waktu per
node, statistik terpisah. Modul 06 membangun *driver telanjang*: cara memegang
register SX1276 langsung dari Python lewat `spidev` dan `RPi.GPIO`, dengan nama
fungsi yang sengaja meniru API sandeepmistry (`beginPacket`, `endPacket`,
`parsePacket`, `packetRssi`). Modul ini menggabungkan keduanya: `src/master.py`
adalah penjadwal round-robin Modul 05, ditulis ulang di atas driver telanjang
Modul 06. Kontrak datanya --- `POLL:<id>` dan `S<id>:DATA:<n>` --- tidak
berubah sedikit pun, dan itulah yang membuat firmware slave dapat dipakai ulang
tanpa modifikasi.

Prasyaratnya adalah M05 untuk logika penjadwalan dan M06 untuk driver
telanjang. Yang dibangun di sini adalah pembuktian bahwa keduanya dapat
disatukan lintas platform: master berganti dari C++/AVR ke Python/Linux, slave
tidak menyadarinya sama sekali. Yang juga dibangun --- dan tidak pernah muncul
di modul-modul satu mesin sebelumnya --- adalah *korelasi log lintas dua
komputer independen*: master direkam di Raspberry Pi lewat SSH, slave direkam
di laptop pengembang lewat USB, dan kedua rekaman tidak berbagi jam sama
sekali. Isinya, bukan cap waktunya, yang membuktikan keduanya benar-benar
saling bicara.

*Peta modul LoRa (penutup arc pertama)*

#tbl(
  table(
    columns: (auto, 1fr),
    align: (center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Fokus (yang ditumpuk di atas modul sebelumnya)]),
    [01], [Tautan satu arah terbentuk; RSSI dan SNR terbaca],
    [02], [Penerimaan lewat interrupt --- `loop()` tidak lagi menunggu],
    [03], [Dua arah bergantian di atas radio half-duplex],
    [04], [Setiap pengiriman diketahui hasilnya: ACK, timeout, statistik],
    [05], [Banyak node --- hak bicara dijadwalkan agar tidak bertabrakan],
    [06], [Isi `LoRa.begin()` tidak pernah terlihat --- register dipegang langsung],
    [*07 (ini)*], [*Penjadwal pindah ke gateway Linux; sisi node tidak berubah sama sekali*],
  ),
  [Peta modul pada arc pertama seri LoRa],
  "tbl:m07-peta",
)

*Kontrak data lab ini.* Sama persis dengan Modul 05: perintah master berbentuk
`POLL:<id>`, jawaban slave berbentuk `S<id>:DATA:<n>`. Tidak ada satu byte pun
yang berubah di udara --- yang berganti hanya bahasa dan platform yang menyusun
serta membaca byte itu. Perbedaan halus satu-satunya ada di pesan pembuka
Serial slave, yang sekarang menyebut `"Master (Raspberry Pi)"`.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Memindahkan penjadwal ke gateway Linux tanpa menyentuh node])[
  + Membuktikan dengan `diff` bahwa memindahkan master ke platform lain tidak
    menuntut perubahan apa pun pada firmware slave, dan menjelaskan properti
    desain yang membuat itu mungkin.
  + Menerapkan ulang logika penjadwalan round-robin Modul 05 di atas driver
    SX1276 telanjang Modul 06, memakai `spidev` dan `RPi.GPIO` atau
    `rpi-lgpio`.
  + Mengkorelasikan log dari dua mesin yang tidak berbagi jam --- satu direkam
    lewat SSH di Raspberry Pi, satu lewat USB lokal --- berdasarkan isi pesan,
    bukan cap waktu.
  + Menjelaskan mengapa mematikan CRC payload membuat paket rusak lolos ke
    lapisan aplikasi sebagai kegagalan yang salah didiagnosis, dan mengukur
    seberapa sering itu terjadi.
  + Menelusuri anggaran waktu sesungguhnya di balik `POLL_TIMEOUT` --- bagian
    siklus mana yang benar-benar dihitungnya --- lalu memakainya untuk
    menjelaskan letak sesungguhnya ambang kegagalan pada EXP-04.
]

*Kriteria keberhasilan*

#checklist((
  [`master.py` berhasil memanggil kedua slave Uno bergiliran tanpa mengubah
   satu baris pun firmware slave --- dibuktikan dengan `diff` terhadap
   `Modul05_lora_master_slave/src/slave/main.cpp`.],
  [`cek_radio.py` membaca balik register SX1276 di Raspberry Pi dan hasilnya
   dibandingkan dengan konfigurasi yang dimaksud.],
  [Satu sesi log master (Raspberry Pi) dan log slave (laptop) dikorelasikan
   lewat isi pesan, bukan lewat waktu perekaman.],
  [Slave dimatikan secara fisik saat sistem berjalan (EXP-03); master tetap
   melayani slave lain dan pulih otomatis begitu slave kembali.],
  [Ambang kegagalan `POLL_TIMEOUT` ditemukan dalam rentang beberapa milidetik,
   dan letaknya dijelaskan lewat anggaran waktu siklus, bukan hanya dicatat
   sebagai angka.],
))

== Dasar Teori (Secukupnya)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [Gateway], [Node yang menjadwalkan jaringan radio dari komputer bertenaga penuh, terpisah dari node yang dijadwalkannya. Di sini: Raspberry Pi.],
    [`spidev`], [Antarmuka kernel Linux ke SPI perangkat keras --- satu-satunya jalan bicara Python ke SX1276.],
    [`RPi.GPIO` / `rpi-lgpio`], [Kendali pin NSS/RESET dan pembacaan DIO0. Pi 5 memakai chip GPIO baru (RP1) yang butuh `rpi-lgpio` sebagai pengganti drop-in.],
    [Jalankan lewat SSH], [Master tidak punya layar sendiri; seluruh interaksi --- unggah kode, jalankan, hentikan --- dilakukan dari terminal jarak jauh.],
    [CRC payload], [Pemeriksaan keutuhan data oleh radio sendiri. *Mati* pada modul ini di kedua sisi --- konsekuensinya dibahas di bagian Percobaan.],
    [Anggaran `POLL_TIMEOUT`], [Bagian siklus yang benar-benar ditunggu batas waktu. TX `POLL` bersifat blocking dan selesai *sebelum* penghitung waktu mulai berjalan, sehingga anggarannya jauh lebih sempit dari dugaan naif.],
    [Korelasi log lintas mesin], [Membuktikan dua rekaman dari komputer berbeda menggambarkan peristiwa yang sama, memakai isi pesan (nomor urut, payload) sebagai pengikat karena keduanya tidak berbagi jam.],
  ),
  [Istilah kerja Modul 07],
  "tbl:m07-istilah",
)

*Mengapa firmware slave tidak perlu tahu siapa master-nya.* Slave hanya
mendengar dua hal: `POLL:<id>` yang cocok dengan nomornya, dan segala sesuatu
yang lain untuk diabaikan. Ia tidak pernah memeriksa dari mana `POLL` itu
berasal, apalagi platform apa yang mengirimkannya. Selama pengirim baru
menghasilkan bentuk gelombang yang identik --- frekuensi, SF, BW, CR yang sama
--- SX1276 di sisi slave tidak dapat membedakan apakah lawan bicaranya Arduino
atau Raspberry Pi. Inilah properti yang membuat pemindahan master menjadi
mungkin tanpa sentuhan pada slave.

*Mengapa anggaran `POLL_TIMEOUT` lebih sempit dari dugaan.* Intuisi naif: batas
waktu 500 ms harus menampung waktu udara `POLL` (#sym.plus.minus 31 ms) *dan*
waktu udara jawaban (#sym.plus.minus 36--41 ms), sehingga ambang kegagalan
diperkirakan baru muncul di atas 70-an ms. Kenyataannya, `transmit(pollMsg)` di
`pollSlave()` bersifat blocking --- ia baru kembali setelah `IRQ_TX_DONE`
menyala, yaitu setelah `POLL` selesai mengudara. Penghitung waktu
(`waitStart = time.monotonic()`) baru dimulai *sesudah* itu. Akibatnya jendela
yang sebenarnya ditunggu hanya: pemrosesan di slave + waktu udara jawaban +
deteksi RX di master --- jauh lebih sempit dari intuisi awal. Bagian Percobaan
mengukur persis di mana ambang itu berada.

*Sekuens yang diamati*

#diagram(```
   Raspberry Pi (master)         Slave 1 (Uno)              Slave 2 (Uno)
     |                             |                           |
  "POLL:1" ---------------------> tiba                     tiba juga
  (TX blocking, ~31ms)       cocok -> jawab            tidak cocok -> [IGNORE]
     |  waitStart mulai DI SINI    |                           |
  tunggu <= POLL_TIMEOUT           |                           |
     |  <----------- "S1:DATA:12" -+                           |
  catat OK                                                     |
     |                                                         |
  "POLL:2" ------------------------------------------------> tiba
     |                        [IGNORE]                    cocok -> jawab
  tunggu <= POLL_TIMEOUT                                        |
     |  <-------------------------------------- "S2:DATA:12" --+
  catat OK, cetak statistik, jeda CYCLE_INTERVAL, ulangi siklus
```.text, rapat: true)

== Topologi

#diagram(```
                    RASPBERRY PI (di ruang server)
                 +-----------------------------+
                 |  Raspberry Pi 5 + LoRa GPS  |
                 |  HAT  --  src/master.py     |
                 |  dijalankan lewat SSH       |
                 |  polling round-robin        |
                 +--------------+--------------+
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
```.text)

#tbl(
  table(
    columns: (auto, 1.2fr, auto, 1.2fr, auto),
    align: (left, left, left, left, left),
    inset: (x: 0.5em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Environment / program], th[Build flag], th[Peran], th[Batas waktu]),
    [Master], [`src/master.py` (Raspberry Pi, lewat SSH)], [---], [Memanggil bergiliran, mencatat statistik], [500 ms per slave],
    [Slave 1], [`slave1`], [`-DSLAVE_ID=1`], [Menjawab `POLL:1`], [---],
    [Slave 2], [`slave2`], [`-DSLAVE_ID=2`], [Menjawab `POLL:2`], [---],
  ),
  [Peran tiap node Modul 07],
  "tbl:m07-topologi",
)

Tidak ada environment PlatformIO untuk master --- Python dijalankan langsung,
tidak dikompilasi. `platformio.ini` di modul ini hanya memuat kedua environment
slave. Kedua slave memakai *file source yang sama*, `src/slave/main.cpp`,
identik dengan `Modul05_lora_master_slave/src/slave/main.cpp` kecuali komentar
dan satu baris pesan pembuka Serial.

== Alat yang Digunakan

Modul ini menggabungkan dua platform: Raspberry Pi 5 dengan Dragino LoRa GPS
HAT v1.4 sebagai master, dan dua Arduino Uno dengan Dragino LoRa Shield v1.2
sebagai slave --- perangkat keras slave sama persis dengan Modul 05.

#tbl(
  table(
    columns: (auto, 1fr, 1.4fr, auto),
    align: (center + horizon, left, left, center + horizon),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[No], th[Peralatan], th[Spesifikasi], th[Jumlah]),
    [1], [Raspberry Pi], [2 / 3 / 4 / 5 --- diuji pada *Pi 5*], [1],
    [2], [Dragino LoRa GPS HAT], [v1.4, SX1276, 433 MHz], [1],
    [3], [Arduino Uno], [ATmega328P], [2],
    [4], [Dragino LoRa Shield], [v1.2, SX1276, 433 MHz], [2],
    [5], [Antena SMA], [*wajib terpasang sebelum diberi daya*, di ketiga board], [3],
    [6], [Kabel USB tipe B], [ke kedua Uno], [2],
    [7], [Akses jaringan ke Raspberry Pi], [SSH, kunci terpasang lebih disarankan daripada kata sandi], [1],
  ),
  [Alat dan bahan Modul 07],
  "tbl:m07-alat",
)

#penting[
  *Baud slave 115200*, sama seperti Modul 05. Master tidak memakai Serial
  Monitor sama sekali --- keluarannya langsung ke terminal SSH.
]

*Pemetaan pin HAT Raspberry Pi* (sisi master)

#tbl(
  table(
    columns: (auto, auto, auto, 1fr),
    align: (left, left, center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[LoRa GPS HAT], th[WiringPi], th[BCM GPIO], th[Padanan di shield Arduino]),
    [`LoRa_NSS`], [GPIO6], [*25*], [D10],
    [`RESET`], [GPIO0], [*17*], [D9],
    [`DIO0`], [GPIO7], [*4*], [D2],
    [SCK / MOSI / MISO], [GPIO14/12/13], [*11 / 10 / 9*], [D13 / D11 / D12],
  ),
  [Pemetaan pin HAT sisi master Modul 07],
  "tbl:m07-pin",
)

Kolom *BCM* adalah yang dipakai `src/master.py` (`GPIO.setmode(GPIO.BCM)`).
*NSS bukan CE0* --- HAT memakai GPIO 25 biasa sebagai chip select, sehingga
kode membuka SPI pada `(0, 0)` tetapi menggerakkan NSS sendiri di sekitar tiap
transaksi, persis seperti driver Arduino menggerakkan D10. Rincian lengkap
pemetaan pin ada pada @tbl:p-pin-hat di bab Pendahuluan.

#catatan[
  *Raspberry Pi 5* memakai chip GPIO baru (RP1) yang tidak didukung
  `RPi.GPIO`. Pasang `rpi-lgpio` sebagai gantinya --- nama modulnya sama
  (`import RPi.GPIO as GPIO`), sehingga tidak ada baris kode yang perlu diubah.
  Jangan memasang keduanya sekaligus. Lihat `requirements.txt`.
]

*Struktur proyek*

#diagram(```
Modul07_rpi_master_slave/
├── platformio.ini          ← hanya 2 environment: slave1, slave2
├── requirements.txt        ← spidev + RPi.GPIO (atau rpi-lgpio untuk Pi 5)
├── logserial.md            ← log referensi hasil uji perangkat, sangat lengkap
├── lora_monitor.py         ← dasbor 2 slave lokal + rekaman CSV (butuh `rich`)
├── cek_radio.py            ← baca balik register SX1276 di Raspberry Pi
├── upload_auto.py          ← deteksi port otomatis saat unggah slave
└── src/
    ├── master.py           ← penjadwal round-robin, dijalankan DI Raspberry Pi
    └── slave/main.cpp      ← satu source untuk kedua slave, identik M05
```.text)

== Kode Program

#sumber-kode("Modul07_rpi_master_slave",
  ("platformio.ini", "requirements.txt", "src/master.py",
   "src/slave/main.cpp", "cek_radio.py", "lora_monitor.py", "upload_auto.py"))

#kode-berkas("Modul07_rpi_master_slave/platformio.ini",
  [`platformio.ini` Modul 07 --- hanya environment `slave1` dan `slave2`],
  "lst:m07-ini",
  pecah: true,
)

#kode-berkas("Modul07_rpi_master_slave/requirements.txt",
  [`requirements.txt` Modul 07 --- paket Python sisi Raspberry Pi],
  "lst:m07-req",
  bahasa: "text",
  pecah: true,
)

#kode-berkas("Modul07_rpi_master_slave/src/master.py",
  [`src/master.py` --- penjadwal round-robin di atas driver register SX1276],
  "lst:m07-master",
  pecah: true,
)

#kode-berkas("Modul07_rpi_master_slave/src/slave/main.cpp",
  [`src/slave/main.cpp` --- firmware slave, identik dengan Modul 05],
  "lst:m07-slave",
  pecah: true,
)

#kode-berkas("Modul07_rpi_master_slave/cek_radio.py",
  [`cek_radio.py` --- baca balik register SX1276 di Raspberry Pi],
  "lst:m07-cek",
  pecah: true,
)

#kode-berkas("Modul07_rpi_master_slave/lora_monitor.py",
  [`lora_monitor.py` --- dasbor dua slave lokal dengan perekaman CSV],
  "lst:m07-monitor",
  pecah: true,
)

#kode-berkas("Modul07_rpi_master_slave/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah slave],
  "lst:m07-upload",
  pecah: true,
)

== Build, Flash, dan Menjalankan

*Build dan flash slave* --- dari laptop pengembang, seperti modul Arduino lain.

#keluaran("pio run -d Modul07_rpi_master_slave -e slave1 -t upload
pio run -d Modul07_rpi_master_slave -e slave2 -t upload")

*Menyiapkan Raspberry Pi* --- sekali per Pi.

#keluaran("ssh pi@<alamat-ip-pi>
sudo raspi-config                                    # Interface Options > SPI > Yes, lalu reboot
ls /dev/spi*                                         # harus muncul spidev0.0

pip3 install -r Modul07_rpi_master_slave/requirements.txt")

*Menjalankan master* --- *kedua slave lebih dahulu*, baru master, dan master
selalu di Raspberry Pi.

#keluaran("ssh pi@<alamat-ip-pi>
cd ~/Documents/WSN-IOT-prak-Lora/Modul07_rpi_master_slave/src
python3 -u master.py            # -u penting bila keluarannya dipipa/direkam")

`master.py` menerima `-h` atau `--help` yang mencetak parameter radio tanpa
menyentuh SPI dan GPIO --- aman dijalankan untuk memeriksa konfigurasi sebelum
sesi sungguhan. Tidak ada opsi lain; seluruh parameter (frekuensi, SF, BW,
`POLL_TIMEOUT`, `CYCLE_INTERVAL`) adalah konstanta di dalam berkas, sengaja
dibuat sama dengan slave.

*Memantau kedua slave dari laptop.* Selagi master berjalan di Pi lewat SSH,
kedua Uno tetap tersambung USB ke laptop pengembang. `lora_monitor.py` adalah
dasbor dua node dengan perekaman CSV, memerlukan pustaka `rich`.

#keluaran("pip install pyserial rich
python3 lora_monitor.py --s1 /dev/ttyACM0 --s2 /dev/ttyACM1
python3 lora_monitor.py --s1 /dev/ttyACM0 --s2 /dev/ttyACM1 --out sesi1.csv")

*Memverifikasi radio sebelum percobaan.* `cek_radio.py`, dijalankan di
Raspberry Pi, membaca balik register SX1276 setelah `loraBegin()` dan
konfigurasi --- bukan menyalin konstanta dari source, melainkan isi chip yang
sesungguhnya.

#keluaran("ssh pi@<alamat-ip-pi>
cd ~/Documents/WSN-IOT-prak-Lora/Modul07_rpi_master_slave
python3 cek_radio.py")

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada HAT dan kedua shield.],
  [SPI aktif di Raspberry Pi --- `ls /dev/spi*` menampilkan `spidev0.0`.],
  [`spidev` dan `RPi.GPIO` (atau `rpi-lgpio` pada Pi 5) sudah terpasang di Pi.],
  [`pio device list` dijalankan di laptop, kedua port Uno dicatat dan diisikan
   ke `platformio.ini`.],
  [SSH ke Raspberry Pi sudah teruji sebelum sesi dimulai --- jangan
   mendiagnosis masalah jaringan di tengah sesi terjadwal.],
  [Label fisik ditempel: SLAVE 1, SLAVE 2. Master tidak perlu label --- hanya
   ada satu Raspberry Pi.],
))

== Percobaan

=== EXP-01 --- Siklus Pertama Lintas Platform

Unggah kedua slave, jalankan `cek_radio.py` untuk memastikan register chip
sesuai, lalu jalankan `master.py` dan amati siklus pertama pada *kedua sisi*:
terminal SSH di Raspberry Pi, dan serial kedua Uno di laptop.

*Expected output --- master (Raspberry Pi)*

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
========================================")

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Isi `MODEM_CFG_2` menurut `cek_radio.py` (SF, CRC)], [#isian],
    [Nomor siklus pertama yang lengkap tanpa `FAIL`], [#isian],
    [RSSI master dari S1 / S2 (dBm)], [#isian],
    [Jumlah `[IGNORE]` per siklus di tiap slave], [#isian],
  ),
  [Lembar pengamatan EXP-01],
  "tbl:m07-exp01",
)

*Verifikasi kesamaan kode* --- bandingkan `src/slave/main.cpp` di modul ini
dengan `Modul05_lora_master_slave/src/slave/main.cpp` memakai `diff`. Jawab:
berapa banyak baris yang berbeda, apa isinya, dan mengapa tidak satu pun di
antaranya menyentuh logika penyaringan `POLL:<SLAVE_ID>`?

#checkpoint[
  Ketiga node mencetak `OK`, tiap slave menampilkan tepat satu `[RX]` dan dua
  `[IGNORE]` per siklus (satu untuk `POLL` milik node lain, satu untuk jawaban
  node lain), dan `diff` menunjukkan hanya komentar serta satu baris pesan
  pembuka yang berbeda dari M05. Bila jumlah baris beda lebih dari itu, ada
  perubahan tak sengaja yang perlu diperiksa sebelum melanjutkan.
]

=== EXP-02 --- Statistik dan Lama Siklus Lintas Mesin

Rekam *bersamaan* selama minimal 50 detik: terminal SSH master di Raspberry Pi,
dan kedua serial slave di laptop lewat `lora_monitor.py`. Dua rekaman ini
berasal dari dua komputer yang *tidak berbagi jam* --- korelasikan lewat nomor
`Data:` dan `RX#`, bukan cap waktu.

*Expected output --- master*

#keluaran("========================================
=== CYCLE 40 ===
[TX] POLL:1
[RX] S1:DATA:40 | RSSI: -60 dBm | SNR: 14.0 dB
[TX] POLL:2
[RX] S2:DATA:40 | RSSI: -58 dBm | SNR: 14.1 dB
--- STATISTIK ---
S1: OK=39 | FAIL=1 | Data: 40
S2: OK=40 | FAIL=0 | Data: 40
Durasi siklus: 145 ms
========================================")

*Data capture*

#tbl(
  table(
    columns: (1.5fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Jumlah siklus dalam jendela rekaman], [#isian],
    [Durasi siklus min / maks / rata-rata saat sehat (ms)], [#isian],
    [Durasi siklus saat satu poll gagal (ms)], [#isian],
    [`RX#` terakhir slave 1 / slave 2 (log lokal) vs `Data:` terakhir master], [#isian],
    [SNR arah slave#sym.arrow master vs master#sym.arrow slave --- simetris?], [#isian],
  ),
  [Lembar pengamatan EXP-02],
  "tbl:m07-exp02",
)

#buka-abstraksi[
  Cari satu siklus di mana `OK` master lebih kecil daripada `RX#` slave pada
  nomor yang sama (misalnya `S1: OK=39` sementara log lokal Slave 1 sudah
  mencetak `RX#: 40`). Jawab: apa yang terjadi pada jawaban itu di udara, dan
  mengapa fakta bahwa CRC payload *mati* (lihat `cek_radio.py`) relevan dengan
  jawabanmu?
]

#checkpoint[
  Angka `Data:` master mengikuti `RX#` slave secara berurutan, dengan
  kemungkinan `FAIL` sesekali yang *tidak pernah* membuat `Data:` melompat
  mundur. Durasi siklus sehat sangat rapat (sebaran hanya sekitar 1 ms pada
  Raspberry Pi 5) --- jauh lebih rapat daripada master Arduino M05, karena Pi
  tidak pernah benar-benar berebut CPU pada beban seringan ini.
]

=== EXP-03 --- Satu Node Hilang

Cabut kabel USB Slave 2 *secara fisik* (bukan hanya menutup port serial ---
Uno bershield LoRa memakai daya dari USB, sehingga mencabutnya mematikan
seluruh node termasuk radionya) selama `master.py` berjalan, tunggu setidaknya
20 siklus, lalu pasang kembali.

*Expected output --- master, tepat setelah kabel dicabut*

#keluaran("=== CYCLE 28 ===
[TX] POLL:1
[RX] S1:DATA:27 | RSSI: -70 dBm | SNR: 13.0 dB
[TX] POLL:2
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
S1: OK=27 | FAIL=1 | Data: 27
S2: OK=0 | FAIL=27 | Data: None
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
    [Apakah Slave 1 terpengaruh matinya Slave 2? (cek log lokal S1)], [#isian],
    [Berapa siklus sampai `OK` Slave 2 bertambah lagi setelah dipasang], [#isian],
    [`dataCounter` Slave 2 setelah dipasang kembali --- mulai dari berapa, dan apa artinya], [#isian],
  ),
  [Lembar pengamatan EXP-03],
  "tbl:m07-exp03",
)

#checkpoint[
  Durasi siklus melonjak dari kondisi sehat menjadi mendekati `POLL_TIMEOUT`
  penuh ditambah overhead, sementara Slave 1 sama sekali tidak terganggu ---
  masih menjawab tiap `POLL:1` seperti biasa. Begitu Slave 2 tersambung
  kembali, ia memulai `dataCounter` dari 1: bukti bahwa yang terjadi adalah
  *reboot penuh*, bukan sekadar port serial yang terputus. Pemulihan di sisi
  master terjadi otomatis pada siklus berikutnya, tanpa intervensi apa pun.
]

=== EXP-04 --- Menekan Batas Waktu Sampai Rusak

Ambang kegagalan `POLL_TIMEOUT` naif diperkirakan di atas 70 ms (waktu udara
`POLL` + waktu udara jawaban). Percobaan ini menunjukkan dugaan itu keliru.
Ubah `POLL_TIMEOUT` di *salinan* `master.py` (jangan ubah `src/master.py`
asli), jalankan tiap nilai selama 60 detik, mulai dari 500 ms turun bertahap
sampai keberhasilan jatuh ke nol.

*Expected output --- pada nilai yang sudah terlalu kecil*

#keluaran("=== CYCLE 12 ===
[TX] POLL:1
[FAIL] Slave 1 tidak merespon!
[TX] POLL:2
[FAIL] Slave 2 tidak merespon!
--- STATISTIK ---
S1: OK=0 | FAIL=12 | Data: None
S2: OK=0 | FAIL=12 | Data: None")

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
  [Lembar pengamatan EXP-04 --- menekan batas waktu],
  "tbl:m07-exp04",
)

#checkpoint[
  Ambangnya adalah *tebing*, bukan lereng: keberhasilan bertahan tinggi sampai
  satu titik, lalu jatuh mendekati nol dalam rentang sempit beberapa
  milidetik. Titik itu jauh *lebih rendah* daripada dugaan naif 70-an ms,
  karena `transmit(pollMsg)` bersifat blocking dan waktu udara `POLL` sudah
  "dibayar" di dalamnya, sebelum penghitung waktu mulai berjalan --- lihat
  kembali bagian Dasar Teori. Jelaskan letak tebing itu memakai anggaran waktu
  yang sesungguhnya, bukan anggaran naif.
]

=== Verifikasi Radio (Dijalankan Sebelum EXP-01)

`cek_radio.py` membaca balik register SX1276 di Raspberry Pi setelah
`loraBegin()` dan konfigurasi.

#keluaran("REG_VERSION   : 0x12   (0x12 = SX1276/77/78/79)
FREKUENSI     : 433.000000 MHz   (target 433.000000, selisih +0.0 Hz)
MODEM_CFG_1   : 0x72 -> BW=125 kHz | CR=4/5 | header=explicit
MODEM_CFG_2   : 0x70 -> SF7 | CRC payload=MATI
PA_CONFIG     : 0x8f -> PA_BOOST, power=17 dBm")

#peringatan[
  *CRC payload mati di kedua sisi.* `LoRa.begin()` milik sandeepmistry (dipakai
  slave) tidak mengaktifkan CRC kecuali diminta lewat `LoRa.enableCrc()`, dan
  `master.py` juga tidak menyalakannya. Konsekuensinya: paket dengan payload
  rusak *tetap lolos* ke lapisan aplikasi sebagai paket sah, karena bendera
  `IRQ_CRC_ERROR` tidak pernah diminta menyala. Kegagalan seperti itu tercatat
  sebagai `[WARN] Balasan tidak valid` lalu `[FAIL]` --- diagnosis yang
  menunjuk ke arah yang salah sama sekali, seolah slave tidak merespons padahal
  slave sudah menjawab benar.
]

=== Verifikasi Perangkat Keras (Log Referensi)

Dijalankan pada satu Raspberry Pi 5 + LoRa GPS HAT v1.4 dan dua Arduino Uno +
Dragino Shield v1.2, 433 MHz, jarak #sym.plus.minus 30 cm. Log lengkap ada di
`logserial.md`.

#tbl(
  table(
    columns: (1.3fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil terukur]),
    [Siklus dalam 50 detik (EXP-02)], [*76*],
    [Durasi siklus sehat min/maks/rata-rata], [*144 / 145 / 145,0 ms*],
    [Sebaran durasi siklus (Pi 5) vs master Arduino (M05)], [*1 ms* vs 7 ms --- Pi justru lebih rapat],
    [EXP-03: durasi siklus saat satu slave mati], [*604--606 ms*, rata-rata 621,4 ms (27 siklus berturut-turut)],
    [EXP-03: pertambahan akibat satu node mati], [*+460 ms* #sym.approx `POLL_TIMEOUT` dikurangi waktu jawaban sehat --- hampir sama dengan +459 ms di M05],
    [EXP-03: apakah node sehat ikut terganggu?], [tidak --- 0 dari 27 siklus],
    [EXP-03: pemulihan setelah node kembali], [seketika, siklus berikutnya],
    [EXP-04: ambang kegagalan], [tebing di *40--45 ms* --- bukan #sym.tilde.op 70 ms seperti dugaan naif],
    [EXP-04: reproduksibilitas ambang], [sempurna pada 6 sesi ulangan (3× titik aman, 3× titik gagal)],
    [Payload rusak lolos (CRC mati)], [0,74 % pada 8 sesi pertama, 0,00 % pada 4 sesi berikutnya --- sporadis, sumbernya belum diketahui],
  ),
  [Hasil verifikasi perangkat keras Modul 07],
  "tbl:m07-verifikasi",
)

#keluaran("Environment    Status    Flash
slave1         SUCCESS   26.4% (8.522 B)
slave2         SUCCESS   26.4% (8.522 B)")

Master tidak dikompilasi --- Python dijalankan langsung di Raspberry Pi. Kedua
slave berukuran identik, bukti keduanya berasal dari source yang sama dan hanya
berbeda `SLAVE_ID`.

#catatan[
  *Temuan tambahan yang tidak diperbaiki secara sengaja.* Perbaikan CRC yang
  jelas --- `LoRa.enableCrc()` di slave dan menyalakan bit yang sepadan di
  `REG_MODEM_CONFIG_2` pada master --- *sengaja tidak diterapkan*, karena
  menyentuh firmware slave akan membatalkan klaim utama modul ini bahwa slave
  identik dengan M05. Rincian investigasinya (pola byte yang rusak, pengujian
  yang menyingkirkan SPI dan FIFO sebagai penyebab) ada di `logserial.md`,
  bagian "Temuan --- Payload rusak lolos karena CRC mati". Tantangan untuk
  menyalakannya sendiri dan mengukur akibatnya ada di CH-2.
]

// Log serial lengkap dari Modul07_rpi_master_slave/logserial.md. Hanya dicetak pada
// edisi dosen agar tidak disalin mahasiswa sebagai hasil laporan
// (lihat config.typ).
#if edisi_buku == "dosen" [
  === Log Serial Terverifikasi

  Log serial lengkap hasil uji pada board nyata, bukan contoh. Bagian ini
  hanya dicetak pada edisi dosen.

  Hasil aktual dari perangkat. Baud *115200*, frekuensi *433 MHz*, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `POLL_TIMEOUT` 500 ms, `CYCLE_INTERVAL` 500 ms. Ketiga node di satu meja, jarak ±30 cm.

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
    [Log serial Modul 07: Board & Port],
    "tbl:m07-log-1",
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
    [Log serial Modul 07: Verifikasi radio sebelum percobaan],
    "tbl:m07-log-2",
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
    [Log serial Modul 07: EXP-01 — Siklus Pertama Lintas Platform],
    "tbl:m07-log-3",
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
    [Log serial Modul 07: EXP-02 — Statistik dan Lama Siklus],
    "tbl:m07-log-4",
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
    [Log serial Modul 07: Lama siklus jauh lebih rapat daripada dugaan README],
    "tbl:m07-log-5",
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
    [Log serial Modul 07: Lama siklus jauh lebih rapat daripada dugaan README],
    "tbl:m07-log-6",
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
    [Log serial Modul 07: EXP-03 — Satu Node Hilang],
    "tbl:m07-log-7",
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
    [Log serial Modul 07: EXP-04 — Menekan Batas Waktu Sampai Rusak],
    "tbl:m07-log-8",
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
    [Log serial Modul 07: EXP-04 — Menekan Batas Waktu Sampai Rusak],
    "tbl:m07-log-9",
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
    [Log serial Modul 07: Temuan — Payload rusak lolos karena CRC mati],
    "tbl:m07-log-10",
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
    [Log serial Modul 07: Temuan — Payload rusak lolos karena CRC mati],
    "tbl:m07-log-11",
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
    [Log serial Modul 07: Temuan — Payload rusak lolos karena CRC mati],
    "tbl:m07-log-12",
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
    [Log serial Modul 07: Verifikasi ulang — 21 Agustus 2026],
    "tbl:m07-log-13",
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
  "tbl:m07-ukur-a",
)

*B. Perbandingan platform master* --- bandingkan langsung dengan
`Modul05_lora_master_slave/logserial.md`.

#tbl(
  table(
    columns: (1.2fr, 1.2fr, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Ukuran], th[Master Raspberry Pi 5 (modul ini)], th[Master Arduino Uno (M05)]),
    [Durasi siklus minimum (ms)], [#isian], [147],
    [Durasi siklus maksimum (ms)], [#isian], [154],
    [Durasi siklus rata-rata (ms)], [#isian], [152],
    [Sebaran (maks #sym.minus min, ms)], [#isian], [7],
  ),
  [Lembar pengukuran B --- perbandingan platform master],
  "tbl:m07-ukur-b",
)

*C. Ambang `POLL_TIMEOUT`* --- ulangi EXP-04 tiga kali pada dua titik: nilai
terkecil yang masih 100 % andal, dan nilai terbesar yang sudah gagal total.

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
  [Lembar pengukuran C --- ambang `POLL_TIMEOUT`],
  "tbl:m07-ukur-c",
)

*D. Rasio payload rusak lolos* --- hitung dari sesi gabungan EXP-02 dan EXP-04
milik sendiri.

#tbl(
  table(
    columns: (auto, 1fr, 1.3fr, 1fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Sesi], th[Paket diterima], th[Paket `[WARN] Balasan tidak valid`], th[Rasio (%)]),
    [1], [#isian], [], [],
    [2], [#isian], [], [],
  ),
  [Lembar pengukuran D --- rasio payload rusak lolos],
  "tbl:m07-ukur-d",
)

== Analisis

+ Dari @tbl:m07-ukur-b, sebutkan dua kemungkinan penyebab master Raspberry Pi
  memiliki sebaran durasi siklus lebih rapat daripada master Arduino, dan
  jelaskan mengapa `POLL_TIMEOUT` yang longgar (500 ms) membuat perbedaan itu
  tidak pernah terlihat pada durasi siklus akhir.
+ Dari @tbl:m07-ukur-c, hitung anggaran waktu tunggu sesungguhnya (bukan naif)
  menggunakan waktu udara jawaban dari bagian Dasar Teori M05. Apakah nilai
  ambang yang ditemukan cocok dengan hitungan itu? Jelaskan selisihnya bila
  ada.
+ Pada EXP-03, mengapa siklus pertama setelah master baru dinyalakan bisa
  mencatat *kedua* slave gagal sekaligus, dan berapa perkiraan durasinya
  dibandingkan satu slave gagal?
+ Dari @tbl:m07-ukur-d, apakah rasio payload rusak berkorelasi dengan jumlah
  siklus dalam sesi, durasi sesi, atau tidak keduanya? Kaitkan jawabannya
  dengan status "belum diketahui" pada temuan CRC di `logserial.md`.
+ `master.py` menghitung `[WARN] Balasan tidak valid` sebagai `[FAIL]` yang
  sama dengan slave yang benar-benar tidak menjawab. Usulkan satu cara
  membedakan keduanya dari sisi statistik master saja, tanpa mengubah firmware
  slave.
+ Bandingkan pekerjaan memindahkan master ke Raspberry Pi (modul ini) dengan
  pekerjaan memindahkan protokol seluruhnya ke LoRaWAN. Sebutkan satu
  keuntungan dan satu kerugian pendekatan "gateway custom" dibanding memakai
  protokol siap pakai.

== Concept Check

+ Mengapa firmware slave tidak perlu tahu bahwa masternya sekarang Raspberry
  Pi, bukan Arduino?
+ Sebutkan dua cara mengorelasikan log dari dua mesin yang tidak berbagi jam,
  selain nomor urut payload.
+ Mengapa `POLL_TIMEOUT` tidak menghitung waktu udara `POLL` itu sendiri?
  Fungsi mana di `master.py` yang menjadi penyebabnya?
+ Apa yang terjadi pada paket yang payload-nya rusak satu bit ketika CRC
  payload mati, dan mengapa `parsePacket()` tetap menyerahkannya ke aplikasi?
+ Mengapa modul ini tidak menyalakan CRC meskipun penyebabnya jelas dan
  perbaikannya sederhana?
+ Apa perbedaan mendasar antara "slave tidak menjawab" (`[FAIL]`) dan "jawaban
  rusak" (`[WARN]`) dari sudut pandang radio, dan mengapa master saat ini tidak
  membedakan keduanya dalam statistik `OK` dan `FAIL`?

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Memperbesar jaringan dan mempertajam diagnosis])[
  / CH-1 --- Slave ketiga: Tambahkan Uno ketiga dengan `SLAVE_ID=3`: satu
    environment PlatformIO baru, dan penyesuaian `SLAVE_COUNT` serta pemanggilan
    `pollSlave(3, ...)` di `master.py`. Ukur pertambahan lama siklus dan
    bandingkan dengan hasil CH-1 pada M05.

  / CH-3 --- Bedakan FAIL dan WARN: Ubah `pollSlave()` di `master.py` agar
    mencatat statistik terpisah untuk "tidak menjawab sama sekali" versus
    "menjawab tapi rusak". Ukur apakah rasio keduanya berubah seiring durasi
    sesi.
]

#tujuan-prak(3, [Menutup celah yang sengaja dibiarkan])[
  / CH-2 --- Nyalakan CRC: Tambahkan `LoRa.enableCrc()` di
    `src/slave/main.cpp` *dan* set bit yang sepadan di `REG_MODEM_CONFIG_2`
    pada `master.py`. Jalankan ulang @tbl:m07-ukur-d dan bandingkan rasio
    payload rusak yang lolos. Perhatikan: ini mengubah firmware slave, sehingga
    klaim "identik dengan M05" tidak lagi berlaku --- jelaskan trade-off-nya di
    laporan.

  / CH-4 --- Jadwal adaptif lintas platform: Port ide CH-4 M05 (lewati slave
    yang gagal tiga kali berturut-turut, tengok kembali tiap sepuluh siklus) ke
    `master.py`. Ukur perbaikan durasi siklus saat satu node mati, bandingkan
    dengan hasil EXP-03.

  / CH-5 --- Korelasi RSSI lintas mesin: Jalankan
    `lora_monitor.py --out sesi.csv` di laptop bersamaan dengan `master.py` di
    Raspberry Pi selama sepuluh menit. Gabungkan kedua rekaman berdasarkan
    nomor urut, lalu buat satu grafik RSSI dari kedua arah (slave#sym.arrow
    master dan master#sym.arrow slave) terhadap waktu.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- mengapa slave tidak perlu tahu platform master,
  anggaran waktu sesungguhnya `POLL_TIMEOUT`, konsekuensi CRC mati.
+ Bukti `diff` bahwa firmware slave tidak berubah dari M05.
+ Hasil eksperimen --- keluaran terminal EXP-01 sampai EXP-04 dari *kedua
  sisi* (master di Raspberry Pi, slave di laptop) beserta checkpoint, dan hasil
  `cek_radio.py`.
+ Data pengukuran --- @tbl:m07-ukur-a sampai @tbl:m07-ukur-d.
+ Analisis dan concept check, termasuk hitungan anggaran waktu `POLL_TIMEOUT`.
+ Challenge --- minimal CH-1 dan CH-3.
+ Kesimpulan yang disusun sendiri mengenai apa yang berubah dan apa yang tidak
  berubah ketika penjadwal jaringan LoRa dipindahkan dari mikrokontroler ke
  gateway Linux.
