// ============================================================================
// Modul 02 — Penerimaan Non-Blocking dan Indikator LED
// Sumber: Modul02_lora_led_notif/README.md; listing kode dibaca langsung dari
//         salinan berkas sumber di assets/code/Modul02_lora_led_notif/.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan, checkpoint, buka-abstraksi, pengantar, tujuan-prak, identitas-modul
#import "../lib/helpers.typ": gbr, tbl, th, isian, kode, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, checklist

#chapter("Modul 02 — Penerimaan Non-Blocking dan Indikator LED", l: "bab:modul-02")

#identitas-modul(
  "Modul 02",
  [Stop Waiting for Packets --- Penerimaan Non-Blocking dan Indikator LED],
  [Arduino Uno + Dragino LoRa Shield v1.2 · LoRa mentah · satu arah ·
   RX interrupt + flag · level Basic · 2 × 50 menit ·
   folder kode `Modul02_lora_led_notif`],
)

#pengantar([Gambaran Umum])[
Modul 02 dirancang untuk dua pertemuan (2 × 50 menit) pada tingkat dasar.
Misinya membebaskan `loop()` penerima dari tugas menunggu: paket dikabarkan
oleh interrupt, bukan dicari terus-menerus. Sebagai bukti visual bahwa radio
benar-benar bekerja, kedua board menyalakan LED saat mengirim dan menerima.
Percobaan memakai dua Arduino Uno bershield Dragino LoRa v1.2, diamati melalui
dua Serial Monitor pada 9600 baud.
]

== Pendahuluan

M01 memakai polling: penerima memanggil `parsePacket()` berulang kali,
sehingga seluruh waktu prosesor habis untuk bertanya "sudah ada paket belum".
Selama `loop()` sibuk mengerjakan hal lain, paket yang tiba akan terlewat.
Modul ini memindahkan pemberitahuan ke jalur perangkat keras: pin DIO0 SX1276
menarik interrupt INT0 Arduino begitu paket selesai diterima, dan `loop()`
cukup memeriksa sebuah penanda. Pola inilah yang membuat penerima tetap
responsif sambil mengerjakan tugas lain --- dan menjadi dasar M04, tempat
penerima harus menunggu ACK sambil menghitung waktu.

Prasyaratnya adalah M01: inisialisasi SX1276, parameter radio, serta pembacaan
RSSI dan SNR. Yang dibangun di sini adalah pemasangan callback
`LoRa.onReceive()`, pemakaian variabel `volatile` sebagai jembatan antara ISR
dan `loop()`, pemahaman mengapa pekerjaan berat tidak boleh dilakukan di dalam
ISR, serta indikator LED yang tidak mengganggu jalur SPI. Semuanya dipakai lagi
pada M04 ketika ACK ditunggu dengan batas waktu, dan M05 ketika master
menjadwalkan giliran bicara.

*Peta modul LoRa*

#tbl(
  table(
    columns: (auto, 1fr),
    align: (center + horizon, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Fokus (yang ditumpuk di atas modul sebelumnya)]),
    [01], [Tautan satu arah terbentuk; RSSI dan SNR terbaca],
    [*02 (ini)*], [*Penerimaan lewat interrupt --- `loop()` tidak lagi menunggu*],
    [03], [Dua arah --- kedua board bergantian mengirim dan menerima],
    [04], [Keandalan diukur: ACK, timeout, dan hitungan gagal],
    [05], [Banyak node --- satu master menjadwalkan giliran bicara],
  ),
  [Peta modul pada arc pertama seri LoRa],
  "tbl:m02-peta",
)

*Kontrak data lab ini.* Payload tetap bernomor (`Hello #n`), sama seperti M01,
sehingga hasil pengukuran kedua modul dapat dibandingkan langsung. Yang berubah
bukan datanya, melainkan *cara penerima mengetahui data itu tiba*.

== Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

#tujuan-prak(1, [Memindahkan penerimaan dari polling ke interrupt])[
  + Menjelaskan perbedaan polling dan interrupt pada penerimaan paket LoRa,
    beserta jalur perangkat kerasnya (DIO0 #sym.arrow D2/INT0).
  + Memasang `LoRa.onReceive()` dan `LoRa.receive()` dengan benar, serta
    menjelaskan mengapa `LoRa.receive()` harus dipanggil ulang setelah sebuah
    paket diolah.
  + Menjelaskan fungsi kata kunci `volatile` dan akibatnya bila dihilangkan.
  + Menyebutkan pekerjaan yang tidak boleh dilakukan di dalam ISR beserta
    alasannya.
  + Menjelaskan mengapa LED indikator sebaiknya tidak memakai D13 pada board
    bershield LoRa.
]

