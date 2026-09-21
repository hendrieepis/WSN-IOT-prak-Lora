// ============================================================================
// Pendahuluan — konversi dari README.md pada akar repositori WSN-IOT-prak-Lora.
//
// Bab ini sengaja tidak diberi nomor agar Modul 01 tetap menjadi modul
// pertama. Seluruh isi dibungkus dalam satu blok konten sehingga aturan
// `set` di bawah (penomoran heading dan figure) hanya berlaku di bab ini.
// ============================================================================

#import "../lib/callouts.typ": penting, peringatan, catatan, tip
#import "../lib/helpers.typ": gbr, tbl, th, diagram, keluaran, kode, kode-berkas, gh, gh-folder, REPO

#[
#set heading(numbering: none)
// Tabel pada bab tanpa nomor diberi awalan "P" (Pendahuluan) supaya tidak
// tertulis sebagai "Tabel 0.1" akibat nomor bab yang belum berjalan.
#set figure(numbering: n => "P." + str(n))

= Pendahuluan <bab:pendahuluan>

== Tentang Lab Ini

Buku ini bukan kumpulan tutorial Arduino, melainkan buku kerja laboratorium.
Setiap modul merupakan satu misi rekayasa dengan target sukses yang terukur,
prosedur eksperimen yang tertulis, dan data yang harus dikumpulkan sendiri oleh
praktikan.

Fokusnya adalah *LoRa mentah* --- modulasi radio tanpa lapisan jaringan di
atasnya. Tidak ada proses join, tidak ada alamat, tidak ada koneksi, dan tidak
ada penjadwalan. Semua yang biasanya disediakan protokol harus dibangun sendiri
di lapisan aplikasi, satu per satu, dan setiap penambahan diukur akibatnya.
Justru di situlah nilai seri ini: praktikan menyaksikan sendiri masalah yang
selama ini disembunyikan protokol, sebelum memakai protokol yang
menyembunyikannya.

Lima modul pertama dikerjakan di atas Arduino Uno bershield Dragino LoRa v1.2.
Dua modul berikutnya berpindah ke Raspberry Pi bershield Dragino LoRa GPS HAT
v1.4 --- bukan sekadar berganti papan, melainkan dua pertanyaan lanjutan.
Modul 06 melepas library dan memegang register SX1276 langsung dari Python,
sehingga isi `LoRa.begin()` terlihat baris per baris. Modul 07 memindahkan
master jaringan Modul 05 ke Raspberry Pi tanpa mengubah firmware slave sama
sekali, membentuk topologi gateway yang lazim di dunia nyata. Chip radionya
tetap sama di seluruh seri, dan kesamaan itulah yang membuat kedua sisi dapat
dipasangkan silang.

Seri ini melengkapi lab WSN-IOT-prak yang membahas BLE, Zigbee, dan Thread.
Perbandingannya disengaja: di sana jaringan mengurus dirinya sendiri, di sini
tidak ada jaringan sama sekali.

== Struktur Setiap Modul

Seluruh modul memakai format yang sama, terdiri atas sebelas bagian seperti
pada @tbl:p-struktur-modul.

#tbl(
  table(
    columns: (auto, auto, 1fr),
    align: (center + horizon, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[No], th[Bagian], th[Isi]),
    [1], [*Pendahuluan*],
    [Identitas modul, keterkaitan dengan modul lain, prasyarat, dan apa yang dipakai lagi sesudahnya --- seluruhnya dalam bentuk kalimat, ditutup peta modul dan kontrak data],
    [2], [*Capaian Pembelajaran*],
    [Lima capaian *terukur* beserta kriteria keberhasilan],
    [3], [*Dasar Teori (secukupnya)*],
    [Hanya istilah yang dipakai di percobaan, beserta sekuens yang diamati],
    [4], [*Topologi*],
    [Diagram bernama board, peran tiap node],
    [5], [*Alat yang Digunakan*],
    [Platform, alat dan bahan, pemetaan pin, `platformio.ini`, pre-flight, perintah deploy],
    [6], [*Percobaan*],
    [EXP-01 sampai EXP-04 dengan *CHECKPOINT* di tiap tahap],
    [7], [*Pengukuran*],
    [Tabel yang diisi sendiri oleh praktikan],
    [8], [*Analisis*],
    [Pertanyaan yang hanya bisa dijawab dari tabel Pengukuran],
    [9], [*Concept Check*],
    [Pertanyaan konseptual, bukan hafalan],
    [10], [*Challenge*],
    [Tugas *modifikasi kode*, bukan "jelaskan hasilnya"],
    [11], [*Laporan*],
    [Daftar deliverable],
  ),
  [Sebelas bagian baku pada setiap modul praktikum],
  "tbl:p-struktur-modul",
)

