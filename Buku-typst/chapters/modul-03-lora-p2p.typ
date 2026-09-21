// ============================================================================
// Modul 03 — Peer-to-Peer Ping-Pong
// Sumber: Modul03_lora_p2p/README.md; listing kode dibaca langsung dari
//         salinan berkas sumber di assets/code/Modul03_lora_p2p/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist
#import "../config.typ": edisi_buku

#chapter("Modul 03 — Peer-to-Peer Ping-Pong", l: "bab:modul-03")

#identitas-modul(
  "Modul 03",
  [Take Turns Talking --- Peer-to-Peer Ping-Pong],
  [Arduino Uno + Dragino LoRa Shield v1.2 · LoRa mentah · dua arah ·
   RX polling · level Intermediate · 2 × 50 menit ·
   folder kode `Modul03_lora_p2p`],
)

#pengantar([Gambaran Umum])[
Modul 03 dirancang untuk dua pertemuan (2 × 50 menit) pada tingkat menengah.
Misinya membuat kedua board bergantian berbicara di atas satu radio yang sama:
Device A memulai `Ping`, Device B membalas `Pong`, dan seterusnya tanpa henti.
Percobaan memakai dua Arduino Uno bershield Dragino LoRa v1.2, diamati melalui
dua Serial Monitor pada 9600 baud.
]

== Pendahuluan

Dua modul pertama hanya memindahkan data satu arah, sehingga peran tiap board
tetap: yang satu selalu bicara, yang lain selalu mendengar. Begitu arah
dibalik, muncul kenyataan yang tidak ada pada BLE maupun Zigbee --- radio LoRa
bersifat *half-duplex*: satu chip tidak dapat mengirim dan menerima pada saat
bersamaan. Setiap board harus bergiliran, dan giliran itu tidak diatur protokol
mana pun, melainkan oleh kode aplikasi. Di sinilah muncul persoalan klasik
komunikasi dua arah: bagaimana bila balasan tidak pernah datang, dan siapa yang
bertanggung jawab memulai ulang percakapan.

Prasyaratnya adalah M01 untuk parameter radio dan pembacaan RSSI, serta M02
untuk pemahaman kapan `loop()` terblokir. Yang dibangun di sini adalah
percakapan bergantian di atas radio half-duplex, penguraian isi paket untuk
menentukan balasan, penanda identitas pengirim di dalam payload, serta
pemulihan otomatis melalui pengiriman ulang berkala. Semuanya dipakai lagi pada
M04 ketika balasan diformalkan menjadi ACK dengan batas waktu, dan M05 ketika
giliran bicara dijadwalkan satu master untuk banyak node.

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
    [*03 (ini)*], [*Dua arah bergantian di atas radio half-duplex + pemulihan otomatis*],
    [04], [Keandalan diukur: ACK, timeout, dan hitungan gagal],
    [05], [Banyak node --- satu master menjadwalkan giliran bicara],
  ),
  [Peta modul pada arc pertama seri LoRa],
  "tbl:m03-peta",
)

*Kontrak data lab ini.* Payload mulai membawa *identitas pengirim* di depan
isinya: `DeviceA:Ping`, `DeviceB:Pong`. Tanpa penanda itu, sebuah board tidak
dapat membedakan gema pesannya sendiri dari balasan lawan bicara. Pola
identitas-di-dalam-payload ini berkembang menjadi `S1:DATA:n` pada M05, dan
merupakan padanan LoRa dari prefiks `A:` dan `B:` pada modul BLE multi-node.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Membangun percakapan dua arah yang pulih sendiri])[
  + Menjelaskan sifat half-duplex radio LoRa dan akibatnya pada rancangan
    percakapan dua arah.
  + Membangun pertukaran Ping-Pong yang berkelanjutan, termasuk penguraian isi
    paket untuk menentukan balasan.
  + Menjelaskan perlunya penanda identitas pada payload ketika beberapa board
    memakai parameter radio yang sama.
  + Menerapkan pemulihan otomatis berbasis batas waktu, dan menjelaskan
    mengapa hanya satu pihak yang boleh memegang peran itu.
  + Mengukur waktu pulang-pergi (_round-trip_) satu siklus Ping-Pong dan
    menjelaskan penyusunnya.
]

