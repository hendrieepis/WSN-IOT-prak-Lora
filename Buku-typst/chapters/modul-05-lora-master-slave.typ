// ============================================================================
// Modul 05 — Master-Slave 3 Node (Round-Robin Polling)
// Sumber: Modul05_lora_master_slave/README.md; listing kode dibaca langsung
//         dari salinan berkas sumber di assets/code/Modul05_lora_master_slave/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist
#import "../config.typ": edisi_buku

#chapter("Modul 05 — Master-Slave 3 Node (Round-Robin Polling)", l: "bab:modul-05")

#identitas-modul(
  "Modul 05",
  [Schedule the Airwaves --- Master-Slave 3 Node (Round-Robin Polling)],
  [Arduino Uno + Dragino LoRa Shield v1.2 · LoRa mentah · topologi bintang,
   3 node · polling terjadwal · level Advanced · 3 × 50 menit ·
   Serial 115200 baud · folder kode `Modul05_lora_master_slave`],
)

#pengantar([Gambaran Umum])[
Modul 05 dirancang untuk tiga pertemuan (3 × 50 menit) pada tingkat lanjut.
Misinya menambah jumlah node menjadi tiga tanpa membiarkan mereka saling
menimpa di udara: satu master memanggil tiap slave bergiliran, dan slave hanya
bersuara ketika namanya disebut. Percobaan memakai tiga Arduino Uno bershield
Dragino LoRa v1.2, diamati melalui tiga Serial Monitor pada 115200 baud.
]

== Pendahuluan

Empat modul sebelumnya selalu melibatkan tepat dua board, sehingga tidak pernah
ada pertanyaan siapa yang boleh bicara. Begitu node ketiga hadir, masalah baru
muncul seketika: radio LoRa tidak memiliki alamat, tidak memiliki mekanisme
penghindaran tabrakan, dan tidak dapat mendengar ketika sedang memancar. Bila
dua slave menjawab bersamaan, kedua paket bertabrakan dan *tidak satu pun* yang
dapat dipecahkan master --- kegagalan yang bahkan tidak terlihat sebagai
kesalahan, hanya sebagai sunyi. Modul ini menyelesaikannya dengan cara paling
tua dan paling mudah dibuktikan: penjadwalan terpusat, tempat hak bicara
diberikan satu per satu oleh master.

Prasyaratnya adalah M03 untuk percakapan dua arah dan penanda identitas pada
payload, serta M04 untuk penungguan berbatas waktu dan statistik keberhasilan.
Yang dibangun di sini adalah pengalamatan di lapisan aplikasi (`POLL:1`,
`S1:DATA:n`), penjadwalan round-robin, penyaringan paket yang bukan miliknya,
batas waktu per node, serta statistik per node yang terpisah. Pola master-slave
ini adalah bentuk paling sederhana dari penjadwalan medium yang pada jaringan
sungguhan dikerjakan lapisan MAC.

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
    [*05 (ini)*], [*Banyak node --- hak bicara dijadwalkan agar tidak bertabrakan*],
  ),
  [Peta modul pada arc pertama seri LoRa],
  "tbl:m05-peta",
)

*Kontrak data lab ini.* Perintah master berbentuk `POLL:<id>` dan jawaban slave
berbentuk `S<id>:DATA:<n>`. Nomor id mengikat keduanya, sedangkan `n` adalah
penghitung lokal slave yang *naik hanya setelah pengiriman benar-benar
dilakukan* --- sehingga angka itu mewakili jumlah jawaban yang sungguh dikirim,
bukan jumlah niat mengirim. Perbedaan halus ini menjadi bahan analisis
tersendiri.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Menjadwalkan hak bicara banyak node di atas satu kanal])[
  + Menjelaskan mengapa tabrakan paket pasti terjadi pada LoRa mentah bila
    beberapa node bicara tanpa penjadwalan, dan mengapa tabrakan itu tidak
    terlihat sebagai pesan kesalahan.
  + Menerapkan pengalamatan di lapisan aplikasi ketika lapisan radio tidak
    menyediakannya.
  + Membangun penjadwalan round-robin dengan batas waktu per node, dan
    menjelaskan pengaruh nilai batas waktu terhadap lama siklus.
  + Mengukur keberhasilan dan waktu tanggap *per node*, bukan gabungan, lalu
    menjelaskan penyebab perbedaannya.
  + Menjelaskan batas skala pendekatan master-slave dan memperkirakan titik
    ketika pendekatan itu tidak lagi memadai.
]

*Kriteria keberhasilan*

#checklist((
  [Master menyelesaikan siklus penuh: memanggil Slave 1 lalu Slave 2
   bergantian tanpa henti.],
  [Setiap slave hanya menjawab panggilan bernomor dirinya, dan mencetak
   `[IGNORE]` untuk yang lain.],
  [Statistik `OK` dan `FAIL` tercatat terpisah untuk tiap slave.],
  [Ketika satu slave dimatikan, master tetap melayani slave lainnya dan
   mencatat kegagalan pada slave yang hilang.],
  [Lama siklus terukur dan dijelaskan penyusunnya.],
))

== Dasar Teori (Secukupnya)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [Master], [Node yang menjadwalkan, memanggil tiap slave bergiliran. Hanya ada satu.],
    [Slave], [Node yang diam sampai dipanggil, lalu menjawab tepat satu kali.],
    [Round-robin], [Penjadwalan bergilir merata: 1, 2, 1, 2, … tanpa prioritas.],
    [Tabrakan], [Dua paket mengudara bersamaan sehingga saling merusak; penerima tidak menerima apa pun.],
    [Masalah hidden node], [Dua slave yang saling tidak terdengar tetap dapat bertabrakan di posisi master. Penjadwalan terpusat menghindarinya.],
    [Batas waktu polling], [Lama master menunggu jawaban sebelum menyatakan slave tidak merespons (500 ms pada modul ini).],
    [Lama siklus], [Waktu satu putaran penuh memanggil seluruh slave. Menentukan seberapa sering tiap node terbaca.],
  ),
  [Istilah kerja Modul 05],
  "tbl:m05-istilah",
)

*Mengapa penjadwalan lebih dahulu, bukan pengalamatan lebih dahulu.* Memberi
nomor pada tiap node menyelesaikan persoalan "pesan ini untuk siapa", tetapi
tidak menyelesaikan "siapa yang boleh bicara sekarang". Seandainya kedua slave
dibiarkan mengirim sendiri secara berkala, penomoran tetap tidak menolong: dua
paket yang bertabrakan di udara rusak sebelum sempat dibaca nomornya. Karena
itu master memberi hak bicara satu per satu, dan nomor node hanya dipakai untuk
memastikan jawaban yang tiba berasal dari node yang sedang dipanggil.