Tiga hal membedakan format ini dari panduan praktikum biasa.

/ CHECKPOINT di tengah percobaan: Praktikan memverifikasi progres sebelum
  lanjut, bukan baru ketahuan salah di akhir sesi.

/ "Buka abstraksinya": Satu kotak per modul yang menyuruh praktikan membongkar
  satu baris kode yang tampak sepele --- menghubungkan API dengan apa yang
  sebenarnya terjadi di udara.

/ Percobaan yang sengaja dirusak: Beberapa modul meminta parameter diubah
  sampai komunikasi gagal (Modul 01 EXP-03, Modul 05 EXP-04), karena kegagalan
  yang terkendali mengajarkan lebih banyak daripada keberhasilan yang mulus.

== Keterkaitan Antar-Modul

Tiap modul menambahkan *satu* kemampuan yang hilang dari modul sebelumnya.

#diagram(```
M01 tautan terbentuk ─► M02 penerimaan tak memblokir ─► M03 dua arah
                                                            │
                            ┌───────────────────────────────┘
                            ▼
                    M04 hasil kirim diketahui ─► M05 banyak node dijadwalkan
                                                            │
                            ┌───────────────────────────────┘
                            ▼
                    M06 library dilepas ─► M07 penjadwal pindah ke gateway
                    (platform berganti)     (sisi node tidak berubah)
```.text, rapat: true)

#tbl(
  table(
    columns: (auto, 1.2fr, 1.2fr),
    align: (center + horizon, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Yang hilang di modul sebelumnya], th[Yang ditambahkan]),
    [01], [---], [Tautan radio, parameter, RSSI dan SNR],
    [02], [Penerima sibuk menunggu, paket terlewat], [Interrupt DIO0 + flag pattern],
    [03], [Data hanya mengalir satu arah], [Percakapan bergantian + auto-retry],
    [04], [Nasib paket tidak pernah diketahui], [ACK, timeout, statistik keberhasilan],
    [05], [Dua node tidak pernah berebut bicara], [Pengalamatan aplikasi + penjadwalan],
    [06], [Isi `LoRa.begin()` tidak pernah terlihat], [Register SX1276 langsung, Python di Linux, uji silang platform],
    [07], [Master mikrokontroler buntu di Serial Monitor], [Gateway Linux menjadwalkan node Arduino tanpa mengubah firmware-nya],
  ),
  [Kemampuan yang ditambahkan tiap modul pada arc pertama],
  "tbl:p-keterkaitan",
)

*Kontrak data yang konsisten.* Beberapa keputusan sengaja dipertahankan lintas
modul supaya datanya dapat dibandingkan, seperti tercantum pada
@tbl:p-kontrak-data.

#tbl(
  table(
    columns: (1.6fr, auto, 1.2fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Kontrak], th[Diperkenalkan], th[Dipakai lagi di]),
    [Nomor urut di dalam payload untuk menghitung loss], [M01 (`Hello LoRa #n`)], [M03, M04 (`DATA:n`), M05 (`S1:DATA:n`)],
    [Parameter radio baku SF7 / BW 125 kHz / CR 4/5 / 17 dBm], [M01], [M02--M05],
    [Identitas pengirim di dalam payload], [M03 (`DeviceA:`)], [M05 (`S1:`, `S2:`)],
    [Pencocokan permintaan dengan balasan], [M04 (`DATA:n` #sym.arrow.l.r `ACK:n`)], [M05, M07 (`POLL:n` #sym.arrow.l.r `S<n>:DATA:m`)],
    [RSSI dan SNR dicatat berpasangan], [M01], [seluruh modul],
    [Payload dua ruangan `NODE=,SEQ=,R1T=,R1H=,R2T=,R2H=`], [M08], [M08B, M08C, M10],
    [Balasan `ACK=<id>,SEQ=<n>`], [M08B], [M08C, M10],
  ),
  [Kontrak data yang dipertahankan lintas modul],
  "tbl:p-kontrak-data",
)

*Satu pengecualian yang disengaja: M09.* Modul CSMA/CA memakai payload yang
lebih pendek (`NODE=,SEQ=,T=,H=` --- satu sensor per node) dan *tanpa ACK sama
sekali*, meski M08B dan M08C sudah memilikinya. Itu bukan kelalaian: M09
mengukur satu variabel saja, yaitu efek mendengarkan kanal sebelum bicara, dan
ACK atau retry akan menutupi kegagalan yang justru sedang diukur. Pembandingnya
karena itu M08, bukan M08C --- dan M09 menyediakan pembanding itu di dalam
dirinya sendiri lewat `CS_MODE=2` (carrier sense dimatikan).

