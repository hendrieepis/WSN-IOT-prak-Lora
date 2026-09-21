// ============================================================================
// Modul 09 — CSMA/CA: Dengar Dulu, Baru Bicara
// Sumber: Modul09_lora_csma_ca/README.md; listing kode dibaca langsung dari
//         salinan berkas sumber di assets/code/Modul09_lora_csma_ca/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul, todo
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist
#import "../config.typ": edisi_buku

#chapter("Modul 09 — CSMA/CA: Dengar Dulu, Baru Bicara", l: "bab:modul-09")

#identitas-modul(
  "Modul 09",
  [Listen Before You Talk --- CSMA/CA],
  [Arduino Uno + Dragino LoRa Shield v1.2 · topologi bintang, 2 node + gateway ·
   carrier sense + backoff · level Advanced · 1 × 50 menit ·
   folder kode `Modul09_lora_csma_ca`],
)

#pengantar([Gambaran Umum])[
Modul 09 dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat lanjut, dan
merupakan langkah keempat dalam menghadapi tabrakan. Tiga modul sebelumnya
menanganinya *setelah* terjadi: M08 membiarkannya senyap, M08B membuatnya
terlihat lewat ACK, M08C memulihkannya lewat retry. Modul ini yang pertama
berusaha *menghindarinya sebelum terjadi* --- node mendengarkan kanal lebih
dahulu, dan hanya bicara kalau sedang sepi.
]

== Pendahuluan

Gagasannya juga membongkar asumsi yang dipegang sejak M05: bahwa supaya banyak
node bisa berbagi satu kanal, harus ada *satu pihak yang mengatur giliran*. M05
memakai master yang memanggil node satu per satu, M07 memindahkan master itu ke
Raspberry Pi --- keduanya bergantung pada koordinator pusat. Di sini
koordinator itu tidak ada, dan penggantinya adalah *kesopanan yang dijalankan
sendiri oleh tiap node*: dengarkan dulu, kalau ada yang sedang bicara, tunggu
sebentar dengan lama tunggu acak, lalu coba lagi.

Topologinya tetap _many-to-one_ seperti M05 --- dua node sensor, satu gateway
--- dan justru kemiripan itulah yang membuat perbandingannya tajam. Yang hilang
cuma satu: gateway tidak pernah lagi berkata "Node 1, sekarang giliranmu." Ia
hanya duduk mendengarkan. Pertanyaan modul ini: bisakah dua node yang tidak
pernah saling berjanji tetap menghindari tabrakan, hanya bermodalkan telinga
masing-masing?

Prasyaratnya M02 untuk pola interrupt DIO0 dan flag di sisi gateway, M04 untuk
pembacaan RSSI per paket, M05 untuk gagasan pengalamatan node di lapisan
aplikasi, dan M08 sebagai pembanding langsung --- kanal yang sama tanpa carrier
sense sama sekali. Yang dibangun di sini adalah _carrier sensing_ pada SX1276
(dua cara: ambang RSSI dan CAD), _random exponential backoff_ dengan pencacah
yang dibekukan selagi kanal terpakai, serta pengukuran *tunda akses kanal* ---
besaran baru yang belum pernah muncul di modul mana pun sebelumnya.

#penting[
  *Dua hal sengaja dikembalikan ke keadaan paling polos di modul ini, dan itu
  keputusan metodologis.* Pertama, *tidak ada ACK* --- padahal M08B dan M08C
  sudah memilikinya. Kedua, *payload-nya lebih sederhana*:
  `NODE=<id>,SEQ=<n>,T=..,H=..`, satu sensor per node, bukan format dua ruangan
  `R1T/R1H/R2T/R2H` yang dipakai arc M08. Alasannya sama untuk keduanya: modul
  ini mengukur *satu variabel saja*, yaitu efek mendengarkan kanal sebelum
  bicara. Kalau ACK dan retry ikut menyala, kegagalan yang tersisa akan
  tertutup oleh pemulihan, dan angka yang terbaca bukan lagi angka carrier
  sense. Karena itu pembandingnya bukan M08C, melainkan *M08* --- dan modul ini
  bahkan menyediakan pembanding itu di dalam dirinya sendiri lewat `CS_MODE=2`
  ("telinga dimatikan"), sehingga kedua kondisi dapat diukur pada perangkat,
  ruangan, dan sesi yang sama.
]

*Peta modul LoRa*

#tbl(
  table(
    columns: (auto, 1fr),
    align: (center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Fokus (yang ditumpuk di atas modul sebelumnya)]),
    [05], [Tabrakan dicegah lewat polling terpusat --- master memanggil satu per satu],
    [08], [Penjadwalan dilepas --- node kirim bebas, tabrakan senyap diamati],
    [08B], [ACK ditempelkan di atas M08 --- node tahu SUCCESS/FAILED, belum ada retry],
    [08C], [Random backoff + retry --- kegagalan dipulihkan, dan Pure ALOHA menjadi lengkap],
    [*09 (ini)*], [*Carrier sense --- dengar dulu sebelum bicara, tabrakan dihindari sebelum terjadi*],
    [10], [SYNC + slot waktu --- Slotted ALOHA (slot diundi) vs TDMA (slot tetap)],
  ),
  [Peta modul pada arc kedua seri LoRa],
  "tbl:m09-peta",
)

*Kontrak data lab ini.* Tiap node membawa *satu* sensor suhu dan kelembaban dan
mengirimkannya sebagai `NODE=<id>,SEQ=<n>,T=<suhu>,H=<lembab>`. Bentuk
`KEY=VALUE` dipisah koma dipilih alih-alih CSV posisional
(`NODE1,TEMP,28.5,HUM,70.2`) karena satu alasan praktis: penerima tidak perlu
tahu urutan field, cukup mencari kuncinya dengan `indexOf` dan `substring` ---
dan bila kelak ada field tambahan (RSSI, tegangan baterai), parser lama tetap
jalan tanpa diubah. Identitas sumber ada di field `NODE`, sehingga gateway
langsung tahu data ini milik siapa tanpa perlu bertanya. Nomor urut `SEQ` naik
untuk *setiap data yang dihasilkan*, termasuk data yang akhirnya dibuang node
karena kanal tak kunjung bebas --- dengan begitu lubang pada `SEQ` di sisi
gateway ikut merekam paket yang bahkan tidak pernah naik ke udara.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Menghindari tabrakan tanpa koordinator pusat])[
  + Menjelaskan tiga bagian CSMA/CA (_carrier sense_, _multiple access_,
    _collision avoidance_) dan menunjukkan baris kode yang mewujudkan
    masing-masing.
  + Melakukan _carrier sensing_ pada SX1276 dengan dua cara --- ambang RSSI dan
    CAD (_Channel Activity Detection_) --- serta menjelaskan kapan keduanya
    memberi jawaban berbeda.
  + Menentukan ambang RSSI kanal-sibuk secara empiris dari pengukuran lantai
    derau dan kekuatan sinyal node tetangga, bukan menebak angkanya.
  + Menjelaskan mengapa _backoff_ harus *acak* dan mengapa jendela kontensi
    (CW) harus *melebar* setiap kali kanal ditemukan sibuk.
  + Mengukur harga yang dibayar CSMA/CA --- tunda akses kanal dan paket yang
    dibuang --- lalu membandingkannya dengan kirim-buta tanpa carrier sense.
]

*Kriteria keberhasilan*

#checklist((
  [Kedua node mengirim data suhu dan kelembaban secara mandiri, tanpa perintah
   apa pun dari gateway.],
  [Gateway mencetak setiap paket lengkap dengan identitas node, RSSI, SNR, dan
   selang dari paket sebelumnya.],
  [Serial monitor node menampilkan `[CS] kanal SIBUK` dan `[BACKOFF]` ketika
   node lain sedang mengirim --- bukti telinganya benar-benar bekerja.],
  [Ketika interval kirim dipersempit, jumlah `[BACKOFF]`, `[FREEZE]`, dan tunda
   akses naik, tetapi paket yang tiba di gateway tetap utuh terbaca.],
))

