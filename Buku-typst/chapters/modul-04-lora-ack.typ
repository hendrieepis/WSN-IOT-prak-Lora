// ============================================================================
// Modul 04 — Keandalan Terukur dengan ACK
// Sumber: Modul04_lora_ack/README.md; listing kode dibaca langsung dari
//         salinan berkas sumber di assets/code/Modul04_lora_ack/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist

#chapter("Modul 04 — Keandalan Terukur dengan ACK", l: "bab:modul-04")

#identitas-modul(
  "Modul 04",
  [Know If It Arrived --- Keandalan Terukur dengan ACK],
  [Arduino Uno + Dragino LoRa Shield v1.2 · LoRa mentah · dua arah ·
   RX interrupt + timeout · level Intermediate · 2 × 50 menit ·
   folder kode `Modul04_lora_ack`],
)

#pengantar([Gambaran Umum])[
Modul 04 dirancang untuk dua pertemuan (2 × 50 menit) pada tingkat menengah.
Misinya mengubah pengiriman yang "mudah-mudahan sampai" menjadi pengiriman yang
*diketahui* sampai atau gagal: pengirim menunggu balasan `ACK:n` dalam batas
waktu tertentu, dan mencatat setiap kegagalan. Percobaan memakai dua Arduino
Uno bershield Dragino LoRa v1.2, diamati melalui dua Serial Monitor pada
9600 baud.
]

== Pendahuluan

Tiga modul sebelumnya memindahkan data tanpa pernah tahu nasibnya. Pada M01 dan
M02 pengirim tidak pernah mendapat kabar apa pun; pada M03 balasan memang ada,
tetapi tidak ada yang menghitung berapa kali balasan itu tidak datang. Modul
ini melengkapi bagian yang hilang tersebut, dan bersamanya memperkenalkan
besaran yang menjadi tolok ukur seluruh sistem komunikasi: *berapa persen
pengiriman yang berhasil*. Angka itulah yang membedakan pernyataan "alatnya
jalan" dari "alatnya andal pada jarak sekian".

Prasyaratnya adalah M02 untuk penerimaan berbasis interrupt, dan M03 untuk
percakapan dua arah di atas radio half-duplex. Yang dibangun di sini adalah
protokol permintaan-balasan sederhana dengan nomor urut, penungguan berbatas
waktu tanpa memblokir pewaktu, penolakan balasan yang tidak sesuai harapan,
serta statistik berhasil dan gagal yang berjalan terus. Semuanya dipakai lagi
pada M05 ketika master memakai batas waktu untuk memutuskan sebuah slave
dianggap tidak menjawab.

*Peta modul LoRa*

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
    [*04 (ini)*], [*Setiap pengiriman diketahui hasilnya: ACK, timeout, statistik*],
    [05], [Banyak node --- satu master menjadwalkan giliran bicara],
  ),
  [Peta modul pada arc pertama seri LoRa],
  "tbl:m04-peta",
)

*Kontrak data lab ini.* Permintaan berbentuk `DATA:n` dan balasan `ACK:n`
dengan *nomor yang sama persis*. Kecocokan nomor itulah yang membuat pengirim
tahu balasan yang tiba benar-benar milik paket yang sedang ditunggu, bukan sisa
balasan lama atau milik pasangan board lain. Prinsip pencocokan
permintaan-balasan ini muncul lagi di M05 sebagai `POLL:1` yang harus dijawab
`S1:DATA:n`.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Mengukur keandalan pengiriman, bukan sekadar mengirim])[
  + Menjelaskan mekanisme ACK sebagai alat ukur keandalan, dan membedakannya
    dari sekadar balasan pada M03.
  + Menerapkan penungguan berbatas waktu (_timeout_) yang tidak menghentikan
    pewaktu maupun interrupt.
  + Menjelaskan perlunya mencocokkan nomor urut antara permintaan dan balasan,
    serta akibat bila pencocokan itu dihilangkan.
  + Menghitung tingkat keberhasilan pengiriman dan menyajikannya sebagai fungsi
    jarak.
  + Menjelaskan mengapa ACK menaikkan keandalan sekaligus menurunkan laju data,
    dan kapan pertukaran itu sepadan.
]