Konsekuensinya, *angka pengukuran modul awal dipakai lagi di modul akhir.* Loss
terhadap jarak dari M01 menjadi pembanding tingkat keberhasilan ACK di M04;
waktu pulang-pergi M03 menjadi dasar penentuan batas waktu di M04 dan M05.

Kontrak yang sama itu pula yang membuat dua modul terakhir arc pertama dapat
disambungkan silang ke modul awal. Payload M06 identik dengan M01
(`Hello LoRa #n`, SF7, BW 125 kHz), sehingga *sender Raspberry Pi dapat diuji
langsung terhadap receiver Arduino M01* dan sebaliknya --- percobaan inti M06.
Firmware slave M07 pun identik dengan slave M05 kecuali satu baris pesan
pembuka, dan kesamaan itu diperiksa dengan `diff` sebagai bagian dari laporan,
bukan sekadar dinyatakan.

== Daftar Modul

#tbl(
  table(
    columns: (auto, auto, 1fr, auto, auto, auto),
    align: (center + horizon, left, left, left, left, center + horizon),
    inset: (x: 0.5em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Folder], th[MISSION], th[Arah data], th[Mekanisme RX], th[Level]),
    [01], [`Modul01_lora_uart`], [Establish the Link], [satu arah], [polling], [Basic],
    [02], [`Modul02_lora_led_notif`], [Stop Waiting for Packets], [satu arah], [interrupt + flag], [Basic],
    [03], [`Modul03_lora_p2p`], [Take Turns Talking], [dua arah], [polling], [Intermediate],
    [04], [`Modul04_lora_ack`], [Know If It Arrived], [dua arah], [interrupt + timeout], [Intermediate],
    [05], [`Modul05_lora_master_slave`], [Schedule the Airwaves], [bintang, 3 node], [polling terjadwal], [Advanced],
    [06], [`Modul06_rpi_lora_python`], [Drop the Library], [satu arah], [polling register], [Intermediate],
    [07], [`Modul07_rpi_master_slave`], [Move the Scheduler to Linux], [bintang, 3 node], [polling terjadwal], [Advanced],
    [07B], [`Modul07b_rpi_master_slave_crc`], [Move the Scheduler to Linux --- varian CRC], [bintang, 3 node], [polling terjadwal + CRC payload], [Advanced],
    [08], [`Modul08_lora_aloha_tanpa_ack`], [Speak Freely, Collide Silently], [bintang, 2 node], [interrupt, tanpa balasan], [Intermediate],
    [08B], [`Modul08b_lora_aloha_ack`], [Finally Know], [bintang, 2 node], [interrupt + timeout], [Intermediate],
    [08C], [`Modul08c_lora_aloha_retry`], [Try Again, Randomly], [bintang, 2 node], [interrupt + timeout + retry], [Advanced],
    [09], [`Modul09_lora_csma_ca`], [Listen Before You Talk], [bintang, 2 node], [carrier sense + backoff], [Advanced],
    [10], [`Modul10_lora_slotted_aloha_tdma`], [Take a Number], [bintang, 2 node], [interrupt + SYNC + slot], [Advanced],
    [11], [`Modul11_lorawan_chirpstack`], [Let the Protocol Take Over], [bintang, 2 node + server], [LoRaWAN Class A (LMIC)], [Advanced],
  ),
  [Mission roster seluruh modul praktikum LoRa],
  "tbl:p-roster",
)

Modul 01--05 memakai Arduino Uno dengan Dragino LoRa Shield v1.2. Modul 06
memakai dua Raspberry Pi dengan LoRa GPS HAT v1.4. Modul 07 mencampur keduanya:
Raspberry Pi sebagai master, dua Arduino Uno sebagai slave.

*Cara membaca penomoran.* Angka adalah nomor modul; huruf di belakangnya
berarti modul itu *menumpuk langsung* di atas modul bernomor sama, bukan
pertemuan yang berdiri sendiri. M08 #sym.arrow M08B #sym.arrow M08C adalah tiga
langkah berturut-turut di atas topologi dan kontrak data yang sama, sedangkan
M07B adalah varian M07 dengan CRC payload diaktifkan.

