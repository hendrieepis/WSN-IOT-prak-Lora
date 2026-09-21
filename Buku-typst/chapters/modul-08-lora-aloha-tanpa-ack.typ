// ============================================================================
// Modul 08 — ALOHA Tanpa Umpan Balik: Bebas Bicara
// Sumber: Modul08_lora_aloha_tanpa_ack/README.md; listing kode dibaca langsung
//         dari salinan berkas sumber di
//         assets/code/Modul08_lora_aloha_tanpa_ack/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist

#chapter("Modul 08 — ALOHA Tanpa Umpan Balik: Bebas Bicara", l: "bab:modul-08")

#identitas-modul(
  "Modul 08",
  [Speak Freely, Collide Silently --- ALOHA Tanpa Umpan Balik],
  [Arduino Uno + Dragino LoRa Shield v1.2 · topologi bintang, 2 node + gateway ·
   interrupt, tanpa balasan · level Intermediate · 1 × 50 menit ·
   folder kode `Modul08_lora_aloha_tanpa_ack`],
)

#pengantar([Gambaran Umum])[
Modul 08 dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat menengah.
Misinya membalik total pelajaran M05: alih-alih menjadwalkan siapa yang boleh
bicara, modul ini justru *melepas* seluruh penjadwalan dan membiarkan setiap
node mengirim data kapan pun ia mau. Sistemnya sederhana --- dua node dan satu
gateway --- tetapi pertanyaannya tajam: apa yang terjadi kalau semua node bebas
mengirim tanpa koordinasi sama sekali?
]

== Pendahuluan

M05 dan M07 menghabiskan seluruh usahanya menghindari tabrakan lewat
penjadwalan terpusat. Modul ini sengaja mundur satu langkah untuk
*menunjukkan* tabrakan itu, bukan menghindarinya --- sebab protokol paling tua
dalam sejarah jaringan paket radio, ALOHAnet (Universitas Hawaii, 1971), justru
dimulai dari titik ini: kirim saja, dan terima risikonya. Memahami kegagalan
protokol paling sederhana ini adalah prasyarat untuk menghargai setiap lapisan
yang ditambahkan sesudahnya --- ACK pada M08B, retry dengan backoff pada M08C,
carrier sense pada M09, dan penjadwalan slot pada M10.

#penting[
  *Satu catatan istilah yang penting.* Yang dijalankan di modul ini belum Pure
  ALOHA yang utuh. Rumusan asli Abramson (1970) sudah memuat *ACK dan
  pengiriman ulang setelah jeda acak* --- keduanya sengaja belum ada di sini,
  supaya kanal kontensi terlihat telanjang lebih dulu. Jadi urutannya: M08
  memperlihatkan kanal tanpa umpan balik sama sekali, M08B menambahkan umpan
  baliknya, dan *M08C-lah yang akhirnya menjadi Pure ALOHA lengkap*. Menyebut
  modul ini "Pure ALOHA" tidak salah dalam percakapan sehari-hari, tetapi di
  laporan sebutkan bagian mana dari protokol itu yang sudah ada dan mana yang
  belum.
]

Prasyaratnya adalah M01 untuk format payload dan penghitungan loss lewat nomor
urut, serta M04 untuk pembacaan RSSI dan SNR per paket. Yang dibangun di sini
adalah pembangkitan data dummy multi-sensor (suhu dan kelembaban, dua ruangan
per node), pengiriman tanpa koordinasi kanal (tanpa _carrier sense_, tanpa ACK,
tanpa retry), dan deteksi kehilangan lewat lompatan nomor urut di sisi gateway.
Payload dan pola nomor urut ini dipakai lagi persis di M08B, M08C, dan M10 ---
hanya lapisan kendalinya yang bertambah.

*Peta modul LoRa*

#tbl(
  table(
    columns: (auto, 1fr),
    align: (center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Fokus (yang ditumpuk di atas modul sebelumnya)]),
    [05], [Tabrakan dicegah lewat polling terpusat --- master memanggil satu per satu],
    [07], [Master pindah ke Raspberry Pi, penjadwalan tetap sama],
    [*08 (ini)*], [*Penjadwalan dilepas --- node kirim bebas, tabrakan senyap diamati*],
    [08B], [ACK ditempelkan di atas M08 --- node tahu SUCCESS/FAILED, belum ada retry],
    [08C], [Random backoff + retry --- kegagalan dipulihkan, dan Pure ALOHA menjadi lengkap],
    [09], [Carrier sense --- dengar dulu sebelum bicara, tabrakan dihindari sebelum terjadi],
    [10], [SYNC + slot waktu --- Slotted ALOHA (slot diundi) vs TDMA (slot tetap)],
  ),
  [Peta modul pada arc kedua seri LoRa],
  "tbl:m08-peta",
)

