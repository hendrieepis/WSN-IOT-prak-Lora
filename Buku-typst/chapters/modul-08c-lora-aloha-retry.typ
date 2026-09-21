// ============================================================================
// Modul 08C — Random Backoff & Retry: Coba Lagi
// Sumber: Modul08c_lora_aloha_retry/README.md; listing kode dibaca langsung
//         dari salinan berkas sumber di assets/code/Modul08c_lora_aloha_retry/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist

#chapter("Modul 08C — Random Backoff dan Retry: Coba Lagi", l: "bab:modul-08c")

#identitas-modul(
  "Modul 08C",
  [Try Again, Randomly --- Random Backoff dan Retry],
  [Arduino Uno + Dragino LoRa Shield v1.2 · topologi bintang, 2 node + gateway ·
   interrupt + timeout + retry · level Advanced · 1 × 50 menit ·
   folder kode `Modul08c_lora_aloha_retry`],
)

#pengantar([Gambaran Umum])[
Modul 08C dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat lanjut,
dan merupakan pengembangan langsung dari M08B --- bukan modul berdiri sendiri.
*Di modul inilah Pure ALOHA akhirnya lengkap*: rumusan asli Abramson (1970)
memang terdiri dari tiga bagian --- kirim bebas (M08), tunggu ACK (M08B), dan
kirim ulang setelah jeda acak bila ACK tak datang (modul ini). Dua modul
sebelumnya adalah potongan protokol; mulai sekarang yang diukur adalah
protokolnya utuh.
]

== Pendahuluan

Misinya menutup satu kelemahan yang sengaja dibiarkan terbuka di M08B: node
yang mencatat `[FAIL]` tidak pernah mencoba lagi, data itu hilang permanen.
Modul ini menambahkan *satu* kemampuan baru --- kirim ulang otomatis dengan
jeda acak sebelum tiap percobaan --- dan membiarkan segala sesuatu yang lain
(payload, kontrak ACK, parameter radio) tetap sama persis dengan M08B.

M08B membuktikan node bisa _tahu_ apakah paketnya sampai. Modul ini menjawab
pertanyaan lanjutannya: kalau tidak sampai, apa yang seharusnya dilakukan node?
Jawaban paling sederhana --- coba lagi segera --- justru berbahaya pada kanal
bersama: dua node yang bertabrakan lalu sama-sama menunggu jeda *tetap* akan
tetap sinkron dan bertabrakan lagi pada percobaan berikutnya. *Random backoff*
memecah sinkronisasi kebetulan itu dengan memberi tiap node jeda tunggu yang
berbeda-beda secara acak sebelum mencoba ulang. Tetapi retry membawa persoalan
baru yang tidak ada di M08B: gateway kini bisa menerima `SEQ` yang sama dua
kali atau lebih --- bukan karena node mengulang datanya, melainkan karena ACK
sebelumnya yang hilang di jalan. Modul ini mengajarkan cara gateway membedakan
*data baru* dari *duplicate*, sebuah persoalan yang tidak pernah muncul selama
tidak ada retry sama sekali.

Prasyaratnya adalah M08B untuk kontrak `NODE=` dan `ACK=` beralamat serta pola
tunggu-ACK-dengan-timeout. Yang dibangun di sini adalah loop retry berbatas
(`MAX_RETRIES`), jeda acak antar-percobaan (_random backoff_), dan pengenalan
paket duplicate di gateway lewat perbandingan `SEQ` --- tanpa mengubah format
payload maupun format ACK sama sekali. Kontrak `SEQ` yang sama ini dipakai lagi
di M10, tempat slot waktu menggantikan backoff sebagai cara menghindari
tabrakan.

*Peta modul LoRa*

#tbl(
  table(
    columns: (auto, 1fr),
    align: (center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Fokus (yang ditumpuk di atas modul sebelumnya)]),
    [08], [Penjadwalan dilepas --- node kirim bebas, tabrakan senyap diamati],
    [08B], [ACK ditempelkan di atas M08 --- node tahu SUCCESS/FAILED, belum ada retry],
    [*08C (ini)*], [*Random backoff + retry --- `[FAIL]` bukan akhir cerita, dan Pure ALOHA menjadi lengkap*],
    [09], [Carrier sense --- dengar dulu sebelum bicara, tabrakan dihindari sebelum terjadi],
    [10], [SYNC + slot waktu --- Slotted ALOHA (slot diundi) vs TDMA (slot tetap)],
  ),
  [Peta modul pada arc kedua seri LoRa],
  "tbl:m08c-peta",
)