*Arc kedua --- akses kanal tanpa penjadwal terpusat.* Modul 01--07 adalah satu
seri utuh yang berakhir di M07. Modul 08 dan seterusnya membuka arc baru di
atas Arduino Uno dengan Dragino LoRa Shield v1.2 (topologi sama seperti M05,
dua node dan satu gateway), yang sengaja *membalik* premis M05 dan M07:
alih-alih menjadwalkan giliran bicara dari pusat, node dibiarkan mengirim data
dummy suhu dan kelembaban dua ruangan kapan saja, dan setiap pertemuan
menambah *satu* lapisan kendali kanal. M08 mengirim bebas tanpa umpan balik
sama sekali, M08B menambahkan ACK, M08C menambahkan random backoff dan retry
sekaligus membuat gateway mengenali paket duplicate lewat SEQ (barulah di sini
ALOHA lengkap seperti yang dirumuskan Abramson), M09 menerapkan carrier sense,
lalu M10 menutup arc ini dengan SYNC dan slot waktu, dengan retry dihapus dan
digantikan penjadwalan. Urutannya mengikuti sejarah protokol akses kanal:
*ALOHA #sym.arrow CSMA #sym.arrow slot terjadwal*, dan yang bertambah tiap
pertemuan adalah cara memperlakukan tabrakan, seperti pada @tbl:p-tabrakan.

#tbl(
  table(
    columns: (auto, 1fr),
    align: (center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Tabrakan diperlakukan bagaimana]),
    [M08], [dibiarkan, bahkan tidak terlihat],
    [M08B], [dideteksi --- ACK membuat kegagalan terbaca],
    [M08C], [dipulihkan --- retry dengan jeda acak],
    [M09], [dihindari sebelum terjadi --- dengar dulu sebelum bicara],
    [M10], [dicegah secara struktural --- tiap node punya jatah waktunya],
  ),
  [Perlakuan terhadap tabrakan sepanjang arc kedua],
  "tbl:p-tabrakan",
)

Dua mode dibandingkan langsung pada M10, dan keduanya protokol yang berbeda:
Random Slot adalah *Slotted ALOHA* yang sesungguhnya (tabrakan berkurang tetapi
belum hilang, throughput puncak #sym.approx 36,8 %), sedangkan Assigned Slot
sudah menjadi *TDMA* --- tiap node punya slot tetap dan tabrakan hilang secara
struktural.

*Arc ketiga --- protokol mengambil alih.* Modul 11 menutup pertanyaan yang
menggantung sejak M04: semua yang dibangun sendiri di lapisan aplikasi ---
alamat node, ACK, nomor urut, retry, giliran bicara --- sudah lama
distandarkan orang lain, dan namanya LoRaWAN. Di modul ini kedua Arduino Uno
menjalankan stack LoRaWAN Class A (MCCI LMIC) dan join lewat OTAA ke ChirpStack
v4 yang berjalan di Raspberry Pi 5, dengan Pi yang sama merangkap *single
channel gateway* memakai driver register lanjutan M06. Payload-nya sengaja
dibiarkan sesederhana mungkin (`T=27.4,H=68`, ASCII, tanpa encoding) supaya
perhatian tertuju pada alur Register Device #sym.arrow OTAA Join #sym.arrow
Uplink #sym.arrow data terlihat di ChirpStack, bukan pada pengemasan byte. Dua
hal baru yang tidak pernah muncul di sepuluh modul sebelumnya: payload
terenkripsi sehingga *gateway sendiri tidak bisa membacanya*, dan alamat
perangkat yang *diberikan server*, bukan ditentukan build flag.

== Perangkat Keras

Dua papan Dragino dipakai di seri ini. Keduanya membawa chip radio yang *sama*,
SX1276; yang berbeda hanya papan pembawa dan pin mana yang tersambung ke mana.
Perbedaan itu tidak terasa sama sekali di udara --- itulah yang dibuktikan M06
dan M07.

=== Arduino Uno + Dragino LoRa Shield v1.2

Dipakai pada Modul 01--05, sisi slave M07 dan M07B, seluruh arc kedua (M08
sampai M10), serta sisi node M11.

#gbr("bab988112f70e658f0ee6025f1f4670d322eb797.jpeg",
  [Arduino Uno dengan Dragino LoRa Shield v1.2 terpasang],
  "gbr:p-shield", w: 72%)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Nilai]),
    [Board], [Arduino Uno (ATmega328P), flash 32 KB, RAM 2 KB],
    [Shield], [Dragino LoRa Shield v1.2],
    [Chip radio], [Semtech SX1276],
    [Frekuensi], [*433 MHz* --- shield yang dipakai lab ini; varian 868 / 915 / 920 MHz juga beredar],
    [Daya pancar], [maksimum +20 dBm; program memakai 17 dBm],
    [Sensitivitas], [hingga #sym.minus 148 dBm],
    [Antarmuka], [SPI perangkat keras + 3 pin kendali (NSS, RST, DIO0)],
    [Antena], [konektor SMA eksternal --- *wajib terpasang*],
  ),
  [Spesifikasi Arduino Uno dengan Dragino LoRa Shield v1.2],
  "tbl:p-shield",
)