*Kontrak data lab ini.* Setiap node mengirim satu paket berisi *dua ruangan
sekaligus*: `NODE=<id>,SEQ=<n>,R1T=<suhu>,R1H=<lembab>,R2T=<suhu>,R2H=<lembab>`.
Bentuk `KEY=VALUE` dipisah koma dipilih alih-alih format multi-baris
(`NODE_ID=1` lalu `ROOM1_TEMP=...`) yang sering dipakai pada contoh IoT berbasis
teks --- pada AVR dengan RAM 2 KB dan payload LoRa yang dibaca byte demi byte,
satu baris tunggal jauh lebih murah untuk di-parse dengan `indexOf` dan
`substring` tanpa risiko pemisahan baris yang keliru. Nomor urut `SEQ` naik di
setiap pengiriman node, *tanpa* kaitan dengan ada-tidaknya balasan --- sebab
pada Pure ALOHA memang tidak ada balasan. Gateway memakai lompatan pada `SEQ`
untuk memperkirakan berapa paket yang hilang, gagasan yang sama dengan
penghitungan loss `Hello LoRa #n` pada M01.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Mengamati kanal kontensi tanpa kendali apa pun])[
  + Menjelaskan mekanisme Pure ALOHA: kirim tanpa dengar-dahulu (_no carrier
    sense_), tanpa ACK, tanpa retry.
  + Membangkitkan data dummy multi-sensor (dua besaran, dua ruangan) dan
    mengemasnya dalam satu payload ringkas.
  + Menunjukkan secara empiris bahwa dua node yang mengirim bebas pada kanal
    yang sama dapat bertabrakan, dan menjelaskan mengapa tabrakan itu *tidak
    muncul sebagai pesan galat* di kedua sisi.
  + Memakai lompatan nomor urut sebagai alat ukur kehilangan paket tanpa perlu
    balasan apa pun dari penerima.
  + Menghitung _throughput_ efektif Pure ALOHA dan membandingkannya dengan
    hasil teoretis (puncak #sym.tilde.op 18,4 % pada beban $G = 0,5$).
]

*Kriteria keberhasilan*

#checklist((
  [Kedua node mengirim data dummy dua ruangan secara mandiri, dengan interval
   acak yang berbeda satu sama lain.],
  [Gateway mencetak setiap paket yang diterima lengkap dengan RSSI, SNR, dan
   isi kedua ruangan.],
  [Ketika interval pengiriman dipersempit, gateway mencatat kemunculan `[GAP]`
   --- tanda tabrakan atau kehilangan mulai terjadi.],
  [Statistik `diterima` dan `perkiraan hilang` per node terpisah dan bertambah
   wajar seiring waktu.],
))

== Dasar Teori (Secukupnya)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [Pure ALOHA], [Protokol akses kanal paling sederhana: kirim kapan saja data siap, tanpa mendengarkan kanal lebih dulu.],
    [Tabrakan (collision)], [Dua paket menempati udara pada waktu yang tumpang tindih sehingga radio penerima tidak dapat mendekode keduanya.],
    [Kegagalan senyap], [Paket yang bertabrakan tidak pernah lolos `parsePacket()` di penerima --- tidak ada galat, hanya ketiadaan.],
    [Vulnerable period], [Rentang waktu selebar *dua kali* waktu udara satu paket, tempat paket lain yang mulai mengirim akan menabrak paket yang sedang berjalan.],
    [Throughput teoretis], [$S = G e^(-2G)$, puncak #sym.approx 18,4 % pada $G = 0,5$ --- jauh di bawah Slotted ALOHA (M10) yang mencapai 36,8 %.],
    [Nomor urut sebagai pengganti ACK], [Tanpa balasan, satu-satunya cara mengetahui ada paket hilang adalah melihat lompatan pada `SEQ` di penerima.],
  ),
  [Istilah kerja Modul 08],
  "tbl:m08-istilah",
)