*Kriteria keberhasilan*

#checklist((
  [Pengirim mencetak `[OK] ACK diterima!` pada jarak dekat, dengan penghitung
   `FAIL` tetap nol.],
  [Penerima membalas setiap `DATA:n` dengan `ACK:n` bernomor sama.],
  [Ketika penerima dimatikan, pengirim mencetak `[FAIL]` tepat setelah batas
   waktu, bukan membeku.],
  [Tabel keberhasilan terhadap jarak terisi, minimal empat jarak.],
))

== Dasar Teori (Secukupnya)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [ACK], [_Acknowledgement_ --- balasan yang menyatakan sebuah paket benar-benar diterima.],
    [Timeout], [Batas waktu menunggu balasan. Modul ini memakai 3000 ms.],
    [Nomor urut], [Angka pada payload yang mengikat permintaan dengan balasannya.],
    [Tingkat keberhasilan], [`OK / (OK + FAIL) × 100 %` --- besaran utama yang diukur modul ini.],
    [Kegagalan senyap], [Paket hilang tanpa ada pihak yang menyadarinya. Inilah yang dihapus oleh ACK.],
    [Waktu udara], [Lama sebuah paket mengudara. Menentukan batas bawah nilai timeout yang masuk akal.],
  ),
  [Istilah kerja Modul 04],
  "tbl:m04-istilah",
)

*Mengapa timeout tidak boleh terlalu pendek.* Satu putaran ACK memerlukan waktu
udara paket data, waktu proses penerima, dan waktu udara paket ACK. Pada SF7
dan BW 125 kHz, paket pendek memakan puluhan milidetik; pada SF12 waktu itu
membengkak menjadi lebih dari satu detik untuk sekali jalan. Timeout yang lebih
pendek daripada waktu pulang-pergi akan mencatat kegagalan padahal ACK sedang
dalam perjalanan --- dan yang lebih buruk, ACK yang terlambat tiba akan
tertinggal di antrian dan mengacaukan siklus berikutnya. Karena itu program ini
menolak balasan yang nomornya tidak cocok, alih-alih menerimanya begitu saja.

*Mengapa ACK bukan jaminan sempurna.* ACK hanya membuktikan paket data sampai
ke penerima; ia tidak membuktikan ACK-nya sendiri sampai kembali ke pengirim.
Bila `DATA:5` diterima dengan baik tetapi `ACK:5` hilang di jalan, penerima
mencatat keberhasilan sedangkan pengirim mencatat kegagalan. Keadaan tidak
sepakat ini nyata dan akan terlihat pada pengukuran jarak jauh --- bandingkan
penghitung di kedua sisi pada EXP-03.

*Sekuens yang diamati*

#diagram(```
   Sender                          (udara)                    Receiver
     |                                                    LoRa.receive() aktif
  "DATA:5" ---------------------------------------------->  paket tiba
  LoRa.receive(); mulai hitung mundur 3000 ms               cetak + RSSI + SNR
     |                                                            |
  ackFlag  <---------------------------- "ACK:5" ------------ balas ACK
  cocokkan dengan "ACK:5" yang ditunggu                       kembali RX
     |
  [OK] atau [FAIL] setelah 3000 ms  ->  OK / FAIL dihitung
  delay(3000), lanjut DATA:6
```.text, rapat: true)

== Topologi

#diagram(```
        BOARD #1                                  BOARD #2
  +------------------+  ----- "DATA:n" ----->  +------------------+
  |   Arduino Uno    |                         |   Arduino Uno    |
  | + LoRa Shield    |  <---- "ACK:n" -------  | + LoRa Shield    |
  |   SENDER-ACK     |                         |  RECEIVER-ACK    |
  | timeout 3000 ms  |                         | balas tiap DATA  |
  | statistik OK/FAIL|                         | abaikan non-DATA |
  +------------------+                         +------------------+
     env: sender                                  env: receiver