*Kriteria keberhasilan*

#checklist((
  [Penerima mencetak paket tanpa memanggil `parsePacket()` sama sekali di
   `loop()`.],
  [LED berkedip pada pengirim setiap kali TX selesai, dan pada penerima setiap
   kali paket tiba.],
  [Penerima tetap menerima paket meskipun `loop()` diberi pekerjaan tambahan
   (EXP-03).],
  [Perbedaan perilaku polling dan interrupt dibuktikan dengan data, bukan
   sekadar dijelaskan.],
))

== Dasar Teori (Secukupnya)

#tbl(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Istilah], th[Definisi kerja di lab ini]),
    [Interrupt], [Sinyal perangkat keras yang menghentikan sementara program utama untuk menjalankan fungsi khusus.],
    [ISR], [_Interrupt Service Routine_ --- fungsi yang dijalankan saat interrupt terjadi. Harus sangat singkat.],
    [DIO0], [Pin keluaran SX1276 yang berubah keadaan saat paket selesai diterima atau dikirim. Tersambung ke D2 (INT0) Arduino.],
    [`volatile`], [Penanda bagi compiler bahwa sebuah variabel dapat berubah di luar alur program utama, sehingga nilainya tidak boleh disimpan di register.],
    [Mode receive kontinu], [Keadaan SX1276 setelah `LoRa.receive()`: radio terus mendengarkan tanpa campur tangan prosesor.],
    [Flag pattern], [Pola baku: ISR hanya menyalakan penanda, seluruh pekerjaan berat dikerjakan `loop()`.],
  ),
  [Istilah kerja Modul 02],
  "tbl:m02-istilah",
)

*Mengapa ISR harus singkat.* Selama ISR berjalan, interrupt lain tertunda dan
`millis()` berhenti bertambah pada AVR. Mencetak ke Serial di dalam ISR ---
operasi yang memakan milidetik --- dapat membuat pewaktuan kacau, paket
berikutnya terlewat, bahkan program membeku. Karena itu `onReceive()` pada
modul ini hanya mengerjakan satu hal: `rxFlag = true`. Pembacaan isi paket,
pencetakan, dan penyalaan LED semuanya dikerjakan `loop()` setelah interrupt
selesai.

*Mengapa bukan D13 untuk LED.* D13 berbagi jalur dengan SCK, denyut clock SPI
menuju SX1276. Setiap kali radio berkomunikasi, LED bawaan ikut berkedip dengan
sendirinya, sehingga tidak dapat dipercaya sebagai indikator kejadian. Program
ini memakai `LED_BUILTIN` agar dapat langsung dijalankan tanpa komponen
tambahan, tetapi untuk indikator yang bersih ganti `LED_PIN` menjadi *D3* dan
pasang LED dengan resistor 220 #sym.Omega ke GND --- hal ini menjadi bagian
dari EXP-02.

*Sekuens yang diamati*

#diagram(```
   Sender                      (udara)                    Receiver
     |                                              LoRa.receive() aktif
  endPacket() ------------------------------------->  paket tiba
  LED nyala 150 ms                                    DIO0 memicu INT0
     |                                                ISR: rxFlag = true
     |                                                     |
  delay(1850)                                         loop(): rxFlag terbaca
     |                                                baca isi, cetak, LED 200 ms
     |                                                LoRa.receive() dipanggil lagi
```.text, rapat: true)

== Topologi

#diagram(```
        BOARD #1                                  BOARD #2
  +------------------+                      +------------------+
  |   Arduino Uno    |                      |   Arduino Uno    |
  | + LoRa Shield    |  ~~~~ 433 MHz ~~~~>  | + LoRa Shield    |
  |     SENDER       |     satu arah        |    RECEIVER      |
  | LED 150 ms       |                      | LED 200 ms       |
  | setelah TX       |                      | interrupt DIO0   |
  +------------------+                      +------------------+
     env: sender                              env: receiver
