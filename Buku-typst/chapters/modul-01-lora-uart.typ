// ============================================================================
// Modul 01 — Tautan LoRa Satu Arah
// Sumber: Modul01_lora_uart/README.md; listing kode dibaca langsung dari
//         salinan berkas sumber di assets/code/Modul01_lora_uart/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist
#import "../config.typ": edisi_buku

#chapter("Modul 01 — Tautan LoRa Satu Arah", l: "bab:modul-01")

#identitas-modul(
  "Modul 01",
  [Establish the Link --- Tautan LoRa Satu Arah],
  [Arduino Uno + Dragino LoRa Shield v1.2 · LoRa mentah · satu arah ·
   RX polling · level Basic · 2 × 50 menit · folder kode `Modul01_lora_uart`],
)

#pengantar([Gambaran Umum])[
Modul 01 dirancang untuk dua pertemuan (2 × 50 menit) pada tingkat dasar.
Misinya membentuk tautan LoRa satu arah yang stabil: satu board mengirim pesan
berkala, satu board lain menerimanya beserta ukuran kualitas sinyal. Percobaan
memakai dua Arduino Uno bershield Dragino LoRa v1.2, diamati melalui dua Serial
Monitor pada 9600 baud.
]

== Pendahuluan

LoRa berbeda mendasar dari BLE, Zigbee, maupun Thread yang berbasis jaringan.
Di sini *tidak ada jaringan sama sekali* --- tidak ada proses join, tidak ada
alamat, tidak ada koneksi. Yang ada hanya modulasi radio: siapa pun yang
menyetel frekuensi, spreading factor, bandwidth, dan coding rate yang sama akan
mendengar apa yang dikirim. Semua yang biasanya disediakan protokol ---
identitas, penyaringan tujuan, konfirmasi, penanganan tabrakan --- harus
dibangun sendiri di lapisan aplikasi, dan itulah yang dikerjakan modul-modul
berikutnya.

Prasyaratnya hanya dasar bahasa C dan alur build PlatformIO; tidak ada modul
LoRa yang mendahuluinya. Yang dibangun di sini adalah inisialisasi SX1276
melalui SPI, penyetelan empat parameter radio yang menentukan tautan,
pengiriman paket secara blocking, penerimaan dengan cara polling, serta
pembacaan RSSI dan SNR sebagai instrumen ukur. Semuanya dipakai lagi pada M02
ketika penerimaan berpindah ke interrupt, M03 ketika arah data menjadi dua
arah, M04 ketika keandalan diukur dengan ACK, dan M05 ketika jumlah node
bertambah.

*Peta modul LoRa*

#tbl(
  table(
    columns: (auto, 1fr),
    align: (center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Fokus (yang ditumpuk di atas modul sebelumnya)]),
    [*01 (ini)*], [*Tautan satu arah terbentuk; RSSI dan SNR terbaca*],
    [02], [Penerimaan tanpa memblokir loop (interrupt) + indikator LED],
    [03], [Dua arah --- kedua board bergantian mengirim dan menerima],
    [04], [Keandalan diukur: ACK, timeout, dan hitungan gagal],
    [05], [Banyak node --- satu master menjadwalkan giliran bicara],
  ),
  [Peta modul pada arc pertama seri LoRa],
  "tbl:m01-peta",
)

*Kontrak data lab ini.* Payload berupa string ASCII pendek dengan *nomor urut*
di dalamnya (`Hello LoRa #7`). Nomor itulah yang membuat paket hilang dapat
dihitung --- cukup mencari lompatan angka di log penerima. Format bernomor yang
sama dipertahankan sampai M05 (`DATA:n`, `S1:DATA:n`), sehingga hasil
pengukuran antar-modul dapat dibandingkan.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Membentuk dan mengukur tautan LoRa satu arah])[
  + Menjelaskan peran empat parameter radio LoRa --- frekuensi, spreading
    factor, bandwidth, dan coding rate --- serta akibatnya bila salah satu
    berbeda antara pengirim dan penerima.
  + Menginisialisasi SX1276 melalui SPI dengan pemetaan pin shield yang benar,
    dan mendiagnosis kegagalan `LoRa.begin()`.
  + Menjelaskan perbedaan pengiriman blocking dan penerimaan berbasis polling,
    beserta konsekuensinya pada `loop()`.
  + Membaca RSSI dan SNR sebagai dua besaran yang berbeda, dan menjelaskan
    mengapa keduanya perlu dicatat bersama.
  + Menghitung packet loss dari nomor urut pada payload.
]

*Kriteria keberhasilan*

#checklist((
  [Kedua board mencetak `Init LoRa ... OK` setelah reset.],
  [Penerima mencetak setiap paket beserta RSSI dan SNR.],
  [Nomor urut yang diterima berurutan tanpa lompatan pada jarak dekat.],
  [Tabel jarak--RSSI--SNR--loss terisi dari pengukuran sendiri, minimal empat
   jarak.],
))

== Dasar Teori (Secukupnya)