#peringatan[
  *Jangan menyalakan shield tanpa antena.* Daya pancar yang tidak menemukan
  beban dipantulkan kembali ke penguat SX1276 dan dapat merusaknya permanen.
]

#tbl(
  table(
    columns: (auto, 1fr, auto),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Pin], th[Fungsi], th[Boleh dipakai program?]),
    [D10], [NSS / CS (jumper R9)], [Tidak],
    [D11, D12, D13], [MOSI, MISO, SCK], [Tidak --- D13 juga LED bawaan],
    [D9], [RST SX1276], [Tidak],
    [D2], [DIO0 (interrupt)], [Tidak],
    [D6, D7, D8], [DIO1, DIO2, DIO5], [Jangan dijadikan output],
    [*D3, D4, D5, A0--A5*], [bebas], [*Ya* --- D3 direkomendasikan untuk LED indikator],
  ),
  [Pemetaan pin Dragino LoRa Shield v1.2 terhadap Arduino Uno],
  "tbl:p-pin-shield",
)

Skematik resmi shield ada pada folder `skematik/` di repositori praktikum.

=== Raspberry Pi + Dragino LoRa GPS HAT v1.4

Dipakai pada Modul 06, sisi master M07 dan M07B, serta gateway dan server
ChirpStack M11.

#gbr("lora-gps-hat-terpasang.webp",
  [Dragino LoRa GPS HAT v1.4 terpasang di Raspberry Pi],
  "gbr:p-hat", w: 72%)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Nilai]),
    [Board], [Raspberry Pi 2 / 3 / 4 --- *diuji pada Pi 4* oleh penyusun kode aslinya],
    [HAT], [Dragino LoRa GPS HAT v1.4],
    [Chip radio], [Semtech SX1276 --- sama persis dengan shield Arduino],
    [GPS], [modul onboard, UART 9600 bps, NMEA 0183 --- *tidak dipakai* di seri ini],
    [Antarmuka], [SPI0 perangkat keras + 3 jalur GPIO (NSS, RESET, DIO0)],
    [Antena], [konektor SMA eksternal --- *wajib terpasang*, sama seperti shield],
  ),
  [Spesifikasi Raspberry Pi dengan Dragino LoRa GPS HAT v1.4],
  "tbl:p-hat",
)

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
    [`GPS_RX` / `GPS_TX` / 1PPS], [GPIO15/16/1], [14 / 15 / 18], [---],
  ),
  [Pemetaan pin LoRa GPS HAT v1.4 dan padanannya di shield Arduino],
  "tbl:p-pin-hat",
)

Kolom *WiringPi* adalah penomoran yang dipakai dokumentasi resmi Dragino;
kolom *BCM* adalah yang dipakai seluruh kode Python di seri ini
(`GPIO.setmode(GPIO.BCM)`). Keduanya menunjuk pin fisik yang sama, dan
tertukarnya keduanya adalah penyebab kegagalan yang paling sering terjadi.

#penting[
  *NSS bukan CE0.* HAT memakai GPIO 25 biasa sebagai chip select, bukan jalur
  CE0 bawaan SPI. Akibatnya kode Python membuka SPI pada `(0, 0)` tetapi
  menggerakkan NSS sendiri di sekitar tiap transaksi --- persis seperti driver
  Arduino menggerakkan D10.
]

#catatan[
  *Raspberry Pi 5* memakai chip GPIO baru (RP1) yang tidak didukung
  `RPi.GPIO`. Pasang `rpi-lgpio` sebagai gantinya; nama modulnya sama, sehingga
  tidak ada baris kode yang perlu diubah. Jangan memasang keduanya sekaligus.
]

Skematik HAT dan user manual resminya ada pada folder `skematik/` dan
`dokumen/` di repositori praktikum.

== Perangkat Lunak

#tbl(
  table(
    columns: (auto, auto, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Library], th[Versi], th[Fungsi]),
    [*LoRa* (sandeepmistry)], [0.8.x], [Driver SX1276: init, TX blocking, RX polling/interrupt, RSSI, SNR],
    [*SPI*], [bawaan framework], [Komunikasi SPI ke SX1276],
  ),
  [Library Arduino yang dipakai seri ini],
  "tbl:p-library",
)

PlatformIO mengunduh keduanya otomatis lewat `lib_deps`; tidak ada pemasangan
manual.

