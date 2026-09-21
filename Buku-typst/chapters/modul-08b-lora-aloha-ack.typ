// ============================================================================
// Modul 08B — Pure ALOHA + ACK: Kini Tahu
// Sumber: Modul08b_lora_aloha_ack/README.md; listing kode dibaca langsung dari
//         salinan berkas sumber di assets/code/Modul08b_lora_aloha_ack/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist
#import "../config.typ": edisi_buku

#chapter("Modul 08B — ALOHA + ACK: Kini Tahu", l: "bab:modul-08b")

#identitas-modul(
  "Modul 08B",
  [Finally Know --- ALOHA + ACK],
  [Arduino Uno + Dragino LoRa Shield v1.2 · topologi bintang, 2 node + gateway ·
   interrupt + timeout · level Intermediate · 1 × 50 menit ·
   folder kode `Modul08b_lora_aloha_ack`],
)

#pengantar([Gambaran Umum])[
Modul 08B dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat menengah,
dan *hanya* pengembangan dari M08 --- bukan modul berdiri sendiri. Misinya
menjawab satu pertanyaan yang M08 sengaja dibiarkan terbuka: bagaimana node
tahu paketnya diterima? Jawabannya adalah mekanisme paling tua untuk itu, ACK,
ditempelkan tepat di atas kode M08 tanpa mengubah cara data dibangkitkan maupun
kapan node boleh mengirim.
]

== Pendahuluan

M08 menunjukkan bahwa tabrakan pada Pure ALOHA bersifat senyap --- kedua sisi
sama-sama tidak sadar. Modul ini menutup separuh dari kebutaan itu: node
pengirim kini menunggu balasan `ACK=<id>,SEQ=<n>` dan mencatat `[OK]` atau
`[FAIL]` secara eksplisit. Yang *belum* dikerjakan modul ini secara sengaja
adalah kirim ulang otomatis --- begitu `[FAIL]` tercatat, node tetap lanjut ke
data berikutnya. Retry, timeout adaptif, dan random backoff baru datang di
M08C, sehingga peningkatan setiap pertemuan tetap dapat diukur satu per satu,
bukan tercampur dalam satu lompatan besar.

Prasyaratnya adalah M08 untuk payload dua ruangan dan pembangkitan dummy, serta
M04 untuk pola tunggu-ACK-dengan-timeout dan pencocokan nomor urut. Yang
ditambahkan di sini adalah balasan ACK dari gateway yang membawa `NODE` *dan*
`SEQ` sekaligus (M04 hanya membawa nomor urut, sebab modulnya cuma satu pasang
board --- di sini gateway melayani dua node, sehingga ACK wajib menyebut untuk
siapa balasan itu ditujukan), serta statistik OK dan FAIL berjalan di sisi
node. Kontrak ACK ini dipakai lagi apa adanya di M08C, hanya ditambah logika
retry di atasnya.

*Peta modul LoRa*

#tbl(
  table(
    columns: (auto, 1fr),
    align: (center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Fokus (yang ditumpuk di atas modul sebelumnya)]),
    [08], [Penjadwalan dilepas --- node kirim bebas, tabrakan senyap diamati],
    [*08B (ini)*], [*ACK ditempelkan di atas M08 --- node tahu SUCCESS/FAILED, belum ada retry*],
    [08C], [Random backoff + retry --- kegagalan dipulihkan, dan Pure ALOHA menjadi lengkap],
    [09], [Carrier sense --- dengar dulu sebelum bicara, tabrakan dihindari sebelum terjadi],
    [10], [SYNC + slot waktu --- Slotted ALOHA (slot diundi) vs TDMA (slot tetap)],
  ),
  [Peta modul pada arc kedua seri LoRa],
  "tbl:m08b-peta",
)