Teori dibatasi pada apa yang dipakai di percobaan. Istilah kerja yang
diperlukan dirangkum pada @tbl:m01-istilah.

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [LoRa], [Teknik modulasi _chirp spread spectrum_ untuk jangkauan jauh dengan laju data rendah. Modul ini memakai LoRa mentah, bukan LoRaWAN.],
    [SX1276], [Chip radio pada shield Dragino, dikendalikan mikrokontroler lewat SPI.],
    [Frekuensi kerja], [Kanal radio yang dipakai. Program disetel *433 MHz* sesuai shield yang dipakai di lab ini; kedua board wajib sama persis.],
    [Spreading Factor (SF)], [Lama satu simbol. SF besar menambah jangkauan dan ketahanan, tetapi memperlambat data dan memperpanjang waktu udara. Modul ini memakai SF7.],
    [Bandwidth (BW)], [Lebar kanal. Semakin sempit semakin sensitif, tetapi semakin lambat. Modul ini memakai 125 kHz.],
    [Coding Rate (CR)], [Rasio kode koreksi galat. 4/5 berarti tiap 4 bit data disertai 1 bit koreksi.],
    [RSSI], [Kuat sinyal terima dalam dBm --- seberapa *keras* sinyal terdengar. Semakin mendekati nol semakin kuat.],
    [SNR], [Selisih sinyal terhadap derau dalam dB --- seberapa *jernih* sinyal terdengar. LoRa masih dapat memecahkan sinyal pada SNR negatif.],
    [Polling], [Penerima memeriksa sendiri secara berulang apakah ada paket (`LoRa.parsePacket()`).],
  ),
  [Istilah kerja Modul 01],
  "tbl:m01-istilah",
)

*Mengapa RSSI saja tidak cukup.* RSSI mengukur daya yang tiba di penerima,
termasuk derau. Sebuah sinyal bisa terdengar keras (RSSI #sym.minus 70 dBm)
tetapi tenggelam dalam gangguan sehingga gagal dipecahkan, dan sebaliknya
sinyal lemah (RSSI #sym.minus 120 dBm) tetap terbaca jika lingkungan sunyi.
Keunggulan LoRa justru terletak di sana: modulasinya sanggup bekerja pada *SNR
negatif*, yaitu ketika sinyal lebih lemah daripada derau di sekitarnya. Karena
itu kedua angka dicatat bersama, dan pada M05 keduanya dipakai untuk
menjelaskan mengapa sebuah node tidak menjawab.

*Sekuens yang diamati*

#diagram(```
   Sender                          (udara 433 MHz)                    Receiver
     |                                                                   |
  beginPacket()                                                    parsePacket()
  print("Hello LoRa #7")                                            (polling terus)
  endPacket()  --- blocking sampai seluruh paket mengudara --->        |
     |                                                           paket terdeteksi
     |                                                           baca isi + RSSI + SNR
  delay(2000)                                                          |
     |                                                           cetak ke Serial
```.text, rapat: true)

== Topologi

#diagram(```
        BOARD #1                                  BOARD #2
  +------------------+                      +------------------+
  |   Arduino Uno    |                      |   Arduino Uno    |
  | + LoRa Shield    |  ~~~~ 433 MHz ~~~~>  | + LoRa Shield    |
  |     SENDER       |     satu arah        |    RECEIVER      |
  | "Hello LoRa #n"  |                      | cetak + RSSI/SNR |
  +------------------+                      +------------------+
     env: sender                              env: receiver
```.text)

#tbl(
  table(
    columns: (auto, auto, auto, 1fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Environment], th[Peran], th[Payload / interval]),
    [Sender], [`sender`], [Pengirim], [`Hello LoRa #n` tiap 2000 ms],
    [Receiver], [`receiver`], [Penerima (polling)], [---],
  ),
  [Peran tiap node Modul 01],
  "tbl:m01-topologi",
)

Tidak ada alamat maupun identitas node pada modul ini. Setiap penerima yang
menyetel parameter radio sama akan menerima paket yang sama --- sifat yang akan
menjadi masalah nyata di M05, dan diselesaikan di sana dengan penomoran di
lapisan aplikasi.

== Alat yang Digunakan

Modul ini dijalankan di atas Arduino Uno (ATmega328P) dengan Dragino LoRa
Shield v1.2 (SX1276), memakai PlatformIO dan library LoRa karya sandeepmistry.

#tbl(
  table(
    columns: (auto, 1fr, 1.3fr, auto),
    align: (center + horizon, left, left, center + horizon),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[No], th[Peralatan], th[Spesifikasi], th[Jumlah]),
    [1], [Arduino Uno], [ATmega328P, flash 32 KB], [2],
    [2], [Dragino LoRa Shield], [v1.2, SX1276, 433 MHz], [2],
    [3], [Antena SMA], [sesuai band shield --- *wajib terpasang sebelum diberi daya*], [2],
    [4], [Kabel USB tipe B], [kabel data], [2],
    [5], [PC/Laptop], [PlatformIO Core/IDE, 2 port USB bebas], [1],
  ),
  [Alat dan bahan Modul 01],
  "tbl:m01-alat",
)