*Mengapa lama siklus penting.* Master menunggu paling lama 500 ms untuk tiap
slave. Bila kedua slave menjawab cepat, satu siklus selesai dalam ratusan
milidetik; bila keduanya mati, siklus memakan sekitar satu detik penuh hanya
untuk menunggu kesunyian. Dengan sepuluh slave, satu node yang mati
memperlambat pembacaan seluruh node lain --- sifat yang perlu diperhitungkan
sebelum jumlah node ditambah.

*Sekuens yang diamati*

#diagram(```
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
```.text, rapat: true)

== Topologi

#diagram(```
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
```.text)

#tbl(
  table(
    columns: (auto, auto, auto, 1.2fr, auto),
    align: (left, left, left, left, left),
    inset: (x: 0.55em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Environment], th[Build flag], th[Peran], th[Batas waktu]),
    [Master], [`master`], [---], [Memanggil bergiliran, mencatat statistik], [500 ms per slave],
    [Slave 1], [`slave1`], [`-DSLAVE_ID=1`], [Menjawab `POLL:1`], [---],
    [Slave 2], [`slave2`], [`-DSLAVE_ID=2`], [Menjawab `POLL:2`], [---],
  ),
  [Peran tiap node Modul 05],
  "tbl:m05-topologi",
)

Kedua slave memakai *file source yang sama*, `src/slave/main.cpp`; nomornya
ditentukan build flag. Menambah slave ketiga berarti menambah satu environment
dan menaikkan `SLAVE_COUNT` di master.

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
    [1], [Arduino Uno], [ATmega328P], [3],
    [2], [Dragino LoRa Shield], [v1.2, SX1276, 433 MHz], [3],
    [3], [Antena SMA], [*wajib terpasang sebelum diberi daya*], [3],
    [4], [Kabel USB tipe B], [kabel data], [3],
    [5], [PC/Laptop], [PlatformIO Core/IDE, idealnya 3 port USB bebas], [1],
  ),
  [Alat dan bahan Modul 05],
  "tbl:m05-alat",
)

#penting[
  *Baud modul ini 115200*, berbeda dari M01--M04 yang memakai 9600. Serial
  Monitor yang masih tersetel 9600 akan menampilkan karakter acak --- gejala
  yang sering disangka kerusakan perangkat.
]

*Struktur proyek*

#diagram(```
Modul05_lora_master_slave/
├── platformio.ini              ← 3 environment; nomor slave lewat build flag
├── monitor_serial.py           ← pantau 3 node, ringkas siklus/keberhasilan/[IGNORE]
├── lora_monitor.py             ← dashboard tiga node dalam satu layar (butuh `rich`)
├── upload_auto.py              ← deteksi port otomatis saat unggah
├── logserial.md                ← log referensi hasil uji perangkat
├── lora_session_20260516_071007.csv   ← contoh rekaman sesi (referensi)
└── src/
    ├── master/main.cpp         ← polling round-robin + statistik per node
    └── slave/main.cpp          ← satu source untuk kedua slave