== Dasar Teori (Secukupnya)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [Carrier Sense (CS)], [Memeriksa kanal sebelum mengirim: adakah orang lain sedang memakai udara di frekuensi ini?],
    [Multiple Access (MA)], [Banyak node berbagi satu frekuensi yang sama, tanpa pembagian waktu atau kanal dari pusat.],
    [Collision Avoidance (CA)], [Bila kanal sibuk: *jangan* langsung kirim begitu sepi, tetapi mundur selama waktu acak lebih dulu.],
    [DIFS], [Rentang waktu kanal harus terbukti bebas *terus-menerus* sebelum node berhak mengirim. Satu sampel bebas tidak cukup.],
    [Slot dan Contention Window (CW)], [Backoff dihitung dalam satuan slot. Node mengundi angka $0 … "CW" - 1$; makin sering kanal ditemukan sibuk, makin lebar CW.],
    [Freeze], [Pencacah backoff *berhenti berkurang* selama ada yang mengirim, lalu lanjut lagi saat sepi --- supaya yang sudah lama antre tidak kehilangan gilirannya.],
    [RSSI sensing], [Kanal dianggap terpakai bila kekuatan sinyal terbaca melewati ambang. Murah, tetapi ikut menghitung derau dan sinyal non-LoRa.],
    [CAD], [SX1276 mengkorelasikan simbol LoRa; ia mengenali sinyal LoRa bahkan yang tenggelam di bawah lantai derau, dan mengabaikan gangguan yang bukan LoRa.],
    [Hidden node], [Dua node yang saling tidak terdengar tetap dapat menabrak di gateway, walau keduanya patuh mendengarkan.],
    [Tunda akses kanal], [Selisih waktu antara "data siap" dan "paket benar-benar naik ke udara" --- harga yang dibayar demi kesopanan.],
  ),
  [Istilah kerja Modul 09],
  "tbl:m09-istilah",
)

*Mengapa CA, bukan CD.* Ethernet klasik memakai CSMA/#[*CD*] --- _collision
detection_ --- karena kabel memungkinkan pengirim mendengarkan jalurnya sendiri
sambil mengirim, dan langsung berhenti ketika dua sinyal beradu. Radio tidak
bisa begitu: pemancar SX1276 membutakan penerimanya sendiri, sehingga selama TX
berlangsung node *buta total* terhadap keadaan kanal. Karena tabrakan tidak
mungkin dideteksi di tengah jalan, satu-satunya strategi yang tersisa adalah
*menghindarinya sebelum berangkat*. Itulah sebabnya semua protokol radio
berbagi kanal --- Wi-Fi, Zigbee, LoRaWAN kelas tertentu --- memakai CA, bukan
CD.

*Mengapa backoff harus acak.* Bayangkan backoff bernilai tetap. Dua node yang
sama-sama menunggu kanal yang sedang dipakai akan selesai menunggu pada saat
yang sama persis, lalu mengirim bersamaan --- tabrakan yang justru *diciptakan*
oleh mekanisme penghindarnya sendiri. Angka acak memecah simetri itu. Dan
ketika kanal berkali-kali ditemukan sibuk (tanda peserta makin banyak atau
makin ramai), rentang undiannya dilebarkan supaya peluang dua node mengundi
angka yang sama makin kecil --- inilah _exponential backoff_.

*Batas yang tetap ada.* CSMA/CA mengurangi tabrakan, tidak menghapusnya. Dua
node yang menyelesaikan DIFS pada milidetik yang sama tetap akan berangkat
bersamaan; node yang mulai mengirim tepat setelah tetangganya selesai menyensor
juga tidak akan terdeteksi. Dan karena modul ini belum punya ACK, tabrakan yang
tetap terjadi tetap *senyap* --- node mengira paketnya berhasil karena kanal
terdengar sepi saat ia berangkat.

*Sekuens yang diamati*

#diagram(```
   Node 1                      (udara)                      Gateway
     |
   data siap
     |-- dengar (DIFS) --> sepi
     |
   "NODE=1,SEQ=5,T=28.5,H=70.2" -------------------------->  tiba, dicetak
     |======== mengirim ~60 ms ========|
                     ^
   Node 2            |
     |               |
   data siap         |
     |-- dengar -----+--> SIBUK  (RSSI tinggi / CAD detected)
     |
     |-- undi slot backoff: 2 dari CW=4  -> tunggu 2 x 20 ms
     |   (pencacah dibekukan selama Node 1 masih mengirim)
     |
     |-- dengar (DIFS) --> sepi
   "NODE=2,SEQ=8,T=29.1,H=68.4" -------------------------->  tiba, dicetak
                                                        Selang tercatat di
                                                        gateway: jelas terpisah
```.text, rapat: true)

== Topologi

#diagram(```
                +---------------------------+
                |   Node 1                  |
                |   Arduino Uno + Shield    |
                |   Sensor suhu & kelembaban|
                |   dengar -> backoff -> TX |
                +-------------+-------------+
                              |
                              | LoRa (kirim sendiri, tanpa diminta)
                              v
                      +---------------+
                      |    Gateway    |
                      | Uno + Shield  |
                      | hanya dengar  |
                      | (bukan master)|
                      +---------------+
                              ^
                              | LoRa (kirim sendiri, tanpa diminta)
                +-------------+-------------+
                |   Node 2                  |
                |   Arduino Uno + Shield    |
                |   Sensor suhu & kelembaban|
                |   dengar -> backoff -> TX |
                +---------------------------+
```.text)

#tbl(
  table(
    columns: (auto, auto, 1.2fr, 1.2fr, auto),
    align: (left, left, left, left, left),
    inset: (x: 0.45em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Environment], th[Peran], th[Mekanisme TX/RX], th[Interval kirim]),
    [Node 1], [`node1`], [Baca sensor, sensing kanal, backoff, kirim], [TX blocking; RX kontinu *hanya* untuk mendengar kanal], [acak 2000--5000 ms],
    [Node 2], [`node2`], [Sama persis, keputusannya independen], [TX blocking; RX kontinu *hanya* untuk mendengar kanal], [acak 2000--5000 ms],
    [Gateway], [`gateway`], [Terima, catat, deteksi lubang `SEQ`], [Interrupt DIO0 + flag, *tanpa TX sama sekali*], [---],
  ),
  [Peran tiap node Modul 09],
  "tbl:m09-topologi",
)

Karena gateway tidak pernah memancar, ia tidak pernah ikut membuat kanal sibuk.
Setiap kali sebuah node melaporkan `[CS] kanal SIBUK`, yang ia dengar
dipastikan node satunya --- bukan gema dari gateway.

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
  [Alat dan bahan Modul 09],
  "tbl:m09-alat",
)

*Sensor suhu dan kelembaban.* Nilai T dan H dibangkitkan di dalam firmware
(dummy, berbeda titik dasar untuk tiap node) supaya modul bisa dijalankan tanpa
sensor fisik --- fokus modul ini ada pada akses kanal, bukan pembacaan sensor.
Untuk memakai DHT22 sungguhan, satu-satunya yang perlu diubah adalah isi fungsi
`bacaSensor()` di `src/node/main.cpp`; tambahkan library-nya ke `lib_deps` dan
pasang pin datanya ke pin digital yang *tidak dipakai shield* (D10, D11, D12,
D13, D9, dan D2 sudah terpakai SPI, RST, dan DIO0 --- gunakan D3--D8). Tidak
ada baris lain yang perlu disentuh, sebab seluruh mekanisme CSMA/CA tidak
peduli dari mana angkanya datang.

*Pemetaan pin Dragino Shield v1.2*

#tbl(
  table(
    columns: (auto, auto),
    align: (left, left),
    inset: (x: 0.7em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Fungsi], th[Pin Uno]),
    [NSS / CS], [D10],
    [RST], [D9],
    [DIO0], [D2],
    [SCK / MOSI / MISO], [D13 / D11 / D12],
  ),
  [Pemetaan pin Modul 09],
  "tbl:m09-pin",
)

*Struktur proyek*

#diagram(```
Modul09_lora_csma_ca/
├── platformio.ini         ← tiga environment; CS_MODE memilih RSSI atau CAD
├── lora_monitor.py        ← dashboard 3-panel live + statistik akses kanal + CSV
├── upload_auto.py         ← unggah ketiga board, port dideteksi sendiri
├── logserial.md           ← log serial aktual dari pengujian perangkat
└── src/
    ├── node/main.cpp      ← sensing + backoff + TX (env node1, node2)
    └── gateway/main.cpp   ← terima & cetak, deteksi lubang SEQ (env gateway)