```.text)

#tbl(
  table(
    columns: (auto, auto, 1.2fr, auto, auto),
    align: (left, left, left, left, left),
    inset: (x: 0.55em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Environment], th[Peran], th[Mekanisme RX], th[Batas waktu]),
    [Sender], [`sender`], [Kirim `DATA:n`, tunggu `ACK:n`], [Interrupt DIO0 + `ackFlag`], [3000 ms],
    [Receiver], [`receiver`], [Terima `DATA:n`, balas `ACK:n`], [Interrupt DIO0 + `rxFlag`], [---],
  ),
  [Peran tiap node Modul 04],
  "tbl:m04-topologi",
)

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
    [1], [Arduino Uno], [ATmega328P], [2],
    [2], [Dragino LoRa Shield], [v1.2, SX1276, 433 MHz], [2],
    [3], [Antena SMA], [*wajib terpasang sebelum diberi daya*], [2],
    [4], [Kabel USB tipe B], [kabel data], [2],
  ),
  [Alat dan bahan Modul 04],
  "tbl:m04-alat",
)

*Struktur proyek*

#diagram(```
Modul04_lora_ack/
├── platformio.ini
├── monitor_serial.py       ← pantau kedua sisi, pisahkan DATA hilang vs ACK hilang
├── upload_auto.py          ← deteksi port otomatis saat unggah
├── logserial.md            ← log referensi hasil uji perangkat
└── src/
    ├── sender/main.cpp     ← kirim DATA:n, tunggu ACK:n, hitung OK/FAIL
    └── receiver/main.cpp   ← terima DATA:n, balas ACK:n, abaikan paket lain