#peringatan[
  *Jangan menyalakan shield tanpa antena.* Daya pancar yang tidak menemukan
  beban akan dipantulkan kembali ke penguat SX1276 dan dapat merusaknya secara
  permanen. Pasang antena lebih dahulu, baru sambungkan USB.
]

*Pin yang dipakai shield (tidak boleh dipakai program)*

#tbl(
  table(
    columns: (auto, auto, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Pin Arduino], th[Fungsi LoRa], th[Keterangan]),
    [D10], [NSS / CS], [Chip select SX1276, ditentukan jumper R9 (0 ohm, terpasang dari pabrik)],
    [D11], [MOSI], [SPI data keluar],
    [D12], [MISO], [SPI data masuk],
    [D13], [SCK], [SPI clock --- *juga LED bawaan Arduino*],
    [D9], [RST], [Reset SX1276],
    [D2], [DIO0], [Interrupt TX-done / RX-done (INT0)],
  ),
  [Pemetaan pin shield Modul 01],
  "tbl:m01-pin",
)

Pin D6, D7, dan D8 tersambung ke DIO1, DIO2, dan DIO5 pada shield. Ketiganya
tidak dipakai program ini, tetapi jangan dijadikan output agar tidak beradu
dengan keluaran chip. Pin yang bebas dipakai: *D3, D4, D5, dan A0--A5*.

*Struktur proyek*

#diagram(```
Modul01_lora_uart/
├── platformio.ini
├── monitor_serial.py       ← pantau TX & RX sekaligus, ringkas loss/RSSI/SNR
├── upload_auto.py          ← deteksi port otomatis saat unggah
├── logserial.md            ← log referensi hasil uji perangkat
└── src/
    ├── sender/main.cpp     ← kirim "Hello LoRa #n" tiap 2 detik
    └── receiver/main.cpp   ← terima, cetak isi + RSSI + SNR
```.text)

== Kode Program

#sumber-kode("Modul01_lora_uart",
  ("platformio.ini", "src/sender/main.cpp", "src/receiver/main.cpp",
   "monitor_serial.py", "upload_auto.py"))

#kode-berkas("Modul01_lora_uart/platformio.ini",
  [`platformio.ini` Modul 01 --- environment `sender` dan `receiver`],
  "lst:m01-ini",
  pecah: true,
)

#kode-berkas("Modul01_lora_uart/src/sender/main.cpp",
  [`src/sender/main.cpp` --- kirim `Hello LoRa #n` tiap 2 detik],
  "lst:m01-sender",
  pecah: true,
)

#kode-berkas("Modul01_lora_uart/src/receiver/main.cpp",
  [`src/receiver/main.cpp` --- terima paket, cetak isi beserta RSSI dan SNR],
  "lst:m01-receiver",
  pecah: true,
)

#kode-berkas("Modul01_lora_uart/monitor_serial.py",
  [`monitor_serial.py` --- pantau TX dan RX pada satu sumbu waktu],
  "lst:m01-monitor",
  pecah: true,
)

#kode-berkas("Modul01_lora_uart/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah],
  "lst:m01-upload",
  pecah: true,
)

== Build dan Flash

Penerima diunggah lebih dahulu, agar paket pertama pengirim tidak terbuang.

#keluaran("pio run -d Modul01_lora_uart -e receiver -t upload -t monitor
pio run -d Modul01_lora_uart -e sender   -t upload -t monitor")

*Memantau kedua board sekaligus.* Dua Serial Monitor terpisah menyulitkan
pembandingan nomor urut, karena tiap jendela memiliki sumbu waktunya sendiri.
Skrip `monitor_serial.py` (@lst:m01-monitor) menggabungkan keduanya pada satu
sumbu waktu, lalu meringkas hasil ukur tautannya saat berhenti.

#keluaran("python3 Modul01_lora_uart/monitor_serial.py
python3 Modul01_lora_uart/monitor_serial.py --durasi 60 --log sesi1.txt
python3 Modul01_lora_uart/monitor_serial.py --port RX=/dev/ttyACM0")

Keluarannya berisi kedua aliran berdampingan, ditutup ringkasan yang langsung
mengisi tabel EXP-02.

#keluaran("[   2.012] RX      | --- Paket Diterima ---
[   2.012] RX      |   Data  : \"Hello LoRa #0\"
[   2.012] RX      |   RSSI  : -41 dBm
[   2.023] TX      | [TX] \"Hello LoRa #0\" ... terkirim
------------------------------------------------------------
  Paket dikirim  : 10  (nomor 0..9)
  Paket diterima : 10  (nomor 0..9)
  Paket hilang   : 0 (0.0 %)
  RSSI  min/maks/rata-rata : -46 / -40 / -41.4 dBm
  SNR   min/maks/rata-rata : 9.25 / 9.75 / 9.45 dB")

Paket hilang dihitung dari *selisih nomor urut* yang benar-benar terlihat
dikirim, bukan dari jumlah baris, sehingga paket yang lewat sebelum monitor
dijalankan tidak ikut dianggap gagal.