```.text)

#tbl(
  table(
    columns: (auto, auto, 1.2fr, auto, auto),
    align: (left, left, left, left, left),
    inset: (x: 0.55em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Node], th[Environment], th[Peran], th[Mekanisme RX], th[LED]),
    [Sender], [`sender`], [Pengirim, `Hello #n` tiap 2 detik], [---], [Kedip 150 ms setelah TX],
    [Receiver], [`receiver`], [Penerima], [Interrupt DIO0 + `rxFlag`], [Kedip 200 ms saat RX],
  ),
  [Peran tiap node Modul 02],
  "tbl:m02-topologi",
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
    [4], [LED + resistor 220 #sym.Omega], [opsional, untuk indikator bersih di D3], [2],
    [5], [Kabel USB tipe B], [kabel data], [2],
  ),
  [Alat dan bahan Modul 02],
  "tbl:m02-alat",
)

*Pin yang dipakai*

#tbl(
  table(
    columns: (auto, auto, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Pin], th[Fungsi], th[Keterangan]),
    [D10, D11, D12, D13], [SPI ke SX1276], [NSS, MOSI, MISO, SCK],
    [D9], [RST], [Reset SX1276],
    [*D2*], [*DIO0*], [Interrupt RX-done --- inti modul ini],
    [D13], [LED bawaan], [Dipakai program sebagai indikator awal, berbagi jalur dengan SCK],
    [*D3*], [LED eksternal], [Pin bebas yang direkomendasikan untuk indikator bersih],
  ),
  [Pemetaan pin Modul 02],
  "tbl:m02-pin",
)

*Struktur proyek*

#diagram(```
Modul02_lora_led_notif/
├── platformio.ini
├── monitor_serial.py       ← pantau TX & RX sekaligus, ringkas loss/RSSI/SNR
├── upload_auto.py          ← deteksi port otomatis saat unggah
├── logserial.md            ← log referensi hasil uji perangkat
└── src/
    ├── sender/main.cpp     ← kirim + kedip LED setelah TX
    └── receiver/main.cpp   ← interrupt DIO0, rxFlag, kedip LED saat RX
```.text)

== Kode Program

#sumber-kode("Modul02_lora_led_notif",
  ("platformio.ini", "src/sender/main.cpp", "src/receiver/main.cpp",
   "monitor_serial.py", "upload_auto.py"))

#kode-berkas("Modul02_lora_led_notif/platformio.ini",
  [`platformio.ini` Modul 02 --- environment `sender` dan `receiver`],
  "lst:m02-ini",
  pecah: true,
)

#kode-berkas("Modul02_lora_led_notif/src/sender/main.cpp",
  [`src/sender/main.cpp` --- kirim `Hello #n` disertai kedip LED setelah TX],
  "lst:m02-sender",
  pecah: true,
)

#kode-berkas("Modul02_lora_led_notif/src/receiver/main.cpp",
  [`src/receiver/main.cpp` --- interrupt DIO0, `rxFlag`, kedip LED saat RX],
  "lst:m02-receiver",
  pecah: true,
)

#kode-berkas("Modul02_lora_led_notif/monitor_serial.py",
  [`monitor_serial.py` --- pantau TX dan RX pada satu sumbu waktu],
  "lst:m02-monitor",
  pecah: true,
)

#kode-berkas("Modul02_lora_led_notif/upload_auto.py",
  [`upload_auto.py` --- pemilih port otomatis saat unggah],
  "lst:m02-upload",
  pecah: true,
)

== Build dan Flash

Penerima diunggah lebih dahulu.

#keluaran("pio run -d Modul02_lora_led_notif -e receiver -t upload -t monitor
pio run -d Modul02_lora_led_notif -e sender   -t upload -t monitor")

*Memantau kedua board sekaligus.* Percobaan inti modul ini (EXP-03) menuntut
pembandingan jumlah paket hilang antara dua firmware penerima. Menghitungnya
dari dua jendela terpisah rawan salah, karena tiap jendela punya sumbu waktu
sendiri. Skrip `monitor_serial.py` menggabungkan keduanya dan langsung
meringkas hasil ukurnya.

#keluaran("python3 Modul02_lora_led_notif/monitor_serial.py
python3 Modul02_lora_led_notif/monitor_serial.py --durasi 40 --log sesi1.txt")