*Kriteria keberhasilan*

#checklist((
  [Kedua board bergantian mencetak `[RX]` dan `[TX]` tanpa henti.],
  [Identitas pengirim pada payload sesuai dengan board asalnya.],
  [Ketika Device B dimatikan, Device A mencetak `[RETRY]` dan pulih sendiri
   setelah B dinyalakan lagi.],
  [Waktu pulang-pergi terukur dari log, minimal 10 siklus.],
))

== Dasar Teori (Secukupnya)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [Half-duplex], [Radio dapat mengirim atau menerima, tetapi tidak keduanya sekaligus. SX1276 harus berpindah mode.],
    [Initiator], [Pihak yang memulai percakapan dan bertanggung jawab mengulang bila macet. Di sini Device A.],
    [Responder], [Pihak yang hanya membalas ketika menerima. Di sini Device B.],
    [Round-trip time], [Selang dari sebuah paket dikirim sampai balasannya diterima.],
    [Auto-retry], [Pengiriman ulang otomatis bila tidak ada balasan dalam selang tertentu (5 detik pada modul ini).],
    [Deadlock percakapan], [Keadaan macet ketika kedua pihak sama-sama menunggu --- pasti terjadi bila tidak ada pihak yang memegang peran initiator.],
  ),
  [Istilah kerja Modul 03],
  "tbl:m03-istilah",
)

*Mengapa hanya satu pihak yang boleh melakukan retry.* Andaikan kedua board
sama-sama mengirim ulang setiap 5 detik ketika sunyi, keduanya berpeluang
memancar pada saat yang hampir bersamaan. Karena radio half-duplex, board yang
sedang memancar tidak mungkin mendengar lawannya, sehingga kedua paket saling
menutupi dan tidak satu pun diterima. Percakapan justru semakin sulit pulih
ketika semakin banyak pihak berinisiatif. Pembagian peran initiator dan
responder menyelesaikannya dengan cara paling sederhana: hanya satu pihak yang
berhak membuka suara.

*Sekuens yang diamati*

#diagram(```
   Device A (initiator)              (udara)              Device B (responder)
        |                                                        |
   "DeviceA:Ping" ---------------------------------------->  paket tiba
        |                                                   cetak + RSSI
   paket tiba  <---------------------------------------- "DeviceB:Pong"
   cetak + RSSI
   balas "DeviceA:Ping" ---------------------------------->     |
        |                                                       ...
   [bila sunyi > 5 detik]
   [RETRY] kirim ulang Ping
```.text, rapat: true)

== Topologi

#diagram(```
        BOARD #1                                      BOARD #2
  +------------------+                          +------------------+
  |   Arduino Uno    |  --- "DeviceA:Ping" -->  |   Arduino Uno    |
  | + LoRa Shield    |                          | + LoRa Shield    |
  |    DEVICE A      |  <-- "DeviceB:Pong" ---  |    DEVICE B      |
  |   INITIATOR      |                          |   RESPONDER      |
  | retry tiap 5 s   |                          | selalu menunggu  |
  +------------------+                          +------------------+
     env: devicea                                 env: deviceb
```.text)

#tbl(
  table(
    columns: (auto, auto, auto, 1fr, 1fr),
    align: (left, left, left, left, left),
    inset: (x: 0.55em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Environment], th[Build flag], th[Peran], th[Pemulihan]),
    [Device A], [`devicea`], [`-DDEVICE_A`], [Initiator, memulai Ping], [Kirim ulang tiap 5 detik bila sunyi],
    [Device B], [`deviceb`], [---], [Responder, membalas tiap paket], [Tidak perlu, selalu menunggu],
  ),
  [Peran tiap node Modul 03],
  "tbl:m03-topologi",
)

Kedua board memakai *file source yang sama*, `src/peer/main.cpp`. Perannya
ditentukan build flag di `platformio.ini`, bukan dengan menyunting `#define`
lalu mengembalikannya --- cara yang sering menjadi sumber kesalahan ketika satu
board diunggahi firmware peran yang keliru.

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
  [Alat dan bahan Modul 03],
  "tbl:m03-alat",
)