#penting[
  *Membuka monitor me-reset kedua board.* Pada Arduino Uno, jalur DTR terhubung
  ke pin RESET, sehingga penghitung paket kembali ke nol setiap kali monitor
  dijalankan. Sifat itu justru berguna --- baris `Init LoRa ... OK` ikut
  terekam --- tetapi berarti monitor harus dijalankan *lebih dahulu*, bukan di
  tengah percobaan yang sedang berlangsung.
]

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada kedua shield.],
  [`pio device list` dijalankan, port kedua board dicatat dan diisikan ke
   `platformio.ini`.],
  [Nilai `FREQUENCY` pada kedua source *sama persis* dan sesuai band shield
   yang dipakai.],
  [Dua Serial Monitor 9600 baud siap, atau `monitor_serial.py` dijalankan lebih
   dahulu.],
))

== Percobaan

=== EXP-01 --- Inisialisasi Radio

Unggah kedua firmware, buka Serial Monitor keduanya, dan amati pesan awal.

*Expected output --- sender*

#keluaran("=== LoRa SENDER ===
Init LoRa ... OK
Frekuensi : 433.00 MHz
SF=7, BW=125kHz, CR=4/5, Power=17dBm
Kirim tiap 2 detik...")

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Pesan init pada sender], [#isian],
    [Pesan init pada receiver], [#isian],
    [Frekuensi yang tercetak (MHz)], [#isian],
    [Pemakaian Flash dari ringkasan build], [#isian],
  ),
  [Lembar pengamatan EXP-01],
  "tbl:m01-exp01",
)

#checkpoint[
  Kedua board mencetak `OK`. Munculnya `GAGAL! Cek kabel/modul.` berarti SX1276
  tidak menjawab lewat SPI: periksa shield benar-benar duduk di header, jumper
  R9 terpasang, dan tidak ada program lain memakai D10.
]

=== EXP-02 --- Aliran Data Satu Arah

Biarkan sistem berjalan dua menit, lalu amati keterhubungan antara nomor urut
di kedua sisi.

*Expected output --- receiver*

#keluaran("--- Paket Diterima ---
  Data  : \"Hello LoRa #2\"
  RSSI  : -55 dBm
  SNR   : 9.50 dB

--- Paket Diterima ---
  Data  : \"Hello LoRa #3\"
  RSSI  : -54 dBm
  SNR   : 9.00 dB")

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Nomor urut terakhir di sender], [#isian],
    [Nomor urut terakhir di receiver], [#isian],
    [Paket hilang (selisih)], [#isian],
    [RSSI rata-rata (dBm)], [#isian],
    [SNR rata-rata (dB)], [#isian],
  ),
  [Lembar pengamatan EXP-02],
  "tbl:m01-exp02",
)

#buka-abstraksi[
  Di `src/receiver/main.cpp`, `LoRa.parsePacket()` dipanggil pada setiap
  putaran `loop()` tanpa jeda sama sekali. Tambahkan `delay(1000)` di akhir
  `loop()` penerima, unggah ulang, lalu amati apa yang terjadi pada paket yang
  tiba selama penerima sedang tertidur. Jelaskan hasilnya, lalu kembalikan
  kodenya. Pengamatan ini adalah alasan M02 berpindah ke interrupt.
]

#checkpoint[
  Nomor urut yang diterima naik satu per satu tanpa lompatan pada jarak dekat.
  Lompatan angka pada jarak 1 meter menandakan gangguan atau parameter yang
  tidak seragam, bukan keterbatasan jangkauan --- telusuri sebelum melanjutkan
  ke pengukuran jarak.
]

=== EXP-03 --- Parameter Harus Seragam

Ubah *satu* parameter di penerima saja, unggah ulang, dan amati akibatnya.
Kembalikan ke nilai semula setelah tiap uji.

#tbl(
  table(
    columns: (auto, 1fr, 1.2fr),
    align: (center + horizon, left, left),
    inset: (x: 0.6em, y: 0.6em),
    stroke: 0.5pt + luma(170),
    table.header(th[Uji], th[Perubahan di receiver], th[Hasil yang teramati]),
    [03-a], [`setSpreadingFactor(8)`], [#isian],
    [03-b], [`setSignalBandwidth(250E3)`], [#isian],
    [03-c], [`setCodingRate4(6)`], [#isian],
    [03-d], [`FREQUENCY 868E6`], [#isian],
  ),
  [Lembar pengamatan EXP-03 --- keseragaman parameter radio],
  "tbl:m01-exp03",
)

#checkpoint[
  Tiga dari empat uji menghentikan penerimaan *sepenuhnya*, bukan sekadar
  memperburuknya: untuk SF, bandwidth, dan frekuensi, radio LoRa tidak mengenal
  "hampir cocok". Satu uji berperilaku berbeda --- temukan yang mana, lalu
  jelaskan sebabnya sebelum melanjutkan. Petunjuk: periksa apa saja yang dibawa
  header PHY sebuah paket LoRa, dan apa yang menentukan bentuk gelombangnya
  secara fisik.
]

*Mengapa coding rate berbeda sendiri.* Uji 03-c tetap menerima paket seperti
biasa. Penyebabnya, program memakai _explicit header mode_ (bawaan library):
tiap paket membawa header PHY berisi panjang payload dan *coding rate yang
dipakai*, dan header itu sendiri selalu dikirim dengan CR 4/8. Penerima membaca
CR dari header lalu menyesuaikan diri, sehingga `setCodingRate4()` di sisi
penerima hanya berlaku ketika penerima *mengirim*. Sebaliknya SF, bandwidth,
dan frekuensi menentukan bentuk gelombang: bila salah satu berbeda, sinyal
tidak dikenali sebagai paket LoRa sama sekali dan header pun tidak pernah
terbaca. Hasil uji ini terekam di `logserial.md`.

=== Verifikasi Perangkat Keras (Log Referensi)

Dijalankan pada dua Arduino Uno bershield Dragino LoRa v1.2, frekuensi 433 MHz,
jarak #sym.plus.minus 30 cm. Log lengkap ada di `logserial.md`.

#keluaran("[   5.851] TX | [TX] \"Hello LoRa #2\" ... terkirim
[   6.051] RX | --- Paket Diterima ---
[   6.051] RX |   Data  : \"Hello LoRa #2\"
[   6.051] RX |   RSSI  : -55 dBm
[   6.051] RX |   SNR   : 9.50 dB")

#tbl(
  table(
    columns: (1.2fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil terukur]),
    [Paket dikirim / diterima dalam 62 s], [28 / 28 (loss 0 %)],
    [RSSI: min / maks / rata-rata], [#sym.minus 56 / #sym.minus 43 / #sym.minus 53,9 dBm],
    [SNR: min / maks / rata-rata], [9,00 / 9,75 / 9,45 dB],
    [Selang TX #sym.arrow RX tercetak], [0,002--0,200 s],
    [Interval kirim terukur], [2,00--2,01 s],
    [EXP-03 diulang pada dua pasangan board], [pola hasil identik],
    [EXP-03: SF / BW / frekuensi berbeda], [penerimaan berhenti total],
    [EXP-03: coding rate berbeda], [*tetap diterima* --- lihat penjelasan header PHY di atas],
  ),
  [Hasil verifikasi perangkat keras Modul 01],
  "tbl:m01-verifikasi",
)

#keluaran("Environment    Status    Flash              RAM
sender         SUCCESS   18.3% (5890 B)     ~14%
receiver       SUCCESS   22.7% (7312 B)     ~15%")

Keduanya jauh di bawah batas 32 KB Arduino Uno --- inilah alasan library
sandeepmistry dipilih alih-alih RadioLib yang melampaui kapasitas flash.

// Log serial lengkap dari Modul01_lora_uart/logserial.md. Hanya dicetak pada
// edisi dosen agar tidak disalin mahasiswa sebagai hasil laporan
// (lihat config.typ).
#if edisi_buku == "dosen" [
  === Log Serial Terverifikasi

  Log serial lengkap hasil uji pada board nyata, bukan contoh. Bagian ini
  hanya dicetak pada edisi dosen.

  Hasil aktual dari perangkat. Baud 9600, frekuensi *433 MHz*, SF7 / BW 125 kHz / CR 4/5 / 17 dBm. Jarak antar-board ±30 cm.

  *Board & Port*

  #tbl(
    table(
      columns: (auto, auto, auto, 1fr, auto),
      align: (left, left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Peran], th[Environment], th[Port], th[Board], th[Status radio]),
      [Sender], [`sender`], [`/dev/ttyACM0`], [Uno asli (`2341:0043`)], [✅ init berhasil],
      [Receiver], [`receiver`], [`/dev/ttyACM1`], [Uno asli (`2341:0043`)], [✅ init berhasil],
    ),
    [Log serial Modul 01: Board & Port],
    "tbl:m01-log-1",
  )

  Pemetaan ini sesuai `platformio.ini` apa adanya, sehingga `--upload-port` tidak diperlukan. Kedua aliran serial direkam bersamaan memakai `monitor_serial.py`, sehingga stempel waktunya berasal dari satu sumbu yang sama dan hitungan paket hilang berasal dari selisih nomor urut, bukan perkiraan.

  *EXP-01 — Inisialisasi Radio*

  #keluaran("[   5.049] RX | -- tersambung ke /dev/ttyACM1 @ 9600 --
[   5.050] TX | -- tersambung ke /dev/ttyACM0 @ 9600 --
[   5.851] TX | [TX] \"Hello LoRa #2\" ... terkirim
[   6.051] RX | --- Paket Diterima ---
[   6.051] RX |   Data  : \"Hello LoRa #2\"
[   6.051] RX |   RSSI  : -55 dBm
[   6.051] RX |   SNR   : 9.50 dB
[   8.054] TX | [TX] \"Hello LoRa #3\" ... terkirim
[   8.056] RX | --- Paket Diterima ---
[   8.056] RX |   Data  : \"Hello LoRa #3\"
[   8.056] RX |   RSSI  : -54 dBm
[   8.056] RX |   SNR   : 9.00 dB", pecah: true)

  Pesan awal kedua board saat reset:

  #keluaran("=== LoRa SENDER ===              === LoRa RECEIVER ===
Init LoRa ... OK                 Init LoRa ... OK
Frekuensi : 433.00 MHz           Frekuensi : 433.00 MHz
SF=7, BW=125kHz, CR=4/5,         SF=7, BW=125kHz, CR=4/5
        Power=17dBm              Menunggu paket...
Kirim tiap 2 detik...", pecah: true)

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Pesan init sender], [`OK`],
      [Pesan init receiver], [`OK`],
      [Frekuensi yang tercetak], [433.00 MHz di kedua board],
      [Selang `[TX]` → paket tercetak di penerima], [0,002–0,200 s],
      [Flash sender / receiver], [18,3 % (5.890 B) / 22,7 % (7.312 B)],
    ),
    [Log serial Modul 01: EXP-01 — Inisialisasi Radio],
    "tbl:m01-log-2",
  )

  *CHECKPOINT terpenuhi.* Kedua board mencetak `OK`.

  *EXP-02 — Aliran Data Satu Arah (62 detik)*

  #tbl(
    table(
      columns: (auto, 1fr),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Paket dikirim / diterima], [*28 / 28* (nomor 2..29)],
      [Paket hilang], [*0 (loss 0 %)*],
      [RSSI: min / maks / rata-rata], [−56 / −43 / *−53,9 dBm*],
      [SNR: min / maks / rata-rata], [9,00 / 9,75 / *9,45 dB*],
      [Interval kirim terukur], [2,00–2,01 s (sesuai `delay(2000)`)],
    ),
    [Log serial Modul 01: EXP-02 — Aliran Data Satu Arah (62 detik)],
    "tbl:m01-log-3",
  )

  RSSI pada sesi ini (−53,9 dBm) lebih lemah daripada sesi sebelumnya yang memakai board berbeda (−41,6 dBm), meskipun jaraknya sama. Selisih ±12 dB itu berasal dari perbedaan antena dan posisi board di meja, bukan dari jarak — pengingat bahwa RSSI hanya dapat dibandingkan bila kondisi ukurnya benar-benar sama. SNR keduanya praktis identik (9,45 dB vs 9,53 dB), karena derau lingkungannya sama.

  *EXP-03 — Parameter Harus Seragam*

  Satu parameter diubah *di penerima saja*, diunggah ulang, lalu penerimaan diamati 16 detik. Pengirim tidak disentuh.

  #tbl(
    table(
      columns: (auto, 1fr, auto, auto),
      align: (left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Uji], th[Perubahan di receiver], th[Paket diterima / 16 s], th[Hasil]),
      [baseline], [SF7, BW 125 kHz, CR 4/5, 433 MHz], [5], [tautan normal],
      [03-a], [`setSpreadingFactor(8)`], [*0*], [komunikasi berhenti total],
      [03-b], [`setSignalBandwidth(250E3)`], [*0*], [komunikasi berhenti total],
      [03-c], [`setCodingRate4(6)`], [*5*], [*tetap diterima normal*],
      [03-d], [`FREQUENCY 868E6`], [*0*], [komunikasi berhenti total],
    ),
    [Log serial Modul 01: EXP-03 — Parameter Harus Seragam],
    "tbl:m01-log-4",
  )

  _Temuan: coding rate tidak harus sama_

  Uji 03-c membantah dugaan awal bahwa keempat parameter sama-sama wajib seragam. Coding rate yang berbeda *tidak* menghentikan penerimaan — jumlah paket yang tertangkap sama persis dengan baseline.

  Hasil ini *tereplikasi pada dua pasangan board yang berbeda*: pengujian pertama memakai Uno klon ber-bridge CH340 sebagai pengirim, pengujian kedua memakai dua Uno asli. Keduanya memberi pola yang sama persis, sehingga temuan ini bukan sifat satu perangkat tertentu.

  Penjelasannya ada pada struktur paket LoRa. Program memakai _explicit header mode_, bawaan library. Pada mode itu setiap paket membawa *header PHY* berisi panjang payload dan *coding rate yang dipakai*, dan header itu sendiri selalu dikirim dengan CR 4/8. Penerima membaca coding rate dari header lalu menyesuaikan diri untuk memecahkan payload. Nilai `setCodingRate4()` di sisi penerima karena itu hanya menentukan CR ketika penerima *mengirim*, bukan ketika menerima.

  Berbeda halnya dengan SF, bandwidth, dan frekuensi. Ketiganya menentukan bentuk gelombang secara fisik: penerima yang menyetel SF atau bandwidth berbeda tidak akan mengenali sinyal sebagai paket LoRa sama sekali, sehingga header pun tidak pernah terbaca. Itulah alasan uji 03-a, 03-b, dan 03-d berhenti total sementara 03-c berjalan seperti biasa.

  Konsekuensi praktisnya: bila suatu saat _implicit header mode_ dipakai — biasanya untuk menghemat waktu udara pada payload tetap — coding rate wajib disepakati kedua sisi, karena tidak ada lagi header yang mengabarkannya.

  *Riwayat: satu shield sempat gagal init*

  Pada sesi pengujian sebelumnya, board Uno di `/dev/ttyACM0` konsisten gagal:

  #keluaran("=== LoRa SENDER ===