```.text)

*Parameter CSMA/CA di `src/node/main.cpp`*

#tbl(
  table(
    columns: (auto, auto, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Konstanta], th[Nilai bawaan], th[Arti]),
    [`RSSI_THRESHOLD`], [#sym.minus 95 dBm], [Di atas ini kanal dianggap terpakai. *Dikalibrasi di EXP-01.*],
    [`DIFS_MS`], [30 ms], [Kanal harus bebas selama ini sebelum boleh mengirim],
    [`SLOT_MS`], [20 ms], [Panjang satu slot backoff],
    [`CW_MIN` / `CW_MAX`], [4 / 64], [Jendela kontensi awal dan batas atasnya],
    [`MAX_ATTEMPT`], [5], [Sesudah ini paket dibuang (`[DROP]`), tidak dipaksakan],
    [`CS_MODE`], [0 (RSSI)], [0 = RSSI, 1 = CAD, 2 = telinga dimatikan (pembanding EXP-04) --- diatur dari `platformio.ini`],
    [`SEND_INTERVAL_MIN` / `MAX`], [2000 / 5000 ms], [Jarak antar data. Bisa ditimpa dari `platformio.ini` untuk EXP-03],
  ),
  [Parameter CSMA/CA Modul 09],
  "tbl:m09-parameter",
)

Waktu udara satu paket modul ini (#sym.approx 26 byte, SF7, BW 125 kHz, CR 4/5,
preamble 8) sekitar *60 ms* menurut perhitungan --- hitung sendiri angka
pastinya sebagai bagian dari Analisis. Seluruh angka di tabel di atas dipilih
relatif terhadap angka itu.

== Kode Program

#sumber-kode("Modul09_lora_csma_ca",
  ("platformio.ini", "src/node/main.cpp", "src/gateway/main.cpp",
   "lora_monitor.py", "upload_auto.py"))

#kode-berkas("Modul09_lora_csma_ca/platformio.ini",
  [`platformio.ini` Modul 09 --- `CS_MODE` dan interval kirim lewat build flag],
  "lst:m09-ini",
  pecah: true,
)

#kode-berkas("Modul09_lora_csma_ca/src/node/main.cpp",
  [`src/node/main.cpp` --- carrier sense (RSSI dan CAD), backoff, dan freeze],
  "lst:m09-node",
  pecah: true,
)

#kode-berkas("Modul09_lora_csma_ca/src/gateway/main.cpp",
  [`src/gateway/main.cpp` --- terima, catat selang, dan tolak paket cacat],
  "lst:m09-gateway",
  pecah: true,
)

#kode-berkas("Modul09_lora_csma_ca/lora_monitor.py",
  [`lora_monitor.py` --- dasbor tiga panel dengan statistik akses kanal],
  "lst:m09-monitor",
  pecah: true,
)

#kode-berkas("Modul09_lora_csma_ca/upload_auto.py",
  [`upload_auto.py` --- unggah ketiga board dengan port terdeteksi sendiri],
  "lst:m09-upload",
  pecah: true,
)

== Build dan Flash

*Gateway lebih dahulu*, supaya paket pertama dari node langsung tertangkap.

#keluaran("pio run -d Modul09_lora_csma_ca -e gateway -t upload -t monitor
pio run -d Modul09_lora_csma_ca -e node1   -t upload -t monitor
pio run -d Modul09_lora_csma_ca -e node2   -t upload -t monitor")

Atau otomatis, tanpa mengedit port di `platformio.ini`:

#keluaran("python3 Modul09_lora_csma_ca/upload_auto.py")

*Monitor dashboard.* `python3 lora_monitor.py` membaca ketiga port sekaligus
dan menampilkan panel Gateway, Node 1, dan Node 2. Panel node modul ini
menampilkan statistik akses kanal: berapa kali kanal ditemukan sibuk, berapa
kali backoff dan freeze terjadi, berapa paket dibuang, serta tunda akses
terakhir dan rata-ratanya. Memerlukan `pip install pyserial rich`.

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada ketiga shield.],
  [Port ketiga board dicatat lewat `pio device list` (atau
   `python3 ../tools/deteksi_port.py`) dan diisikan ke `platformio.ini`.],
  [Tiga Serial Monitor 115200 baud siap, ketiganya terlihat bersamaan.],
  [`NODE_ID` pada `node1` dan `node2` sudah benar, dicek dari baris pembuka
   `NODE 1` atau `NODE 2`.],
  [Baris `Carrier sense:` pada kedua node menunjukkan mode dan ambang yang
   sama.],
))

== Percobaan

=== EXP-01 --- Kalibrasi Telinga: Berapa Nilai "Sibuk"?

Ambang #sym.minus 95 dBm di kode hanyalah tebakan awal. Sebelum mempercayai
keputusan node, ukur dulu seperti apa kanal ini sebenarnya.

+ Nyalakan *satu node saja*, board lain dimatikan. Saat menyala, node mengambil
  200 sampel RSSI kanal kosong dan melaporkannya sendiri.

  #keluaran("[KALIBRASI] lantai derau 200 sampel: min -119 | rata-rata -112 | maks -104 dBm
[KALIBRASI] ambang terpakai sekarang: -95 dBm -- lihat EXP-01")

  Angka di atas hanya bentuk barisnya; nilai sesungguhnya bergantung pada
  lingkungan masing-masing.

+ Nyalakan node kedua. Pada serial node pertama, baca nilai RSSI yang tercetak
  pada baris `[CS] kanal SIBUK (RSSI ...)` --- itulah kekuatan sinyal tetangga
  saat sedang mengirim.

+ Tentukan ambang di tengah-tengah kedua nilai itu, lalu isikan ke
  `RSSI_THRESHOLD` dan unggah ulang kedua node. Baris `[KALIBRASI]` kedua akan
  mengonfirmasi ambang baru sudah terpasang.

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr, 1fr),
    align: (left, left, left),
    inset: (x: 0.55em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Verifikasi 23-08-2026], th[Hasil sendiri]),
    [Lantai derau --- min / rata-rata / maks (dBm)], [#sym.minus 117 / #sym.minus 110 / #sym.minus 105], [#isian],
    [RSSI saat node tetangga mengirim], [#sym.minus 29 … #sym.minus 33], [#isian],
    [Selisih keduanya (dB)], [#sym.approx 80], [#isian],
    [`RSSI_THRESHOLD` yang dipilih], [#sym.minus 95 (bawaan, sudah di tengah rentang)], [#isian],
  ),
  [Lembar pengamatan EXP-01 --- kalibrasi ambang carrier sense],
  "tbl:m09-exp01",
)

#checkpoint[
  *Terpenuhi pada verifikasi.* Selisihnya ternyata sangat lebar --- sekitar
  *80 dB* antara kanal kosong (#sym.approx #sym.minus 110 dBm) dan kanal
  terpakai (#sym.approx #sym.minus 30 dBm) pada jarak meja --- sehingga ambang
  bawaan #sym.minus 95 dBm aman di tengah rentang dan tidak perlu diubah.
  Selisih sebesar itu tidak dijamin di ruangan lain; tetap ukur sendiri.
  Selisih antara kanal kosong dan kanal terpakai harus jelas (belasan hingga
  puluhan dB pada jarak meja). Bila selisihnya kecil, jarak antar-board terlalu
  jauh atau antena belum terpasang benar. Ambang yang terlalu tinggi membuat
  node tuli (semua dianggap sepi); terlalu rendah membuatnya paranoid (semua
  dianggap sibuk, semua paket berakhir `[DROP]`).
]

=== EXP-02 --- Dua Node Sopan

Nyalakan ketiga board dengan parameter bawaan dan amati beberapa menit.

*Expected output --- node*

#keluaran("=== LoRa CSMA/CA - NODE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
Carrier sense: RSSI (ambang -95 dBm) | DIFS 30 ms | slot 20 ms | CW 4..64
Peran: NODE (CSMA/CA) -- dengar dulu, mundur acak, baru kirim
Tanpa ACK: node tahu kanal sepi, tetap tidak tahu paketnya sampai
[KALIBRASI] lantai derau 200 sampel: min -117 | rata-rata -110 | maks -105 dBm
[KALIBRASI] ambang terpakai sekarang: -95 dBm -- lihat EXP-01

[TX] NODE=1,SEQ=0,T=27.1,H=70.5 | attempt=1 | tunda=31 ms
[STAT] TX=1 | DROP=0 | kanal sibuk=0 | rata-rata tunda=31 ms")

Ketika tetangganya sedang bicara:

#keluaran("[CS] kanal SIBUK (RSSI -47 dBm)
[BACKOFF] percobaan 1/5 | CW=4 | slot=2 -> 40 ms
[FREEZE] pencacah backoff dibekukan -- kanal terpakai
[TX] NODE=2,SEQ=3,T=29.2,H=67.8 | attempt=2 | tunda=118 ms")

*Expected output --- gateway*

#keluaran("=== PAKET DITERIMA ===
  Node    : 1
  SEQ     : 0
  Suhu    : 27.1 C
  Lembab  : 70.5 %
  RSSI    : -45 dBm
  SNR     : 9.25 dB
  Statistik Node 1: diterima=1 | perkiraan hilang=0
  Total diterima gateway: 1
=====================

=== PAKET DITERIMA ===
  Node    : 2
  SEQ     : 0
  Suhu    : 27.1 C
  Lembab  : 71.0 %
  RSSI    : -55 dBm
  SNR     : 9.50 dB
  Selang  : 136 ms dari paket sebelumnya
  Statistik Node 2: diterima=1 | perkiraan hilang=0
  Total diterima gateway: 2
=====================")

*Data capture* --- amati 3 menit.

#tbl(
  table(
    columns: (1.4fr, 1.1fr, 1fr),
    align: (left, left, left),
    inset: (x: 0.55em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Verifikasi 23-08-2026], th[Hasil sendiri]),
    [Paket diterima gateway --- N1 / N2], [49 / 49 (dari 50 / 49 dikirim)], [#isian],
    [Jumlah `[CS] kanal SIBUK` --- N1 / N2], [1 / 2], [#isian],
    [Jumlah `[BACKOFF]` --- N1 / N2], [1 / 2], [#isian],
    [Jumlah `[DROP]` --- N1 / N2], [0 / 0], [#isian],
    [Tunda akses rata-rata (ms) --- N1 / N2], [31,7 / 34,3], [#isian],
    [Selang antar-paket terkecil di gateway (ms)], [116], [#isian],
  ),
  [Lembar pengamatan EXP-02 --- dua node sopan],
  "tbl:m09-exp02",
)

#checkpoint[
  *Terpenuhi.* Pada interval bawaan (2--5 detik) kanal jarang berebut: 97 dari
  99 paket berangkat dengan `attempt=1` dan tunda #sym.approx `DIFS_MS`
  (30 ms). Tiga kali sepanjang 3 menit sebuah node menemukan kanal terpakai,
  mundur, lalu berhasil pada percobaan kedua. Yang wajib muncul minimal
  beberapa kali adalah baris `[CS] kanal SIBUK` --- itulah bukti telinga node
  benar-benar mendengar tetangganya. Bila tidak pernah muncul sama sekali
  sepanjang 3 menit, ambang RSSI kemungkinan masih terlalu tinggi; ulangi
  EXP-01.
]

=== EXP-03 --- Memaksa Berebut

Perkecil interval kirim pada *kedua* node menjadi 300--500 ms lewat build flag
di `platformio.ini` (tidak perlu mengedit source), seperti @lst:m09-exp03.

#kode(```ini
build_flags = -DNODE_ID=1 -DCS_MODE=0 -DSEND_INTERVAL_MIN=300 -DSEND_INTERVAL_MAX=500
```.text,
  [Build flag EXP-03 --- interval kirim dipersempit],
  "lst:m09-exp03",
  bahasa: "ini",
)

Unggah ulang kedua node, lalu amati kembali. Beban kanal kini jauh melewati
kapasitasnya (dua paket #sym.tilde.op 60 ms setiap #sym.tilde.op 400 ms per
node), sehingga mekanisme CA dipaksa bekerja keras.

*Data capture* --- amati 3 menit.

#tbl(
  table(
    columns: (1.4fr, 1.2fr, 1fr),
    align: (left, left, left),
    inset: (x: 0.55em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Verifikasi 23-08-2026], th[Hasil sendiri]),
    [Interval kirim yang dipakai (ms)], [300--500], [#isian],
    [Paket diterima gateway --- N1 / N2], [351 / 343 (dari 352 / 348 dikirim)], [#isian],
    [Jumlah `[BACKOFF]` --- N1 / N2], [32 / 67], [#isian],
    [Jumlah `[FREEZE]` --- N1 / N2], [26 / 46], [#isian],
    [Jumlah `[DROP]` --- N1 / N2], [0 / 0], [#isian],
    [CW terbesar yang sempat terpakai], [16], [#isian],
    [Tunda akses rata-rata (ms) --- N1 / N2], [37,2 / 46,1 (maks 238 / 257)], [#isian],
    [Jumlah `[GAP]` di gateway --- N1 / N2], [0 / 4], [#isian],
  ),
  [Lembar pengamatan EXP-03 --- memaksa berebut kanal],
  "tbl:m09-exp03-tbl",
)

#buka-abstraksi[
  Di `src/node/main.cpp`, fungsi `hitungMundurSlot()` *tidak* sekadar
  `delay(slot * SLOT_MS)`. Pencacahnya berhenti berkurang selama kanal terpakai
  dan lanjut lagi saat sepi. Ganti sementara isi fungsi itu dengan
  `delay((long)slot * SLOT_MS)` biasa, unggah ulang, lalu ulangi EXP-03 dan
  bandingkan jumlah `[DROP]`-nya. Jelaskan: node mana yang dirugikan oleh
  backoff yang _tidak_ dibekukan, dan mengapa?
]

#checkpoint[
  *Terpenuhi sebagian.* `[BACKOFF]` melonjak dari 3 (EXP-02) menjadi 99, tunda
  akses rata-rata naik #sym.tilde.op 30 %, dan CW sempat melebar sampai 16.
  Tetapi `[DROP]` *tetap nol*: dengan dua node, lima percobaan selalu cukup
  untuk memperoleh kanal. Untuk benar-benar memunculkan `[DROP]`, perkecil
  `MAX_ATTEMPT` atau tambahkan node ketiga (CH-2). Yang paling penting justru
  ini: dari 700 paket yang naik ke udara, gateway mencatat *0 paket cacat* ---
  CA memindahkan kegagalan dari "rusak di udara" menjadi "tertunda" (dan, pada
  beban lebih tinggi, "dibuang sebelum berangkat") --- kegagalan yang
  setidaknya *diketahui pengirimnya*.
]

=== EXP-04 --- Matikan Telinganya

Ini percobaan pembanding yang paling menentukan. Pada *kedua* node, matikan
telinganya lewat build flag --- pertahankan interval sempit dari EXP-03.

#kode(```ini
build_flags = -DNODE_ID=1 -DCS_MODE=2 -DSEND_INTERVAL_MIN=300 -DSEND_INTERVAL_MAX=500
```.text,
  [Build flag EXP-04 --- carrier sense dimatikan (`CS_MODE=2`)],
  "lst:m09-exp04",
  bahasa: "ini",
)

Node kini mengirim buta --- persis Pure ALOHA. Unggah ulang kedua node, amati
3 menit, lalu *kembalikan `CS_MODE=0`*. Baris pembuka node akan menegaskan mode
yang sedang aktif: `Carrier sense: MATI -- kirim buta`.

*Data capture* --- hasil verifikasi 23 Agustus 2026, masing-masing 3 menit,
beban kirim setara.

#tbl(
  table(
    columns: (1.3fr, 1fr, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Dengan CS (EXP-03)], th[Tanpa CS (EXP-04)]),
    [Paket dikirim node --- total], [700], [757],
    [Paket diterima gateway --- total], [695], [581],
    [Paket hilang], [*5 (0,7 %)*], [*176 (23,2 %)*],
    [Jumlah `[GAP]` di gateway --- total], [4], [102],
    [`[WARN]` paket cacat di gateway], [0], [37],
    [Tunda akses rata-rata (ms)], [37--46], [*0*],
    [Paket dibuang node (`[DROP]`)], [0], [0 (tidak ada mekanismenya)],
  ),
  [Hasil EXP-04 --- CSMA/CA dibanding kirim buta],
  "tbl:m09-exp04-tbl",
)

#checkpoint[
  *Terpenuhi.* Tanpa carrier sense tunda akses turun ke nol --- dan satu dari
  setiap empat paket lenyap. Inilah pertukaran inti modul ini: CSMA/CA *membeli
  keandalan dengan waktu*, sekitar 40 ms per paket untuk menekan kehilangan
  dari 23 % menjadi di bawah 1 %. Perhatikan juga bahwa tanpa carrier sense,
  node mengirim *lebih banyak* paket (757 vs 700, karena tidak pernah menunggu)
  namun gateway justru menerima *lebih sedikit*. Bila kedua kolom nyaris sama,
  beban kanal belum cukup tinggi --- persempit lagi intervalnya.
]

*Tabrakan terlihat langsung di sini.* Pada sesi tanpa carrier sense, gateway
mencetak paket yang awalannya masih terbaca sementara sisanya hancur --- inilah
wujud tabrakan yang selama EXP-03 tidak pernah muncul sama sekali.

#keluaran("[WARN] Paket cacat (field tidak lengkap): NODE=2,SEQ=1,T=28.t,??,a?2")

=== EXP-05 --- RSSI dibanding CAD

Ubah `-DCS_MODE=0` menjadi `-DCS_MODE=1` pada *kedua* node di
`platformio.ini`, unggah ulang, lalu ulangi EXP-03 dengan interval yang sama
persis.

*Data capture* --- hasil verifikasi 23 Agustus 2026, beban kirim setara.

#tbl(
  table(
    columns: (1.4fr, 1fr, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[`CS_MODE=0` (RSSI)], th[`CS_MODE=1` (CAD)]),
    [Jumlah `[CS] kanal SIBUK` --- total], [99], [*107*],
    [Jumlah `[FREEZE]` --- total], [72], [96],
    [Jumlah `[DROP]` --- total], [0], [0],
    [Tunda akses rata-rata (ms) --- N1 / N2], [37,2 / 46,1], [43,3 / 41,3],
    [Paket dikirim / diterima gateway], [700 / 695], [699 / 694],
  ),
  [Hasil EXP-05 --- carrier sense berbasis RSSI dibanding CAD],
  "tbl:m09-exp05",
)

#checkpoint[
  *Terpenuhi.* CAD tidak memerlukan ambang sama sekali (perhatikan: baris
  pembuka node tidak lagi menyebut angka dBm), sebab ia mengenali bentuk simbol
  LoRa, bukan sekadar besar energi. Hasil akhirnya praktis setara --- selisih
  satu paket dari #sym.tilde.op 700 --- tetapi CAD melaporkan kanal sibuk
  *lebih sering* (107 vs 99). Pikirkan mana dari keduanya yang sedang keliru:
  apakah CAD terlalu waspada, atau justru ambang #sym.minus 95 dBm yang
  melewatkan sinyal lemah?
]

#buka-abstraksi[
  *Untuk yang mengutak-atik mode ini.* Library `sandeepmistry/LoRa` tidak
  menyediakan CAD sama sekali, jadi `kanalTerpakai()` versi CAD menulis register
  SX1276 langsung. Dua jebakan yang ditemukan saat modul ini diuji --- keduanya
  sudah diperbaiki di kode, dan keduanya layak ditelusuri sendiri di
  `src/node/main.cpp`:

  + CAD *harus* dimasuki dari STANDBY. Perintah CAD dari mode RX kontinu tidak
    pernah dijalankan: `CadDone` tak pernah naik dan tiap pemeriksaan berakhir
    di timeout.
  + `isTransmitting()` milik library menguji `(RegOpMode & 0x03) == 0x03`, dan
    mode CAD (`0x07`) *lolos uji itu*. Bila modem masih di CAD saat
    `beginPacket()` dipanggil, `beginPacket()` gagal diam-diam tanpa me-reset
    FIFO, dan yang naik ke udara adalah sampah. Rinciannya di `logserial.md`.
]

=== Verifikasi Perangkat Keras

#catatan[
  *Diuji di perangkat pada 23 Agustus 2026* --- tiga Arduino Uno asli
  (`2341:0043`) + Dragino LoRa Shield v1.2 (gateway, node1, node2 pada
  `/dev/ttyACM0/1/2`, cocok dengan `platformio.ini` bawaan). Ketiga environment
  dibangun dan diunggah tanpa modifikasi. *EXP-01 sampai EXP-05 seluruhnya
  dijalankan*, masing-masing jendela rekam 180 detik, dan angka pada semua
  tabel Data capture di atas serta bagian Pengukuran adalah hasil ukur nyata
  dari sesi itu --- log lengkap beserta cuplikan serial ketiga board ada di
  `logserial.md`.
]

Dua perbaikan lahir dari pengujian ini dan sudah masuk ke kode: gateway kini
menolak paket yang field-nya tidak lengkap (tanpa itu, satu paket rusak akibat
tabrakan membuat perkiraan kehilangan melonjak ke 1177 dari kenyataan
#sym.tilde.op 30), dan jalur CAD kini masuk lewat STANDBY serta memanggil
`LoRa.idle()` sebelum `beginPacket()` (tanpa itu CAD tidak pernah mendeteksi
apa pun *dan* merusak transmisi node sendiri). Keduanya diuraikan di
`logserial.md`.

Satu hal yang *tidak* berhasil dibuktikan: `[DROP]` tetap nol di seluruh sesi.
Dengan dua node, `MAX_ATTEMPT=5` selalu cukup. Untuk melihat paket benar-benar
dibuang, perkecil `MAX_ATTEMPT` atau tambahkan node ketiga (CH-2).

// Log serial lengkap dari Modul09_lora_csma_ca/logserial.md. Hanya dicetak pada
// edisi dosen agar tidak disalin mahasiswa sebagai hasil laporan
// (lihat config.typ).
#if edisi_buku == "dosen" [
  === Log Serial Terverifikasi

  Log serial lengkap hasil uji pada board nyata, bukan contoh. Bagian ini
  hanya dicetak pada edisi dosen.

  Hasil aktual dari perangkat, direkam *2026-08-23*. Baud *115200*, frekuensi *433 MHz*, SF7 / BW 125 kHz / CR 4/5 / 17 dBm. Ketiga board di satu meja dengan jarak berbeda-beda — Node 1 lebih dekat ke gateway daripada Node 2 (lihat RSSI di bawah).

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
    [Log serial Modul 09: Board & Port],
    "tbl:m09-log-1",
  )

  Ketiga aliran serial direkam bersamaan (tiga thread `pyserial`, satu per port), masing-masing sesi *180 detik* dihitung sejak perekaman dimulai — mencakup boot ketiga board. Parameter CSMA/CA memakai nilai bawaan modul: DIFS 30 ms, slot 20 ms, CW 4…64, `MAX_ATTEMPT` 5, ambang RSSI −95 dBm.

  *Ringkasan keempat sesi*

  #tbl(
    table(
      columns: (auto, auto, auto, auto, 1fr, auto, auto, auto),
      align: (left, left, left, left, left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Sesi], th[Carrier sense], th[Interval kirim], th[Dikirim node], th[Tiba di gateway], th[Hilang], th[`[GAP]`], th[`[WARN]`]),
      [EXP-02], [RSSI], [2000–5000 ms], [99], [98], [1 (1,0%)], [1], [0],
      [EXP-03], [RSSI], [300–500 ms], [700], [695], [4 (0,6%)], [4], [0],
      [EXP-04], [*mati*], [300–500 ms], [757], [581], [*176 (23,2%)*], [102], [37],
      [EXP-05], [CAD], [300–500 ms], [699], [694], [4 (0,6%)], [4], [2],
    ),
    [Log serial Modul 09: Ringkasan keempat sesi],
    "tbl:m09-log-2",
  )

  Perkiraan kehilangan dari lompatan `SEQ` di gateway (62 + 113 \= 175 pada EXP-04) cocok dengan selisih kirim-terima yang sebenarnya (757 − 581 \= 176) — selisih satu paket berasal dari paket terakhir yang belum sempat tercatat saat perekaman berhenti.

  *Statistik akses kanal per node*

  #tbl(
    table(
      columns: (auto, auto, auto, auto, auto, auto, auto, auto, 1fr),
      align: (left, left, left, left, left, left, left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Sesi], th[Node], th[TX], th[`[CS]` sibuk], th[`[BACKOFF]`], th[`[FREEZE]`], th[`[DROP]`], th[CW maks], th[Tunda akses med / rata / maks (ms)]),
      [EXP-02], [1], [50], [1], [1], [1], [0], [4], [31 / 31,7 / 116],
      [EXP-02], [2], [49], [2], [2], [2], [0], [4], [32 / 34,3 / 87],
      [EXP-03], [1], [352], [32], [32], [26], [0], [8], [32 / 37,2 / 238],
      [EXP-03], [2], [348], [67], [67], [46], [0], [16], [44 / 46,1 / 257],
      [EXP-04], [1], [377], [0], [0], [0], [0], [—], [0 / 0 / 0],
      [EXP-04], [2], [380], [0], [0], [0], [0], [—], [0 / 0 / 0],
      [EXP-05], [1], [350], [56], [56], [53], [0], [8], [41 / 43,3 / 240],
      [EXP-05], [2], [349], [51], [51], [43], [0], [16], [39 / 41,3 / 299],
    ),
    [Log serial Modul 09: Statistik akses kanal per node],
    "tbl:m09-log-3",
  )

  `[DROP]` *nol di seluruh sesi*: bahkan pada beban tertinggi, lima percobaan selalu cukup untuk memperoleh kanal. Untuk memaksa `[DROP]` muncul, perkecil `MAX_ATTEMPT` atau tambah node ketiga (lihat CH-2).

  *RSSI & SNR di gateway*

  #tbl(
    table(
      columns: (auto, 1fr, auto),
      align: (left, left, left),
      inset: (x: 0.6em, y: 0.45em),
      stroke: 0.5pt + luma(170),
      table.header(th[Sesi], th[Node 1], th[Node 2]),
      [EXP-02], [−44,3 dBm / 9,38 dB], [−55,8 dBm / 9,63 dB],
      [EXP-03], [−44,7 dBm / 9,77 dB], [−54,5 dBm / 9,73 dB],
      [EXP-04], [−43,3 dBm / *8,58 dB*], [−54,0 dBm / 9,63 dB],
      [EXP-05], [−44,5 dBm / 9,77 dB], [−56,1 dBm / 9,85 dB],
    ),
    [Log serial Modul 09: RSSI & SNR di gateway],
    "tbl:m09-log-4",
  )

  Selisih ±11 dB antar node murni posisi fisik di meja. SNR Node 1 yang turun \~1,2 dB khusus di EXP-04 adalah jejak tabrakan: paket yang tetap berhasil didekode pun sebagian tercemar sinyal node lain.

  *EXP-02 — Boot dan peristiwa backoff pertama*

  Cuplikan 1,5 detik pertama. Ketiga board menyala hampir bersamaan; kedua node melaporkan lantai derau sekitar −110 dBm. Perhatikan Node 2: pengukuran kalibrasinya sendiri sudah "tercemar" transmisi Node 1 (`maks -30 dBm`), lalu ia langsung mendeteksi kanal sibuk, mundur 2 slot, membekukan pencacahnya, dan baru mengirim 136 ms setelah paket Node 1 tiba.

  #keluaran("[11:12:28.633] N1 | === LoRa CSMA/CA - NODE 1 ===
[11:12:28.649] N1 | Init LoRa ... OK
[11:12:28.653] N1 | Freq: 433.00 MHz
[11:12:28.658] N1 | Carrier sense: RSSI (ambang -95 dBm) | DIFS 30 ms | slot 20 ms | CW 4..64
[11:12:28.666] N1 | Peran: NODE (CSMA/CA) -- dengar dulu, mundur acak, baru kirim
[11:12:28.670] N1 | Tanpa ACK: node tahu kanal sepi, tetap tidak tahu paketnya sampai
[11:12:28.687] GW | === LoRa CSMA/CA - GATEWAY ===
[11:12:28.707] GW | Init LoRa ... OK
[11:12:28.707] GW | Freq: 433.00 MHz
[11:12:28.715] GW | Peran: GATEWAY (CSMA/CA) -- hanya mendengar, tanpa polling, tanpa ACK
[11:12:28.715] N2 | === LoRa CSMA/CA - NODE 2 ===
[11:12:28.718] GW | Menunggu paket dari Node 1 & Node 2...
[11:12:28.718] GW |
[11:12:28.735] N2 | Init LoRa ... OK
[11:12:28.735] N2 | Freq: 433.00 MHz
[11:12:28.743] N2 | Carrier sense: RSSI (ambang -95 dBm) | DIFS 30 ms | slot 20 ms | CW 4..64
[11:12:28.747] N2 | Peran: NODE (CSMA/CA) -- dengar dulu, mundur acak, baru kirim
[11:12:28.755] N2 | Tanpa ACK: node tahu kanal sepi, tetap tidak tahu paketnya sampai
[11:12:29.677] N1 | [KALIBRASI] lantai derau 200 sampel: min -117 | rata-rata -110 | maks -105 dBm
[11:12:29.685] N1 | [KALIBRASI] ambang terpakai sekarang: -95 dBm -- lihat EXP-01
[11:12:29.686] N1 |
[11:12:29.763] N2 | [KALIBRASI] lantai derau 200 sampel: min -118 | rata-rata -110 | maks -30 dBm
[11:12:29.767] N2 | [KALIBRASI] ambang terpakai sekarang: -95 dBm -- lihat EXP-01
[11:12:29.767] N2 |
[11:12:29.771] N2 | [CS] kanal SIBUK (RSSI -33 dBm)
[11:12:29.775] N2 | [BACKOFF] percobaan 1/5 | CW=4 | slot=2 -> 40 ms
[11:12:29.776] N1 | [TX] NODE=1,SEQ=0,T=27.1,H=70.5 | attempt=1 | tunda=31 ms
[11:12:29.779] GW | === PAKET DITERIMA ===
[11:12:29.779] N2 | [FREEZE] pencacah backoff dibekukan -- kanal terpakai
[11:12:29.780] GW |   Node    : 1
[11:12:29.780] GW |   SEQ     : 0
[11:12:29.783] N1 | [STAT] TX=1 | DROP=0 | kanal sibuk=0 | rata-rata tunda=31 ms
[11:12:29.784] GW |   Suhu    : 27.1 C
[11:12:29.784] GW |   Lembab  : 70.5 %
[11:12:29.784] GW |   RSSI    : -45 dBm
[11:12:29.784] N1 |
[11:12:29.788] GW |   SNR     : 9.25 dB
[11:12:29.792] GW |   Statistik Node 1: diterima=1 | perkiraan hilang=0
[11:12:29.796] GW |   Total diterima gateway: 1
[11:12:29.796] GW | =====================
[11:12:29.796] GW |
[11:12:29.915] GW | === PAKET DITERIMA ===
[11:12:29.915] GW |   Node    : 2
[11:12:29.915] N2 | [TX] NODE=2,SEQ=0,T=27.1,H=71.0 | attempt=2 | tunda=84 ms
[11:12:29.918] N2 | [STAT] TX=1 | DROP=0 | kanal sibuk=1 | rata-rata tunda=84 ms
[11:12:29.918] N2 |
[11:12:29.919] GW |   SEQ     : 0
[11:12:29.919] GW |   Suhu    : 27.1 C
[11:12:29.919] GW |   Lembab  : 71.0 %
[11:12:29.923] GW |   RSSI    : -55 dBm
[11:12:29.923] GW |   SNR     : 9.50 dB
[11:12:29.927] GW |   Selang  : 136 ms dari paket sebelumnya
[11:12:29.931] GW |   Statistik Node 2: diterima=1 | perkiraan hilang=0
[11:12:29.935] GW |   Total diterima gateway: 2
[11:12:29.935] GW | =====================
[11:12:29.935] GW |", pecah: true)

  Baris kuncinya:

  #keluaran("[11:12:29.771] N2 | [CS] kanal SIBUK (RSSI -33 dBm)      <- telinga bekerja
[11:12:29.775] N2 | [BACKOFF] percobaan 1/5 | CW=4 | slot=2 -> 40 ms
[11:12:29.776] N1 | [TX] NODE=1,SEQ=0,... | attempt=1 | tunda=31 ms
[11:12:29.779] N2 | [FREEZE] pencacah backoff dibekukan  <- N1 masih mengudara
[11:12:29.915] N2 | [TX] NODE=2,SEQ=0,... | attempt=2 | tunda=84 ms
[11:12:29.927] GW |   Selang  : 136 ms dari paket sebelumnya", pecah: true)

  Tunda akses Node 1 \= 31 ms, yaitu DIFS saja (kanal memang sepi). Tunda akses Node 2 \= 84 ms: DIFS + backoff + waktu beku menunggu Node 1 selesai.

  *EXP-03 — Beban tinggi: contention window melebar*

  Interval kirim dipersempit menjadi 300–500 ms pada kedua node. Cuplikan berikut memperlihatkan `CW` menggandakan diri 4 → 8 → 16 karena kanal ditemukan sibuk tiga kali berturut-turut, sampai akhirnya Node 2 memperoleh kanal pada percobaan ke-4 dengan tunda 155 ms:

  #keluaran("[11:02:03.950] N2 | [BACKOFF] percobaan 1/5 | CW=4 | slot=0 -> 0 ms
[11:02:03.954] N2 | [CS] kanal SIBUK (RSSI -31 dBm)
[11:02:03.958] N2 | [BACKOFF] percobaan 2/5 | CW=8 | slot=0 -> 0 ms
[11:02:03.962] N2 | [CS] kanal SIBUK (RSSI -32 dBm)
[11:02:03.966] N2 | [BACKOFF] percobaan 3/5 | CW=16 | slot=3 -> 60 ms
[11:02:03.970] N2 | [FREEZE] pencacah backoff dibekukan -- kanal terpakai
[11:02:04.009] GW | === PAKET DITERIMA ===
[11:02:04.010] N1 | [TX] NODE=1,SEQ=231,T=29.1,H=67.5 | attempt=1 | tunda=31 ms
[11:02:04.013] GW |   Node    : 1
[11:02:04.013] GW |   SEQ     : 231
[11:02:04.014] GW |   Suhu    : 29.1 C
[11:02:04.014] N1 | [STAT] TX=232 | DROP=0 | kanal sibuk=19 | rata-rata tunda=37 ms
[11:02:04.014] N1 |
[11:02:04.018] GW |   Lembab  : 67.5 %
[11:02:04.018] GW |   RSSI    : -45 dBm
[11:02:04.021] GW |   SNR     : 9.75 dB
[11:02:04.026] GW |   Selang  : 409 ms dari paket sebelumnya
[11:02:04.030] GW |   Statistik Node 1: diterima=232 | perkiraan hilang=0
[11:02:04.030] GW |   Total diterima gateway: 457
[11:02:04.034] GW | =====================
[11:02:04.034] GW |
[11:02:04.166] N2 | [TX] NODE=2,SEQ=228,T=29.7,H=72.1 | attempt=4 | tunda=155 ms
[11:02:04.169] GW | === PAKET DITERIMA ===
[11:02:04.169] GW |   Node    : 2
[11:02:04.169] GW |   SEQ     : 228
[11:02:04.171] N2 | [STAT] TX=229 | DROP=0 | kanal sibuk=47 | rata-rata tunda=44 ms
[11:02:04.171] N2 |
[11:02:04.173] GW |   Suhu    : 29.7 C
[11:02:04.173] GW |   Lembab  : 72.1 %
[11:02:04.173] GW |   RSSI    : -55 dBm
[11:02:04.177] GW |   SNR     : 9.50 dB
[11:02:04.181] GW |   Selang  : 155 ms dari paket sebelumnya
[11:02:04.186] GW |   Statistik Node 2: diterima=226 | perkiraan hilang=3
[11:02:04.189] GW |   Total diterima gateway: 458
[11:02:04.189] GW | =====================
[11:02:04.190] GW |", pecah: true)

  Meski kanal diperebutkan sepanjang sesi, *tidak satu pun `[WARN]`* muncul di gateway: setiap paket yang berhasil naik ke udara tiba utuh dan terbaca penuh.

  *EXP-04 — Telinga dimatikan (pembanding Pure ALOHA)*

  Kedua node dibangun dengan `-DCS_MODE=2`, interval tetap 300–500 ms. Tunda akses jatuh ke *0 ms* — dan konsekuensinya langsung terlihat di gateway. Cuplikan di bawah menangkap satu paket Node 2 yang bertabrakan di udara: awalannya masih utuh terbaca (`NODE=2,SEQ=1,T=28.`), sisanya hancur.

  #keluaran("[10:56:40.865] N2 | [TX] NODE=2,SEQ=1,T=28.4,H=72.1 | attempt=1 | tunda=0 ms
[10:56:40.866] GW | [WARN] Paket cacat (field tidak lengkap): NODE=2,SEQ=1,T=28.t,??,a?2
[10:56:40.869] N2 | [STAT] TX=2 | DROP=0 | kanal sibuk=0 | rata-rata tunda=0 ms
[10:56:40.869] N2 |
[10:56:40.913] N1 | [TX] NODE=1,SEQ=1,T=30.4,H=72.0 | attempt=1 | tunda=0 ms
[10:56:40.917] N1 | [STAT] TX=2 | DROP=0 | kanal sibuk=0 | rata-rata tunda=0 ms
[10:56:40.917] N1 |", pecah: true)

  Sepanjang sesi ini gateway mencatat *102 `[GAP]` dan 37 paket cacat* — bandingkan dengan 4 `[GAP]` dan 0 cacat pada EXP-03 yang mengirim jumlah paket serupa.

  Paket cacat semacam inilah yang memaksa gateway memeriksa kelengkapan field sebelum mempercayai isinya. Tanpa pemeriksaan itu, `SEQ` yang hilang dibaca sebagai `0` dan satu paket rusak saja sanggup merusak statistik seluruh sesi — pada percobaan pertama sebelum perbaikan, perkiraan kehilangan Node 2 melonjak ke *1177* padahal kenyataannya sekitar 30:

  #keluaran("[10:54:09.727] GW |   Selang  : 387 ms dari paket sebelumnya
[10:54:09.735] GW |   [GAP] SEQ meloncat 272 -- paket dibuang node atau bertabrakan
[10:54:09.739] GW |   Statistik Node 2: diterima=233 | perkiraan hilang=1177", pecah: true)

  *EXP-05 — Carrier sense berbasis CAD*

  Kedua node dibangun dengan `-DCS_MODE=1`. Node tidak lagi memakai ambang dBm apa pun; SX1276 sendiri yang memutuskan ada-tidaknya simbol LoRa di kanal.

  #keluaran("[11:09:12.395] N1 | [CS] kanal SIBUK (CAD mendeteksi sinyal LoRa)
[11:09:12.400] N1 | [BACKOFF] percobaan 1/5 | CW=4 | slot=1 -> 20 ms
[11:09:12.407] N1 | [FREEZE] pencacah backoff dibekukan -- kanal terpakai
[11:09:12.419] GW | === PAKET DITERIMA ===
[11:09:12.422] N2 | [TX] NODE=2,SEQ=19,T=31.4,H=65.2 | attempt=1 | tunda=31 ms
[11:09:12.423] GW |   Node    : 2
[11:09:12.423] GW |   SEQ     : 19
[11:09:12.423] GW |   Suhu    : 31.4 C
[11:09:12.426] N2 | [STAT] TX=20 | DROP=0 | kanal sibuk=5 | rata-rata tunda=46 ms
[11:09:12.426] N2 |
[11:09:12.427] GW |   Lembab  : 65.2 %
[11:09:12.427] GW |   RSSI    : -56 dBm
[11:09:12.431] GW |   SNR     : 9.75 dB
[11:09:12.435] GW |   Selang  : 412 ms dari paket sebelumnya
[11:09:12.439] GW |   Statistik Node 2: diterima=20 | perkiraan hilang=0
[11:09:12.439] GW |   Total diterima gateway: 39
[11:09:12.443] GW | =====================
[11:09:12.443] GW |
[11:09:12.537] GW | === PAKET DITERIMA ===
[11:09:12.538] GW |   Node    : 1
[11:09:12.538] GW |   SEQ     : 19
[11:09:12.538] N1 | [TX] NODE=1,SEQ=19,T=30.0,H=65.7 | attempt=2 | tunda=79 ms
[11:09:12.542] GW |   Suhu    : 30.0 C
[11:09:12.542] GW |   Lembab  : 65.7 %
[11:09:12.542] N1 | [STAT] TX=20 | DROP=0 | kanal sibuk=1 | rata-rata tunda=32 ms
[11:09:12.542] N1 |
[11:09:12.546] GW |   RSSI    : -44 dBm
[11:09:12.546] GW |   SNR     : 9.50 dB
[11:09:12.550] GW |   Selang  : 116 ms dari paket sebelumnya
[11:09:12.554] GW |   Statistik Node 1: diterima=20 | perkiraan hilang=0
[11:09:12.559] GW |   Total diterima gateway: 40
[11:09:12.559] GW | =====================
[11:09:12.559] GW |", pecah: true)

  Hasil akhirnya setara RSSI (694 vs 695 paket tiba, sama-sama 4 hilang), tetapi CAD *melaporkan kanal sibuk lebih sering*: 107 kali berbanding 99 kali pada beban yang sama persis. Ini konsisten dengan sifat CAD yang mengenali sinyal LoRa sampai di bawah lantai derau, sementara ambang RSSI −95 dBm melewatkan sinyal lemah.

  Satu catatan penting untuk yang mengutak-atik mode ini: pada percobaan pertama, CAD sama sekali tidak pernah mendeteksi apa pun (`[CS] kanal SIBUK` \= 0) *dan* merusak transmisi node itu sendiri — 103 dari 440 paket tiba dalam keadaan cacat. Dua sebabnya, keduanya sudah diperbaiki di kode sekarang:

  + *CAD harus dimasuki dari STANDBY.* Perintah CAD yang dikirim selagi modem masih di RX kontinu tidak pernah dijalankan; `CadDone` tidak pernah naik dan setiap pemeriksaan hanya berakhir di timeout 50 ms (terlihat dari tunda akses yang konstan 50 ms).
  + *`isTransmitting()` di library menganggap mode CAD sebagai "sedang TX".* Fungsi itu menguji `(RegOpMode & 0x03) == 0x03`, dan mode CAD bernilai `0x07` lolos uji tersebut. Bila modem kebetulan masih berada di CAD saat `beginPacket()` dipanggil, `beginPacket()` gagal diam-diam tanpa me-reset FIFO — dan yang naik ke udara adalah sampah. Karena itu `LoRa.idle()` dipanggil sebelum `beginPacket()`.

  Kedua jebakan itu tidak akan pernah terlihat dari dokumentasi library, sebab library ini memang tidak menyediakan CAD sama sekali.
]

== Pengukuran

*A. Beban kanal terhadap perilaku CSMA/CA.* Baris bertanda OK adalah hasil
verifikasi 23 Agustus 2026; baris kosong dijalankan sendiri.

#tbl(
  table(
    columns: (auto, 1.3fr, auto, auto, 1.1fr),
    align: (left, left, center + horizon, center + horizon, left),
    inset: (x: 0.45em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Interval (ms)], th[Diterima gateway (3 menit)], th[`[BACKOFF]`], th[`[DROP]`], th[Tunda rata-rata (ms)]),
    [2000--5000 (OK)], [98 dari 99 dikirim], [3], [0], [31,7 / 34,3],
    [1000--2000], [#isian], [], [], [],
    [300--500 (OK)], [695 dari 700 dikirim], [99], [0], [37,2 / 46,1],
  ),
  [Lembar pengukuran A --- beban kanal terhadap perilaku CSMA/CA],
  "tbl:m09-ukur-a",
)

*B. RSSI, SNR, dan tunda akses per node* --- hasil verifikasi pada beban tinggi
(interval 300--500 ms, sesi EXP-03).

#tbl(
  table(
    columns: (auto, 1fr, 1fr, 1.2fr, auto),
    align: (left, left, left, left, center + horizon),
    inset: (x: 0.5em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[RSSI rata-rata (dBm)], th[SNR rata-rata (dB)], th[Tunda akses rata-rata (ms)], th[`[GAP]`]),
    [Node 1], [#sym.minus 44,7], [9,77], [37,2 (maks 238)], [0],
    [Node 2], [#sym.minus 54,5], [9,73], [46,1 (maks 257)], [4],
  ),
  [Lembar pengukuran B --- RSSI, SNR, dan tunda akses per node],
  "tbl:m09-ukur-b",
)

Selisih #sym.plus.minus 10 dB antar node murni posisi fisik di meja. Menarik:
node yang sinyalnya lebih lemah di gateway (Node 2) justru yang lebih sering
menemukan kanal sibuk dan paling banyak mundur --- periksa apakah pola itu
terulang pada pengukuran sendiri.

*C. CSMA/CA dibanding kirim buta* (dari EXP-04)

#tbl(
  table(
    columns: (1.3fr, auto, auto, 1.2fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.5em),
    stroke: 0.5pt + luma(170),
    table.header(th[Metrik], th[Dengan CS], th[Tanpa CS], th[Selisih]),
    [Paket dikirim node], [700], [757], [+57 tanpa CS],
    [Paket tiba di gateway], [695], [581], [*#sym.minus 114 tanpa CS*],
    [Paket hilang (perkiraan dari `SEQ`)], [4 (0,6 %)], [175 (23,1 %)], [44× lebih banyak],
    [Paket cacat di gateway], [0], [37], [---],
    [Tunda akses rata-rata], [#sym.tilde.op 41 ms], [0 ms], [harga yang dibayar],
    [Paket dibuang sebelum berangkat], [0], [0], [---],
  ),
  [Lembar pengukuran C --- CSMA/CA dibanding kirim buta],
  "tbl:m09-ukur-c",
)

== Analisis

+ Hitung waktu udara satu paket modul ini pada SF7, BW 125 kHz, CR 4/5, lalu
  bandingkan dengan `DIFS_MS` dan `SLOT_MS`. Apakah satu slot cukup panjang
  untuk membedakan kanal yang benar-benar bebas dari sela antar-simbol? Bila
  `SLOT_MS` dibuat 5 ms, apa yang diperkirakan terjadi?
+ Dari @tbl:m09-ukur-c, hitung berapa milidetik tunda akses yang harus dibayar
  untuk setiap satu paket yang berhasil diselamatkan dari tabrakan. Di aplikasi
  seperti apa harga itu murah, dan di aplikasi seperti apa terlalu mahal?
+ Pada verifikasi dengan dua node, `[DROP]` tidak pernah muncul sekali pun ---
  lima percobaan selalu cukup. Perkirakan (dengan hitungan, bukan tebakan)
  berapa node atau berapa `MAX_ATTEMPT` yang diperlukan agar `[DROP]` mulai
  terjadi pada interval 300--500 ms, lalu uji perkiraan itu. Jelaskan juga
  mengapa node lebih baik membuang paket daripada terus mencoba tanpa batas.
+ Node menaikkan `SEQ` juga untuk paket yang dibuangnya sendiri. Jelaskan apa
  yang akan hilang dari kemampuan analisis gateway seandainya `SEQ` hanya naik
  saat paket benar-benar terkirim.
+ Gateway menolak paket yang field-nya tidak lengkap. Baca `logserial.md`
  bagian EXP-04: tanpa pemeriksaan itu, satu paket rusak membuat perkiraan
  kehilangan melonjak dari #sym.tilde.op 30 menjadi 1177. Telusuri persis
  bagaimana satu paket cacat bisa menghasilkan angka sebesar itu, lalu usulkan
  satu pemeriksaan tambahan yang membuat statistik gateway lebih tahan banting.
+ Gateway modul ini tidak pernah memancar sama sekali. Bila kelak ia mulai
  mengirim ACK (modul berikutnya), sebutkan *dua* hal yang berubah bagi
  mekanisme carrier sense di node.

#todo[
  Penomoran daftar Analisis pada berkas sumber
  (`Modul09_lora_csma_ca/README.md`) melompat: butir bernomor 6 ditulis sebelum
  butir bernomor 5. Urutan isinya dipertahankan apa adanya di sini dan
  penomorannya dibuat otomatis, sehingga butir "gateway menolak paket cacat"
  kini menjadi nomor 5 dan "gateway tidak pernah memancar" menjadi nomor 6.
  Mohon dikonfirmasi apakah urutan itu memang yang dikehendaki, atau kedua
  butir perlu ditukar posisinya.
]

== Concept Check

+ Apa beda mendasar CSMA/CA di modul ini dengan polling terjadwal pada M05 ---
  siapa yang memegang keputusan "kapan boleh bicara" pada masing-masing?
+ Mengapa radio tidak bisa memakai _collision detection_ seperti Ethernet,
  sehingga harus puas dengan _collision avoidance_?
+ Mengapa backoff harus acak? Apa yang terjadi bila semua node memakai lama
  tunggu tetap yang sama?
+ Mengapa jendela kontensi dilebarkan setiap kali kanal ditemukan sibuk,
  alih-alih dipertahankan tetap?
+ Jelaskan masalah _hidden node_: dua node patuh mendengarkan, tetapi paketnya
  tetap bertabrakan di gateway. Bagaimana ini bisa terjadi, dan apakah
  menaikkan `MAX_ATTEMPT` menolong?
+ CAD dan RSSI sama-sama menjawab "kanal sibuk atau tidak". Sebutkan satu
  keadaan di mana keduanya memberi jawaban berbeda, dan mana yang lebih tepat
  pada keadaan itu.

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Telinga yang mengkalibrasi dirinya sendiri])[
  / CH-1 --- Ambang adaptif: Buat node mengukur lantai derau sendiri saat
    `setup()` (rata-rata puluhan sampel RSSI pada kanal kosong), lalu
    menetapkan `RSSI_THRESHOLD` sebagai lantai derau ditambah margin tetap.
    Bandingkan hasilnya dengan ambang manual dari EXP-01.

  / CH-2 --- Node ketiga: Tambahkan environment `node3` dan jalankan EXP-03
    dengan tiga node. Ukur bagaimana tunda akses rata-rata dan `[DROP]` berubah
    ketika jumlah peserta naik dari dua menjadi tiga pada beban yang sama.
]

#tujuan-prak(3, [Prioritas dan pemetaan kesibukan kanal])[
  / CH-3 --- Prioritas lewat DIFS: Beri Node 1 rentang tunggu yang lebih pendek
    daripada Node 2 (misalnya DIFS 20 ms vs 40 ms), lalu buktikan dari data
    gateway bahwa Node 1 memperoleh porsi kanal yang lebih besar. Ini adalah
    versi sederhana dari mekanisme prioritas 802.11e.

  / CH-4 --- Laporkan kesibukan: Sisipkan jumlah backoff dan tunda akses paket
    ini ke dalam payload (`,BO=<n>,DLY=<ms>`), lalu buat gateway mencetak peta
    kesibukan kanal dari sudut pandang masing-masing node. Perhatikan bahwa
    parser gateway tidak perlu diubah untuk field yang tidak dikenalnya ---
    buktikan klaim itu sebelum menambahkan pembacaannya.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- CS/MA/CA, DIFS, contention window, exponential
  backoff, freeze, hidden node.
+ Konfigurasi --- format payload, parameter CSMA/CA yang dipakai, ambang RSSI
  hasil kalibrasi EXP-01, parameter radio.
+ Hasil eksperimen --- log serial ketiga board (EXP-01 sampai EXP-05 beserta
  checkpoint).
+ Data pengukuran --- @tbl:m09-ukur-a, @tbl:m09-ukur-b, dan @tbl:m09-ukur-c.
+ Analisis dan concept check.
+ Challenge --- minimal CH-1.
+ Kesimpulan yang disusun sendiri, khususnya mengenai harga yang dibayar (tunda
  akses dan paket yang dibuang) untuk keandalan yang diperoleh, dan mengapa
  jaringan nyata tetap memilih membayarnya.