*Kontrak data lab ini.* Payload data dan format ACK *identik* dengan M08B:
`NODE=<id>,SEQ=<n>,R1T=..,R1H=..,R2T=..,R2H=..` dibalas `ACK=<id>,SEQ=<n>`.
Yang berubah adalah *kapan* `SEQ` bertambah: pada M08B, `SEQ` naik setiap
siklus tanpa peduli hasilnya; pada modul ini, `SEQ` *tetap* selama node masih
dalam proses retry untuk data yang sama, dan baru naik setelah siklus itu
berakhir --- entah karena ACK akhirnya diterima, atau karena jatah retry habis.
Prinsip inilah yang membuat gateway bisa mengenali paket ber-`SEQ` sama sebagai
percobaan ulang dari data yang sama, bukan data baru yang kebetulan bernomor
sama.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Memulihkan kegagalan tanpa merusak keutuhan data])[
  + Menerapkan loop retry berbatas jumlah (`MAX_RETRIES`) yang mengulang paket
    yang sama, bukan membangkitkan data baru pada tiap percobaan.
  + Menjelaskan mengapa jeda antar-retry harus acak, dan menunjukkan risiko
    konkret jeda tetap lewat percobaan dua node yang disinkronkan sengaja.
  + Merancang dan menjelaskan mekanisme deteksi duplicate di gateway berbasis
    `SEQ`, termasuk mengapa gateway tetap harus membalas ACK untuk duplicate.
  + Membandingkan tingkat kegagalan *permanen* (setelah retry habis) pada modul
    ini dengan tingkat kegagalan *sekali coba* pada M08B, pada kondisi kanal
    yang sama.
  + Menghitung ongkos tambahan (waktu, lalu lintas radio) yang dibayar retry
    untuk menaikkan keandalan, dan menentukan titik ketika `MAX_RETRIES` yang
    lebih besar tidak lagi sepadan.
]

*Kriteria keberhasilan*

#checklist((
  [Node mencetak `[RETRY n/MAX]` dan `[BACKOFF]` ketika ACK pertama tidak tiba,
   lalu akhirnya `[OK]` atau `[FAIL]` setelah jatah retry habis.],
  [Gateway mencetak `PAKET DITERIMA (DUPLICATE)` untuk retry yang `SEQ`-nya
   sudah pernah diproses, dan *tidak* menambah statistik data baru untuknya.],
  [Gateway tetap membalas ACK baik untuk data baru maupun duplicate.],
  [`[GAP]` di gateway (gagal permanen) jauh lebih jarang muncul dibanding
   `[FAIL]` M08B pada interval kirim yang sama.],
))

== Dasar Teori (Secukupnya)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [Retry], [Mengirim ulang paket DATA yang *sama* (`SEQ` tidak berubah) setelah ACK-nya tidak tiba sebelum timeout.],
    [Random backoff], [Jeda tunggu *acak* (bukan tetap) sebelum tiap percobaan retry, dimaksudkan memecah sinkronisasi kebetulan antar-node.],
    [`MAX_RETRIES`], [Batas jumlah percobaan ulang. Modul ini memakai 3 --- total maksimum 4 kali kirim per `SEQ` (1 asli + 3 retry).],
    [Gagal permanen], [Keadaan ketika seluruh percobaan (asli + retry) tidak mendapat ACK. Baru di titik inilah data benar-benar dianggap hilang.],
    [Duplicate], [Paket ber-`SEQ` sama dengan yang sudah pernah diproses gateway sebagai data baru --- hasil retry, bukan pembacaan sensor baru.],
    [_Thundering herd_ / sinkronisasi kebetulan], [Risiko dua node yang bertabrakan lalu mengulang pada waktu yang (hampir) sama karena jeda retry-nya sama, sehingga bertabrakan lagi.],
  ),
  [Istilah kerja Modul 08C],
  "tbl:m08c-istilah",
)