*Mengapa vulnerable period-nya dua kali waktu udara, bukan satu kali.* Paket A
yang sedang mengudara akan tertabrak oleh paket B yang mulai mengirim *kapan
saja* selama durasi transmisi A itu sendiri (B mulai di tengah A), maupun oleh
B yang sudah mulai lebih dulu dan masih berlangsung ketika A mulai (A mulai di
tengah B). Kedua kemungkinan itu menjumlahkan rentang rawan menjadi dua kali
waktu udara satu paket --- inilah yang membuat Pure ALOHA hanya mencapai
separuh throughput Slotted ALOHA, meski keduanya sama-sama tanpa carrier sense.

*Mengapa modul ini tidak memakai ACK sama sekali.* Menambahkan ACK sekarang
akan mengaburkan pelajaran utamanya: bahwa kegagalan pada kanal bersama itu
*nyata dan senyap* sebelum ada mekanisme apa pun yang mendeteksinya. M08B
menambahkan ACK persis di atas kode ini, sehingga perbandingan sebelum dan
sesudah menjadi jelas --- bukan dibangun dari nol lagi.

*Sekuens yang diamati (kasus tabrakan)*

#diagram(```
   Node 1                      (udara)                      Gateway
     |
  "NODE=1,SEQ=5,..." ------------------------------------->  tiba, dicetak
     |                                                            |
                    Node 2                                        |
                      |                                           |
                   "NODE=2,SEQ=8,..." ------X (tabrakan)---->  TIDAK tiba
                      |                                           |
     |  (Node 1 tidak tahu, tidak menunggu apa pun)               |
     |  (Node 2 tidak tahu, tidak menunggu apa pun)               |
                                                       SEQ Node 2 berikutnya
                                                       meloncat -> [GAP]
```.text, rapat: true)

== Topologi

#diagram(```
                +---------------------------+
                |   Node 1                  |
                |   Arduino Uno + Shield    |
                |   Ruang 1: T, H (dummy)   |
                |   Ruang 2: T, H (dummy)   |
                +-------------+-------------+
                              |
                              | LoRa (kirim bebas, tanpa ACK)
                              v
                      +---------------+
                      |    Gateway    |
                      | Uno + Shield  |
                      |  hanya dengar |
                      +---------------+
                              ^
                              | LoRa (kirim bebas, tanpa ACK)
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
    table.header(th[Node], th[Environment], th[Peran], th[Mekanisme TX/RX], th[Interval kirim]),
    [Node 1], [`node1`], [Bangkitkan dan kirim dummy Ruang 1+2], [TX blocking, tanpa RX], [acak 2000--5000 ms],
    [Node 2], [`node2`], [Bangkitkan dan kirim dummy Ruang 1+2], [TX blocking, tanpa RX], [acak 2000--5000 ms],
    [Gateway], [`gateway`], [Terima dan cetak dari kedua node], [Interrupt DIO0 + flag, tanpa TX], [---],
  ),
  [Peran tiap node Modul 08],
  "tbl:m08-topologi",
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
  [Alat dan bahan Modul 08],
  "tbl:m08-alat",
)

*Struktur proyek*

#diagram(```
Modul08_lora_aloha_tanpa_ack/
├── platformio.ini
├── lora_monitor.py        ← dashboard 3-panel live (Gateway/Node1/Node2) + CSV
├── upload_auto.py         ← deteksi port otomatis saat unggah
├── logserial.md           ← cuplikan log serial aktual dari pengujian perangkat
└── src/
    ├── node/main.cpp      ← dummy Ruang 1+2, kirim bebas (env node1, node2)
    └── gateway/main.cpp   ← terima & cetak, deteksi gap SEQ (env gateway)