```.text)

== Kode Program

#sumber-kode("Modul04_lora_ack",
  ("platformio.ini", "src/sender/main.cpp", "src/receiver/main.cpp",
   "monitor_serial.py", "upload_auto.py"))

#kode-berkas("Modul04_lora_ack/platformio.ini",
  [`platformio.ini` Modul 04 --- environment `sender` dan `receiver`],
  "lst:m04-ini",
  pecah: true,
)

#kode-berkas("Modul04_lora_ack/src/sender/main.cpp",
  [`src/sender/main.cpp` --- kirim `DATA:n`, tunggu `ACK:n`, hitung OK dan FAIL],
  "lst:m04-sender",
  pecah: true,
)

#kode-berkas("Modul04_lora_ack/src/receiver/main.cpp",
  [`src/receiver/main.cpp` --- terima `DATA:n`, balas `ACK:n`, abaikan paket lain],
  "lst:m04-receiver",
  pecah: true,
)

#kode-berkas("Modul04_lora_ack/monitor_serial.py",
  [`monitor_serial.py` --- pisahkan kegagalan DATA hilang dari ACK hilang],
  "lst:m04-monitor",
  pecah: true,
)

#kode-berkas("Modul04_lora_ack/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah],
  "lst:m04-upload",
  pecah: true,
)

== Build dan Flash

*Penerima lebih dahulu*, agar paket pertama pengirim tidak langsung tercatat
gagal.

#keluaran("pio run -d Modul04_lora_ack -e receiver -t upload -t monitor
pio run -d Modul04_lora_ack -e sender   -t upload -t monitor")

*Memantau kedua board sekaligus.* Lembar pengukuran B menuntut pembandingan
penghitung kedua sisi. Skrip `monitor_serial.py` melakukannya otomatis, dan
memisahkan dua jenis kegagalan yang akibatnya berbeda: DATA yang tidak pernah
tiba, dan DATA yang tiba tetapi ACK-nya hilang di jalan pulang.

#keluaran("python3 Modul04_lora_ack/monitor_serial.py
python3 Modul04_lora_ack/monitor_serial.py --durasi 60 --log sesi1.txt")

#keluaran("  DATA dikirim pengirim  : 14  (nomor 0..13)
  DATA tiba di penerima  : 14
  ACK dibalas penerima   : 14
  ACK kembali ke pengirim: 14
  DATA hilang            : 0 (0.0 %)
  DATA tiba tapi ACK hilang: 0 (0.0 %)
  Keberhasilan menurut pengirim : 100.0 %
  Keberhasilan menurut penerima : 100.0 %
  Waktu DATA->ACK min/maks/rata-rata : 0 / 201 / 143 ms")

#peringatan[
  *Jangan memantau port board yang hendak diunggah.* Monitor menahan port itu,
  sehingga `pio run -t upload` gagal membukanya. Saat menguji EXP-02, pantau
  pengirim saja dan biarkan port penerima bebas.
]

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada kedua shield.],
  [Port kedua board dicatat lewat `pio device list` dan diisikan ke
   `platformio.ini`.],
  [Dua Serial Monitor 9600 baud siap, keduanya terlihat bersamaan.],
  [Penghitung `OK` dan `FAIL` pada pengirim diamati sejak baris pertama.],
))

== Percobaan

=== EXP-01 --- Siklus ACK yang Sehat

Unggah kedua firmware sesuai urutan dan amati sepuluh siklus pertama.

*Expected output --- sender*

#keluaran("=== LoRa ACK SENDER ===
Init LoRa ... OK
Freq: 433.00 MHz | SF7 | ACK timeout: 3000 ms

[TX] Kirim: DATA:0 ... selesai
[RX] Balasan: ACK:0
[OK] ACK diterima! | OK: 1 | FAIL: 0")

*Expected output --- receiver*

#keluaran("=== PAKET DITERIMA ===
  Data  : DATA:0
  RSSI  : -39.00 dBm
  SNR   : 9.75 dB
  Total : 1
=====================
[TX] ACK: ACK:0")

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Nilai `OK` setelah 10 siklus], [#isian],
    [Nilai `FAIL` setelah 10 siklus], [#isian],
    [Tingkat keberhasilan (%)], [#isian],
    [RSSI arah data / arah ACK (dBm)], [#isian],
  ),
  [Lembar pengamatan EXP-01],
  "tbl:m04-exp01",
)

#checkpoint[
  Pada jarak satu meter, `FAIL` harus tetap nol selama sepuluh siklus.
  Munculnya kegagalan pada jarak sedekat itu menandakan masalah perangkat,
  bukan keterbatasan jangkauan --- periksa antena dan catu daya sebelum
  melanjutkan.
]

=== EXP-02 --- Batas Waktu Bekerja

Cabut USB penerima di tengah percobaan, amati pengirim, lalu pasang kembali.

*Expected output --- sender saat penerima mati*

#keluaran("[TX] Kirim: DATA:7 ... selesai
[FAIL] Tidak ada ACK! | OK: 7 | FAIL: 1")

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Selang `[TX]` #sym.arrow `[FAIL]` (detik)], [#isian],
    [Apakah sesuai nilai `ACK_TIMEOUT`?], [#isian],
    [Apakah pengirim tetap melanjutkan siklus?], [#isian],
    [Berapa siklus sampai pulih setelah penerima kembali?], [#isian],
  ),
  [Lembar pengamatan EXP-02],
  "tbl:m04-exp02",
)

#buka-abstraksi[
  Di `src/sender/main.cpp`, penungguan ACK memakai
  `while (millis() - waitStart < ACK_TIMEOUT)` alih-alih `delay(3000)`.
  Jelaskan apa yang tetap dapat dikerjakan pengirim di dalam lingkaran itu,
  lalu telusuri mengapa `updateLED()` dipanggil di dalamnya. Terakhir, jawab:
  apa yang akan rusak bila lingkaran itu diganti `delay(3000)` disusul satu
  pemeriksaan `ackFlag`?
]

#checkpoint[
  Selang dari `[TX]` ke `[FAIL]` harus mendekati 3 detik, dan pengirim wajib
  melanjutkan ke `DATA` berikutnya. Pengirim yang membeku menandakan penungguan
  dilakukan dengan cara yang menghalangi interrupt.
]

=== EXP-03 --- Nomor Urut Harus Cocok

Uji apa yang terjadi ketika balasan tidak sesuai harapan.

#tbl(
  table(
    columns: (auto, 1.2fr, 1.3fr),
    align: (center + horizon, left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Uji], th[Perlakuan], th[Hasil yang diharapkan]),
    [03-a], [Ubah penerima agar membalas `ACK:99` untuk semua paket], [pengirim mencetak peringatan lalu tetap gagal setelah timeout],
    [03-b], [Ubah penerima agar membalas `OKE`], [balasan diabaikan, pengirim tetap menunggu],
    [03-c], [Jalankan pasangan board lain berdekatan dengan program sama], [catat apakah ada ACK milik pasangan lain yang diterima],
  ),
  [Perlakuan EXP-03 --- pencocokan nomor urut],
  "tbl:m04-exp03",
)

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Pesan pengirim saat menerima ACK bernomor salah], [#isian],
    [Apakah `OK` ikut bertambah?], [#isian],
    [Jumlah `OK` di penerima vs `OK` di pengirim setelah 20 siklus], [#isian],
  ),
  [Lembar pengamatan EXP-03],
  "tbl:m04-exp03-data",
)

#checkpoint[
  Uji 03-c adalah yang paling membuka mata. Karena tidak ada alamat sama sekali
  pada LoRa mentah, ACK dari pasangan board lain berpotensi diterima.
  Pencocokan nomor urut menahan sebagian besar di antaranya, tetapi tidak
  seluruhnya --- dan itulah alasan M05 memperkenalkan penomoran node.
]

=== Verifikasi Perangkat Keras (Log Referensi)

Dijalankan pada dua Arduino Uno bershield Dragino LoRa v1.2, 433 MHz, jarak
#sym.plus.minus 30 cm. Log lengkap ada di `logserial.md`.

#tbl(
  table(
    columns: (1.2fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil terukur]),
    [Keberhasilan (45 detik, jarak dekat)], [14/14 --- *100 %* di kedua sisi],
    [Waktu DATA#sym.arrow ACK min/maks/rata-rata], [0 / 201 / *143 ms* (4,8 % dari timeout)],
    [Selang `[TX]` #sym.arrow `[FAIL]` saat penerima mati], [*3,05 s* --- sesuai `ACK_TIMEOUT`],
    [Lama siklus sehat vs gagal], [*3,10 s vs 6,03 s* --- satu kegagalan menggandakannya],
    [Pemulihan setelah penerima kembali], [1 siklus (3,1 s)],
    [EXP-03a/03b: balasan bernomor salah], [tiba, dibaca, *ditolak*; pengirim tetap menunggu sampai timeout],
    [EXP-03c: pasangan board lain], [belum diuji --- hanya dua shield berfungsi],
  ),
  [Hasil verifikasi perangkat keras Modul 04],
  "tbl:m04-verifikasi",
)

#keluaran("Environment    Status    Flash
sender         SUCCESS   23.0% (7424 B)
receiver       SUCCESS   26.9% (8686 B)")

== Pengukuran

*A. Tingkat keberhasilan terhadap jarak* --- masing-masing 20 siklus.

#tbl(
  table(
    columns: (auto, 1fr, 1fr, auto, auto, 1fr),
    align: (left, left, left, left, left, left),
    inset: (x: 0.5em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Jarak], th[RSSI data (dBm)], th[SNR (dB)], th[OK], th[FAIL], th[Keberhasilan (%)]),
    [1 m], [#isian], [], [], [], [],
    [25 m], [#isian], [], [], [], [],
    [50 m], [#isian], [], [], [], [],
    [100 m], [#isian], [], [], [], [],
  ),
  [Lembar pengukuran A --- keberhasilan terhadap jarak],
  "tbl:m04-ukur-a",
)

*B. Ketidaksepakatan kedua sisi* --- bandingkan penghitung pengirim dan
penerima pada jarak yang sama.

#tbl(
  table(
    columns: (auto, 1fr, 1fr, auto, 1.2fr),
    align: (left, left, left, left, left),
    inset: (x: 0.55em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Jarak], th[`OK` di pengirim], th[`Total` di penerima], th[Selisih], th[Tafsiran]),
    [1 m], [#isian], [], [], [],
    [50 m], [#isian], [], [], [],
    [100 m], [#isian], [], [], [],
  ),
  [Lembar pengukuran B --- ketidaksepakatan kedua sisi],
  "tbl:m04-ukur-b",
)

*C. Pengaruh nilai timeout* --- pada jarak tetap 50 m.

#tbl(
  table(
    columns: (auto, auto, auto, 1fr, 1fr),
    align: (left, left, left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[`ACK_TIMEOUT`], th[OK], th[FAIL], th[Keberhasilan (%)], th[Catatan]),
    [500 ms], [#isian], [], [], [],
    [1000 ms], [#isian], [], [], [],
    [3000 ms], [#isian], [], [], [],
  ),
  [Lembar pengukuran C --- pengaruh nilai timeout],
  "tbl:m04-ukur-c",
)

== Analisis

+ Dari @tbl:m04-ukur-a, pada jarak berapa tingkat keberhasilan mulai turun di
  bawah 90 %? Bandingkan dengan jarak tempat loss mulai terlihat pada M01.
+ @tbl:m04-ukur-b memperlihatkan penerima kadang mencatat lebih banyak
  keberhasilan daripada pengirim. Jelaskan mengapa hal itu mungkin terjadi, dan
  sisi mana yang lebih layak dipercaya.
+ Dari @tbl:m04-ukur-c, apa akibat memperpendek timeout? Tentukan nilai
  terkecil yang masih masuk akal untuk SF7, disertai alasan berbasis waktu
  udara.
+ ACK menambah satu paket untuk setiap data yang dikirim. Hitung berapa persen
  tambahan lalu lintas radionya, dan sebutkan satu kondisi ketika tambahan itu
  tidak sepadan.
+ Rancang perbaikan agar `DATA` yang gagal dikirim ulang secara otomatis.
  Sebutkan risiko baru yang muncul, terutama kemungkinan penerima memproses
  data yang sama dua kali.

== Concept Check

+ Apa perbedaan balasan pada M03 dan ACK pada modul ini?
+ Mengapa nomor pada `ACK:n` harus dicocokkan, bukan sekadar diterima apa
  adanya?
+ Mengapa penungguan ACK memakai `millis()`, bukan `delay()`?
+ Apa yang dibuktikan oleh ACK, dan apa yang *tidak* dibuktikannya?
+ Mengapa penerima diunggah lebih dahulu?

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Statistik yang langsung terbaca])[
  / CH-1 --- Kirim ulang otomatis: Ulangi pengiriman `DATA:n` maksimum tiga
    kali sebelum menyatakan gagal, dan tampilkan berapa kali percobaan
    diperlukan untuk tiap keberhasilan.

  / CH-2 --- Persentase langsung: Tampilkan tingkat keberhasilan berjalan dalam
    persen di setiap baris statistik pengirim.
]

#tujuan-prak(3, [Protokol yang menyesuaikan diri])[
  / CH-3 --- Timeout adaptif: Ukur waktu pulang-pergi sepuluh siklus pertama,
    lalu setel timeout menjadi tiga kali rata-rata tersebut. Bandingkan
    hasilnya dengan nilai tetap 3000 ms.

  / CH-4 --- ACK membawa informasi: Sertakan RSSI penerima di dalam ACK
    (`ACK:n:-45`) sehingga pengirim mengetahui kualitas tautan dari sisi
    seberang. Jelaskan mengapa informasi itu tidak dapat diperoleh dengan cara
    lain.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- ACK, timeout, nomor urut, kegagalan senyap.
+ Konfigurasi --- nilai `ACK_TIMEOUT`, format `DATA:n` dan `ACK:n`, parameter
  radio.
+ Hasil eksperimen --- log serial kedua board (EXP-01 sampai EXP-03 beserta
  checkpoint).
+ Data pengukuran --- @tbl:m04-ukur-a, @tbl:m04-ukur-b, dan @tbl:m04-ukur-c.
+ Analisis dan concept check.
+ Challenge --- minimal CH-1 dan CH-2.
+ Kesimpulan yang disusun sendiri, khususnya mengenai harga yang dibayar untuk
  memperoleh kepastian.