*Kontrak data lab ini.* Payload data *identik* dengan M08:
`NODE=<id>,SEQ=<n>,R1T=<suhu>,R1H=<lembab>,R2T=<suhu>,R2H=<lembab>`. Yang baru
hanyalah balasan gateway, `ACK=<id>,SEQ=<n>` --- dua field, karena gateway
melayani lebih dari satu node dan ACK yang hanya membawa `SEQ` (seperti M04)
berisiko dianggap milik node lain yang kebetulan memakai nomor urut sama. Node
menolak ACK yang `id` atau `SEQ`-nya tidak cocok persis, mengikuti prinsip
pencocokan permintaan-balasan dari M04.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Membuat kegagalan pada kanal bersama menjadi terbaca])[
  + Menjelaskan mengapa ACK pada topologi banyak-node harus membawa identitas
    pengirim, bukan sekadar nomor urut seperti pada M04.
  + Menerapkan penungguan ACK berbatas waktu tanpa memblokir interrupt, memakai
    pola yang sama dengan M04.
  + Membedakan kegagalan yang *diketahui* (M08B, lewat `[FAIL]`) dari kegagalan
    yang *senyap* (M08, lewat lompatan `SEQ`), dan menjelaskan mengapa keduanya
    seharusnya menghasilkan angka yang mirip pada kondisi kanal yang sama.
  + Mengukur tingkat keberhasilan (`OK / (OK+FAIL) × 100 %`) dua node yang
    berbagi satu kanal, dan membandingkannya dengan tingkat keberhasilan satu
    pasang board pada M04.
  + Menjelaskan mengapa modul ini *belum* mengirim ulang paket yang gagal, dan
    risiko apa yang muncul bila retry ditambahkan sembarangan tanpa
    mempertimbangkan duplikasi.
]

*Kriteria keberhasilan*

#checklist((
  [Kedua node mencetak `[OK]` atau `[FAIL]` setelah setiap pengiriman, tidak
   pernah membeku menunggu ACK.],
  [Gateway membalas *setiap* paket data valid dengan ACK yang menyebut `NODE`
   dan `SEQ` yang benar.],
  [Statistik `diterima` (gateway) dan `OK` (node) pada node yang sama saling
   mendekati pada jarak dekat.],
  [`[GAP]` di gateway dan `[FAIL]` di node sama-sama meningkat ketika interval
   kirim dipersempit (EXP-02 M08 masih berlaku di sini).],
))

== Dasar Teori (Secukupnya)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [ACK beralamat], [Balasan yang menyebut *untuk siapa* ia ditujukan (`ACK=<id>,SEQ=<n>`), diperlukan begitu gateway melayani lebih dari satu pengirim.],
    [SUCCESS / FAILED], [Hasil satu siklus kirim-tunggu-ACK di sisi node: `[OK]` bila ACK yang sesuai tiba sebelum timeout, `[FAIL]` bila tidak.],
    [Kegagalan diketahui vs senyap], [M08B membuat kegagalan *diketahui node* lewat timeout; kegagalan tetap *senyap bagi gateway* karena paket yang bertabrakan tidak pernah tiba untuk diketahui apa pun.],
    [Retry (belum ada di sini)], [Mengirim ulang paket yang gagal. Sengaja ditunda ke M08C agar efeknya (dan risiko duplikasi) dapat diukur terpisah.],
    [Overhead ACK], [Setiap paket data kini diikuti satu paket ACK dan satu jendela tunggu --- menambah waktu udara total dibanding M08.],
  ),
  [Istilah kerja Modul 08B],
  "tbl:m08b-istilah",
)

*Mengapa ACK di sini harus menyebut `NODE`, sedangkan M04 cukup `ACK:n`.* M04
hanya punya satu pasang board, sehingga nomor urut saja sudah cukup unik untuk
mencocokkan balasan dengan permintaan. Begitu gateway melayani dua node
sekaligus, dua kondisi rawan bisa muncul: (a) `SEQ` kedua node kebetulan
bernilai sama di waktu yang berdekatan, dan (b) ACK milik Node 1 terdengar oleh
Node 2 karena LoRa mentah tidak memiliki alamat radio. Menyisipkan `NODE` ke
dalam ACK menutup keduanya --- node menolak ACK yang `NODE`-nya bukan miliknya,
persis seperti slave M05 menolak `POLL` yang bukan nomornya.

*Mengapa belum ada retry.* Menambahkan retry sekarang akan mencampur dua
pertanyaan berbeda dalam satu percobaan: "apakah node tahu paketnya gagal?"
(pertanyaan M08B) dan "apa yang terjadi kalau node mencoba lagi?" (pertanyaan
M08C, lengkap dengan risiko gateway menerima data yang sama dua kali).
Memisahkan keduanya membuat setiap pertemuan mengukur *satu* variabel baru.

*Sekuens yang diamati*