```.text)

== Kode Program

#sumber-kode("Modul08_lora_aloha_tanpa_ack",
  ("platformio.ini", "src/node/main.cpp", "src/gateway/main.cpp",
   "lora_monitor.py", "upload_auto.py"))

#kode-berkas("Modul08_lora_aloha_tanpa_ack/platformio.ini",
  [`platformio.ini` Modul 08 --- environment `gateway`, `node1`, `node2`],
  "lst:m08-ini",
  pecah: true,
)

#kode-berkas("Modul08_lora_aloha_tanpa_ack/src/node/main.cpp",
  [`src/node/main.cpp` --- dummy dua ruangan, kirim bebas tanpa ACK],
  "lst:m08-node",
  pecah: true,
)

#kode-berkas("Modul08_lora_aloha_tanpa_ack/src/gateway/main.cpp",
  [`src/gateway/main.cpp` --- terima, cetak, dan deteksi lompatan `SEQ`],
  "lst:m08-gateway",
  pecah: true,
)

#kode-berkas("Modul08_lora_aloha_tanpa_ack/lora_monitor.py",
  [`lora_monitor.py` --- dasbor tiga panel dengan perekaman CSV],
  "lst:m08-monitor",
  pecah: true,
)

#kode-berkas("Modul08_lora_aloha_tanpa_ack/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah],
  "lst:m08-upload",
  pecah: true,
)

== Build dan Flash

*Gateway lebih dahulu*, supaya paket pertama dari node langsung tertangkap.

#keluaran("pio run -d Modul08_lora_aloha_tanpa_ack -e gateway -t upload -t monitor
pio run -d Modul08_lora_aloha_tanpa_ack -e node1   -t upload -t monitor
pio run -d Modul08_lora_aloha_tanpa_ack -e node2   -t upload -t monitor")

*Monitor dashboard.* `python3 lora_monitor.py` membaca ketiga port sekaligus
dan menampilkan panel Gateway, Node 1, dan Node 2 (statistik diterima, RSSI dan
SNR, deteksi `[GAP]`) di terminal, plus perekaman CSV otomatis. Memerlukan
`pip install pyserial rich`. Jalankan setelah ketiga board selesai diunggah.

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada ketiga shield.],
  [Port ketiga board dicatat lewat `pio device list` (atau
   `python3 ../tools/deteksi_port.py`) dan diisikan ke `platformio.ini`.],
  [Tiga Serial Monitor 115200 baud siap, ketiganya terlihat bersamaan.],
  [`NODE_ID` pada `node1` dan `node2` sudah benar, dicek dari baris pembuka
   `NODE 1` atau `NODE 2` di Serial Monitor.],
))

== Percobaan

=== EXP-01 --- Dua Node Mengirim Bebas

Nyalakan ketiga board dan amati gateway selama beberapa menit tanpa mengubah
apa pun.

*Expected output --- node*

#keluaran("=== LoRa PURE ALOHA - NODE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
Peran: NODE (Pure ALOHA) -- kirim bebas, tanpa ACK, tanpa retry

[TX] NODE=1,SEQ=0,R1T=28.4,R1H=63,R2T=24.7,R2H=71 | total dikirim: 1")

*Expected output --- gateway*

#keluaran("=== PAKET DITERIMA ===
  Node    : 1
  SEQ     : 0
  Ruang 1 : 28.4 C, 63 %
  Ruang 2 : 24.7 C, 71 %
  RSSI    : -41.00 dBm
  SNR     : 9.50 dB
  Statistik Node 1: diterima=1 | perkiraan hilang=0
=====================")

*Data capture* --- diukur 90 detik (bukan 5 menit; lihat `logserial.md` untuk
cuplikan log dan metodologi rekam).

#tbl(
  table(
    columns: (1.3fr, 1.2fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Jumlah paket diterima gateway (90 detik) --- Node 1], [*27*],
    [Jumlah paket diterima gateway (90 detik) --- Node 2], [*24*],
    [Jumlah `[GAP]` muncul --- Node 1 / Node 2], [*0 / 0*],
    [RSSI dan SNR rata-rata kedua node], [Node 1: #sym.minus 45,9 dBm / 10,00 dB --- Node 2: #sym.minus 57,9 dBm / 9,79 dB],
  ),
  [Hasil pengamatan EXP-01 pada sesi verifikasi perangkat],
  "tbl:m08-exp01",
)

#checkpoint[
  *Terpenuhi.* Pada jarak dekat dan interval kirim standar (2--5 detik),
  `[GAP]` *tidak muncul sama sekali* selama 90 detik (51 paket total) ---
  sesuai prediksi teoretis: pada beban rendah, peluang tumpang-tindih dua node
  sangat kecil meski tanpa carrier sense. Beda RSSI #sym.plus.minus 12 dB antar
  node murni posisi fisik di meja pengujian, bukan indikasi masalah.
]

=== EXP-02 --- Memaksa Tabrakan

Perkecil `SEND_INTERVAL_MIN` dan `SEND_INTERVAL_MAX` pada *kedua* node menjadi
mendekati sama (misalnya 300--500 ms untuk keduanya), unggah ulang, lalu amati
gateway.

*Data capture*

#tbl(
  table(
    columns: (1.6fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Interval kirim yang dipakai (ms)], [#isian],
    [Jumlah `[GAP]` per menit --- Node 1 / Node 2], [#isian],
    [Perkiraan _throughput_ gateway (diterima / seharusnya dikirim)], [#isian],
    [Bandingkan dengan prediksi teoretis Pure ALOHA (#sym.tilde.op 18,4 % pada beban puncak)], [#isian],
  ),
  [Lembar pengamatan EXP-02 --- memaksa tabrakan],
  "tbl:m08-exp02",
)

#buka-abstraksi[
  Di `src/node/main.cpp`, node *tidak pernah* memanggil `LoRa.receive()` atau
  menunggu apa pun setelah `endPacket()`. Jelaskan mengapa hal ini membuat node
  tidak pernah bisa tahu apakah paketnya bertabrakan, lalu telusuri: informasi
  apa yang *hilang total* dibanding modul ACK (M04, M08B) pada titik ini?
]

#checkpoint[
  Interval yang dipersempit harus menaikkan jumlah `[GAP]` di gateway secara
  terlihat. Bila tidak ada perubahan sama sekali, periksa apakah kedua node
  benar-benar terunggah ulang dengan interval baru.
]

=== EXP-03 --- Payload Dua Ruangan

Bandingkan isi payload dua node dan pastikan keduanya membawa data Ruang 1
*dan* Ruang 2 dalam satu paket, bukan dua paket terpisah.

*Data capture*

#tbl(
  table(
    columns: (1.3fr, 1.2fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Jumlah field dalam satu payload], [*6* (`NODE`, `SEQ`, `R1T`, `R1H`, `R2T`, `R2H`)],
    [Apakah Ruang 1 dan Ruang 2 selalu tiba bersamaan (satu paket)?], [*ya* --- tidak pernah terpisah pada 51 paket yang diamati],
    [Ukuran payload (jumlah karakter)], [*45*, misalnya `NODE=1,SEQ=2,R1T=29.8,R1H=59,R2T=25.4,R2H=68`],
  ),
  [Hasil pengamatan EXP-03 --- payload dua ruangan],
  "tbl:m08-exp03",
)

#checkpoint[
  *Terpenuhi.* Satu paket selalu membawa *kedua* ruangan sekaligus. Ini yang
  membuat modul ini lebih hemat lalu lintas radio dibanding mengirim empat
  paket terpisah (Suhu R1, Lembab R1, Suhu R2, Lembab R2) untuk data yang sama.
]

=== Verifikasi Perangkat Keras

#catatan[
  *Diuji di perangkat pada 22 Agustus 2026* --- tiga Arduino Uno asli +
  Dragino LoRa Shield v1.2 (gateway, node1, node2; port `/dev/ttyACM0/1/2`,
  sudah cocok dengan `platformio.ini` bawaan). Build dan upload ketiga
  environment sukses tanpa modifikasi kode. EXP-01 dan EXP-03 dijalankan dan
  datanya nyata (lihat tabel di atas serta `logserial.md`). EXP-02 (memaksa
  tabrakan dengan interval sempit) memerlukan mengubah
  `SEND_INTERVAL_MIN`/`MAX` di kode dan unggah ulang kedua node --- *belum
  dijalankan pada sesi verifikasi ini*, diserahkan sebagai latihan praktikum
  sesuai instruksi modul.
]

== Pengukuran

*A. Tingkat kedatangan paket terhadap kepadatan kirim*

#tbl(
  table(
    columns: (auto, 1.4fr, 1fr, 1.2fr),
    align: (left, left, left, left),
    inset: (x: 0.5em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Interval kirim (ms)], th[Total dikirim (kedua node, 90 s)], th[Diterima gateway], th[Throughput (%)]),
    [2000--5000 (bawaan)], [51 (27+24, tanpa hilang di jendela rekam)], [51], [#sym.tilde.op 100 (beban rendah, jauh dari puncak $G = 0,5$)],
    [1000--2000], [_belum diuji --- jalankan EXP-02_], [#isian], [],
    [300--500], [_belum diuji --- jalankan EXP-02_], [#isian], [],
  ),
  [Lembar pengukuran A --- kedatangan paket terhadap kepadatan kirim],
  "tbl:m08-ukur-a",
)

*B. RSSI dan SNR per node*

#tbl(
  table(
    columns: (auto, 1fr, 1fr, 1fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[RSSI rata-rata (dBm)], th[SNR rata-rata (dB)], th[Jumlah `[GAP]`]),
    [Node 1], [#sym.minus 45,9], [10,00], [0],
    [Node 2], [#sym.minus 57,9], [9,79], [0],
  ),
  [Lembar pengukuran B --- RSSI dan SNR per node (sesi verifikasi)],
  "tbl:m08-ukur-b",
)

== Analisis

+ Dari @tbl:m08-ukur-a, pada interval berapa throughput mulai menurun tajam?
  Bandingkan pola penurunannya dengan kurva teoretis $S = G e^(-2G)$.
+ Jelaskan mengapa node yang mengirim tidak pernah tahu paketnya bertabrakan
  pada modul ini --- telusuri baris kode yang membuktikannya.
+ Gateway memperkirakan kehilangan lewat lompatan `SEQ`. Sebutkan satu skenario
  di mana metode ini *melebih-lebihkan* jumlah paket hilang, dan satu skenario
  di mana ia *meremehkannya*.
+ Bandingkan jumlah `[GAP]` Node 1 dengan Node 2. Bila berbeda jauh padahal
  intervalnya sama, apa penjelasan yang mungkin?
+ Hitung _vulnerable period_ untuk payload modul ini pada SF7 dan BW 125 kHz,
  lalu jelaskan hubungannya dengan interval kirim minimum yang masih aman dari
  tabrakan berlebihan.

== Concept Check

+ Apa perbedaan mendasar Pure ALOHA dengan polling terjadwal pada M05?
+ Mengapa vulnerable period Pure ALOHA dua kali lipat waktu udara satu paket,
  bukan sama dengan waktu udara itu sendiri?
+ Mengapa gateway pada modul ini tidak pernah mengirim balasan apa pun?
+ Apa kelemahan memakai lompatan `SEQ` sebagai satu-satunya alat ukur
  kehilangan paket?
+ Sebutkan satu keadaan nyata di mana Pure ALOHA (kirim bebas, tanpa
  koordinasi) tetap menjadi pilihan yang masuk akal walau throughput-nya
  rendah.

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Membuat gateway mengukur sendiri])[
  / CH-1 --- Hitung throughput otomatis: Tambahkan penghitung total `SEQ`
    maksimum yang terlihat per node di gateway, lalu hitung dan cetak
    persentase throughput setiap 30 detik tanpa perlu dihitung manual dari log.

  / CH-2 --- Tiga node: Tambahkan environment `node3` dan amati apakah `[GAP]`
    bertambah ketika jumlah node naik dari dua menjadi tiga pada interval kirim
    yang sama.
]

#tujuan-prak(3, [Menjembatani ke modul berikutnya])[
  / CH-3 --- RSSI di payload: Sisipkan estimasi RSSI terakhir yang diterima
    node dari paket node lain (bila node ikut mendengarkan) ke dalam payloadnya
    sendiri, sebagai langkah awal menuju _carrier sense_.

  / CH-4 --- Simulasikan $G$: Buat mode di gateway yang menghitung $G$ (beban
    tawar, dalam paket per vulnerable period) dari data yang teramati, lalu
    bandingkan throughput terukur dengan prediksi $S = G e^(-2G)$.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- Pure ALOHA, vulnerable period, throughput teoretis.
+ Konfigurasi --- format payload dua ruangan, interval kirim tiap node,
  parameter radio.
+ Hasil eksperimen --- log serial ketiga board (EXP-01 sampai EXP-03 beserta
  checkpoint).
+ Data pengukuran --- @tbl:m08-ukur-a dan @tbl:m08-ukur-b.
+ Analisis dan concept check.
+ Challenge --- minimal CH-1.
+ Kesimpulan yang disusun sendiri, khususnya mengenai harga throughput yang
  dibayar demi kesederhanaan protokol.