```.text)

== Kode Program

#sumber-kode("Modul05_lora_master_slave",
  ("platformio.ini", "src/master/main.cpp", "src/slave/main.cpp",
   "monitor_serial.py", "lora_monitor.py", "upload_auto.py"))

#kode-berkas("Modul05_lora_master_slave/platformio.ini",
  [`platformio.ini` Modul 05 --- tiga environment, nomor slave lewat build flag],
  "lst:m05-ini",
  pecah: true,
)

#kode-berkas("Modul05_lora_master_slave/src/master/main.cpp",
  [`src/master/main.cpp` --- polling round-robin dan statistik per node],
  "lst:m05-master",
  pecah: true,
)

#kode-berkas("Modul05_lora_master_slave/src/slave/main.cpp",
  [`src/slave/main.cpp` --- satu source untuk kedua slave],
  "lst:m05-slave",
  pecah: true,
)

#kode-berkas("Modul05_lora_master_slave/monitor_serial.py",
  [`monitor_serial.py` --- pantau tiga node pada satu sumbu waktu],
  "lst:m05-monitor",
  pecah: true,
)

#kode-berkas("Modul05_lora_master_slave/lora_monitor.py",
  [`lora_monitor.py` --- dasbor tiga node dengan perekaman CSV],
  "lst:m05-dashboard",
  pecah: true,
)

#kode-berkas("Modul05_lora_master_slave/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah],
  "lst:m05-upload",
  pecah: true,
)

== Build dan Flash

*Kedua slave lebih dahulu*, master belakangan.

#keluaran("pio run -d Modul05_lora_master_slave -e slave1 -t upload
pio run -d Modul05_lora_master_slave -e slave2 -t upload
pio run -d Modul05_lora_master_slave -e master -t upload -t monitor")

*Memantau ketiga node sekaligus.* Tiga Serial Monitor terpisah menyulitkan
penilaian urutan kejadian, karena tiap jendela memiliki sumbu waktunya sendiri.
Tersedia dua alat.

`monitor_serial.py` --- sama seperti Modul 01--04, tanpa pustaka tambahan, dan
meringkas hasil ukur saat berhenti.

#keluaran("python3 Modul05_lora_master_slave/monitor_serial.py --baud 115200 --durasi 40
python3 Modul05_lora_master_slave/monitor_serial.py --baud 115200 --port S2=/dev/ttyUSB0")

#keluaran("  Siklus polling : 53  (nomor 7..59)
  Lama siklus min/maks/rata-rata : 147 / 154 / 152 ms
  Slave 1 : dipanggil 53  menjawab 52  gagal 0  -> keberhasilan 98.1 %
  Slave 2 : dipanggil 52  menjawab 52  gagal 0  -> keberhasilan 100.0 %
  S1 membuang 116 panggilan milik node lain ([IGNORE])
  S2 membuang 115 panggilan milik node lain ([IGNORE])")

`lora_monitor.py` --- dasbor berwarna dengan perekaman CSV, memerlukan pustaka
`rich`.

#keluaran("pip install pyserial rich
python3 lora_monitor.py --master /dev/ttyACM0 --s1 /dev/ttyACM1 --s2 /dev/ttyACM2 --baud 115200
python3 lora_monitor.py --master /dev/ttyACM0 --s1 /dev/ttyACM1 --s2 /dev/ttyACM2 --out sesi1.csv")

Berkas `lora_session_20260516_071007.csv` adalah contoh keluarannya, berguna
untuk melihat format kolom sebelum merekam sesi sendiri. Rekaman itu diambil
dengan revisi firmware terdahulu, sehingga baris pembukanya masih mencetak nama
port Windows (`Peran: MASTER (COM3)`) --- firmware sekarang mencetak nama
environment PlatformIO. Isi dan format kolomnya tetap sama.

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada ketiga shield.],
  [`pio device list` dijalankan, ketiga port dicatat dan diisikan ke
   `platformio.ini`.],
  [Serial Monitor *115200* baud disiapkan, bukan 9600.],
  [Label fisik ditempel pada board: MASTER, SLAVE 1, SLAVE 2.],
))

== Percobaan

=== EXP-01 --- Slave Menyaring Panggilan

Nyalakan kedua slave lebih dahulu tanpa master, lalu nyalakan master dan amati
Serial kedua slave.

*Expected output --- Slave 1*

#keluaran("=== LoRa SLAVE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
Menunggu POLL:1 dari Master...

[RX] POLL:1 | RSSI: -62 dBm | SNR: 9.00 dB | RX#: 1
[TX] S1:DATA:1

[IGNORE] POLL:2
[IGNORE] S2:DATA:1")

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Apakah Slave 1 menerima `POLL:2`?], [#isian],
    [Apa yang dilakukannya terhadap paket itu?], [#isian],
    [Jumlah `[IGNORE]` per siklus di tiap slave], [#isian],
  ),
  [Lembar pengamatan EXP-01],
  "tbl:m05-exp01",
)

#checkpoint[
  Setiap slave *menerima* panggilan untuk slave lain, lalu membuangnya. Inilah
  bukti langsung bahwa LoRa tidak memiliki pengalamatan: penyaringan sepenuhnya
  dikerjakan aplikasi. Slave yang tidak pernah mencetak `[IGNORE]` berarti
  tidak mendengar panggilan sama sekali --- periksa jarak dan antena.
]

=== EXP-02 --- Siklus Round-Robin

Amati master selama dua menit.

*Expected output --- master*

#keluaran("========================================
=== CYCLE 8 ===
[TX] POLL:1
[RX] S1:DATA:35 | RSSI: -58 dBm | SNR: 9.50 dB
[TX] POLL:2
[RX] S2:DATA:8 | RSSI: -56 dBm | SNR: 9.75 dB
--- STATISTIK ---
S1: OK=8 | FAIL=0 | Data: 35
S2: OK=8 | FAIL=0 | Data: 8
Durasi siklus: 148 ms
========================================")

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Lama siklus saat kedua slave sehat (ms)], [#isian],
    [Jumlah siklus per menit], [#isian],
    [`OK` / `FAIL` Slave 1 setelah 2 menit], [#isian],
    [`OK` / `FAIL` Slave 2 setelah 2 menit], [#isian],
    [RSSI Slave 1 / Slave 2 (dBm)], [#isian],
  ),
  [Lembar pengamatan EXP-02],
  "tbl:m05-exp02",
)

#buka-abstraksi[
  Di `src/slave/main.cpp`, `dataCounter++` sengaja diletakkan *sesudah* paket
  diterima tetapi *sebelum* `transmit()`, sementara komentarnya menjelaskan
  alasannya. Bandingkan dengan `rxCount++` yang naik lebih awal. Jawab: apa
  arti berbeda dari kedua penghitung itu, dan angka mana yang akan berbeda
  dengan `Data:` yang tercatat master ketika sebagian jawaban hilang di udara?
]

#checkpoint[
  Nilai `Data:` di master harus mengikuti penghitung slave secara berurutan.
  Lompatan pada nilai itu berarti ada jawaban yang tidak sampai --- catat,
  karena itulah bahan tabel pengukuran.
]

=== EXP-03 --- Satu Node Hilang

Uji ketahanan jadwal ketika salah satu slave menghilang.

#tbl(
  table(
    columns: (auto, auto, 1fr, 1.2fr),
    align: (center + horizon, left, left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[\#], th[Skenario], th[Langkah], th[Yang diamati]),
    [1], [Slave 2 mati], [Cabut USB Slave 2], [pesan master, lama siklus, `FAIL`],
    [2], [Slave 2 kembali], [Pasang lagi], [berapa siklus sampai `OK` bertambah lagi],
    [3], [Kedua slave mati], [Cabut keduanya], [lama siklus saat sunyi total],
    [4], [Slave 1 dijauhkan], [Bawa ke jarak 50 m], [`FAIL` Slave 1 vs Slave 2],
  ),
  [Skenario EXP-03 --- satu node hilang],
  "tbl:m05-exp03",
)

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Pesan master saat slave tidak menjawab], [#isian],
    [Lama siklus dengan satu slave mati (ms)], [#isian],
    [Lama siklus dengan kedua slave mati (ms)], [#isian],
    [Apakah Slave 1 terpengaruh oleh matinya Slave 2?], [#isian],
    [Apakah pemulihan terjadi otomatis?], [#isian],
  ),
  [Lembar pengamatan EXP-03 --- data],
  "tbl:m05-exp03-data",
)

#checkpoint[
  Skenario 3 memperlihatkan sifat penting penjadwalan terpusat: lama siklus
  *membengkak* menjadi sekitar jumlah seluruh batas waktu, karena master tetap
  menunggu setiap node yang sudah tidak ada. Catat angkanya --- inilah dasar
  perhitungan batas skala pada bagian Analisis.
]

=== EXP-04 --- Tabrakan yang Disengaja

Percobaan ini memperlihatkan mengapa penjadwalan diperlukan. Ubah *kedua* slave
agar menjawab panggilan mana pun, dengan mengganti pemeriksaan nomor seperti
pada @lst:m05-exp04.

#kode(```cpp
  // Sengaja dilumpuhkan untuk EXP-04: kedua slave menjawab semua panggilan
  // if (!received.equals("POLL:" + String(SLAVE_ID))) { ... return; }