#catatan[
  *Mengapa bukan RadioLib?* RadioLib terkompilasi menjadi lebih dari 33 KB pada
  Arduino Uno --- melampaui flash 32 KB yang tersedia. Library sandeepmistry
  hanya memakai 18--30 % flash pada seluruh modul seri ini, sebagaimana
  terlihat pada @tbl:p-verifikasi.
]

*Sisi Raspberry Pi (M06 dan master M07)* tidak memakai library LoRa sama
sekali.

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Paket], th[Fungsi]),
    [`spidev`], [Akses `/dev/spidev0.0` --- satu-satunya jalan bicara ke SX1276],
    [`RPi.GPIO`], [Kendali jalur NSS dan RESET, pembacaan DIO0],
    [`rpi-lgpio`], [Pengganti `RPi.GPIO` khusus Raspberry Pi 5 --- nama modul sama, kode tidak berubah],
  ),
  [Paket Python yang dipakai di sisi Raspberry Pi],
  "tbl:p-paket-python",
)

Driver SX1276-nya ditulis di dalam berkas program itu sendiri, langsung di atas
register. Nama fungsinya sengaja dibuat menyerupai API sandeepmistry
(`beginPacket`, `endPacket`, `parsePacket`, `packetRssi`) agar kedua platform
dapat dibandingkan baris per baris --- dan agar terlihat bahwa library Arduino
tidak melakukan apa pun yang ajaib, hanya menulis register yang sama.
Pemasangannya lewat `requirements.txt` di masing-masing folder modul.

== Board Bercampur: Uno Asli dan Klon

Catatan ini berlaku untuk seluruh Arduino di lab. Lab ini memakai Arduino Uno
asli maupun klon secara bercampur. *Firmware kedua jenis board identik* ---
tidak ada satu baris pun yang perlu diubah, dan tidak ada environment terpisah.
Hal itu sudah diverifikasi di perangkat, bukan sekadar diasumsikan.

#tbl(
  table(
    columns: (1.1fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Yang diperiksa], th[Hasil]),
    [Mikrokontroler], [`Device signature = 0x1e950f (m328p)` --- sama pada kedua jenis],
    [Protokol unggah], [`arduino` pada kedua jenis],
    [Berkas `.hex` untuk `upload_port` berbeda], [*md5 identik* --- port bukan masukan kompilasi],
    [Modul 01 dengan peran ditukar antar-jenis], [berjalan normal di kedua arah, RSSI #sym.minus 54,0 vs #sym.minus 53,8 dBm],
    [Modul 05 dengan master asli + satu slave klon], [53 siklus, keberhasilan 100 % di kedua slave],
  ),
  [Hasil verifikasi kesetaraan board Uno asli dan klon],
  "tbl:p-board-campur",
)

Yang berbeda hanya *chip jembatan USB-ke-serial* di atas board, dan itu hanya
mengubah nama port di sistem operasi.

#tbl(
  table(
    columns: (auto, 1fr, auto),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Jenis board], th[Jembatan USB], th[Nama port di Linux]),
    [Uno asli], [ATmega16U2 (`2341:0043`)], [`/dev/ttyACM*`],
    [Klon], [CH340 (`1a86:7523`), CH343 (`1a86:55d3`), FTDI, CP2102], [`/dev/ttyUSB*`],
  ),
  [Jembatan USB dan penamaan port tiap jenis board],
  "tbl:p-jembatan-usb",
)

Di Windows keduanya sama-sama muncul sebagai `COMx`, sehingga perbedaan ini
tidak terasa sama sekali.

*Kenali port sebelum mengunggah.*

#keluaran("python3 tools/deteksi_port.py          # daftar port + jenis board
python3 tools/deteksi_port.py --ini    # potongan platformio.ini siap tempel")

#keluaran("Port             VID:PID      Jenis          Jembatan USB
--------------------------------------------------------------
/dev/ttyACM0     2341:0043    Uno asli       ATmega16U2 (Arduino LLC)
/dev/ttyACM1     2341:0043    Uno asli       ATmega16U2 (Arduino LLC)
/dev/ttyUSB0     1a86:7523    klon           CH340/CH341")

#peringatan[
  *Satu hal yang benar-benar berbeda perilakunya*, dan hanya di sisi perkakas:
  skrip Python yang menyetel jalur DTR/RTS *sebelum* `open()` ditolak oleh CDC
  ATmega16U2 pada Uno asli dengan `[Errno 110] Connection timed out`, sementara
  pada klon CH340 hal itu lolos. Seluruh `monitor_serial.py` pada seri ini
  sudah tidak menyentuh jalur tersebut. Bila menulis skrip serial sendiri, buka
  port apa adanya --- jangan mengatur DTR/RTS sebelum membukanya.
]