#diagram(```
   Node                          (udara)                       Gateway
     |
  "NODE=1,SEQ=5,..." ------------------------------------->   tiba, di-parse
  LoRa.receive(); mulai hitung mundur 2000 ms                 cetak + statistik
     |                                                               |
  ackFlag  <----------------------- "ACK=1,SEQ=5" -------------- balas ACK
  cocokkan NODE & SEQ dengan yang ditunggu                     kembali RX
     |
  [OK] jika cocok sebelum 2000 ms, [FAIL] jika timeout
  lanjut ke data berikutnya (SEQ+1) -- TANPA mengulang yang gagal
```.text, rapat: true)

== Topologi

#diagram(```
                +---------------------------+
                |   Node 1                  |
                |   Arduino Uno + Shield    |
                |   Ruang 1: T, H (dummy)   |
                |   Ruang 2: T, H (dummy)   |
                +-------------+-------------+
                     |  DATA        ^  ACK
                     v              |
                      +---------------+
                      |    Gateway    |
                      | Uno + Shield  |
                      | balas tiap OK |
                      +---------------+
                     ^              |
                     |  DATA        v  ACK
                +-------------+-------------+
                |   Node 2                  |
                |   Arduino Uno + Shield    |
                |   Ruang 1: T, H (dummy)   |
                |   Ruang 2: T, H (dummy)   |
                +---------------------------+
```.text)

#tbl(
  table(
    columns: (auto, auto, 1.2fr, 1fr, auto),
    align: (left, left, left, left, left),
    inset: (x: 0.5em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Environment], th[Peran], th[Mekanisme TX/RX], th[Timeout ACK]),
    [Node 1], [`node1`], [Kirim dummy Ruang 1+2, tunggu ACK], [TX blocking + RX interrupt], [2000 ms],
    [Node 2], [`node2`], [Kirim dummy Ruang 1+2, tunggu ACK], [TX blocking + RX interrupt], [2000 ms],
    [Gateway], [`gateway`], [Terima, cetak, balas ACK beralamat], [RX interrupt + TX blocking], [---],
  ),
  [Peran tiap node Modul 08B],
  "tbl:m08b-topologi",
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
  [Alat dan bahan Modul 08B],
  "tbl:m08b-alat",
)

*Struktur proyek*

#diagram(```
Modul08b_lora_aloha_ack/
├── platformio.ini
├── lora_monitor.py        ← dashboard 3-panel live (Gateway/Node1/Node2) + CSV
├── upload_auto.py         ← deteksi port otomatis saat unggah
├── logserial.md           ← cuplikan log serial aktual dari pengujian perangkat
└── src/
    ├── node/main.cpp      ← dummy Ruang 1+2, kirim + tunggu ACK (env node1, node2)
    └── gateway/main.cpp   ← terima, cetak, balas ACK beralamat (env gateway)