*Struktur proyek*

#diagram(```
Modul03_lora_p2p/
├── platformio.ini          ← peran ditentukan build flag -DDEVICE_A
├── monitor_serial.py       ← pantau kedua peer, ringkas siklus/retry/RTT
├── upload_auto.py          ← deteksi port otomatis saat unggah
├── logserial.md            ← log referensi hasil uji perangkat
└── src/
    └── peer/main.cpp       ← satu source untuk kedua board
```.text)

== Kode Program

#sumber-kode("Modul03_lora_p2p",
  ("platformio.ini", "src/peer/main.cpp", "monitor_serial.py",
   "upload_auto.py"))

#kode-berkas("Modul03_lora_p2p/platformio.ini",
  [`platformio.ini` Modul 03 --- peran ditentukan build flag `-DDEVICE_A`],
  "lst:m03-ini",
  pecah: true,
)

#kode-berkas("Modul03_lora_p2p/src/peer/main.cpp",
  [`src/peer/main.cpp` --- satu source untuk initiator dan responder],
  "lst:m03-peer",
  pecah: true,
)

#kode-berkas("Modul03_lora_p2p/monitor_serial.py",
  [`monitor_serial.py` --- pantau kedua peer, ringkas siklus, retry, dan RTT],
  "lst:m03-monitor",
  pecah: true,
)

#kode-berkas("Modul03_lora_p2p/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah],
  "lst:m03-upload",
  pecah: true,
)

== Build dan Flash

*Responder lebih dahulu*, agar sudah siap ketika initiator mengirim Ping
pertama pada detik pertama setelah reset.

#keluaran("pio run -d Modul03_lora_p2p -e deviceb -t upload -t monitor
pio run -d Modul03_lora_p2p -e devicea -t upload -t monitor")

*Memantau kedua peer sekaligus.* Waktu pulang-pergi tidak dapat diukur dari dua
jendela terpisah, karena tiap jendela punya sumbu waktunya sendiri. Skrip
`monitor_serial.py` menggabungkan keduanya dan langsung menghitung siklus,
retry, serta waktu pulang-pergi.

#keluaran("python3 Modul03_lora_p2p/monitor_serial.py
python3 Modul03_lora_p2p/monitor_serial.py --durasi 30 --log sesi1.txt")

#keluaran("  A       kirim 79   terima 78   retry 0
          RSSI min/maks/rata-rata : -46 / -40 / -40.2 dBm
  B       kirim 78   terima 78   retry 0
  Siklus Ping-Pong selesai : 156
  Waktu pulang-pergi min/maks/rata-rata : 200 / 401 / 220 ms")

#peringatan[
  *Jangan memantau port board yang hendak diunggah.* Monitor menahan port itu,
  sehingga `pio run -t upload` tidak dapat membukanya dan unggahan gagal tanpa
  pesan yang jelas. Saat menguji EXP-03, pantau node yang *diamati* saja dan
  biarkan port node yang dimatikan-hidupkan tetap bebas.
]

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada kedua shield.],
  [Port kedua board dicatat lewat `pio device list` dan diisikan ke
   `platformio.ini`.],
  [Dua Serial Monitor 9600 baud siap, keduanya terlihat bersamaan.],
  [Urutan unggah dipahami: `deviceb` dahulu, `devicea` kemudian.],
))

== Percobaan

=== EXP-01 --- Percakapan Berkelanjutan

Unggah kedua firmware sesuai urutan, lalu amati kedua Serial Monitor bersamaan.

*Expected output --- Device A*

#keluaran("=== LoRa PEER-TO-PEER ===
Init LoRa ... OK
Freq  : 433.00 MHz
Peran : INITIATOR (Device A)

[TX] DeviceA:Ping
================================
[RX] Pesan  : DeviceB:Pong
[RX] RSSI   : -38 dBm
[RX] SNR    : 9.75 dB
================================
[TX] DeviceA:Ping")

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Isi payload yang diterima Device A], [#isian],
    [Isi payload yang diterima Device B], [#isian],
    [Jumlah siklus dalam 60 detik], [#isian],
    [RSSI arah A#sym.arrow B / B#sym.arrow A (dBm)], [#isian],
  ),
  [Lembar pengamatan EXP-01],
  "tbl:m03-exp01",
)

#buka-abstraksi[
  Di `src/peer/main.cpp`, balasan disusun dari pemeriksaan
  `received.indexOf("Ping") >= 0`. Jawab: apa yang terjadi bila kedua board
  diunggahi environment yang sama, misalnya `devicea` pada keduanya? Ramalkan
  hasilnya lebih dahulu, baru buktikan dengan mencobanya, lalu kembalikan
  konfigurasi semula.
]

#checkpoint[
  Kedua Serial Monitor menampilkan `[RX]` dan `[TX]` bergantian tanpa henti.
  Bila salah satu board hanya mencetak `[TX]` berulang tanpa pernah `[RX]`,
  paketnya tidak pernah tiba --- periksa parameter radio dan antena sebelum
  melanjutkan.
]

=== EXP-02 --- Waktu Pulang-Pergi

Ukur selang antara `[TX]` dan `[RX]` berikutnya pada Device A, sebanyak sepuluh
siklus.

#tbl(
  table(
    columns: (auto, 1fr, 1fr),
    align: (center + horizon, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Siklus], th[Waktu pulang-pergi (ms)], th[RSSI balasan (dBm)]),
    [1], [#isian], [],
    [2], [#isian], [],
    [3], [#isian], [],
    [4], [#isian], [],
    [5], [#isian], [],
    [6], [#isian], [],
    [7], [#isian], [],
    [8], [#isian], [],
    [9], [#isian], [],
    [10], [#isian], [],
    [*Rata-rata*], [#isian], [],
  ),
  [Lembar pengamatan EXP-02 --- waktu pulang-pergi sepuluh siklus],
  "tbl:m03-exp02",
)

#checkpoint[
  Waktu pulang-pergi harus stabil, tidak berbeda jauh antar-siklus pada jarak
  tetap. Sebaran yang lebar menandakan sebagian paket hilang lalu dipulihkan
  retry --- periksa apakah ada baris `[RETRY]` di antaranya.
]

=== EXP-03 --- Percakapan Terputus dan Pulih

Uji perilaku sistem ketika salah satu pihak menghilang.

#tbl(
  table(
    columns: (auto, auto, 1fr, 1fr, 1fr),
    align: (center + horizon, left, left, left, left),
    inset: (x: 0.55em, y: 0.6em),
    stroke: 0.5pt + luma(170),
    table.header(th[\#], th[Skenario], th[Langkah], th[Hasil di Device A], th[Hasil di Device B]),
    [1], [Responder hilang], [Cabut USB Device B], [#isian], [---],
    [2], [Responder kembali], [Pasang lagi Device B], [#isian], [],
    [3], [Initiator hilang], [Cabut USB Device A], [---], [#isian],
    [4], [Initiator kembali], [Pasang lagi Device A], [#isian], [],
  ),
  [Lembar pengamatan EXP-03 --- skenario terputus dan pulih],
  "tbl:m03-exp03",
)

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Selang antar-baris `[RETRY]` (detik)], [#isian],
    [Waktu pemulihan setelah Device B kembali (detik)], [#isian],
    [Apakah percakapan pulih tanpa mereset Device A?], [#isian],
    [Apakah percakapan pulih tanpa mereset Device B?], [#isian],
  ),
  [Lembar pengamatan EXP-03 --- data pemulihan],
  "tbl:m03-exp03-data",
)

#checkpoint[
  Skenario 3 adalah yang paling penting. Ketika *initiator* yang hilang,
  Device B diam selamanya tanpa satu pun pesan kesalahan: ia memang dirancang
  hanya membalas. Pada pengujian rujukan, B mencetak *nol baris* selama
  23,5 detik tanpa initiator --- dari sisi B, "lawan bicara mati" tidak dapat
  dibedakan dari "belum ada yang mengajak bicara". Catat berapa lama keadaan
  itu bertahan, lalu kaitkan dengan pertanyaan nomor 4 pada bagian Analisis.
]

*Angka rujukan* (hasil ukur nyata, lihat `logserial.md`).

#tbl(
  table(
    columns: (auto, auto, 1fr, 1fr),
    align: (left, center + horizon, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Yang hilang], th[Terdeteksi?], th[Gejala], th[Waktu pemulihan]),
    [Responder (B)], [ya], [`[RETRY]` tiap 5,04 s], [4,86 s --- dibatasi `PING_INTERVAL`],
    [Initiator (A)], [*tidak*], [B diam total, 0 baris], [1,1 s setelah A kembali],
  ),
  [Angka rujukan EXP-03 --- deteksi hilangnya lawan bicara],
  "tbl:m03-rujukan",
)

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
    [Siklus Ping-Pong (30 detik)], [*156* --- #sym.plus.minus 5,2 siklus/detik],
    [Waktu pulang-pergi min/maks/rata-rata], [200 / 401 / *220 ms*],
    [Retry selama percakapan normal], [*0*],
    [RSSI di A / di B (rata-rata)], [#sym.minus 40,2 / #sym.minus 40,7 dBm --- tautan hampir simetris],
    [Responder hilang #sym.arrow terdeteksi?], [ya, `[RETRY]` tiap 5,04 s; pulih 4,86 s],
    [*Initiator hilang #sym.arrow terdeteksi?*], [*tidak --- responder diam total, 0 baris selama 23,5 detik*],
  ),
  [Hasil verifikasi perangkat keras Modul 03],
  "tbl:m03-verifikasi",
)

#keluaran("Environment    Status    Flash
devicea        SUCCESS   26.3% (8486 B)
deviceb        SUCCESS   25.4% (8206 B)")

Selisih #sym.plus.minus 280 byte berasal dari blok `#ifdef DEVICE_A` yang hanya
ikut terkompilasi pada initiator --- bukti bahwa build flag benar-benar
mengubah firmware, bukan sekadar penanda.