*Mengapa backoff harus acak, bukan tetap.* Andaikan kedua node memakai jeda
retry tetap, katakanlah 500 ms. Bila keduanya bertabrakan pada percobaan
pertama, keduanya akan menunggu tepat 500 ms yang sama, lalu mengirim ulang
pada saat yang (hampir) sama lagi --- tabrakan berulang tanpa akhir yang pasti.
Random backoff memutus pola ini: peluang kedua node memilih jeda yang sama
persis sangat kecil, sehingga salah satu hampir selalu mengirim lebih dulu dan
berhasil sebelum yang lain mencoba. Ini adalah prinsip yang sama dengan _binary
exponential backoff_ pada Ethernet klasik, hanya saja modul ini memakai jeda
acak seragam (bukan bertambah eksponensial) untuk tetap sederhana --- lihat
Challenge CH-1 untuk pengembangannya.

*Mengapa gateway harus mengenali duplicate, bukan sekadar menerima apa adanya.*
Tanpa deteksi duplicate, satu pembacaan sensor yang di-retry dua kali akan
tercatat sebagai *dua* data berbeda di sisi gateway --- padahal keduanya
berasal dari satu `SEQ`, satu pembacaan sensor yang sama. Kesalahan ini murni
administratif (bukan kesalahan sensor), tetapi bila dibiarkan akan mengacaukan
setiap statistik yang dihitung dari jumlah paket diterima. Perbandingan
`seq <= lastSeq[nodeId]` menutup celah ini: `SEQ` yang tidak lebih besar dari
yang terakhir diproses pasti bukan data baru.

*Mengapa gateway tetap membalas ACK untuk duplicate.* Duplicate terjadi justru
*karena* ACK sebelumnya tidak sampai ke node --- node tidak tahu bahwa
gateway-nya sebenarnya sudah menerima data itu. Bila gateway diam saja terhadap
duplicate, node akan terus mengulang sampai `MAX_RETRIES` habis dan mencatat
`[FAIL]` padahal datanya sebenarnya sudah tersimpan sejak percobaan pertama.
Membalas ACK untuk duplicate adalah yang membuat retry benar-benar menaikkan
keandalan, bukan sekadar menambah lalu lintas radio tanpa hasil.

*Sekuens yang diamati (ACK pertama hilang, retry berhasil)*

#diagram(```
   Node                             (udara)                       Gateway
     |
  "NODE=1,SEQ=9,..." -------------------------------------->    tiba, DATA BARU
     |                                                          rxCount++, lastSeq=9
  tunggu ACK 2000 ms                    "ACK=1,SEQ=9" ----X   (hilang di jalan)
     |
  [FAIL sementara] -> BACKOFF acak (mis. 730 ms)
     |
  "NODE=1,SEQ=9,..." (RETRY 1/3) --------------------------->  tiba, SEQ==lastSeq
     |                                                         -> DUPLICATE, tidak dihitung baru
  tunggu ACK 2000 ms   <----------------------- "ACK=1,SEQ=9" -- tetap dibalas ACK
     |
  [OK] SUCCESS setelah 1 retry
```.text, rapat: true)

== Topologi

#diagram(```
                +---------------------------+
                |   Node 1                  |
                |   Arduino Uno + Shield    |
                |   Ruang 1: T, H (dummy)   |
                |   Ruang 2: T, H (dummy)   |
                |   retry + backoff acak    |
                +-------------+-------------+
                     |  DATA (+retry)  ^  ACK
                     v                 |
                      +-------------------+
                      |     Gateway       |
                      | Uno + Shield      |
                      | kenali duplicate  |
                      +-------------------+
                     ^                 |
                     |  DATA (+retry)  v  ACK
                +-------------+-------------+
                |   Node 2                  |
                |   Arduino Uno + Shield    |
                |   Ruang 1: T, H (dummy)   |
                |   Ruang 2: T, H (dummy)   |
                |   retry + backoff acak    |
                +---------------------------+