#keluaran("  Paket dikirim  : 9  (nomor 0..8)
  Paket diterima : 9  (nomor 0..8)
  Paket hilang   : 0 (0.0 %)
  RSSI  min/maks/rata-rata : -38 / -38 / -38.0 dBm
  SNR   min/maks/rata-rata : 9.00 / 9.50 / 9.28 dB")

#penting[
  *Membuka monitor me-reset kedua board.* Pada Arduino Uno, DTR terhubung ke
  pin RESET, sehingga penghitung paket kembali ke nol setiap monitor
  dijalankan. Jalankan monitor lebih dahulu, baru mulai mengukur.
]

*Pre-flight checklist*

#checklist((
  [Antena terpasang pada kedua shield.],
  [Port kedua board dicatat lewat `pio device list` dan diisikan ke
   `platformio.ini`.],
  [Dua Serial Monitor 9600 baud siap.],
  [Bila memakai LED eksternal: kaki panjang ke D3 lewat resistor
   220 #sym.Omega, kaki pendek ke GND.],
))

== Percobaan

=== EXP-01 --- Penerimaan Tanpa Polling

Unggah kedua firmware dan amati aliran data seperti pada M01.

*Expected output --- receiver*

#keluaran("=== LoRa RECEIVER (Dragino) ===
Init LoRa ... OK
Freq: 433.00 MHz | BW: 125.00 kHz | SF7
Menunggu paket (non-blocking)...

================================
[RX] Pesan : Hello #5
[RX] RSSI  : -41 dBm
[RX] SNR   : 9.50 dB
================================")

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil]),
    [Apakah `parsePacket()` ada di `loop()` penerima?], [#isian],
    [Nomor urut terakhir sender / receiver], [#isian],
    [RSSI rata-rata (dBm)], [#isian],
    [Lama kedip LED penerima (ms)], [#isian],
  ),
  [Lembar pengamatan EXP-01],
  "tbl:m02-exp01",
)

#buka-abstraksi[
  Di `src/receiver/main.cpp`, cari fungsi `onReceive()`. Isinya hanya satu
  baris pemberian nilai. Jawab: mengapa pembacaan `LoRa.available()` dan
  pencetakan Serial tidak diletakkan di sana padahal itu terasa lebih ringkas?
  Lalu telusuri di mana `LoRa.receive()` dipanggil untuk kedua kalinya, dan
  jelaskan apa yang terjadi bila baris itu dihapus.
]

#checkpoint[
  Penerima mencetak paket *tanpa* satu pun panggilan `parsePacket()` di
  `loop()`. Bila baris itu masih ada, yang diuji bukan mekanisme interrupt.
]

=== EXP-02 --- LED Sebagai Instrumen

Amati LED bawaan (D13) pada kedua board, lalu ganti `LED_PIN` menjadi `3`,
pasang LED eksternal, dan bandingkan.

*Data capture*