```.text,
  [Penyaringan nomor slave yang sengaja dilumpuhkan untuk EXP-04],
  "lst:m05-exp04",
)

Unggah ke kedua slave, amati master selama satu menit, lalu *kembalikan
kodenya*.

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Berapa jawaban yang berhasil dipecahkan master?], [#isian],
    [Pesan apa yang muncul di master?], [#isian],
    [Apakah master menerima campuran keduanya?], [#isian],
  ),
  [Lembar pengamatan EXP-04 --- tabrakan yang disengaja],
  "tbl:m05-exp04-data",
)

#checkpoint[
  Sebagian besar siklus akan berakhir dengan `[FAIL]` atau
  `[WARN] Balasan tidak valid`, padahal kedua slave jelas-jelas mengirim.
  Tabrakan tidak menghasilkan pesan kesalahan dari radio --- hanya kesunyian
  atau data rusak. Pengamatan ini adalah inti seluruh modul.
]

*Perhatikan kolom SNR.* Pada pengujian rujukan, SNR di master anjlok dari
9,0--9,8 dB menjadi *1,25--1,75 dB* begitu kedua slave menjawab bersamaan:
jawaban satu slave menjadi derau bagi jawaban slave lainnya. Inilah cara paling
langsung mendeteksi tabrakan dari sisi aplikasi, dan bahan jawaban pertanyaan
nomor 5 pada bagian Analisis. Perhatikan pula bahwa kegagalannya *tidak
merata* --- Slave 2 tetap terbaca master sedangkan Slave 1 tidak pernah
berhasil sama sekali, karena penerima memenangkan sinyal yang lebih kuat
(_capture effect_). Dari sisi master, node yang kalah tampak seperti mati.

=== Verifikasi Perangkat Keras (Log Referensi)

Dijalankan pada tiga Arduino Uno bershield Dragino LoRa v1.2, 433 MHz, jarak
#sym.plus.minus 30 cm. Log lengkap ada di `logserial.md`.

#tbl(
  table(
    columns: (1.2fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil terukur]),
    [Siklus dalam 40 detik], [*53* --- lama siklus 147 / 154 / *152 ms*],
    [Keberhasilan kedua slave], [*100 %*, 0 `FAIL`],
    [`[IGNORE]` per slave per siklus], [*2* --- panggilan _dan_ jawaban milik node lain],
    [Lama siklus saat satu node mati], [*611 ms* --- melipat *4×* dari 152 ms],
    [Pertambahan akibat satu node mati], [+459 ms #sym.approx `POLL_TIMEOUT`],
    [Apakah node sehat ikut terganggu?], [tidak],
    [*EXP-04 tabrakan: SNR di master*], [*9,0--9,8 dB #sym.arrow 1,25--1,75 dB*],
    [EXP-04: keberhasilan Slave 1], [100 % #sym.arrow *0 %* (kalah _capture_ dari Slave 2)],
  ),
  [Hasil verifikasi perangkat keras Modul 05],
  "tbl:m05-verifikasi",
)

#keluaran("Environment    Status    Flash
master         SUCCESS   29.7% (9574 B)
slave1         SUCCESS   26.3% (8492 B)
slave2         SUCCESS   26.3% (8492 B)")

Master paling besar karena memuat penjadwal dan statistik dua node. Kedua slave
berukuran sama persis --- bukti bahwa keduanya berasal dari source yang sama
dan hanya berbeda nilai `SLAVE_ID`.

*Verifikasi ulang --- 21 Agustus 2026.* Ketiga board diunggah ulang dan direkam
40 detik pada konfigurasi port yang berbeda dari log di atas (ketiganya kini
Uno asli, `ttyACM0/1/2`, bukan lagi klon CH340). Lama siklus steady-state
*147--149 ms, rata-rata 148,0 ms* (n = 59) --- sejalan dengan sesi sebelumnya.
Balasan Slave 2 pada sesi ini sempat menunjukkan *SNR rendah tak wajar*
(rata-rata 1,23 dB, mirip tanda tabrakan pada @tbl:m05-verifikasi) meski
Slave 2 sendiri menerima `POLL:2` dengan bersih (9,00 dB) --- gangguannya ada
di penerimaan master, bukan di Slave 2.

*Anomali itu terselesaikan pada sesi lanjutan hari yang sama*, setelah bug
banner startup diperbaiki (lihat catatan di bawah) dan kedua slave diunggah
ulang: RSSI balasan Slave 2 turun dari #sym.minus 39 dBm menjadi
*#sym.minus 61 dBm* --- sepadan dengan Slave 1 (#sym.minus 65 dBm) --- dan
SNR-nya kembali normal, *rata-rata 9,34 dB* dari 60 balasan, tidak satu pun di
bawah 5 dB. Dugaannya terkonfirmasi: pada sesi anomali, Slave 2 kemungkinan
besar duduk terlalu dekat dengan master, menyebabkan penerima master jenuh
(near-field), bukan tabrakan sungguhan. Rincian dan tabel perbandingan kedua
sesi ada di `logserial.md`, bagian "Verifikasi anomali SNR --- sesi lanjutan
21 Agustus 2026".

#catatan[
  *Catatan perbaikan --- banner yang berbohong.* Sebelum diperbaiki,
  `src/slave/main.cpp` mencetak
  `Serial.println(F("Menunggu POLL:1 dari Master...\n"))` sebagai literal
  tetap, tidak memakai `SLAVE_ID` --- sehingga Slave 2 pun mencetak "menunggu
  POLL:1" di layarnya sendiri, padahal logika penyaringannya
  (`received.equals("POLL:" + String(SLAVE_ID))`) sudah benar sejak awal. Bug
  ini murni kosmetik --- tidak memengaruhi jawaban maupun statistik --- tetapi
  cukup untuk menyesatkan siapa pun yang mendiagnosis dari banner saja. Baris
  itu sekarang `Serial.print(F("Menunggu POLL:")); Serial.print(SLAVE_ID);`
  --- bukti bahwa dua baris kode yang tampak sepele pun bisa diam-diam salah
  selama tidak ada yang membandingkannya dengan `SLAVE_ID` sungguhan.
]

// Log serial lengkap dari Modul05_lora_master_slave/logserial.md. Hanya dicetak pada
// edisi dosen agar tidak disalin mahasiswa sebagai hasil laporan
// (lihat config.typ).
#if edisi_buku == "dosen" [
  === Log Serial Terverifikasi

  Log serial lengkap hasil uji pada board nyata, bukan contoh. Bagian ini
  hanya dicetak pada edisi dosen.

  Hasil aktual dari perangkat. Baud *115200*, frekuensi *433 MHz*, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `POLL_TIMEOUT` 500 ms. Ketiga board di satu meja, jarak ±30 cm.

  *Board & Port*

  #tbl(
    table(
      columns: (auto, auto, auto, 1fr),
      align: (left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Peran], th[Environment], th[Port], th[Board]),
      [Master], [`master`], [`/dev/ttyACM0`], [Uno asli (`2341:0043`)],
      [Slave 1], [`slave1`], [`/dev/ttyACM1`], [Uno asli (`2341:0043`)],
      [Slave 2], [`slave2`], [`/dev/ttyUSB0`], [Uno klon, bridge CH340 (`1a86:7523`)],
    ),
    [Log serial Modul 05: Board & Port],
    "tbl:m05-log-1",
  )

  Board ketiga pada pengujian ini adalah klon ber-bridge CH340 yang muncul sebagai `/dev/ttyUSB0`, bukan `/dev/ttyACM2` seperti tertulis di `platformio.ini`. Karena itu unggahan dan pemantauannya memakai `--upload-port /dev/ttyUSB0` dan `--port S2=/dev/ttyUSB0`.

  Ketiga aliran serial direkam bersamaan memakai `monitor_serial.py`.

  *EXP-01 — Slave Menyaring Panggilan*

  #keluaran("[   1.822] S1 | === LoRa SLAVE 1 ===
[   1.822] S1 | Init LoRa ... OK
[   1.822] S1 | Menunggu POLL:1 dari Master...
[   1.822] S1 | [RX] POLL:1 | RSSI: -62 dBm | SNR: 9.00 dB | RX#: 1
[   1.822] S1 | [TX] S1:DATA:1
[   1.822] S1 | [IGNORE] POLL:2
[   1.822] S1 | [IGNORE] S2:DATA:1
[   1.831] S2 | [RX] POLL:2 | RSSI: -62 dBm | SNR: 9.00 dB | RX#: 1
[   1.831] S2 | [TX] S2:DATA:1
[   2.432] S2 | [IGNORE] POLL:1
[   2.432] S2 | [IGNORE] S1:DATA:2", pecah: true)

  #tbl(
    table(
      columns: (auto, 1fr),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Apakah Slave 1 menerima `POLL:2`?], [*ya* — lalu dibuang],
      [Baris `[IGNORE]` per siklus di tiap slave], [*2* (`POLL` milik node lain + jawaban node lain)],
      [Total `[IGNORE]` selama 40 detik], [S1: 116, S2: 115],
      [Flash master / slave1 / slave2], [29,6 % / 26,3 % / 26,3 %],
    ),
    [Log serial Modul 05: EXP-01 — Slave Menyaring Panggilan],
    "tbl:m05-log-2",
  )

  *CHECKPOINT terpenuhi.* Setiap slave menerima panggilan untuk slave lain, lalu membuangnya. Yang menarik, slave juga membuang *jawaban* slave lain (`[IGNORE] S2:DATA:1`) — bukti bahwa di LoRa mentah setiap node mendengar seluruh lalu lintas, dan penyaringan sepenuhnya dikerjakan aplikasi.

  *EXP-02 — Siklus Round-Robin (40 detik)*

  #keluaran("[   6.307] MASTER | === CYCLE 8 ===
[   6.307] MASTER | [TX] POLL:1
[   6.507] MASTER | [RX] S1:DATA:35 | RSSI: -58 dBm | SNR: 9.50 dB
[   6.507] MASTER | [TX] POLL:2
[   6.507] MASTER | [RX] S2:DATA:8 | RSSI: -56 dBm | SNR: 9.75 dB
[   6.507] MASTER | --- STATISTIK ---
[   6.507] MASTER | S1: OK=8 | FAIL=0 | Data: 35
[   6.507] MASTER | S2: OK=8 | FAIL=0 | Data: 8
[   6.507] MASTER | Durasi siklus: 148 ms", pecah: true)

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Siklus selesai dalam 40 detik], [*53*],
      [Lama siklus min / maks / rata-rata], [147 / 154 / *152 ms*],
      [Slave 1: dipanggil / menjawab / gagal], [53 / 52 / *0*],
      [Slave 2: dipanggil / menjawab / gagal], [52 / 52 / *0*],
      [RSSI di master (dari kedua slave)], [−58 … −55, rata-rata −56,3 dBm],
      [RSSI di S1 / S2 (dari master)], [−62,0 / −61,8 dBm],
      [SNR di seluruh node], [±9,0–9,8 dB],
    ),
    [Log serial Modul 05: EXP-02 — Siklus Round-Robin (40 detik)],
    "tbl:m05-log-3",
  )

  Selisih satu jawaban pada Slave 1 berasal dari siklus terakhir yang terpotong saat perekaman berhenti, bukan paket hilang.

  Lama siklus 152 ms terbagi menjadi dua giliran ±76 ms. Karena master menambahkan `CYCLE_INTERVAL` 500 ms di antara siklus, satu node terbaca ulang setiap ±650 ms.

  *EXP-03 — Satu Node Hilang*

  Ketiadaan Slave 2 ditirukan dengan mengunggah *sketsa diam* (radio tidak pernah diinisialisasi), bukan mencabut USB.

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Lama siklus saat kedua slave sehat], [*152 ms*],
      [Lama siklus saat Slave 2 mati], [*611 ms* (min 610, maks 612)],
      [Pertambahan akibat satu node mati], [*+459 ms*],
      [`[FAIL] Slave 2 tidak merespon!` selama 14 detik], [11],
      [Apakah Slave 1 ikut terganggu?], [*tidak* — `OK` Slave 1 terus bertambah],
      [Lama siklus setelah Slave 2 kembali], [178 ms (kembali normal)],
      [Pemulihan], [otomatis, tanpa mereset master],
    ),
    [Log serial Modul 05: EXP-03 — Satu Node Hilang],
    "tbl:m05-log-4",
  )

  Pertambahan 459 ms mendekati `POLL_TIMEOUT` 500 ms dikurangi waktu yang biasanya dipakai jawaban yang sehat (±40 ms). Dengan kata lain, *master tetap membayar penuh waktu tunggu untuk node yang sudah tidak ada*. Lama siklus melipat *empat kali* hanya karena satu dari dua node mati — dan pelipatan itu memperlambat pembacaan node yang masih hidup.

  Perkiraan lama siklus yang dapat diuji ulang:

  #keluaran("lama siklus ≈ (jumlah node hidup × ±76 ms) + (jumlah node mati × 500 ms)", pecah: true)

  *EXP-04 — Tabrakan yang Disengaja*

  Penyaringan `POLL:<id>` dilumpuhkan pada *kedua* slave, sehingga keduanya menjawab setiap panggilan.

  #keluaran("[  2.78] [TX] POLL:1
[  2.86] [WARN] Balasan tidak valid: S2:DATA:3
[  3.31] [FAIL] Slave 1 tidak merespon!
[  3.31] [TX] POLL:2
[  3.39] [RX] S2:DATA:4 | RSSI: -54 dBm | SNR: 1.25 dB
[  3.39] S1: OK=0 | FAIL=2 | Data: 0
[  3.39] S2: OK=2 | FAIL=0 | Data: 4", pecah: true)

  #tbl(
    table(
      columns: (1fr, auto, auto),
      align: (left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Penyaringan aktif], th[Penyaringan dilumpuhkan]),
      [Jawaban terbaca master (30 detik)], [±53 per node], [23 total],
      [`[FAIL] tidak merespon`], [0], [*27*],
      [`[WARN] Balasan tidak valid`], [0], [*24*],
      [Lama siklus rata-rata], [152 ms], [*643 ms*],
      [*SNR di master*], [*9,0–9,8 dB*], [*1,25–1,75 dB*],
      [Keberhasilan Slave 1], [100 %], [*0 %* (OK\=0, FAIL\=27)],
    ),
    [Log serial Modul 05: EXP-04 — Tabrakan yang Disengaja],
    "tbl:m05-log-5",
  )

  _Bacaan hasil_

  *Tabrakan tidak memunculkan pesan kesalahan dari radio.* Master tidak pernah mencetak "collision" atau semacamnya — yang terlihat hanya `[FAIL] tidak merespon` dan `[WARN] Balasan tidak valid`, dua pesan yang tampak seperti masalah lain sama sekali. Padahal kedua slave jelas-jelas mengirim setiap kali.

  *SNR adalah petunjuk yang paling jujur.* Saat penyaringan aktif, SNR bertahan di 9–9,8 dB. Saat kedua slave memancar bersamaan, SNR anjlok ke 1,25–1,75 dB — sekitar *8 dB lebih buruk* — karena jawaban satu slave menjadi derau bagi jawaban slave lainnya. Inilah cara mendeteksi tabrakan dari sisi aplikasi tanpa dukungan radio, dan menjadi jawaban pertanyaan nomor 5 pada bagian Analisis.

  *Satu node menang, satu node hilang sama sekali.* Master masih dapat memecahkan jawaban Slave 2 (efek _capture_: sinyal yang lebih kuat memenangkan penerima), sedangkan Slave 1 tidak pernah berhasil satu kali pun. Kegagalan tabrakan karena itu tidak merata — ia menghukum node yang lebih lemah, dan dari sisi master node itu tampak seperti mati.

  *Penghitung master menjadi tidak bermakna.* Nilai `Data:` Slave 2 bertambah dua tiap siklus karena ia menjawab dua panggilan, sedangkan Slave 1 tertahan di 0. Statistik yang biasanya dipercaya justru menyesatkan ketika asumsi dasarnya — satu panggilan, satu penjawab — dilanggar.

  *Sesi verifikasi ulang — 21 Agustus 2026*

  Ketiga board diunggah ulang dari `src/` saat ini (`pio run -e slave1|slave2|master -t upload`, ketiganya SUCCESS, flash terverifikasi avrdude) lalu direkam 40 detik dengan reset serentak lewat DTR. Tujuannya memverifikasi bahwa ketiga node yang tersambung memang menjalankan firmware modul ini — bukan mengulang EXP-01–04 secara penuh.

  *Board & Port saat ini* — berbeda dari tabel di atas: ketiga board sekarang Uno asli (`2341:0043`) pada `/dev/ttyACM0` (master), `/dev/ttyACM1` (slave1), `/dev/ttyACM2` (slave2). Tidak ada lagi board klon CH340 di rig ini.

  #keluaran("[  20.373] MASTER  | === CYCLE 44 ===
[  20.373] MASTER  | [TX] POLL:1
[  20.373] MASTER  | [RX] S1:DATA:44 | RSSI: -56 dBm | SNR: 9.50 dB
[  20.373] MASTER  | [TX] POLL:2
[  20.433] S2      | [RX] POLL:2 | RSSI: -34 dBm | SNR: 9.00 dB | RX#: 36
[  20.433] S2      | [TX] S2:DATA:36
[  20.573] MASTER  | [RX] S2:DATA:36 | RSSI: -38 dBm | SNR: 1.50 dB
[  20.573] MASTER  | --- STATISTIK ---
[  20.573] MASTER  | S1: OK=43 | FAIL=1 | Data: 44
[  20.573] MASTER  | S2: OK=42 | FAIL=2 | Data: 36
[  20.573] MASTER  | Durasi siklus: 147 ms", pecah: true)

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Siklus penuh dalam 40 detik], [*61* (60 bernomor berurutan)],
      [`Durasi siklus` steady-state min/maks/rata-rata], [147 / 149 / *148,0 ms* (n\=59, mengecualikan 2 siklus timeout)],
      [Periode siklus sesungguhnya (jarak antar `=== CYCLE n ===`)], [600 / 769 / *655,0 ms* (n\=57 steady-state)],
      [Bagian periode yang tak tampak pada `Durasi siklus`], [*507 ms ≈ 77 %* — didominasi `delay(CYCLE_INTERVAL)` 500 ms],
      [Biaya perangkat lunak per paket (dari 148,0 ms − 134,1 ms air time, dibagi 4 paket)], [*≈ 3,5 ms/paket*],
      [Slave 1: dipanggil / OK / FAIL], [61 / 71\\\* / 2 → 97,3 %],
      [Slave 2: dipanggil / OK / FAIL], [61 / 71\\\* / 2 → 97,3 %],
      [`[IGNORE]` per slave (40 detik)], [S1: 120, S2: 120],
      [SNR balasan Slave 1 di master], [9,25–9,75 dB, rata-rata *9,50 dB* (n\=58)],
      [SNR balasan Slave 2 di master], [0,75–1,75 dB, rata-rata *1,23 dB* (n\=60)],
      [RSSI balasan Slave 1 / Slave 2 di master], [−56 dBm (stabil) / *−39 dBm* (lebih kuat)],
    ),
    [Log serial Modul 05: Sesi verifikasi ulang — 21 Agustus 2026],
    "tbl:m05-log-6",
  )

  \\\* jumlah `OK` melebihi jumlah siklus karena firmware langsung reset saat unggahan sebelum jendela 40 detik mulai dihitung; angka `OK`/`FAIL` diambil dari statistik kumulatif master di akhir sesi, `[IGNORE]` dan SNR/RSSI dari jendela 40 detik penuh.

  *Anomali belum terjelaskan — SNR Slave 2 rendah secara konsisten.* Seluruh 60 balasan Slave 2 pada sesi ini bersnr di bawah 2 dB — persis kisaran yang menurut analisis EXP-04 pada modul ini menjadi tanda tabrakan (bandingkan 1,25–1,75 dB pada tabel EXP-04 di atas). Namun konteksnya berbeda: tidak ada percobaan tabrakan yang sengaja dijalankan di sesi ini, dan *Slave 2 sendiri menerima `POLL:2` dengan SNR bersih 9,00 dB* — jadi yang terganggu bukan penerimaan Slave 2, melainkan penerimaan *master* saat Slave 2 membalas. RSSI balasan Slave 2 di master juga jauh lebih kuat daripada Slave 1 (−39 dBm vs −56 dBm), mengindikasikan Slave 2 duduk jauh lebih dekat ke master pada sesi ini — kemungkinan penyebabnya near-field/kejenuhan penerima pada jarak sangat dekat, bukan tabrakan sungguhan, tetapi ini *belum dipastikan* dan perlu diperiksa langsung (jarak fisik Slave 2 terhadap master, kondisi antena) sebelum angka SNR ini dipakai sebagai rujukan kondisi normal. Meski begitu keberhasilan paket (`OK`/`FAIL`) tidak terpengaruh — seluruh balasan tetap terdekode benar.

  *Verifikasi anomali SNR — sesi lanjutan 21 Agustus 2026*

  Sesi sebelumnya ("Sesi verifikasi ulang — 21 Agustus 2026" di atas) mencatat SNR balasan Slave 2 anjlok ke rata-rata 1,23 dB pada seluruh 60 balasan, mirip tanda tabrakan pada EXP-04, padahal tidak ada percobaan tabrakan yang dijalankan. Antara sesi itu dan sesi ini, firmware slave juga diperbaiki: banner startup sebelumnya selalu mencetak `Menunggu POLL:1` untuk kedua slave (`SLAVE_ID` tidak dipakai di baris itu); sekarang mencetak nomor yang benar. Kedua slave diunggah ulang, lalu direkam 40 detik lagi tanpa mengubah posisi board secara sengaja.

  #keluaran("[  20.023] S1      | [RX] POLL:1 | RSSI: -70 dBm | SNR: 8.75 dB | RX#: 61
[  20.023] S1      | [TX] S1:DATA:61
[  20.023] S2      | [RX] POLL:2 | RSSI: -67 dBm | SNR: 8.75 dB | RX#: 36
[  20.023] S2      | [TX] S2:DATA:36
[  20.121] MASTER  | [RX] S2:DATA:36 | RSSI: -61 dBm | SNR: 9.25 dB
[  20.121] MASTER  | --- STATISTIK ---", pecah: true)

  #tbl(
    table(
      columns: (auto, auto, 1fr),
      align: (left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Sesi sebelumnya (anomali)], th[Sesi ini]),
      [RSSI balasan S2 di master], [*−39 dBm* (janggal, jauh lebih kuat dari S1)], [*−61 dBm* (n\=60, sepadan dengan S1)],
      [SNR balasan S2 di master], [*0,75–1,75 dB, rata-rata 1,23 dB*], [*8,75–9,75 dB, rata-rata 9,34 dB* (n\=60)],
      [SNR balasan S1 di master], [9,25–9,75 dB, rata-rata 9,50 dB], [8,50–9,50 dB, rata-rata 9,06 dB (n\=59)],
      [S2 SNR \< 5 dB], [60 / 60], [*0 / 60*],
      [`Durasi siklus` steady-state], [147–149 ms, rata-rata 148,0 ms (n\=59)], [147–149 ms, rata-rata *148,1 ms* (n\=61)],
      [Siklus dalam jendela 40 detik], [61], [61],
      [`[FAIL]` dalam jendela], [S1: 1, S2: 2 (dari statistik kumulatif, bukan murni jendela)], [S1: *1*, S2: *0* (dihitung langsung dari baris `[FAIL]` dalam jendela)],
    ),
    [Log serial Modul 05: Verifikasi anomali SNR — sesi lanjutan 21 Agustus 2026],
    "tbl:m05-log-7",
  )

  *Kesimpulan.* Anomali SNR Slave 2 tidak berulang. RSSI-nya turun dari −39 dBm ke −61 dBm — mendekati RSSI Slave 1 (−65 dBm pada sesi ini) — sehingga dugaan sebelumnya terkonfirmasi: pada sesi anomali, Slave 2 kemungkinan besar duduk terlalu dekat dengan master, menyebabkan penerima master jenuh atau terpengaruh efek near-field saat mendekode balasannya. Begitu jaraknya kembali wajar, SNR Slave 2 identik pola dengan Slave 1. Durasi siklus (148 ms) dan air time tetap konsisten di kedua sesi, mengonfirmasi angka itu sebagai baseline yang stabil, terlepas dari anomali SNR yang sifatnya spesifik-posisi.

  *Implikasi untuk laporan.* Anomali ini sekaligus contoh nyata poin di bagian "Membaca anomali di log": nilai SNR/RSSI yang janggal pada satu node harus diperiksa dulu terhadap kemungkinan sebab fisik (jarak, posisi, near-field) sebelum disimpulkan sebagai tabrakan atau kegagalan protokol.

  *Catatan pengambilan log*

  - Seluruh perubahan sumber pada EXP-04 dikembalikan, kedua slave diunggah ulang, dan baseline diukur ulang untuk memastikan penyaringan kembali bekerja.
  - Saat menguji EXP-03 dan EXP-04, monitor hanya dijalankan pada port master. Port slave dibiarkan bebas agar dapat diunggahi; monitor yang menahan port membuat `pio run -t upload` gagal membukanya.
  - Tabel pengukuran jarak, skenario asimetris, dan pengaruh `POLL_TIMEOUT` pada README belum terisi: seluruh percobaan dijalankan di satu meja pada jarak tetap ±30 cm.
]

== Pengukuran

*A. Keberhasilan per node terhadap jarak* --- kedua slave ditempatkan pada
jarak sama, 30 siklus per baris.

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
  [Lembar pengukuran A --- keberhasilan per node terhadap jarak],
  "tbl:m05-ukur-a",
)

*B. Skenario asimetris* (wajib) --- Slave 1 didekatkan, Slave 2 dijauhkan.

#tbl(
  table(
    columns: (auto, auto, 1fr, 1fr, 1fr, 1.2fr),
    align: (left, left, left, left, left, left),
    inset: (x: 0.45em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Posisi S1], th[Posisi S2], th[Berhasil S1 (%)], th[Berhasil S2 (%)], th[Lama siklus (ms)], th[Kesimpulan]),
    [1 m], [100 m], [#isian], [], [], [],
  ),
  [Lembar pengukuran B --- skenario asimetris],
  "tbl:m05-ukur-b",
)

*C. Lama siklus terhadap jumlah node yang hidup*

#tbl(
  table(
    columns: (1.2fr, 1fr, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Kondisi], th[Lama siklus (ms)], th[Siklus per menit]),
    [Kedua slave hidup], [#isian], [],
    [Satu slave mati], [#isian], [],
    [Kedua slave mati], [#isian], [],
  ),
  [Lembar pengukuran C --- lama siklus terhadap jumlah node hidup],
  "tbl:m05-ukur-c",
)

*D. Pengaruh batas waktu polling* --- ubah `POLL_TIMEOUT` pada master, jarak
tetap.

#tbl(
  table(
    columns: (auto, 1fr, 1fr, 1fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[`POLL_TIMEOUT`], th[Lama siklus (ms)], th[Berhasil S1 (%)], th[Berhasil S2 (%)]),
    [200 ms], [#isian], [], [],
    [500 ms], [#isian], [], [],
    [1000 ms], [#isian], [], [],
  ),
  [Lembar pengukuran D --- pengaruh batas waktu polling],
  "tbl:m05-ukur-d",
)

== Analisis

+ Dari @tbl:m05-ukur-c, berapa milidetik yang ditambahkan tiap node mati
  terhadap lama siklus? Susun rumus perkiraan lama siklus untuk $n$ slave
  dengan $k$ di antaranya mati.
+ Berdasarkan rumus tersebut, berapa jumlah slave maksimum bila setiap node
  harus terbaca minimal sekali setiap 5 detik pada kondisi terburuk? Sebutkan
  asumsinya.
+ Dari @tbl:m05-ukur-d, apa akibat memperpendek batas waktu menjadi 200 ms?
  Kaitkan dengan waktu udara pada SF7 dan jelaskan mengapa nilai yang terlalu
  kecil menghasilkan kegagalan palsu.
+ Pada @tbl:m05-ukur-b, apakah slave yang jauh menurunkan kualitas slave yang
  dekat? Bandingkan jawabannya dengan perilaku topologi bintang pada modul BLE
  multi-node, dan jelaskan sumber perbedaannya.
+ EXP-04 memperlihatkan tabrakan tidak menghasilkan pesan kesalahan. Sebutkan
  dua cara mendeteksi tabrakan dari sisi aplikasi, beserta keterbatasan
  masing-masing.
+ Pendekatan master-slave menjadwalkan hak bicara secara terpusat. Sebutkan dua
  kelemahan mendasarnya, lalu bandingkan dengan pendekatan lain seperti ALOHA
  atau LoRaWAN kelas A.

== Concept Check

+ Mengapa slave tetap menerima paket yang bukan miliknya, dan di lapisan mana
  penyaringan dilakukan?
+ Apa yang terjadi bila kedua slave menjawab bersamaan, dan mengapa hal itu
  tidak muncul sebagai pesan kesalahan?
+ Apa fungsi `POLL_TIMEOUT`, dan apa yang menentukan nilai terkecilnya yang
  masuk akal?
+ Mengapa `dataCounter` dinaikkan setelah paket diterima dan bukan pada saat
  pengiriman dinyatakan berhasil?
+ Mengapa kedua slave dapat memakai satu file source yang sama?
+ Mengapa modul ini memakai 115200 baud sementara modul sebelumnya 9600? Apa
  gejalanya bila Serial Monitor salah setel?

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Memperbesar dan memperkaya jaringan])[
  / CH-1 --- Slave ketiga: Tambahkan `SLAVE_ID=3`: satu environment baru dan
    penyesuaian `SLAVE_COUNT` di master. Ukur pertambahan lama siklus dan
    bandingkan dengan rumus dari bagian Analisis.

  / CH-2 --- Sensor sungguhan: Ganti penghitung slave dengan pembacaan sensor
    pada A0, lalu kirimkan nilainya (`S1:DATA:512`). Bahas mengapa laju
    pembacaan kini dibatasi lama siklus master.

  / CH-3 --- Perintah turun: Tambahkan perintah `CMD:1:LED_ON` dari master,
    sehingga komunikasi tidak hanya mengambil data tetapi juga mengendalikan
    slave.
]

#tujuan-prak(3, [Penjadwal yang belajar dari kegagalan])[
  / CH-4 --- Jadwal adaptif: Buat master melewati slave yang sudah gagal tiga
    kali berturut-turut, dan menengoknya kembali sekali setiap sepuluh siklus.
    Ukur perbaikan lama siklus saat satu node mati.

  / CH-5 --- Rekam dan analisis: Jalankan `lora_monitor.py --out sesi.csv`
    selama sepuluh menit, lalu olah CSV-nya untuk membuat grafik RSSI terhadap
    waktu bagi kedua slave.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- tabrakan, penjadwalan terpusat, round-robin, batas
  waktu.
+ Konfigurasi --- build flag nomor slave, `POLL_TIMEOUT`, format `POLL:n` dan
  `S<n>:DATA:m`.
+ Hasil eksperimen --- log serial ketiga board (EXP-01 sampai EXP-04 beserta
  checkpoint), sebaiknya rekaman CSV dari `lora_monitor.py`.
+ Data pengukuran --- @tbl:m05-ukur-a sampai @tbl:m05-ukur-d.
+ Analisis dan concept check, termasuk rumus perkiraan lama siklus.
+ Challenge --- minimal CH-1 dan CH-4.
+ Kesimpulan yang disusun sendiri mengenai batas skala pendekatan master-slave
  pada LoRa mentah.