```.text)

#tbl(
  table(
    columns: (auto, auto, 1.1fr, 1fr, auto, auto),
    align: (left, left, left, left, left, left),
    inset: (x: 0.4em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Environment], th[Peran], th[Mekanisme TX/RX], th[Timeout], th[Retry / Backoff]),
    [Node 1], [`node1`], [Kirim dummy, retry bila gagal], [TX blocking + RX interrupt], [2000 ms], [maks 3× / 200--1500 ms acak],
    [Node 2], [`node2`], [Kirim dummy, retry bila gagal], [TX blocking + RX interrupt], [2000 ms], [maks 3× / 200--1500 ms acak],
    [Gateway], [`gateway`], [Terima, kenali duplicate, balas ACK], [RX interrupt + TX blocking], [---], [---],
  ),
  [Peran tiap node Modul 08C],
  "tbl:m08c-topologi",
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
    [1], [Arduino Uno], [ATmega328P], [3],
    [2], [Dragino LoRa Shield], [v1.2, SX1276, 433 MHz], [3],
    [3], [Antena SMA], [*wajib terpasang sebelum diberi daya*], [3],
    [4], [Kabel USB tipe B], [kabel data], [3],
  ),
  [Alat dan bahan Modul 08C],
  "tbl:m08c-alat",
)

*Struktur proyek*

#diagram(```
Modul08c_lora_aloha_retry/
├── platformio.ini
├── lora_monitor.py        ← dashboard 3-panel live (Gateway/Node1/Node2) + CSV
├── upload_auto.py         ← deteksi port otomatis saat unggah
├── logserial.md           ← cuplikan log serial aktual dari pengujian perangkat
└── src/
    ├── node/main.cpp      ← dummy Ruang 1+2, retry + backoff acak (env node1, node2)
    └── gateway/main.cpp   ← terima, kenali duplicate via SEQ, balas ACK (env gateway)