== Menjalankan

*Modul 01--05, sisi slave M07, dan seluruh arc kedua --- Arduino, lewat
PlatformIO:*

#keluaran("pio device list                                      # catat port tiap board
pio run -d Modul01_lora_uart -e receiver -t upload    # penerima dahulu
pio run -d Modul01_lora_uart -e sender   -t upload -t monitor")

*Modul 06 dan sisi master Modul 07 --- Raspberry Pi, langsung dengan Python:*

#keluaran("sudo raspi-config                                    # Interface Options > SPI > Yes, lalu reboot
ls /dev/spi*                                         # harus muncul spidev0.0

pip3 install -r Modul06_rpi_lora_python/requirements.txt
python3 Modul06_rpi_lora_python/src/receiver.py       # penerima dahulu
python3 Modul06_rpi_lora_python/src/sender.py         # di Pi kedua")

Tidak ada yang dikompilasi di sisi Raspberry Pi, sehingga tidak ada
`platformio.ini` untuknya. `Modul07_rpi_master_slave/platformio.ini` hanya
memuat kedua environment slave; masternya dijalankan sebagai
`python3 src/master.py`.

Port di tiap `platformio.ini` masih memakai nilai contoh untuk tiga Uno asli.
Jalankan `tools/deteksi_port.py` lebih dahulu, lalu sesuaikan
`upload_port` dan `monitor_port` sesuai board yang benar-benar terpasang.

#penting[
  *Urutan unggah* penting di sebagian besar modul: pihak yang *menunggu*
  diunggah lebih dahulu, pihak yang *memulai* belakangan. Tiap modul menyebutkan
  urutannya.

  *Baud Serial Monitor*: 9600 untuk M01--M04, *115200 untuk M05 dan slave M07*.
  Modul 06 tidak memakai Serial Monitor sama sekali --- keluarannya langsung ke
  terminal Raspberry Pi.
]

== Status Verifikasi

Seluruh modul Arduino dikompilasi ulang setelah dikonversi ke PlatformIO.
Modul 05 dan Modul 07 sudah diuji langsung di perangkat keras (tiga Arduino Uno
bershield Dragino, satu Raspberry Pi 5 bershield LoRa GPS HAT) --- rincian sesi
dan angka terukurnya ada pada `logserial.md` masing-masing folder. Modul 01--04
dan Modul 06 belum diuji ulang pada konversi ini; perilaku yang dijelaskan
berasal dari kode sumber asli beserta dokumentasinya, bukan dari pengamatan
ulang. Modul 08, 08B, 09, dan 10 baru dikompilasi (`pio run`), *belum diuji di
perangkat keras sama sekali* --- belum ada log serial, belum ada RSSI atau SNR
nyata. Angka pada tabel pengukuran modul yang belum diuji tetap disediakan
kosong untuk diisi praktikan.

#tbl(
  table(
    columns: (auto, auto, auto, 1fr),
    align: (center + horizon, left, center + horizon, left),
    inset: (x: 0.6em, y: 0.4em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Environment], th[Build], th[Flash (dari 32.256 B)]),
    [01], [`sender`], [OK], [18,3 % (5.890 B)],
    [01], [`receiver`], [OK], [22,7 % (7.312 B)],
    [02], [`sender`], [OK], [22,9 % (7.380 B)],
    [02], [`receiver`], [OK], [24,5 % (7.916 B)],
    [03], [`devicea`], [OK], [26,3 % (8.486 B)],
    [03], [`deviceb`], [OK], [25,4 % (8.206 B)],
    [04], [`sender`], [OK], [23,0 % (7.424 B)],
    [04], [`receiver`], [OK], [26,9 % (8.686 B)],
    [05], [`master`], [OK], [29,6 % (9.560 B)],
    [05], [`slave1`], [OK], [26,3 % (8.492 B)],
    [05], [`slave2`], [OK], [26,3 % (8.492 B)],
    [07], [`slave1`], [OK], [26,4 % (8.522 B)],
    [07], [`slave2`], [OK], [26,4 % (8.522 B)],
    [08], [`gateway`], [OK], [33,7 % (10.868 B)],
    [08], [`node1` / `node2`], [OK], [29,5 % (9.526 B)],
    [08B], [`gateway`], [OK], [35,9 % (11.566 B)],
    [08B], [`node1` / `node2`], [OK], [33,2 % (10.702 B)],
    [09], [`gateway`], [OK], [37,1 % (11.978 B)],
    [09], [`node1` / `node2`], [OK], [34,6 % (11.176 B)],
    [10], [`gateway`], [OK], [37,0 % (11.922 B)],
    [10], [`node1` / `node2`], [OK], [35,2 % (11.366 B)],
  ),
  [Status build dan pemakaian flash tiap environment],
  "tbl:p-verifikasi",
)