Init LoRa ... GAGAL! Cek kabel/modul.", pecah: true)

  Firmware kedua board ditukar untuk memastikan penyebabnya:

  #tbl(
    table(
      columns: (1fr, auto, auto),
      align: (left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Board fisik], th[Sebagai sender], th[Sebagai receiver]),
      [di `/dev/ttyACM0`], [GAGAL], [*GAGAL*],
      [di `/dev/ttyACM1`], [OK], [*OK*],
    ),
    [Log serial Modul 01: Riwayat: satu shield sempat gagal init],
    "tbl:m01-log-5",
  )

  Kegagalan mengikuti *board fisik*, bukan firmware, bukan port, dan bukan pengaturan frekuensi — `LoRa.begin()` memeriksa register versi SX1276 *sebelum* frekuensi diterapkan, sehingga perubahan 920 MHz ke 433 MHz tidak mengubah gejalanya. Setelah shield diperbaiki, board yang sama menginisialisasi dengan normal dan dipakai pada seluruh pengukuran di atas.

  Catatan ini dipertahankan karena gejalanya khas dan langkah diagnosisnya — menukar firmware untuk memisahkan kesalahan perangkat dari kesalahan program — berlaku untuk seluruh modul dalam seri ini.

  *Uji kompatibilitas board asli vs klon*

  Lab memakai Uno asli dan klon bercampur, sehingga perlu dipastikan firmware yang sama benar-benar berjalan di keduanya.

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Yang diperiksa], th[Hasil]),
      [`Device signature` board asli (`ttyACM0`)], [`0x1e950f (m328p)`],
      [`Device signature` board klon (`ttyUSB0`)], [`0x1e950f (m328p)` — sama],
      [Protokol unggah], [`arduino` pada keduanya],
      [md5 `.hex` saat `upload_port` diubah], [`f263400e…` pada keduanya — *identik*],
    ),
    [Log serial Modul 01: Uji kompatibilitas board asli vs klon],
    "tbl:m01-log-6",
  )

  Perilaku dengan peran ditukar antar-jenis board, 26 detik per konfigurasi:

  #tbl(
    table(
      columns: (1fr, auto, auto, auto),
      align: (left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Konfigurasi], th[Paket], th[Hilang], th[RSSI rata-rata]),
      [TX asli (`ttyACM0`) → RX klon (`ttyUSB0`)], [12], [1 (nomor *0*)], [−54,0 dBm],
      [TX klon (`ttyUSB0`) → RX asli (`ttyACM0`)], [12], [0], [−53,8 dBm],
    ),
    [Log serial Modul 01: Uji kompatibilitas board asli vs klon],
    "tbl:m01-log-7",
  )

  Satu-satunya paket hilang adalah *\#0*, yaitu paket yang dikirim ketika penerima masih menyelesaikan boot — bukan gejala ketidakcocokan board. Membuka port menyebabkan kedua board reset bersamaan, dan pengirim siap ±0,2 detik lebih cepat daripada penerima. Inilah alasan README meminta penerima diunggah lebih dahulu, dan alasan paket pertama sebaiknya tidak dihitung dalam pengukuran.

  Kesimpulan: *tidak ada penyesuaian kode apa pun* yang diperlukan untuk board klon. Yang berbeda hanya nama port di sistem operasi.

  *Catatan pengambilan log*

  - Arduino Uno melakukan reset otomatis setiap kali port serial dibuka, karena jalur DTR terhubung ke pin RESET lewat kapasitor. Sifat ini dipakai agar pesan `setup()` ikut terekam tanpa menekan tombol reset.
  - `monitor_serial.py` sempat gagal membuka port kedua Uno asli dengan `[Errno 110] Connection timed out`. Penyebabnya, skrip menyetel DTR/RTS *sebelum* `open()` — hal yang ditolak CDC ATmega16U2 pada Uno asli, tetapi kebetulan lolos pada klon ber-bridge CH340 yang dipakai di sesi sebelumnya. Skrip diperbaiki agar tidak menyentuh jalur itu sama sekali, dan perbaikannya diterapkan ke seluruh salinan monitor pada Modul 01–04.
  - Baris `[TX] ... terkirim` *bukan* bukti paket mengudara. Program mencetaknya setelah `LoRa.endPacket()` kembali, tanpa memeriksa status radio. Pada board yang `LoRa.begin()`-nya gagal, baris itu tetap muncul.
  - Seluruh perubahan sumber pada EXP-03 dikembalikan ke kondisi semula setelah pengujian, dan baseline diukur ulang untuk memastikannya.
  - Tabel pengukuran jarak, penghalang, dan spreading factor pada README belum terisi: percobaan ini dijalankan di satu meja pada jarak tetap ±30 cm.
]