```.text)

== Kode Program

#sumber-kode("Modul08c_lora_aloha_retry",
  ("platformio.ini", "src/node/main.cpp", "src/gateway/main.cpp",
   "lora_monitor.py", "upload_auto.py"))

#kode-berkas("Modul08c_lora_aloha_retry/platformio.ini",
  [`platformio.ini` Modul 08C --- environment `gateway`, `node1`, `node2`],
  "lst:m08c-ini",
  pecah: true,
)

#kode-berkas("Modul08c_lora_aloha_retry/src/node/main.cpp",
  [`src/node/main.cpp` --- retry berbatas dengan random backoff],
  "lst:m08c-node",
  pecah: true,
)

#kode-berkas("Modul08c_lora_aloha_retry/src/gateway/main.cpp",
  [`src/gateway/main.cpp` --- pengenalan duplicate lewat perbandingan `SEQ`],
  "lst:m08c-gateway",
  pecah: true,
)

#kode-berkas("Modul08c_lora_aloha_retry/lora_monitor.py",
  [`lora_monitor.py` --- dasbor tiga panel dengan perekaman CSV],
  "lst:m08c-monitor",
  pecah: true,
)

#kode-berkas("Modul08c_lora_aloha_retry/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah],
  "lst:m08c-upload",
  pecah: true,
)

== Build dan Flash

*Gateway lebih dahulu*, supaya paket pertama dari node langsung dibalas.

#keluaran("pio run -d Modul08c_lora_aloha_retry -e gateway -t upload -t monitor
pio run -d Modul08c_lora_aloha_retry -e node1   -t upload -t monitor
pio run -d Modul08c_lora_aloha_retry -e node2   -t upload -t monitor")

*Monitor dashboard.* `python3 lora_monitor.py` membaca ketiga port sekaligus
dan menampilkan panel Gateway, Node 1, dan Node 2 (OK/FAIL/retry, data baru vs
duplicate, RSSI dan SNR) di terminal, plus perekaman CSV otomatis. Memerlukan
`pip install pyserial rich`.

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada ketiga shield.],
  [Port ketiga board dicatat lewat `pio device list` (atau
   `python3 ../tools/deteksi_port.py`) dan diisikan ke `platformio.ini`.],
  [Tiga Serial Monitor 115200 baud siap, ketiganya terlihat bersamaan.],
  [Penghitung `OK`, `FAIL`, dan `Total retry terpakai` pada kedua node diamati
   sejak baris pertama.],
))

== Percobaan

=== EXP-01 --- Retry Sehat, Jarak Dekat

Nyalakan ketiga board dan amati sepuluh siklus pertama. Pada jarak dekat,
sebagian besar siklus seharusnya berhasil tanpa retry sama sekali.

*Expected output --- node*

#keluaran("=== LoRa ALOHA+ACK+RETRY - NODE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
ACK timeout: 2000 ms | Max retry: 3 | Backoff: 200-1500 ms
Peran: NODE (ALOHA + ACK + Random Backoff + Retry)

[TX] NODE=1,SEQ=0,R1T=28.4,R1H=63,R2T=24.7,R2H=71
[OK] SUCCESS setelah 0 retry | OK: 1 | FAIL: 0 | Total retry terpakai: 0")

*Expected output --- gateway*

#keluaran("=== PAKET DITERIMA (DATA BARU) ===
  Node    : 1
  SEQ     : 0
  Ruang 1 : 28.4 C, 63 %
  Ruang 2 : 24.7 C, 71 %
  RSSI    : -41.00 dBm
  SNR     : 9.50 dB
  Statistik Node 1: baru=1 | duplicate=0 | gagal permanen (est.)=0
  [TX] ACK=1,SEQ=0
=====================")

*Data capture* --- diukur 90 detik (bukan 10 siklus; lihat `logserial.md`).

#tbl(
  table(
    columns: (1.3fr, 1.3fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [`OK`/`FAIL` Node 1 (23 siklus)], [*23 / 0*],
    [`OK`/`FAIL` Node 2 (23 siklus)], [*23 / 0*],
    [Rata-rata retry per siklus sukses], [Node 1: 3 retry / 23 siklus #sym.approx *0,13* --- Node 2: 2 retry / 23 siklus #sym.approx *0,09*],
    [`duplicate` yang tercatat di gateway], [Node 1: *1* --- Node 2: *1*],
  ),
  [Hasil pengamatan EXP-01 pada sesi verifikasi perangkat],
  "tbl:m08c-exp01",
)

#checkpoint[
  *Terpenuhi.* Sebagian besar siklus (21/23 Node 1, 22/23 Node 2) sukses
  langsung dengan `SUCCESS setelah 0 retry`; hanya satu siklus per node yang
  butuh retry (2× dan 1× untuk Node 1, 2× untuk Node 2) pada jarak dekat.
]

=== EXP-02 --- Memaksa Retry: M08B vs M08C pada Interval Sama

Persempit interval kirim kedua node (300--500 ms, seperti EXP-02 M08) supaya
tabrakan lebih sering terjadi, lalu bandingkan hasil M08B dan M08C pada kondisi
yang sama.

*Data capture*

#tbl(
  table(
    columns: (1.3fr, 1.1fr, 1.2fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[M08B (tanpa retry)], th[M08C (dengan retry)]),
    [Tingkat kegagalan per node (%)], [`FAIL / (OK+FAIL)`], [`[GAP]` permanen / total `SEQ`],
    [Rata-rata retry terpakai per siklus], [---], [#isian],
    [Total lalu lintas ACK tambahan], [---], [#isian],
  ),
  [Lembar pengamatan EXP-02 --- M08B dibanding M08C],
  "tbl:m08c-exp02",
)

#buka-abstraksi[
  Di `src/node/main.cpp`, nilai `r1t`, `r1h`, `r2t`, `r2h` dibangkitkan
  *sekali* di awal `loop()`, sebelum lingkaran `while(true)` retry dimulai.
  Jelaskan mengapa data itu *tidak* boleh dibangkitkan ulang di dalam lingkaran
  retry, dan telusuri: apa yang akan rusak di sisi gateway bila data
  dibangkitkan ulang setiap percobaan? Petunjuk: gateway hanya mencetak isi
  ruangan untuk data BARU, tidak untuk duplicate.
]

#checkpoint[
  Tingkat kegagalan permanen M08C harus jauh lebih rendah daripada tingkat
  `[FAIL]` M08B pada interval kirim yang sama. Bila keduanya mirip, periksa
  apakah `MAX_RETRIES` atau rentang backoff sudah benar ter-flash.
]

=== EXP-03 --- Duplicate Betul-Betul Tidak Dihitung Ganda

Amati log gateway secara khusus mencari baris `PAKET DITERIMA (DUPLICATE)`.

*Data capture*

#tbl(
  table(
    columns: (1.6fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Jumlah `(DUPLICATE)` per node dalam 5 menit], [#isian],
    [Apakah `baru=` di statistik gateway ikut bertambah saat duplicate diterima?], [#isian],
    [Apakah gateway tetap mencetak `[TX] ACK=...` untuk duplicate?], [#isian],
  ),
  [Lembar pengamatan EXP-03 --- deteksi duplicate],
  "tbl:m08c-exp03",
)

#checkpoint[
  `baru=` pada statistik gateway *tidak boleh* bertambah ketika `(DUPLICATE)`
  dicetak. Bila ikut bertambah, periksa kembali syarat
  `seq <= lastSeq[nodeId]` pada perbandingan `SEQ` di `gateway/main.cpp`.
]

=== Verifikasi Perangkat Keras

#catatan[
  *Diuji di perangkat pada 22 Agustus 2026* --- tiga Arduino Uno asli +
  Dragino LoRa Shield v1.2 (gateway, node1, node2; port `/dev/ttyACM0/1/2`).
  Build dan upload ketiga environment sukses tanpa modifikasi kode. EXP-01
  dijalankan (90 detik) dan datanya nyata, termasuk siklus yang benar-benar
  butuh retry dan backoff untuk sukses --- lihat `logserial.md`, yang juga
  memuat perbandingan langsung M08B vs M08C pada interval bawaan yang sama
  (retry menurunkan kegagalan permanen dari 4 kejadian menjadi 0). EXP-02 versi
  modul (interval dipersempit 300--500 ms) dan pengukuran EXP-03 selama 5 menit
  penuh *belum dijalankan* pada sesi verifikasi ini, diserahkan sebagai latihan
  praktikum.
]

== Pengukuran

*A. Distribusi jumlah retry per siklus sukses* (90 detik, interval bawaan)

#tbl(
  table(
    columns: (1.5fr, 1fr, 1fr),
    align: (left, center + horizon, center + horizon),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Retry terpakai], th[Siklus --- Node 1], th[Siklus --- Node 2]),
    [0 (langsung sukses)], [21], [22],
    [1], [1], [0],
    [2], [1], [1],
    [3 (batas; tetap gagal bila ini pun tak cukup)], [0], [0],
  ),
  [Lembar pengukuran A --- distribusi retry per siklus sukses],
  "tbl:m08c-ukur-a",
)

*B. M08B dibanding M08C pada interval kirim sama* (90 detik, jarak dan posisi
board identik)

#tbl(
  table(
    columns: (auto, 1fr, 1.1fr, 1.3fr),
    align: (left, left, left, left),
    inset: (x: 0.5em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Interval (ms)], th[`FAIL` M08B (N1+N2)], th[Gagal permanen M08C], th[Rata-rata retry M08C]),
    [2000--5000 (bawaan)], [4], [*0*], [N1: 0,13/siklus --- N2: 0,09/siklus],
    [1000--2000], [_belum diuji_], [#isian], [],
    [300--500], [_belum diuji --- jalankan EXP-02_], [#isian], [],
  ),
  [Lembar pengukuran B --- M08B dibanding M08C],
  "tbl:m08c-ukur-b",
)

*C. Duplicate dibanding data baru* (dari sisi gateway, 90 detik)

#tbl(
  table(
    columns: (auto, auto, auto, 1.2fr),
    align: (left, center + horizon, center + horizon, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Data baru], th[Duplicate], th[Rasio duplicate/baru (%)]),
    [Node 1], [25], [1], [4,0],
    [Node 2], [24], [1], [4,2],
  ),
  [Lembar pengukuran C --- duplicate dibanding data baru],
  "tbl:m08c-ukur-c",
)

== Analisis

+ Dari @tbl:m08c-ukur-a, berapa persen siklus yang sukses tanpa retry sama
  sekali? Bandingkan dengan proporsi yang membutuhkan retry pada interval kirim
  bawaan.
+ Dari @tbl:m08c-ukur-b, seberapa besar penurunan tingkat kegagalan dari M08B
  ke M08C pada interval yang sama? Jelaskan mengapa retry tidak pernah membuat
  kegagalan menjadi nol, hanya menurunkannya.
+ Dari @tbl:m08c-ukur-c, jelaskan mengapa rasio duplicate terhadap data baru
  naik seiring interval kirim yang dipersempit --- kaitkan dengan peluang
  tabrakan yang lebih tinggi.
+ Hitung tambahan waktu rata-rata yang dibayar per siklus akibat retry (waktu
  tunggu ACK yang gagal + backoff + kirim ulang), lalu bandingkan dengan waktu
  siklus sukses tanpa retry.
+ Rancang, tanpa menulis kodenya, skenario ketika `MAX_RETRIES = 3` masih tidak
  cukup untuk mencapai tingkat keberhasilan yang dapat diterima. Solusi apa
  dari M10 (bukan menambah `MAX_RETRIES`) yang menyelesaikan akar masalahnya,
  bukan sekadar mencoba lebih banyak?

== Concept Check

+ Mengapa data dummy (`r1t`, `r1h`, `r2t`, `r2h`) dibangkitkan sekali per
  `SEQ`, bukan setiap kali retry?
+ Apa yang salah bila backoff antar-retry memakai jeda *tetap*, bukan acak?
+ Bagaimana gateway membedakan paket duplicate dari data baru, dan mengapa
  perbandingannya `<=`, bukan `==` saja?
+ Mengapa gateway tetap mengirim ACK untuk paket yang dikenali sebagai
  duplicate?
+ Apa perbedaan antara "gagal" pada M08B dan "gagal permanen" pada M08C?

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Backoff yang lebih pintar])[
  / CH-1 --- Exponential backoff: Ganti rentang backoff acak seragam dengan
    backoff yang jangkauannya melebar tiap percobaan (misalnya percobaan ke-$n$
    memakai `random(0, BACKOFF_MIN_MS * 2^n)`), lalu bandingkan tingkat
    keberhasilan dan rata-rata retry dengan versi seragam pada interval kirim
    yang sama.

  / CH-2 --- Retry adaptif: Sesuaikan `MAX_RETRIES` secara otomatis berdasarkan
    tingkat keberhasilan berjalan (naikkan bila `FAIL` sering, turunkan bila
    selalu `SUCCESS setelah 0 retry`), dan jelaskan trade-off latensi terhadap
    keandalan yang muncul.
]

#tujuan-prak(3, [Mengukur ongkos radio sesungguhnya])[
  / CH-3 --- Statistik gap sesungguhnya: Tambahkan penghitung total kirim (asli
    + retry) yang benar-benar mengudara per node di gateway (bukan hanya data
    baru), lalu hitung _airtime utilization_ kanal untuk membandingkan ongkos
    radio M08B dengan M08C.

  / CH-4 --- Tiga node dengan retry: Tambahkan environment `node3`, sesuaikan
    `NODE_COUNT` di gateway, dan amati apakah rata-rata retry per siklus naik
    signifikan ketika jumlah node bertambah pada interval kirim yang sama.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- retry, random backoff, gagal permanen, duplicate.
+ Konfigurasi --- `MAX_RETRIES`, rentang backoff, `ACK_TIMEOUT`, kontrak
  `NODE=` dan `ACK=` (tak berubah dari M08B).
+ Hasil eksperimen --- log serial ketiga board (EXP-01 sampai EXP-03 beserta
  checkpoint).
+ Data pengukuran --- @tbl:m08c-ukur-a, @tbl:m08c-ukur-b, dan
  @tbl:m08c-ukur-c.
+ Analisis dan concept check.
+ Challenge --- minimal CH-1.
+ Kesimpulan yang disusun sendiri, khususnya mengenai batas kemampuan retry dan
  backoff sebelum penjadwalan slot (M10) benar-benar diperlukan.