#tbl(
  table(
    columns: (1.4fr, 1fr, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[LED bawaan (D13)], th[LED eksternal (D3)]),
    [Berkedip saat paket tiba?], [#isian], [],
    [Berkedip juga saat radio diam?], [#isian], [],
    [Dapat dipercaya sebagai indikator kejadian?], [#isian], [],
  ),
  [Lembar pengamatan EXP-02 --- LED sebagai instrumen],
  "tbl:m02-exp02",
)

#checkpoint[
  LED di D13 berkedip tidak beraturan mengikuti lalu lintas SPI, sedangkan LED
  di D3 hanya berkedip saat kejadian yang dimaksud. Pengamatan inilah alasan
  pin indikator dipisahkan dari jalur komunikasi.
]

=== EXP-03 --- Bukti Non-Blocking

Tambahkan pekerjaan tiruan pada `loop()` penerima, tepat sebelum pemeriksaan
`rxFlag`, seperti pada @lst:m02-exp03.

#kode(```cpp
  // pekerjaan tiruan: seolah-olah penerima sedang mengolah sensor
  delay(1500);
```.text,
  [Pekerjaan tiruan yang disisipkan pada `loop()` penerima],
  "lst:m02-exp03",
)

Unggah ulang, amati 2 menit, lalu ulangi percobaan yang sama pada penerima
*M01* yang berbasis polling.

*Data capture*

#tbl(
  table(
    columns: (1.5fr, 1fr, 1fr, 1fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Firmware], th[Paket dikirim], th[Paket diterima], th[Loss (%)]),
    [M02 (interrupt) + `delay(1500)`], [#isian], [], [],
    [M01 (polling) + `delay(1500)`], [#isian], [], [],
  ),
  [Lembar pengamatan EXP-03 --- bukti non-blocking],
  "tbl:m02-exp03-tbl",
)

Gunakan *pengirim yang sama* untuk kedua pengukuran, dan ganti firmware
penerimanya saja --- dengan begitu satu-satunya variabel adalah mekanisme
penerimaan.

#checkpoint[
  Penerima M02 tetap menangkap *seluruh* paket pada `delay(1500)`, sedangkan
  penerima M01 kehilangan hampir semuanya. Selisih inilah nilai sesungguhnya
  dari mekanisme interrupt. Hapus `delay()` setelah percobaan selesai.
]

*Angka rujukan* (hasil ukur nyata, 40 detik per baris, pengirim tiap 2 detik
--- lihat `logserial.md`).

#tbl(
  table(
    columns: (auto, auto, auto),
    align: (left, center + horizon, center + horizon),
    inset: (x: 0.7em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[`delay()` di `loop()`], th[M02 interrupt], th[M01 polling]),
    [0 ms], [0 %], [0 %],
    [500 ms], [*0 %*], [68,4 %],
    [1500 ms], [*0 %*], [94,7 %],
    [3000 ms], [42,1 %], [100 %],
  ),
  [Angka rujukan EXP-03 --- loss interrupt dibanding polling],
  "tbl:m02-rujukan",
)

Perhatikan bahwa interrupt pun akhirnya runtuh, dan batasnya dapat dihitung:
penahanan 3000 ms melampaui interval kirim 2000 ms, sehingga paket baru tiba
sebelum paket sebelumnya diambil dan `LoRa.receive()` dipanggil ulang --- SX1276
hanya menyimpan satu paket pada satu waktu. Interrupt memindahkan pemberitahuan
ke perangkat keras, tetapi tidak membuat penerima kebal.

=== Verifikasi Perangkat Keras (Log Referensi)

Dijalankan pada dua Arduino Uno bershield Dragino LoRa v1.2, 433 MHz, jarak
#sym.plus.minus 30 cm. Log lengkap ada di `logserial.md`.

#keluaran("[   1.813] RX | Init LoRa ... OK
[   1.813] RX | Freq: 433.00 MHz | BW: 125.00 kHz | SF7
[   2.013] RX | [RX] Pesan : Hello #0
[   2.013] RX | [RX] RSSI  : -38 dBm
[   2.022] TX | [TX] Kirim: \"Hello #0\" ... OK")

#tbl(
  table(
    columns: (1.2fr, 1fr),
    align: (left, left),
    inset: (x: 0.6em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Parameter], th[Hasil terukur]),
    [Paket dikirim / diterima (20 s)], [9 / 9 (loss 0 %)],
    [RSSI rata-rata], [#sym.minus 38,0 dBm],
    [SNR rata-rata], [9,28 dB],
    [EXP-03 pada `delay(1500)`], [interrupt 0 % vs polling 94,7 % hilang],
    [EXP-02 (pengamatan LED)], [belum diverifikasi --- bersifat visual, tidak terekam serial],
  ),
  [Hasil verifikasi perangkat keras Modul 02],
  "tbl:m02-verifikasi",
)

#keluaran("Environment    Status    Flash
sender         SUCCESS   22.9% (7380 B)
receiver       SUCCESS   24.5% (7916 B)")

Penerima berbasis interrupt hanya menambah #sym.plus.minus 600 byte dibanding
penerima polling M01 (7312 B) --- biaya yang sangat kecil dibanding manfaatnya.

== Pengukuran

*A. Ketahanan terhadap kesibukan `loop()`* --- ulangi EXP-03 dengan beberapa
lama pekerjaan tiruan.

#tbl(
  table(
    columns: (auto, 1fr, 1fr),
    align: (left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[`delay()` pada loop], th[Loss M01 polling (%)], th[Loss M02 interrupt (%)]),
    [0 ms], [#isian], [],
    [500 ms], [#isian], [],
    [1500 ms], [#isian], [],
    [3000 ms], [#isian], [],
  ),
  [Lembar pengukuran A --- ketahanan terhadap kesibukan `loop()`],
  "tbl:m02-ukur-a",
)

*B. Jarak terhadap kualitas tautan* --- untuk dibandingkan langsung dengan
lembar pengukuran A pada M01.

#tbl(
  table(
    columns: (auto, 1fr, 1fr, 1fr),
    align: (left, left, left, left),
    inset: (x: 0.6em, y: 0.55em),
    stroke: 0.5pt + luma(170),
    table.header(th[Jarak], th[RSSI (dBm)], th[SNR (dB)], th[Loss (%)]),
    [1 m], [#isian], [], [],
    [10 m], [#isian], [], [],
    [50 m], [#isian], [], [],
  ),
  [Lembar pengukuran B --- jarak terhadap kualitas tautan],
  "tbl:m02-ukur-b",
)

== Analisis

+ Dari @tbl:m02-ukur-a, pada lama `delay()` berapa perbedaan polling dan
  interrupt mulai menonjol? Jelaskan mengapa interrupt pun akhirnya ikut
  kehilangan paket.
+ Mengapa ISR hanya boleh mengubah penanda? Sebutkan dua akibat konkret bila
  `Serial.println()` dipanggil di dalamnya.
+ Apa yang terjadi bila kata kunci `volatile` dihapus dari `rxFlag`? Jelaskan
  dari sisi optimasi compiler.
+ Bandingkan hasil @tbl:m02-ukur-b dengan lembar pengukuran A pada M01. Apakah
  mekanisme penerimaan memengaruhi jangkauan? Jelaskan alasannya.
+ LED penerima menyala 200 ms dengan `delay()`. Sebutkan kelemahan cara itu,
  dan pada kondisi apa kelemahannya menjadi nyata.

== Concept Check

+ Apa perbedaan polling dan interrupt dalam menerima paket?
+ Jalur perangkat keras apa yang menghubungkan SX1276 ke interrupt Arduino, dan
  lewat pin mana?
+ Mengapa `LoRa.receive()` harus dipanggil lagi setelah sebuah paket selesai
  diolah?
+ Mengapa `rxFlag` harus `volatile`?
+ Mengapa D13 kurang tepat dijadikan indikator kejadian pada board bershield
  LoRa?

== Challenge (Tugas Modifikasi)

Modifikasi kode, bukan sekadar menjelaskan hasil.

#tujuan-prak(2, [Indikator yang tidak menghalangi])[
  / CH-1 --- LED tanpa `delay()`: Ganti kedip LED penerima dengan penjadwalan
    berbasis `millis()`, lalu buktikan dengan EXP-03 bahwa penerima menjadi
    lebih tahan terhadap paket yang datang beruntun.

  / CH-2 --- Dua LED: Pakai D3 untuk paket diterima dan D4 untuk paket ditolak
    (misalnya payload yang tidak diawali `Hello`). Jelaskan mengapa penyaringan
    seperti ini akan diperlukan pada M05.
]

#tujuan-prak(3, [Kualitas tautan yang terlihat tanpa Serial Monitor])[
  / CH-3 --- Intensitas mengikuti sinyal: Kedipkan LED dengan PWM yang
    terangnya mengikuti RSSI, sehingga kualitas tautan terlihat tanpa membaca
    Serial Monitor.

  / CH-4 --- Hitung paket terlewat: Uraikan nomor urut dari payload, dan
    tampilkan jumlah paket yang hilang secara berjalan pada penerima.
]

== Laporan

*Deliverable*

+ Misi dan capaian pembelajaran.
+ Dasar teori ringkas --- interrupt, ISR, `volatile`, mode receive kontinu.
+ Konfigurasi --- pin DIO0, pilihan pin LED, parameter radio.
+ Hasil eksperimen --- log serial kedua board (EXP-01 sampai EXP-03 beserta
  checkpoint), foto atau video LED.
+ Data pengukuran --- @tbl:m02-ukur-a dan @tbl:m02-ukur-b.
+ Analisis dan concept check.
+ Challenge --- minimal CH-1.
+ Kesimpulan yang disusun sendiri, khususnya mengenai kapan interrupt sepadan
  dengan tambahan kerumitannya.