// Log serial lengkap dari Modul03_lora_p2p/logserial.md. Hanya dicetak pada
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
      columns: (auto, auto, auto, 1fr),
      align: (left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Peran], th[Environment], th[Port], th[Board]),
      [Device A — initiator], [`devicea`], [`/dev/ttyUSB0`], [Uno klon, bridge CH340 (`1a86:7523`)],
      [Device B — responder], [`deviceb`], [`/dev/ttyACM1`], [Uno asli (`2341:0043`)],
    ),
    [Log serial Modul 03: Board & Port],
    "tbl:m03-log-1",
  )

  Board Uno asli di `/dev/ttyACM0` tidak dipakai: shield-nya gagal `LoRa.begin()` (lihat `../Modul01_lora_uart/logserial.md`).

  *EXP-01 — Percakapan Berkelanjutan*

  #keluaran("[   1.811] B | === LoRa PEER-TO-PEER ===
[   1.811] B | Init LoRa ... OK
[   1.811] B | Freq  : 433.00 MHz
[   1.811] B | Peran : RESPONDER  (Device B, env deviceb)
[   1.811] B | Menunggu paket...
[   1.822] A | Peran : INITIATOR (Device A, env devicea)
[   2.824] A | [TX] DeviceA:Ping
[   3.013] B | [RX] Pesan  : DeviceA:Ping
[   3.013] B | [RX] RSSI   : -41 dBm
[   3.013] B | [RX] SNR    : 9.75 dB
[   3.013] B | [TX] DeviceB:Pong", pecah: true)

  Device A menunggu 1 detik sesudah init sebelum mengirim Ping pertama, sesuai `delay(1000)` di `setup()` yang memberi waktu responder bersiap.

  *EXP-02 — Waktu Pulang-Pergi (30 detik)*

  Diukur dengan `monitor_serial.py`, yang menghitung selang antara `[TX]` sebuah node dan `[RX]` berikutnya pada node yang sama.

  #tbl(
    table(
      columns: (auto, 1fr),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Siklus Ping-Pong selesai], [*156 dalam 30 detik* (±5,2 siklus/detik)],
      [Waktu pulang-pergi min / maks / rata-rata], [200 / 401 / *220 ms*],
      [Device A: kirim / terima / retry], [79 / 78 / *0*],
      [Device B: kirim / terima / retry], [78 / 78 / —],
      [RSSI di A (dari B) min/maks/rata-rata], [−46 / −40 / −40,2 dBm],
      [RSSI di B (dari A) min/maks/rata-rata], [−41 / −40 / −40,7 dBm],
      [SNR di A / di B (rata-rata)], [9,86 dB / 9,35 dB],
      [Flash devicea / deviceb], [26,3 % (8.486 B) / 25,4 % (8.206 B)],
    ),
    [Log serial Modul 03: EXP-02 — Waktu Pulang-Pergi (30 detik)],
    "tbl:m03-log-2",
  )

  Percakapan berjalan *tanpa satu pun retry* selama 30 detik. Waktu pulang-pergi 220 ms terdiri dari dua kali waktu udara paket SF7 ditambah waktu proses kedua board — jauh lebih besar daripada `delay(50)` yang disisipkan sebelum membalas.

  Tautan bersifat hampir simetris: RSSI yang dilihat A (−40,2 dBm) dan yang dilihat B (−40,7 dBm) berselisih di bawah 1 dB.

  *EXP-03 — Percakapan Terputus dan Pulih*

  Ketiadaan node ditirukan dengan mengunggah *sketsa diam* (`setup()` dan `loop()` kosong, radio tidak pernah diinisialisasi), bukan dengan mencabut USB — agar seluruh rangkaian percobaan dapat diulang tanpa campur tangan tangan dan waktunya tercatat tepat.

  _Skenario 1–2: responder hilang lalu kembali_

  Device A dipantau terus-menerus; hanya Device B yang dimatikan dan dinyalakan.

  #keluaran("[  13.90] * | >>> Device B kini diam