== Pengukuran

*A. Jarak terhadap kualitas tautan* --- sender dan receiver dipisahkan pada
empat jarak, masing-masing diamati 60 detik.

#tbl(
  table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: (left, left, left, left, left, left),
    inset: (x: 0.5em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Jarak], th[RSSI (dBm)], th[SNR (dB)], th[Dikirim], th[Diterima], th[Loss (%)]),
    [1 m], [#isian], [], [], [], [],
    [10 m], [#isian], [], [], [], [],
    [50 m], [#isian], [], [], [], [],
    [100 m], [#isian], [], [], [], [],
  ),
  [Lembar pengukuran A --- jarak terhadap kualitas tautan],
  "tbl:m01-ukur-a",
)

*B. Pengaruh penghalang* --- pada jarak tetap 10 m.

#tbl(
  table(
    columns: (1.3fr, 1fr, 1fr, 1fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Kondisi], th[RSSI (dBm)], th[SNR (dB)], th[Loss (%)]),
    [Garis pandang bebas], [#isian], [], [],
    [Terhalang satu dinding], [#isian], [], [],
    [Terhalang dua dinding], [#isian], [], [],
    [Antena menempel di logam], [#isian], [], [],
  ),
  [Lembar pengukuran B --- pengaruh penghalang pada jarak 10 m],
  "tbl:m01-ukur-b",
)

*C. Pengaruh spreading factor* --- ubah SF pada *kedua* board, ukur pada jarak
yang sama.

#tbl(
  table(
    columns: (auto, 1.3fr, 1fr, 1fr, 1fr),
    align: (center + horizon, left, left, left, left),
    inset: (x: 0.55em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[SF], th[Waktu udara per paket (perkiraan)], th[RSSI (dBm)], th[SNR (dB)], th[Loss (%)]),
    [7], [#isian], [], [], [],
    [9], [#isian], [], [], [],
    [12], [#isian], [], [], [],
  ),
  [Lembar pengukuran C --- pengaruh spreading factor],
  "tbl:m01-ukur-c",
)

== Analisis

+ Bagaimana hubungan jarak terhadap RSSI pada data @tbl:m01-ukur-a? Apakah
  penurunannya sebanding dengan jarak, dan mengapa demikian?
+ Pada baris mana RSSI masih baik tetapi SNR sudah memburuk? Jelaskan apa yang
  terjadi secara fisik pada kondisi itu.
+ Dari @tbl:m01-ukur-c, apa yang dipertukarkan ketika spreading factor
  dinaikkan? Kaitkan dengan waktu udara dan konsumsi energi.
+ Tiga parameter pada EXP-03 membuat komunikasi gagal total, satu lagi tidak
  berpengaruh sama sekali. Kelompokkan keempatnya berdasarkan apakah parameter
  itu menentukan bentuk gelombang atau hanya cara payload dikodekan, lalu
  jelaskan mengapa pengelompokan itu memprediksi hasilnya.
+ Modul ini tidak memiliki alamat maupun identitas node. Sebutkan dua masalah
  yang pasti muncul bila ada tiga board menyala bersamaan dengan firmware yang
  sama.

== Concept Check

+ Apa perbedaan RSSI dan SNR, dan mengapa keduanya dicatat bersama?
+ Mengapa antena wajib terpasang sebelum shield diberi daya?
+ Apa arti "TX blocking" pada `LoRa.endPacket()`, dan apa yang tidak dapat
  dikerjakan Arduino selama pengiriman berlangsung?
+ D13 dipakai sebagai SCK sekaligus LED bawaan. Apa akibatnya bila LED bawaan
  dipakai sebagai indikator komunikasi?
+ Mengapa LoRa pada modul ini disebut LoRa mentah dan bukan LoRaWAN? Sebutkan
  satu hal yang disediakan LoRaWAN tetapi tidak ada di sini.

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Membuat penerima menghitung sendiri])[
  / CH-1 --- Hitung loss otomatis: Uraikan nomor urut dari payload di penerima,
    bandingkan dengan nomor sebelumnya, dan cetak `LOSS: n paket` setiap kali
    terjadi lompatan.

  / CH-2 --- Statistik berjalan: Tampilkan RSSI minimum, maksimum, dan
    rata-rata pada penerima setiap 10 paket.
]

#tujuan-prak(3, [Mencari batas tautan])[
  / CH-3 --- Uji jangkauan maksimum: Turunkan `setTxPower()` bertahap dari
    17 dBm ke 2 dBm pada jarak tetap, catat pada daya berapa paket mulai
    hilang, lalu bandingkan dengan hasil menaikkan SF.

  / CH-4 --- Payload lebih besar: Naikkan panjang payload bertahap sampai
    200 byte, ukur pengaruhnya terhadap loss dan waktu kirim. Jelaskan mengapa
    paket panjang lebih rapuh.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- parameter radio, RSSI vs SNR, polling.
+ Konfigurasi --- pemetaan pin shield, nilai SF/BW/CR/frekuensi, environment
  PlatformIO.
+ Hasil eksperimen --- log serial kedua board (EXP-01 sampai EXP-03 beserta
  checkpoint).
+ Data pengukuran --- @tbl:m01-ukur-a, @tbl:m01-ukur-b, dan @tbl:m01-ukur-c.
+ Analisis dan concept check.
+ Challenge --- minimal CH-1.
+ Kesimpulan yang disusun sendiri berdasarkan hasil pengujian.