Modul 06 dan master Modul 07 tidak muncul pada tabel di atas karena tidak ada
yang dikompilasi: keduanya Python yang dijalankan langsung. Yang diperiksa pada
keduanya hanya kesahihan sintaksis (`python3 -m py_compile`), sebab `spidev`
dan `RPi.GPIO` hanya dapat dipasang di Raspberry Pi. Kode aslinya berasal dari
repositori Dragino LoRa GPS HAT yang menyatakan telah diuji berjalan pada
Raspberry Pi 4.

*Perubahan terhadap kode asli.* Yang berubah hampir seluruhnya cara membangun
dan menamai berkas, bukan isi programnya; satu-satunya perubahan perilaku
adalah baris terakhir @tbl:p-perubahan.

#tbl(
  table(
    columns: (1fr, 1fr, 1.1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Sebelum], th[Sesudah], th[Alasan]),
    [Berkas `.ino` per folder], [`src/<peran>/main.cpp` + `platformio.ini`], [Mengikuti alur PlatformIO seperti lab WSN-IOT-prak],
    [`#define DEVICE_A` disunting manual (M03)], [build flag `-DDEVICE_A` pada environment], [Satu source untuk dua board; menghilangkan risiko lupa mengembalikan],
    [`slave1.ino` dan `slave2.ino` terpisah (M05)], [satu `slave/main.cpp` + `-DSLAVE_ID=n`], [Kedua slave identik kecuali nomornya],
    [Port ditulis `COM8`/`COM9` di komentar], [`upload_port` di `platformio.ini`], [Port terkumpul di satu tempat, tidak tersebar di komentar],
    [`01a-sender.py` / `01b-receiver.py` (M06)], [`src/sender.py` / `src/receiver.py`], [Tata letak `src/` seragam dengan seluruh modul lain],
    [Nama modul disebut di docstring sebagai contoh lepas], [Docstring menunjuk modul lab yang dicerminkannya], [Tiap berkas Python menyebut padanan Arduino-nya secara langsung],
    [Pesan pembuka slave M07 tertulis mati `POLL:1`], [Menyebut `SLAVE_ID` yang sesungguhnya], [Slave 2 tidak lagi mencetak `Menunggu POLL:1`. Cacat yang sama sempat ada juga di M05, ditemukan dan diperbaiki lewat pengujian perangkat 21 Agustus 2026],
  ),
  [Perubahan yang dilakukan terhadap kode asli],
  "tbl:p-perubahan",
)

== Kode Sumber dan Repositori

Seluruh berkas kode sumber setiap modul dimuat *lengkap* di dalam buku ini,
pada bagian "Kode Program" masing-masing bab, sehingga buku dapat dipakai tanpa
akses jaringan. Salinan daringnya berada pada repositori praktikum
#link(REPO)[`github.com/hendrieepis/WSN-IOT-prak-Lora`].

Kotak *KODE SUMBER* di awal tiap bagian Kode Program menyediakan tautan
langsung ke folder dan berkas yang bersangkutan, sehingga kode dapat diunduh
tanpa mengetik ulang. Perkakas yang dipakai lintas modul berada di
#gh-folder("tools") dan dimuat pada Lampiran A.

== Referensi

*Arduino --- shield (M01--M05, slave M07, M08--M11)*

- #link("https://github.com/dragino/Lora/tree/master/Lora%20Shield")[Dragino LoRa Shield --- repositori resmi]
- Skematik Shield v1.2 (PDF) --- `skematik/Lora Shield v1.2.sch.pdf`
- #link("https://github.com/sandeepmistry/arduino-LoRa")[Library LoRa by sandeepmistry]

*Raspberry Pi --- HAT (M06, master M07, gateway M11)*

- #link("https://wiki1.dragino.com/index.php?title=Lora/GPS_HAT")[Wiki Dragino --- Lora/GPS HAT]
- #link("https://github.com/dragino/Lora/tree/master/Lora_GPS%20HAT/v1.4")[Dragino LoRa GPS HAT v1.4 --- repositori resmi]
- Skematik LoRa GPS HAT v1.4 (PDF) --- `skematik/Lora GPS HAT for RPi v1.4.pdf`
- User Manual LoRa GPS HAT v1.0 (PDF) --- `dokumen/LoRa_GPS_HAT_UserManual_v1.0.pdf`

*Umum*

- #link("https://www.semtech.com/products/wireless-rf/lora-connect/sx1276")[Datasheet SX1276]

]