[  17.42] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  22.46] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  27.49] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  32.54] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  37.60] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  42.64] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  47.68] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  48.07] * | >>> Device B kembali aktif
[  52.72] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  52.72] A | [TX] DeviceA:Ping
[  52.93] A | [RX] Pesan  : DeviceB:Pong        <-- percakapan pulih
[  52.96] A | [RX] RSSI   : -45 dBm", pecah: true)

  #tbl(
    table(
      columns: (auto, 1fr),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Selang B diam → `[RETRY]` pertama], [3,5 s],
      [Selang antar-`[RETRY]`], [*5,04 s* (sesuai `PING_INTERVAL 5000`)],
      [Jumlah retry selama 34 detik sunyi], [8],
      [Waktu pemulihan setelah B kembali], [*4,86 s*],
      [Perlu mereset Device A?], [*tidak*],
      [Perlu mereset Device B?], [tidak],
    ),
    [Log serial Modul 03: Skenario 1–2: responder hilang lalu kembali],
    "tbl:m03-log-3",
  )

  Pemulihan memakan 4,86 detik bukan karena tautan lambat, melainkan karena Device A hanya mencoba lagi *pada jadwal retry berikutnya*. Batas atas waktu pemulihan sistem ini adalah satu `PING_INTERVAL`, yaitu 5 detik.

  _Skenario 3–4: initiator hilang lalu kembali_

  Kebalikannya: Device B dipantau, Device A yang dimatikan.

  #tbl(
    table(
      columns: (1fr, auto),
      align: (left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Parameter], th[Hasil]),
      [Baris yang dicetak B selama 23,5 detik tanpa initiator], [*0 baris*],
      [Pesan kesalahan dari B], [*tidak ada*],
      [Waktu pemulihan setelah A kembali], [1,1 s],
    ),
    [Log serial Modul 03: Skenario 3–4: initiator hilang lalu kembali],
    "tbl:m03-log-4",
  )

  Inilah temuan terpenting modul ini: ketika *initiator* yang hilang, responder tidak mencetak apa pun sama sekali — tidak ada peringatan, tidak ada retry, hanya sunyi. Dari sisi Device B, keadaan "lawan bicara mati" tidak dapat dibedakan dari "belum ada yang mengajak bicara". Responder memang dirancang hanya membalas, dan tidak memiliki pewaktu apa pun untuk menyadari kesunyian.

  Perbandingan kedua arah kegagalan:

  #tbl(
    table(
      columns: (auto, 1fr, auto, auto),
      align: (left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Yang hilang], th[Yang terjadi], th[Terdeteksi?], th[Waktu pemulihan]),
      [Responder (B)], [A mencetak `[RETRY]` tiap 5 detik], [*ya*], [≤ 5 s (terukur 4,86 s)],
      [Initiator (A)], [B diam total tanpa pesan], [*tidak*], [1,1 s setelah A kembali],
    ),
    [Log serial Modul 03: Skenario 3–4: initiator hilang lalu kembali],
    "tbl:m03-log-5",
  )

  *Catatan pengambilan log*

  - Percobaan pertama EXP-03 gagal karena `monitor_serial.py` menahan `/dev/ttyACM1`, sehingga unggah pemulihan ke Device B tidak dapat membuka port itu dan Device B tetap diam. Rangkaian diulang dengan hanya memantau node yang datanya dibutuhkan, sehingga port node lainnya bebas untuk diunggah. Ini juga berlaku saat praktikum: jangan menjalankan monitor pada port board yang hendak diunggah.
  - Payload modul ini tidak bernomor, sehingga paket hilang tidak dapat dihitung dari lompatan angka seperti Modul 01. Yang diukur adalah waktu pulang-pergi dan jumlah retry. Penomoran payload menjadi bahan CH-2.
  - Kode sumber sempat memuat sisa penamaan port Windows (`COM8`, `COM9`) pada pesan `setup()`, warisan dari repositori asal. Keduanya diganti nama environment PlatformIO agar tidak menyesatkan.
  - Tabel pengukuran jarak, tautan asimetris, dan spreading factor pada README belum terisi: percobaan ini dijalankan di satu meja pada jarak tetap ±30 cm.
]