```.text)

== Kode Program

#sumber-kode("Modul08b_lora_aloha_ack",
  ("platformio.ini", "src/node/main.cpp", "src/gateway/main.cpp",
   "lora_monitor.py", "upload_auto.py"))

#kode-berkas("Modul08b_lora_aloha_ack/platformio.ini",
  [`platformio.ini` Modul 08B --- environment `gateway`, `node1`, `node2`],
  "lst:m08b-ini",
  pecah: true,
)

#kode-berkas("Modul08b_lora_aloha_ack/src/node/main.cpp",
  [`src/node/main.cpp` --- kirim dummy dua ruangan lalu tunggu ACK beralamat],
  "lst:m08b-node",
  pecah: true,
)

#kode-berkas("Modul08b_lora_aloha_ack/src/gateway/main.cpp",
  [`src/gateway/main.cpp` --- terima, cetak, dan balas `ACK=<id>,SEQ=<n>`],
  "lst:m08b-gateway",
  pecah: true,
)

#kode-berkas("Modul08b_lora_aloha_ack/lora_monitor.py",
  [`lora_monitor.py` --- dasbor tiga panel dengan perekaman CSV],
  "lst:m08b-monitor",
  pecah: true,
)

#kode-berkas("Modul08b_lora_aloha_ack/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah],
  "lst:m08b-upload",
  pecah: true,
)

== Build dan Flash

*Gateway lebih dahulu*, supaya paket pertama dari node langsung dibalas.

#keluaran("pio run -d Modul08b_lora_aloha_ack -e gateway -t upload -t monitor
pio run -d Modul08b_lora_aloha_ack -e node1   -t upload -t monitor
pio run -d Modul08b_lora_aloha_ack -e node2   -t upload -t monitor")

*Monitor dashboard.* `python3 lora_monitor.py` membaca ketiga port sekaligus
dan menampilkan panel Gateway, Node 1, dan Node 2 (OK/FAIL/retry, RSSI dan SNR,
deteksi `[GAP]`) di terminal, plus perekaman CSV otomatis. Memerlukan
`pip install pyserial rich`.

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada ketiga shield.],
  [Port ketiga board dicatat lewat `pio device list` (atau
   `python3 ../tools/deteksi_port.py`) dan diisikan ke `platformio.ini`.],
  [Tiga Serial Monitor 115200 baud siap, ketiganya terlihat bersamaan.],
  [Penghitung `OK` dan `FAIL` pada kedua node diamati sejak baris pertama.],
))

== Percobaan

=== EXP-01 --- Siklus ACK Sehat, Dua Node

Nyalakan ketiga board dan amati sepuluh siklus pertama pada kedua node.

*Expected output --- node*

#keluaran("=== LoRa ALOHA+ACK - NODE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
ACK timeout: 2000 ms
Peran: NODE (ALOHA + ACK) -- masih tanpa retry, lihat M08C

[TX] NODE=1,SEQ=0,R1T=28.4,R1H=63,R2T=24.7,R2H=71
[OK] ACK diterima | OK: 1 | FAIL: 0")

*Expected output --- gateway*

#keluaran("=== PAKET DITERIMA ===
  Node    : 1
  SEQ     : 0
  Ruang 1 : 28.4 C, 63 %
  Ruang 2 : 24.7 C, 71 %
  RSSI    : -41.00 dBm
  SNR     : 9.50 dB
  Statistik Node 1: diterima=1 | perkiraan hilang=0
  [TX] ACK=1,SEQ=0
=====================")

*Data capture* --- diukur 90 detik (bukan 10 siklus; lihat `logserial.md`).

#tbl(
  table(
    columns: (1.4fr, 1.2fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [`OK`/`FAIL` Node 1 (90 detik, 24 percobaan)], [*22 / 2*],
    [`OK`/`FAIL` Node 2 (90 detik, 21 percobaan)], [*19 / 2*],
    [Tingkat keberhasilan (%) kedua node], [*91,7 % / 90,5 %*],
    [RSSI/SNR arah DATA (di gateway) --- Node 1 / Node 2], [*#sym.minus 46,3 dBm / 9,84 dB --- #sym.minus 59,5 dBm / 9,60 dB*],
    [Latensi ACK round-trip (TX #sym.arrow OK) --- Node 1 / Node 2], [*rata-rata 60 ms / 59 ms*],
  ),
  [Hasil pengamatan EXP-01 pada sesi verifikasi perangkat],
  "tbl:m08b-exp01",
)

#checkpoint[
  *Tidak sepenuhnya terpenuhi --- dan itu justru instruktif.* `FAIL` tidak nol:
  sesi ini menangkap satu tabrakan nyata antara Node 1 dan Node 2 (`SEQ=5`,
  selisih TX #sym.tilde.op 90 ms, dalam _vulnerable period_), lihat
  `logserial.md`. Sesi M08 (90 detik, interval sama) justru *nihil* `[GAP]`
  --- kebetulan statistik semata (tabrakan adalah peristiwa acak; 90 detik
  terlalu singkat untuk menyimpulkan tingkat kegagalan "sebenarnya" dari satu
  sesi saja), bukan bukti bahwa M08B lebih rentan tabrakan daripada M08
  (keduanya memakai mekanisme kirim yang identik, hanya M08B menambahkan ACK di
  atasnya).
]

=== EXP-02 --- Dibandingkan dengan M08 (Kegagalan Senyap vs Diketahui)

Jalankan M08 dan M08B berturut-turut pada interval kirim yang dipersempit
(300--500 ms, seperti EXP-02 M08), lalu bandingkan.

*Data capture*

#tbl(
  table(
    columns: (1.3fr, 1fr, 1.2fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[M08 (Pure ALOHA)], th[M08B (ALOHA + ACK)]),
    [Cara kegagalan terlihat], [`[GAP]` di gateway saja], [`[FAIL]` di node + `[GAP]` di gateway],
    [Jumlah kegagalan per menit --- Node 1], [#isian], [],
    [Jumlah kegagalan per menit --- Node 2], [#isian], [],
    [Lalu lintas radio tambahan (paket ACK)], [---], [#isian],
  ),
  [Lembar pengamatan EXP-02 --- M08 dibanding M08B],
  "tbl:m08b-exp02",
)

#buka-abstraksi[
  Di `src/gateway/main.cpp`, ACK dikirim *setelah* statistik `[GAP]` dicetak,
  bukan sebelumnya. Jelaskan mengapa urutan ini tidak memengaruhi kebenaran ACK
  (radio tetap half-duplex, hanya satu arah aktif pada satu waktu), lalu
  telusuri: apa yang terjadi bila `LoRa.receive()` di akhir `loop()` gateway
  dihapus?
]

#checkpoint[
  Jumlah `[FAIL]` di node dan jumlah `[GAP]` di gateway untuk node yang sama
  seharusnya *mendekati*, bukan identik persis --- sebab `[FAIL]` juga mencakup
  kasus DATA sampai tetapi ACK-nya yang hilang (lihat Analisis, soal 3).
]

=== EXP-03 --- Node Tanpa Retry Tetap Berjalan

Matikan gateway sesaat, amati kedua node, lalu nyalakan kembali.

*Data capture*

#tbl(
  table(
    columns: (1.5fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Selang `[TX]` #sym.arrow `[FAIL]` saat gateway mati (detik)], [#isian],
    [Apakah node melanjutkan ke `SEQ` berikutnya walau gagal?], [#isian],
    [Berapa siklus sampai `[OK]` kembali muncul setelah gateway hidup?], [#isian],
  ),
  [Lembar pengamatan EXP-03],
  "tbl:m08b-exp03",
)

#checkpoint[
  Node harus *tetap melanjutkan* ke `SEQ` berikutnya setelah `[FAIL]`, bukan
  mengulang `SEQ` yang sama. Perilaku "coba lagi" baru boleh muncul di M08C ---
  di modul ini, `[FAIL]` berarti data hilang permanen.
]

=== Verifikasi Perangkat Keras

#catatan[
  *Diuji di perangkat pada 22 Agustus 2026* --- tiga Arduino Uno asli +
  Dragino LoRa Shield v1.2 (gateway, node1, node2; port `/dev/ttyACM0/1/2`).
  Build dan upload ketiga environment sukses tanpa modifikasi kode. EXP-01
  dijalankan (90 detik) dan datanya nyata, termasuk satu tabrakan sungguhan
  yang terekam langsung --- lihat `logserial.md`. EXP-02 (perbandingan
  sistematis M08 vs M08B pada interval dipersempit) dan EXP-03 (mematikan
  gateway sesaat) *belum dijalankan* pada sesi verifikasi ini, diserahkan
  sebagai latihan praktikum.
]

// Log serial lengkap dari Modul08b_lora_aloha_ack/logserial.md. Hanya dicetak pada
// edisi dosen agar tidak disalin mahasiswa sebagai hasil laporan
// (lihat config.typ).
#if edisi_buku == "dosen" [
  === Log Serial Terverifikasi

  Log serial lengkap hasil uji pada board nyata, bukan contoh. Bagian ini
  hanya dicetak pada edisi dosen.

  Hasil aktual dari perangkat. Baud *115200*, frekuensi *433 MHz*, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `ACK_TIMEOUT` 2000 ms. Ketiga board di posisi sama seperti M08 (Node 1 lebih dekat ke gateway daripada Node 2). Interval kirim bawaan (2000–5000 ms acak), tidak diubah.

  *Board & Port*

  #tbl(
    table(
      columns: (auto, auto, auto, 1fr),
      align: (left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Peran], th[Environment], th[Port], th[Board]),
      [Gateway], [`gateway`], [`/dev/ttyACM0`], [Uno asli (`2341:0043`)],
      [Node 1], [`node1`], [`/dev/ttyACM1`], [Uno asli (`2341:0043`)],
      [Node 2], [`node2`], [`/dev/ttyACM2`], [Uno asli (`2341:0043`)],
    ),
    [Log serial Modul 08B: Board & Port],
    "tbl:m08b-log-1",
  )

  Ketiga aliran serial direkam bersamaan, jendela rekam 90 detik setelah ketiga board di-_upload_ ulang dan _boot_ bersih.

  *EXP-01 — Siklus ACK Sehat, Dua Node*

  Siklus normal (paket sampai, ACK sampai, latensi round-trip \~60 ms):

  #keluaran("[07:55:29.194] GW | === PAKET DITERIMA ===
[07:55:29.198] GW |   Node    : 2
[07:55:29.198] GW |   SEQ     : 1
[07:55:29.198] GW |   Ruang 1 : 26.3 C, 45 %
[07:55:29.202] GW |   Ruang 2 : 23.8 C, 80 %
[07:55:29.202] GW |   RSSI    : -61 dBm
[07:55:29.206] GW |   SNR     : 9.25 dB
[07:55:29.210] GW |   Statistik Node 2: diterima=1 | perkiraan hilang=0
[07:55:29.247] GW |   [TX] ACK=2,SEQ=1
[07:55:29.251] GW | =====================
[07:55:29.819] N1 | [TX] NODE=1,SEQ=1,R1T=25.9,R1H=74,R2T=26.9,R2H=59
[07:55:29.881] N1 | [OK] ACK diterima | OK: 1 | FAIL: 1", pecah: true)

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil (90 detik, bukan 10 siklus — lihat catatan)]),
      [`OK`/`FAIL` Node 1], [*22 / 2* (24 percobaan)],
      [`OK`/`FAIL` Node 2], [*19 / 2* (21 percobaan tercatat lengkap)],
      [Tingkat keberhasilan Node 1 / Node 2], [*91,7% / 90,5%*],
      [Latensi ACK round-trip (TX → OK) Node 1 / Node 2], [*rata-rata 60 ms / 59 ms* (min 57, maks 65 ms)],
      [RSSI/SNR arah DATA (di gateway) — Node 1 / Node 2], [*-46,3 dBm / 9,84 dB — -59,5 dBm / 9,60 dB*],
    ),
    [Log serial Modul 08B: EXP-01 — Siklus ACK Sehat, Dua Node],
    "tbl:m08b-log-2",
  )

  *CHECKPOINT sebagian terpenuhi.* `FAIL` tidak nol: masing-masing node mengalami 2 kegagalan dalam 90 detik — satu di antaranya adalah tabrakan nyata yang berhasil direkam langsung (lihat EXP-02 di bawah). Ini konsisten dengan M08: pada jarak dan interval yang sama, tabrakan tetap mungkin terjadi walau jarang.

  *Temuan Tambahan A — Tabrakan Nyata Tertangkap Langsung*

  (Bukan EXP-02 versi README — itu perbandingan sistematis M08 vs M08B pada interval dipersempit, belum dijalankan. Ini adalah tabrakan yang kebetulan terekam pada sesi EXP-01 di atas.)

  Pada sesi ini, Node 1 dan Node 2 kebetulan mengirim `SEQ=5` hampir bersamaan (selisih \~90 ms — dalam _vulnerable period_). Log berikut menunjukkan efeknya di kedua sisi:

  #keluaran("[07:55:44.196] N2 | [TX] NODE=2,SEQ=5,R1T=24.1,R1H=51,R2T=24.9,R2H=55
[07:55:44.286] N1 | [TX] NODE=1,SEQ=5,R1T=27.9,R1H=74,R2T=22.3,R2H=55
[07:55:44.295] N2 | [RX] WARN: balasan tak sesuai (NODE=1,SEQ=5,R1T=27.9,R1H=74,R2T=22.3,R2H=55), tetap tunggu...
[07:55:46.195] N2 | [FAIL] Tidak ada ACK | OK: 4 | FAIL: 2
[07:55:46.288] N1 | [FAIL] Tidak ada ACK | OK: 4 | FAIL: 2
[07:55:49.055] GW |   Ruang 2 : 27.6 C, 64 %
[07:55:49.055] GW |   RSSI    : -46 dBm
[07:55:49.059] GW |   SNR     : 10.00 dB
[07:55:49.062] GW |   [GAP] SEQ meloncat 1 -- indikasi tabrakan/paket hilang
[07:55:49.066] GW |   Statistik Node 1: diterima=5 | perkiraan hilang=1", pecah: true)

  Yang menarik: Node 2 sempat menerima *paket DATA milik Node 1* di jendela tunggu ACK-nya sendiri (`[RX] WARN: balasan tak sesuai`) — bukti langsung bahwa radio LoRa mentah tidak beralamat, semua node saling mendengar lalu lintas siapa pun. Kedua node akhirnya `[FAIL]` pada `SEQ=5` yang sama, dan gateway mencatat `[GAP]` pada Node 1 (SEQ meloncat dari 4 ke 6) — konsisten dengan paket Node 1 yang hilang akibat tabrakan ini.

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Total `[GAP]` gateway (90 detik)], [*1* (Node 1, SEQ 4→6)],
      [Total `[FAIL]` Node 1 / Node 2 (90 detik)], [*2 / 2*],
      [Selisih waktu TX kedua node saat tabrakan], [*\~90 ms*],
    ),
    [Log serial Modul 08B: Temuan Tambahan A — Tabrakan Nyata Tertangkap Langsung],
    "tbl:m08b-log-3",
  )

  *Temuan Tambahan B — Ketidaksepakatan Node vs Gateway (DATA sampai, ACK hilang)*

  (Bukan EXP-03 versi README — itu uji mematikan gateway sesaat, belum dijalankan. Ini adalah data untuk Tabel B bagian Pengukuran README, dihitung dari sesi EXP-01 di atas.)

  #tbl(
    table(
      columns: (auto, auto, auto, auto, 1fr),
      align: (left, left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Node], th[`OK` di node], th[`diterima` di gateway (akhir jendela)], th[Selisih], th[Tafsiran]),
      [Node 1], [22], [22], [*0*], [Kedua `FAIL` Node 1 (boot-race SEQ\=0 + tabrakan SEQ\=5) memang DATA yang tidak pernah sampai — konsisten dengan `[GAP]` gateway.],
      [Node 2], [19], [20], [*1*], [Satu `FAIL` di Node 2 ternyata DATA-nya *sampai* di gateway (`diterima` gateway lebih tinggi dari `OK` node) — kemungkinan ACK balasannya yang hilang di jalur pulang, bukan DATA-nya di jalur pergi.],
    ),
    [Log serial Modul 08B: Temuan Tambahan B — Ketidaksepakatan Node vs Gateway (DATA sampai, ACK hilang)],
    "tbl:m08b-log-4",
  )

  Baris Node 2 adalah bukti nyata dari poin analisis modul ini: `[FAIL]` di node *tidak selalu berarti* DATA hilang — bisa juga DATA sampai tapi ACK balasannya yang tidak pernah tiba kembali. Node tidak bisa membedakan kedua kasus ini hanya dari timeout-nya sendiri.

  *Ringkasan Verifikasi Hardware*

  Diuji di perangkat pada 2026-08-22: 3× Arduino Uno asli + Dragino LoRa Shield v1.2 (gateway + node1 + node2, port `/dev/ttyACM0/1/2`). Build dan upload ketiga environment sukses. Protokol ALOHA+ACK berjalan sesuai desain: gateway membalas ACK untuk setiap paket valid yang diterima, kedua node menunggu ACK dengan timeout 2000 ms tanpa retry. Sesi 90 detik ini bahkan menangkap satu tabrakan nyata antara Node 1 dan Node 2, memberi bukti langsung untuk konsep _vulnerable period_ dan perbedaan antara "DATA hilang" vs "ACK hilang". EXP-02 versi README (uji sistematis M08 vs M08B pada interval dipersempit) dan EXP-03 versi README (mematikan gateway sesaat) *belum dijalankan* pada sesi ini — diserahkan sebagai latihan praktikum.
]

== Pengukuran

*A. Tingkat keberhasilan per node* (90 detik, interval bawaan 2000--5000 ms)

#tbl(
  table(
    columns: (auto, auto, auto, 1fr, 1.2fr),
    align: (left, left, left, left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[OK], th[FAIL], th[Keberhasilan (%)], th[RSSI rata-rata (dBm)]),
    [Node 1], [22], [2], [91,7], [#sym.minus 46,3],
    [Node 2], [19], [2], [90,5], [#sym.minus 59,5],
  ),
  [Lembar pengukuran A --- tingkat keberhasilan per node (sesi verifikasi)],
  "tbl:m08b-ukur-a",
)

*B. Ketidaksepakatan node dan gateway* (lihat Analisis soal 3)

#tbl(
  table(
    columns: (auto, auto, auto, auto, 1.6fr),
    align: (left, left, left, left, left),
    inset: (x: 0.5em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[`OK` di node], th[`diterima` di gateway], th[Selisih], th[Tafsiran]),
    [Node 1], [22], [22], [0], [Kedua `FAIL` Node 1 memang DATA yang tidak pernah sampai (konsisten dengan `[GAP]` gateway).],
    [Node 2], [19], [20], [*1*], [Satu `FAIL` Node 2 ternyata DATA-nya *sampai* di gateway --- ACK balasannya yang hilang di jalur pulang, bukan DATA di jalur pergi.],
  ),
  [Lembar pengukuran B --- ketidaksepakatan node dan gateway],
  "tbl:m08b-ukur-b",
)

*C. M08 dibanding M08B pada interval kirim sama*

#tbl(
  table(
    columns: (auto, 1.2fr, 1.4fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Interval kirim (ms)], th[`[GAP]` M08 (90 s)], th[`[FAIL]` M08B (90 s, N1+N2)]),
    [2000--5000 (bawaan)], [0], [4 (2+2)],
    [300--500], [_belum diuji --- jalankan EXP-02_], [#isian],
  ),
  [Lembar pengukuran C --- M08 dibanding M08B],
  "tbl:m08b-ukur-c",
)

== Analisis

+ Bandingkan @tbl:m08b-ukur-a dengan tingkat keberhasilan M04 (satu pasang
  board). Jelaskan mengapa dua node yang berbagi kanal cenderung menghasilkan
  tingkat keberhasilan yang lebih rendah pada beban kirim yang sama.
+ Dari @tbl:m08b-ukur-c, apakah `[FAIL]` M08B selalu lebih besar atau sama
  dengan `[GAP]` M08 pada interval yang sama? Jelaskan mengapa secara teori
  seharusnya begitu.
+ @tbl:m08b-ukur-b dapat menunjukkan `diterima` di gateway lebih besar daripada
  `OK` di node untuk node yang sama. Jelaskan mekanisme yang membuat itu
  mungkin --- kaitkan dengan arah mana (DATA atau ACK) yang hilang.
+ Modul ini menambah satu paket ACK untuk setiap DATA dibanding M08. Hitung
  tambahan lalu lintas radio dalam persen, lalu jelaskan mengapa tambahan itu
  tidak menaikkan _jumlah_ tabrakan DATA antar-node secara langsung, meski
  menambah total waktu kanal terpakai.
+ Rancang, tanpa menulis kodenya, bagaimana M08C seharusnya membedakan retry
  dari kiriman baru di sisi gateway --- mengapa `SEQ` yang sama harus *tidak*
  dihitung dua kali sebagai data baru?

== Concept Check

+ Mengapa ACK pada modul ini harus menyebut `NODE`, sedangkan ACK M04 cukup
  nomor urut saja?
+ Apa bedanya kegagalan yang "diketahui" (M08B) dengan kegagalan yang "senyap"
  (M08)? Sisi mana yang mengetahuinya masing-masing?
+ Mengapa `[FAIL]` tidak lantas berarti gateway tidak menerima apa-apa?
+ Mengapa modul ini sengaja belum mengirim ulang paket yang gagal?
+ Apa risiko yang harus diantisipasi *sebelum* retry ditambahkan di M08C?

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Statistik dan informasi tautan yang lebih kaya])[
  / CH-1 --- Persentase langsung: Tampilkan tingkat keberhasilan berjalan
    (`OK / (OK+FAIL) × 100 %`) di setiap baris statistik node, seperti CH-2
    pada M04.

  / CH-2 --- RSSI di ACK: Sisipkan RSSI yang diterima gateway ke dalam ACK
    (`ACK=1,SEQ=5,RSSI=-45`), sehingga node mengetahui kualitas tautan dari
    sisi gateway tanpa paket tambahan.
]

#tujuan-prak(3, [Mengukur harga keandalan])[
  / CH-3 --- Bandingkan overhead: Ukur total waktu kanal terpakai (waktu udara
    DATA + waktu udara ACK + waktu tunggu) per siklus sukses, lalu bandingkan
    dengan waktu satu siklus M08 (tanpa ACK sama sekali).

  / CH-4 --- Tiga node: Tambahkan environment `node3`, sesuaikan `NODE_COUNT`
    di gateway, dan amati apakah tingkat keberhasilan turun ketika jumlah node
    bertambah pada interval kirim yang sama.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- ACK beralamat, kegagalan diketahui vs senyap,
  overhead ACK.
+ Konfigurasi --- format `NODE=...` dan `ACK=...`, nilai `ACK_TIMEOUT`,
  parameter radio.
+ Hasil eksperimen --- log serial ketiga board (EXP-01 sampai EXP-03 beserta
  checkpoint).
+ Data pengukuran --- @tbl:m08b-ukur-a, @tbl:m08b-ukur-b, dan
  @tbl:m08b-ukur-c.
+ Analisis dan concept check.
+ Challenge --- minimal CH-1.
+ Kesimpulan yang disusun sendiri, khususnya mengenai apa yang sudah diketahui
  sekarang dibanding M08, dan apa yang masih belum (retry --- lihat M08C).