== Pengukuran

*A. Jarak terhadap kelangsungan percakapan*

#tbl(
  table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr),
    align: (left, left, left, left, left),
    inset: (x: 0.5em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Jarak], th[RSSI A#sym.arrow B (dBm)], th[RSSI B#sym.arrow A (dBm)], th[Siklus per menit], th[`[RETRY]` per menit]),
    [1 m], [#isian], [], [], [],
    [10 m], [#isian], [], [], [],
    [50 m], [#isian], [], [], [],
    [100 m], [#isian], [], [], [],
  ),
  [Lembar pengukuran A --- jarak terhadap kelangsungan percakapan],
  "tbl:m03-ukur-a",
)

*B. Tautan asimetris* --- sering terjadi di lapangan dan mudah dilewatkan.

#tbl(
  table(
    columns: (1.2fr, 1fr, 1fr, 1.2fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Kondisi], th[RSSI A#sym.arrow B], th[RSSI B#sym.arrow A], th[Percakapan berlanjut?]),
    [Kedua antena tegak], [#isian], [], [],
    [Antena B direbahkan], [#isian], [], [],
    [Antena B dekat logam], [#isian], [], [],
  ),
  [Lembar pengukuran B --- tautan asimetris],
  "tbl:m03-ukur-b",
)

*C. Waktu pulang-pergi terhadap spreading factor* --- ubah SF pada *kedua*
board.

#tbl(
  table(
    columns: (auto, 1.4fr, 1fr),
    align: (center + horizon, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[SF], th[Waktu pulang-pergi rata-rata (ms)], th[Siklus per menit]),
    [7], [#isian], [],
    [9], [#isian], [],
    [12], [#isian], [],
  ),
  [Lembar pengukuran C --- waktu pulang-pergi terhadap spreading factor],
  "tbl:m03-ukur-c",
)

== Analisis

+ Dari @tbl:m03-ukur-c, berapa kali waktu pulang-pergi memanjang ketika SF
  dinaikkan dari 7 ke 12? Bandingkan dengan perkiraan waktu udara secara teori.
+ Pada @tbl:m03-ukur-b, mungkinkah A mendengar B tetapi B tidak mendengar A?
  Jelaskan penyebab fisiknya dan akibatnya pada percakapan dua arah.
+ Mengapa hanya Device A yang melakukan retry? Ramalkan apa yang terjadi bila
  kedua board sama-sama melakukannya, dan kaitkan dengan sifat half-duplex.
+ Device B tidak dapat mendeteksi bahwa lawan bicaranya hilang. Rancang
  mekanisme paling sederhana yang membuatnya sadar, dan sebutkan biayanya.
+ Sistem ini menganggap setiap balasan yang tiba pasti berasal dari lawan
  bicara yang benar. Sebutkan apa yang terjadi bila ada kelompok lain memakai
  frekuensi dan SF yang sama di ruangan yang sama.

== Concept Check

+ Apa arti half-duplex, dan bagian mana dari kode yang memaksa kedua board
  bergiliran?
+ Mengapa payload perlu memuat identitas pengirim?
+ Apa fungsi `PING_INTERVAL`, dan apa akibatnya bila nilainya diperkecil
  menjadi 200 ms?
+ Mengapa responder diunggah lebih dahulu?
+ Mengapa satu file source dapat menghasilkan dua firmware yang berbeda, dan di
  mana perbedaannya ditentukan?

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Percakapan yang mengukur dirinya sendiri])[
  / CH-1 --- Ukur sendiri waktu pulang-pergi: Catat `millis()` saat Ping
    dikirim, hitung selisihnya saat Pong tiba, dan tampilkan langsung di Serial
    Monitor beserta rata-rata berjalan.

  / CH-2 --- Nomor urut percakapan: Ubah payload menjadi `DeviceA:Ping:n`, dan
    buat kedua board mendeteksi paket yang hilang dari lompatan nomor.
]

#tujuan-prak(3, [Pemulihan yang lebih cerdas])[
  / CH-3 --- Responder yang sadar: Buat Device B mencetak peringatan bila tidak
    menerima apa pun selama 15 detik, lalu jelaskan mengapa ia tetap tidak
    boleh mulai mengirim sendiri.

  / CH-4 --- Retry dengan jeda menaik: Ganti retry tetap 5 detik dengan jeda
    yang membesar (5, 10, 20 detik) dan kembali normal setelah berhasil.
    Jelaskan keuntungannya bila ada banyak pasangan board di satu ruangan.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- half-duplex, initiator dan responder, auto-retry.
+ Konfigurasi --- build flag peran, parameter radio, format payload.
+ Hasil eksperimen --- log serial kedua board (EXP-01 sampai EXP-03 beserta
  checkpoint).
+ Data pengukuran --- @tbl:m03-ukur-a, @tbl:m03-ukur-b, dan @tbl:m03-ukur-c.
+ Analisis dan concept check.
+ Challenge --- minimal CH-1 dan CH-2.
+ Kesimpulan yang disusun sendiri, khususnya mengenai siapa yang bertanggung
  jawab memulihkan percakapan.
