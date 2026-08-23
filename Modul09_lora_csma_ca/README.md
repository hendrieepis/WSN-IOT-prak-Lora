```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
     MODUL 09 — CSMA/CA: Dengar Dulu, Baru Bicara

   Arduino Uno + Dragino LoRa Shield v1.2 · Advanced
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 09 dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat lanjut, dan merupakan langkah keempat dalam menghadapi tabrakan. Tiga modul sebelumnya menanganinya **setelah** terjadi: M08 membiarkannya senyap, M08B membuatnya terlihat lewat ACK, M08C memulihkannya lewat retry. Modul ini yang pertama berusaha **menghindarinya sebelum terjadi** — node mendengarkan kanal lebih dahulu, dan hanya bicara kalau sedang sepi.

Gagasannya juga membongkar asumsi yang dipegang sejak M05: bahwa supaya banyak node bisa berbagi satu kanal, harus ada **satu pihak yang mengatur giliran**. M05 memakai master yang memanggil node satu per satu, M07 memindahkan master itu ke Raspberry Pi — keduanya bergantung pada koordinator pusat. Di sini koordinator itu tidak ada, dan penggantinya adalah **kesopanan yang dijalankan sendiri oleh tiap node**: dengarkan dulu, kalau ada yang sedang bicara, tunggu sebentar dengan lama tunggu acak, lalu coba lagi.

Topologinya tetap *many-to-one* seperti M05 — dua node sensor, satu gateway — dan justru kemiripan itulah yang membuat perbandingannya tajam. Yang hilang cuma satu: gateway tidak pernah lagi berkata "Node 1, sekarang giliranmu." Ia hanya duduk mendengarkan. Pertanyaan modul ini: **bisakah dua node yang tidak pernah saling berjanji tetap menghindari tabrakan, hanya bermodalkan telinga masing-masing?**

Prasyaratnya M02 untuk pola interrupt DIO0 + flag di sisi gateway, M04 untuk pembacaan RSSI per paket, M05 untuk gagasan pengalamatan node di lapisan aplikasi, dan M08 sebagai pembanding langsung — kanal yang sama tanpa carrier sense sama sekali. Yang dibangun di sini adalah *carrier sensing* pada SX1276 (dua cara: ambang RSSI dan CAD), *random exponential backoff* dengan pencacah yang dibekukan selagi kanal terpakai, serta pengukuran **tunda akses kanal** — besaran baru yang belum pernah muncul di modul mana pun sebelumnya.

**Dua hal sengaja dikembalikan ke keadaan paling polos di modul ini, dan itu keputusan metodologis.** Pertama, **tidak ada ACK** — padahal M08B dan M08C sudah memilikinya. Kedua, **payload-nya lebih sederhana**: `NODE=<id>,SEQ=<n>,T=..,H=..`, satu sensor per node, bukan format dua ruangan `R1T/R1H/R2T/R2H` yang dipakai arc M08. Alasannya sama untuk keduanya: modul ini mengukur **satu variabel saja**, yaitu efek mendengarkan kanal sebelum bicara. Kalau ACK dan retry ikut menyala, kegagalan yang tersisa akan tertutup oleh pemulihan, dan angka yang terbaca bukan lagi angka carrier sense. Karena itu pembandingnya bukan M08C, melainkan **M08** — dan modul ini bahkan menyediakan pembanding itu di dalam dirinya sendiri lewat `CS_MODE=2` ("telinga dimatikan"), sehingga kedua kondisi dapat diukur pada perangkat, ruangan, dan sesi yang sama.

**Peta modul LoRa**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 05 | Tabrakan dicegah lewat polling terpusat — master memanggil satu per satu |
| 08 | Penjadwalan dilepas — node kirim bebas, tabrakan senyap diamati |
| 08B | ACK ditempelkan di atas M08 — node tahu SUCCESS/FAILED, belum ada retry |
| 08C | Random backoff + retry — kegagalan dipulihkan, dan Pure ALOHA menjadi lengkap |
| **09 (ini)** | **Carrier sense — dengar dulu sebelum bicara, tabrakan dihindari sebelum terjadi** |
| 10 | SYNC + slot waktu — Slotted ALOHA (slot diundi) vs TDMA (slot tetap) |


**Kontrak data lab ini.** Tiap node membawa **satu** sensor suhu & kelembaban dan mengirimkannya sebagai `NODE=<id>,SEQ=<n>,T=<suhu>,H=<lembab>`. Bentuk `KEY=VALUE` dipisah koma dipilih alih-alih CSV posisional (`NODE1,TEMP,28.5,HUM,70.2`) karena satu alasan praktis: penerima tidak perlu tahu urutan field, cukup mencari kuncinya dengan `indexOf`/`substring` — dan bila kelak ada field tambahan (RSSI, tegangan baterai), parser lama tetap jalan tanpa diubah. Identitas sumber ada di field `NODE`, sehingga gateway langsung tahu data ini milik siapa tanpa perlu bertanya. Nomor urut `SEQ` naik untuk **setiap data yang dihasilkan**, termasuk data yang akhirnya dibuang node karena kanal tak kunjung bebas — dengan begitu lubang pada `SEQ` di sisi gateway ikut merekam paket yang bahkan tidak pernah naik ke udara.

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Menjelaskan tiga bagian CSMA/CA (*carrier sense*, *multiple access*, *collision avoidance*) dan menunjukkan baris kode yang mewujudkan masing-masing.
2. Melakukan *carrier sensing* pada SX1276 dengan dua cara — ambang RSSI dan CAD (*Channel Activity Detection*) — serta menjelaskan kapan keduanya memberi jawaban berbeda.
3. Menentukan ambang RSSI kanal-sibuk secara empiris dari pengukuran lantai derau dan kekuatan sinyal node tetangga, bukan menebak angkanya.
4. Menjelaskan mengapa *backoff* harus **acak** dan mengapa jendela kontensi (CW) harus **melebar** setiap kali kanal ditemukan sibuk.
5. Mengukur harga yang dibayar CSMA/CA — tunda akses kanal dan paket yang dibuang — lalu membandingkannya dengan kirim-buta tanpa carrier sense.

**Kriteria keberhasilan**

- ☐ Kedua node mengirim data suhu/kelembaban secara mandiri, tanpa perintah apa pun dari gateway.
- ☐ Gateway mencetak setiap paket lengkap dengan identitas node, RSSI, SNR, dan selang dari paket sebelumnya.
- ☐ Serial monitor node menampilkan `[CS] kanal SIBUK` dan `[BACKOFF]` ketika node lain sedang mengirim — bukti telinganya benar-benar bekerja.
- ☐ Ketika interval kirim dipersempit, jumlah `[BACKOFF]`, `[FREEZE]`, dan tunda akses naik, tetapi paket yang tiba di gateway tetap utuh terbaca.

## 3 · Dasar Teori (secukupnya)

| Istilah | Definisi kerja di lab ini |
|---|---|
| Carrier Sense (CS) | Memeriksa kanal sebelum mengirim: adakah orang lain sedang memakai udara di frekuensi ini? |
| Multiple Access (MA) | Banyak node berbagi satu frekuensi yang sama, tanpa pembagian waktu atau kanal dari pusat. |
| Collision Avoidance (CA) | Bila kanal sibuk: **jangan** langsung kirim begitu sepi, tetapi mundur selama waktu acak lebih dulu. |
| DIFS | Rentang waktu kanal harus terbukti bebas **terus-menerus** sebelum node berhak mengirim. Satu sampel bebas tidak cukup. |
| Slot & Contention Window (CW) | Backoff dihitung dalam satuan slot. Node mengundi angka 0…CW−1; makin sering kanal ditemukan sibuk, makin lebar CW. |
| Freeze | Pencacah backoff **berhenti berkurang** selama ada yang mengirim, lalu lanjut lagi saat sepi — supaya yang sudah lama antre tidak kehilangan gilirannya. |
| RSSI sensing | Kanal dianggap terpakai bila kekuatan sinyal terbaca melewati ambang. Murah, tetapi ikut menghitung derau dan sinyal non-LoRa. |
| CAD | SX1276 mengkorelasikan simbol LoRa; ia mengenali sinyal LoRa bahkan yang tenggelam di bawah lantai derau, dan mengabaikan gangguan yang bukan LoRa. |
| Hidden node | Dua node yang saling tidak terdengar tetap dapat menabrak di gateway, walau keduanya patuh mendengarkan. |
| Tunda akses kanal | Selisih waktu antara "data siap" dan "paket benar-benar naik ke udara" — harga yang dibayar demi kesopanan. |

**Mengapa CA, bukan CD.** Ethernet klasik memakai CSMA/**CD** — *collision detection* — karena kabel memungkinkan pengirim mendengarkan jalurnya sendiri sambil mengirim, dan langsung berhenti ketika dua sinyal beradu. Radio tidak bisa begitu: pemancar SX1276 membutakan penerimanya sendiri, sehingga selama TX berlangsung node **buta total** terhadap keadaan kanal. Karena tabrakan tidak mungkin dideteksi di tengah jalan, satu-satunya strategi yang tersisa adalah **menghindarinya sebelum berangkat**. Itulah sebabnya semua protokol radio berbagi kanal — Wi-Fi, Zigbee, LoRaWAN kelas tertentu — memakai CA, bukan CD.

**Mengapa backoff harus acak.** Bayangkan backoff bernilai tetap. Dua node yang sama-sama menunggu kanal yang sedang dipakai akan selesai menunggu pada saat yang sama persis, lalu mengirim bersamaan — tabrakan yang justru **diciptakan** oleh mekanisme penghindarnya sendiri. Angka acak memecah simetri itu. Dan ketika kanal berkali-kali ditemukan sibuk (tanda peserta makin banyak atau makin ramai), rentang undiannya dilebarkan supaya peluang dua node mengundi angka yang sama makin kecil — inilah *exponential backoff*.

**Batas yang tetap ada.** CSMA/CA mengurangi tabrakan, tidak menghapusnya. Dua node yang menyelesaikan DIFS pada milidetik yang sama tetap akan berangkat bersamaan; node yang mulai mengirim tepat setelah tetangganya selesai menyensor juga tidak akan terdeteksi. Dan karena modul ini belum punya ACK, tabrakan yang tetap terjadi tetap **senyap** — node mengira paketnya berhasil karena kanal terdengar sepi saat ia berangkat.

**Sekuens yang diamati**

```
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
```

## 4 · Topologi

```
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
```

| Node | Environment | Peran | Mekanisme TX/RX | Interval kirim |
|---|---|---|---|---|
| Node 1 | `node1` | Baca sensor, sensing kanal, backoff, kirim | TX blocking; RX kontinu **hanya** untuk mendengar kanal | acak 2000–5000 ms |
| Node 2 | `node2` | Sama persis, keputusannya independen | TX blocking; RX kontinu **hanya** untuk mendengar kanal | acak 2000–5000 ms |
| Gateway | `gateway` | Terima, catat, deteksi lubang SEQ | Interrupt DIO0 + flag, **tanpa TX sama sekali** | — |

Karena gateway tidak pernah memancar, ia tidak pernah ikut membuat kanal sibuk. Setiap kali sebuah node melaporkan `[CS] kanal SIBUK`, yang ia dengar dipastikan node satunya — bukan gema dari gateway.

## 5 · Alat yang Digunakan

Modul ini dijalankan di atas Arduino Uno (ATmega328P) dengan Dragino LoRa Shield v1.2 (SX1276), memakai PlatformIO dan library LoRa karya sandeepmistry.

| No | Peralatan | Spesifikasi | Jumlah |
|---|---|---|---|
| 1 | Arduino Uno | ATmega328P | 3 |
| 2 | Dragino LoRa Shield | v1.2, SX1276, 433 MHz | 3 |
| 3 | Antena SMA | **wajib terpasang sebelum diberi daya** | 3 |
| 4 | Kabel USB tipe B | kabel data | 3 |

**Sensor suhu & kelembaban.** Nilai T dan H dibangkitkan di dalam firmware (dummy, berbeda titik dasar untuk tiap node) supaya modul bisa dijalankan tanpa sensor fisik — fokus modul ini ada pada akses kanal, bukan pembacaan sensor. Untuk memakai DHT22 sungguhan, satu-satunya yang perlu diubah adalah isi fungsi `bacaSensor()` di `src/node/main.cpp`; tambahkan library-nya ke `lib_deps` dan pasang pin datanya ke pin digital yang **tidak dipakai shield** (D10, D11, D12, D13, D9, dan D2 sudah terpakai SPI/RST/DIO0 — gunakan D3–D8). Tidak ada baris lain yang perlu disentuh, sebab seluruh mekanisme CSMA/CA tidak peduli dari mana angkanya datang.

**Pemetaan pin Dragino Shield v1.2**

| Fungsi | Pin Uno |
|---|---|
| NSS / CS | D10 |
| RST | D9 |
| DIO0 | D2 |
| SCK / MOSI / MISO | D13 / D11 / D12 |

**Struktur proyek**

```
Modul09_lora_csma_ca/
├── platformio.ini         ← tiga environment; CS_MODE memilih RSSI atau CAD
├── lora_monitor.py        ← dashboard 3-panel live + statistik akses kanal + CSV
├── upload_auto.py         ← unggah ketiga board, port dideteksi sendiri
├── logserial.md           ← log serial aktual dari pengujian perangkat + ringkasannya
└── src/
    ├── node/main.cpp      ← sensing + backoff + TX (env node1, node2)
    └── gateway/main.cpp   ← terima & cetak, deteksi lubang SEQ (env gateway)
```

**Parameter CSMA/CA di `src/node/main.cpp`**

| Konstanta | Nilai bawaan | Arti |
|---|---|---|
| `RSSI_THRESHOLD` | −95 dBm | Di atas ini kanal dianggap terpakai. **Dikalibrasi di EXP-01.** |
| `DIFS_MS` | 30 ms | Kanal harus bebas selama ini sebelum boleh mengirim |
| `SLOT_MS` | 20 ms | Panjang satu slot backoff |
| `CW_MIN` / `CW_MAX` | 4 / 64 | Jendela kontensi awal dan batas atasnya |
| `MAX_ATTEMPT` | 5 | Sesudah ini paket dibuang (`[DROP]`), tidak dipaksakan |
| `CS_MODE` | 0 (RSSI) | 0 = RSSI, 1 = CAD, 2 = telinga dimatikan (pembanding EXP-04) — diatur dari `platformio.ini` |
| `SEND_INTERVAL_MIN` / `MAX` | 2000 / 5000 ms | Jarak antar data. Bisa ditimpa dari `platformio.ini` untuk EXP-03 |

Waktu udara satu paket modul ini (≈26 byte, SF7, BW 125 kHz, CR 4/5, preamble 8) sekitar **60 ms** menurut perhitungan — hitung sendiri angka pastinya sebagai bagian dari Analisis. Seluruh angka di tabel atas dipilih relatif terhadap angka itu.

**Build & flash** — **gateway lebih dahulu**, supaya paket pertama dari node langsung tertangkap.

```bash
pio run -d Modul09_lora_csma_ca -e gateway -t upload -t monitor
pio run -d Modul09_lora_csma_ca -e node1   -t upload -t monitor
pio run -d Modul09_lora_csma_ca -e node2   -t upload -t monitor
```

Atau otomatis, tanpa mengedit port di `platformio.ini`:

```bash
python3 Modul09_lora_csma_ca/upload_auto.py
```

**Monitor dashboard** — `python3 lora_monitor.py` membaca ketiga port sekaligus dan menampilkan panel Gateway/Node 1/Node 2. Panel node modul ini menampilkan statistik akses kanal: berapa kali kanal ditemukan sibuk, berapa kali backoff dan freeze terjadi, berapa paket dibuang, serta tunda akses terakhir dan rata-ratanya. Butuh `pip install pyserial rich`.

**Pre-flight checklist**

- ☐ Antena terpasang pada ketiga shield.
- ☐ Port ketiga board dicatat lewat `pio device list` (atau `python3 ../tools/deteksi_port.py`) dan diisikan ke `platformio.ini`.
- ☐ Tiga Serial Monitor 115200 baud siap, ketiganya terlihat bersamaan.
- ☐ `NODE_ID` pada `node1`/`node2` sudah benar (dicek dari baris pembuka `NODE 1`/`NODE 2`).
- ☐ Baris `Carrier sense:` pada kedua node menunjukkan mode dan ambang yang sama.

## 6 · Percobaan

### EXP-01 — Kalibrasi Telinga: Berapa Nilai "Sibuk"?

Ambang −95 dBm di kode hanyalah tebakan awal. Sebelum mempercayai keputusan node, ukur dulu seperti apa kanal ini sebenarnya.

1. Nyalakan **satu node saja**, board lain dimatikan. Saat menyala, node mengambil 200 sampel RSSI kanal kosong dan melaporkannya sendiri:

   ```
   [KALIBRASI] lantai derau 200 sampel: min -119 | rata-rata -112 | maks -104 dBm
   [KALIBRASI] ambang terpakai sekarang: -95 dBm -- lihat EXP-01
   ```

   (angka di atas hanya bentuk barisnya; nilai sesungguhnya bergantung lingkungan Anda)

2. Nyalakan node kedua. Pada serial node pertama, baca nilai RSSI yang tercetak pada baris `[CS] kanal SIBUK (RSSI ...)` — itulah kekuatan sinyal tetangga saat sedang mengirim.
3. Tentukan ambang di tengah-tengah kedua nilai itu, lalu isikan ke `RSSI_THRESHOLD` dan unggah ulang kedua node. Baris `[KALIBRASI]` kedua akan mengonfirmasi ambang baru sudah terpasang.

**Data capture**

| Parameter | Hasil verifikasi 2026-08-23 | Hasil Anda |
|---|---|---|
| Lantai derau `[KALIBRASI]` — min / rata-rata / maks (dBm) | −117 / −110 / −105 | |
| RSSI saat node tetangga mengirim | −29 … −33 | |
| Selisih keduanya (dB) | ≈ 80 | |
| `RSSI_THRESHOLD` yang dipilih | −95 (bawaan, sudah di tengah rentang) | |

> **CHECKPOINT terpenuhi pada verifikasi.** Selisihnya ternyata sangat lebar — sekitar **80 dB** antara kanal kosong (≈ −110 dBm) dan kanal terpakai (≈ −30 dBm) pada jarak meja — sehingga ambang bawaan −95 dBm aman di tengah rentang dan tidak perlu diubah. Selisih sebesar itu tidak dijamin di ruangan lain; tetap ukur sendiri. Selisih antara kanal kosong dan kanal terpakai harus jelas (belasan hingga puluhan dB pada jarak meja). Bila selisihnya kecil, jarak antar-board terlalu jauh atau antena belum terpasang benar. Ambang yang terlalu tinggi membuat node tuli (semua dianggap sepi); terlalu rendah membuatnya paranoid (semua dianggap sibuk, semua paket berakhir `[DROP]`).

### EXP-02 — Dua Node Sopan

Nyalakan ketiga board dengan parameter bawaan dan amati beberapa menit.

**Expected output — node**

```
=== LoRa CSMA/CA - NODE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
Carrier sense: RSSI (ambang -95 dBm) | DIFS 30 ms | slot 20 ms | CW 4..64
Peran: NODE (CSMA/CA) -- dengar dulu, mundur acak, baru kirim
Tanpa ACK: node tahu kanal sepi, tetap tidak tahu paketnya sampai
[KALIBRASI] lantai derau 200 sampel: min -119 | rata-rata -112 | maks -104 dBm
[KALIBRASI] ambang terpakai sekarang: -95 dBm -- lihat EXP-01

[TX] NODE=1,SEQ=0,T=28.4,H=70.6 | attempt=1 | tunda=30 ms
[STAT] TX=1 | DROP=0 | kanal sibuk=0 | rata-rata tunda=30 ms
```

Ketika tetangganya sedang bicara:

```
[CS] kanal SIBUK (RSSI -47 dBm)
[BACKOFF] percobaan 1/5 | CW=4 | slot=2 -> 40 ms
[FREEZE] pencacah backoff dibekukan -- kanal terpakai
[TX] NODE=2,SEQ=3,T=29.2,H=67.8 | attempt=2 | tunda=118 ms
```

**Expected output — gateway**

```
=== PAKET DITERIMA ===
  Node    : 1
  SEQ     : 0
  Suhu    : 28.4 C
  Lembab  : 70.6 %
  RSSI    : -41 dBm
  SNR     : 9.50 dB
  Selang  : 1843 ms dari paket sebelumnya
  Statistik Node 1: diterima=1 | perkiraan hilang=0
  Total diterima gateway: 1
=====================
```

**Data capture** — amati 3 menit

| Parameter | Hasil verifikasi 2026-08-23 | Hasil Anda |
|---|---|---|
| Paket diterima gateway — Node 1 / Node 2 | 49 / 49 (dari 50 / 49 dikirim) | |
| Jumlah `[CS] kanal SIBUK` — Node 1 / Node 2 | 1 / 2 | |
| Jumlah `[BACKOFF]` — Node 1 / Node 2 | 1 / 2 | |
| Jumlah `[DROP]` — Node 1 / Node 2 | 0 / 0 | |
| Tunda akses rata-rata (ms) — Node 1 / Node 2 | 31,7 / 34,3 | |
| Selang antar-paket terkecil yang tercatat gateway (ms) | 116 | |

> **CHECKPOINT terpenuhi.** Pada interval bawaan (2–5 detik) kanal jarang berebut: 97 dari 99 paket berangkat dengan `attempt=1` dan tunda ≈ `DIFS_MS` (30 ms). Tiga kali sepanjang 3 menit sebuah node menemukan kanal terpakai, mundur, lalu berhasil pada percobaan kedua. Yang wajib muncul minimal beberapa kali adalah baris `[CS] kanal SIBUK` — itulah bukti telinga node benar-benar mendengar tetangganya. Bila tidak pernah muncul sama sekali sepanjang 3 menit, ambang RSSI kemungkinan masih terlalu tinggi; ulangi EXP-01.

### EXP-03 — Memaksa Berebut

Perkecil interval kirim pada **kedua** node menjadi 300–500 ms lewat build flag di `platformio.ini` (tidak perlu mengedit source):

```ini
build_flags = -DNODE_ID=1 -DCS_MODE=0 -DSEND_INTERVAL_MIN=300 -DSEND_INTERVAL_MAX=500
```

Unggah ulang kedua node, lalu amati kembali. Beban kanal kini jauh melewati kapasitasnya (dua paket ~60 ms setiap ~400 ms per node), sehingga mekanisme CA dipaksa bekerja keras.

**Data capture** — amati 3 menit

| Parameter | Hasil verifikasi 2026-08-23 | Hasil Anda |
|---|---|---|
| Interval kirim yang dipakai (ms) | 300–500 | |
| Paket diterima gateway — Node 1 / Node 2 | 351 / 343 (dari 352 / 348 dikirim) | |
| Jumlah `[BACKOFF]` — Node 1 / Node 2 | 32 / 67 | |
| Jumlah `[FREEZE]` — Node 1 / Node 2 | 26 / 46 | |
| Jumlah `[DROP]` — Node 1 / Node 2 | 0 / 0 | |
| CW terbesar yang sempat terpakai | 16 | |
| Tunda akses rata-rata (ms) — Node 1 / Node 2 | 37,2 / 46,1 (maks 238 / 257) | |
| Jumlah `[GAP]` di gateway — Node 1 / Node 2 | 0 / 4 | |

**Buka abstraksinya** — di `src/node/main.cpp`, fungsi `hitungMundurSlot()` **tidak** sekadar `delay(slot * SLOT_MS)`. Pencacahnya berhenti berkurang selama kanal terpakai dan lanjut lagi saat sepi. Ganti sementara isi fungsi itu dengan `delay((long)slot * SLOT_MS)` biasa, unggah ulang, lalu ulangi EXP-03 dan bandingkan jumlah `[DROP]`-nya. Jelaskan: node mana yang dirugikan oleh backoff yang *tidak* dibekukan, dan mengapa?

> **CHECKPOINT terpenuhi sebagian.** `[BACKOFF]` melonjak dari 3 (EXP-02) menjadi 99, tunda akses rata-rata naik ~30%, dan CW sempat melebar sampai 16. Tetapi `[DROP]` **tetap nol**: dengan dua node, lima percobaan selalu cukup untuk memperoleh kanal. Untuk benar-benar memunculkan `[DROP]`, perkecil `MAX_ATTEMPT` atau tambahkan node ketiga (CH-2). Yang paling penting justru ini: dari 700 paket yang naik ke udara, gateway mencatat **0 paket cacat** — CA memindahkan kegagalan dari "rusak di udara" menjadi "tertunda" (dan, pada beban lebih tinggi, "dibuang sebelum berangkat") — kegagalan yang setidaknya **diketahui pengirimnya**.

### EXP-04 — Matikan Telinganya

Ini percobaan pembanding yang paling menentukan. Pada **kedua** node, matikan telinganya lewat build flag — pertahankan interval sempit dari EXP-03:

```ini
build_flags = -DNODE_ID=1 -DCS_MODE=2 -DSEND_INTERVAL_MIN=300 -DSEND_INTERVAL_MAX=500
```

Node kini mengirim buta — persis Pure ALOHA. Unggah ulang kedua node, amati 3 menit, lalu **kembalikan `CS_MODE=0`**. Baris pembuka node akan menegaskan mode yang sedang aktif: `Carrier sense: MATI -- kirim buta`.

**Data capture**

Hasil verifikasi 2026-08-23 (masing-masing 3 menit, beban kirim setara):

| Parameter | Dengan carrier sense (EXP-03) | Tanpa carrier sense (EXP-04) |
|---|---|---|
| Paket dikirim node — total | 700 | 757 |
| Paket diterima gateway — total | 695 | 581 |
| Paket hilang | **5 (0,7%)** | **176 (23,2%)** |
| Jumlah `[GAP]` di gateway — total | 4 | 102 |
| `[WARN]` paket cacat/tak dikenal di gateway | 0 | 37 |
| Tunda akses rata-rata (ms) | 37–46 | **0** |
| Paket dibuang node (`[DROP]`) | 0 | 0 (tidak ada mekanismenya) |

> **CHECKPOINT terpenuhi.** Tanpa carrier sense tunda akses turun ke nol — dan satu dari setiap empat paket lenyap. Inilah pertukaran inti modul ini: CSMA/CA **membeli keandalan dengan waktu**, sekitar 40 ms per paket untuk menekan kehilangan dari 23% menjadi di bawah 1%. Perhatikan juga bahwa tanpa carrier sense, node mengirim **lebih banyak** paket (757 vs 700, karena tidak pernah menunggu) namun gateway justru menerima **lebih sedikit**. Bila kedua kolom nyaris sama, beban kanal belum cukup tinggi — persempit lagi intervalnya.

**Tabrakan terlihat langsung di sini.** Pada sesi tanpa carrier sense, gateway mencetak paket yang awalannya masih terbaca sementara sisanya hancur — inilah wujud tabrakan yang selama EXP-03 tidak pernah muncul sama sekali:

```
[WARN] Paket cacat (field tidak lengkap): NODE=2,SEQ=1,T=28.t,??,a?2
```

### EXP-05 — RSSI vs CAD

Ubah `-DCS_MODE=0` menjadi `-DCS_MODE=1` pada **kedua** node di `platformio.ini`, unggah ulang, lalu ulangi EXP-03 dengan interval yang sama persis.

**Data capture** — hasil verifikasi 2026-08-23, beban kirim setara

| Parameter | CS_MODE=0 (RSSI) | CS_MODE=1 (CAD) |
|---|---|---|
| Jumlah `[CS] kanal SIBUK` — total | 99 | **107** |
| Jumlah `[FREEZE]` — total | 72 | 96 |
| Jumlah `[DROP]` — total | 0 | 0 |
| Tunda akses rata-rata (ms) — Node 1 / Node 2 | 37,2 / 46,1 | 43,3 / 41,3 |
| Paket dikirim / diterima gateway | 700 / 695 | 699 / 694 |

> **CHECKPOINT terpenuhi.** CAD tidak memerlukan ambang sama sekali (perhatikan: baris pembuka node tidak lagi menyebut angka dBm), sebab ia mengenali bentuk simbol LoRa, bukan sekadar besar energi. Hasil akhirnya praktis setara — selisih satu paket dari ~700 — tetapi CAD melaporkan kanal sibuk **lebih sering** (107 vs 99). Pikirkan mana dari keduanya yang sedang keliru: apakah CAD terlalu waspada, atau justru ambang −95 dBm yang melewatkan sinyal lemah?

**Buka abstraksinya (untuk yang mengutak-atik mode ini).** Library `sandeepmistry/LoRa` tidak menyediakan CAD sama sekali, jadi `kanalTerpakai()` versi CAD menulis register SX1276 langsung. Dua jebakan yang ditemukan saat modul ini diuji — keduanya sudah diperbaiki di kode, dan keduanya layak ditelusuri sendiri di `src/node/main.cpp`:
> 1. CAD **harus** dimasuki dari STANDBY. Perintah CAD dari mode RX kontinu tidak pernah dijalankan: `CadDone` tak pernah naik dan tiap pemeriksaan berakhir di timeout.
> 2. `isTransmitting()` milik library menguji `(RegOpMode & 0x03) == 0x03`, dan mode CAD (`0x07`) **lolos uji itu**. Bila modem masih di CAD saat `beginPacket()` dipanggil, `beginPacket()` gagal diam-diam tanpa me-reset FIFO, dan yang naik ke udara adalah sampah. Rinciannya di `logserial.md`.

### Verifikasi hardware

**Diuji di perangkat pada 2026-08-23** — 3× Arduino Uno asli (`2341:0043`) + Dragino LoRa Shield v1.2 (gateway + node1 + node2 pada `/dev/ttyACM0/1/2`, cocok dengan `platformio.ini` bawaan). Ketiga environment dibangun dan diunggah tanpa modifikasi. **EXP-01 sampai EXP-05 seluruhnya dijalankan**, masing-masing jendela rekam 180 detik, dan angka pada semua tabel Data capture di atas serta bagian Pengukuran adalah hasil ukur nyata dari sesi itu — log lengkap beserta cuplikan serial ketiga board ada di `logserial.md`.

Dua perbaikan lahir dari pengujian ini dan sudah masuk ke kode: gateway kini menolak paket yang field-nya tidak lengkap (tanpa itu, satu paket rusak akibat tabrakan membuat perkiraan kehilangan melonjak ke 1177 dari kenyataan ~30), dan jalur CAD kini masuk lewat STANDBY serta memanggil `LoRa.idle()` sebelum `beginPacket()` (tanpa itu CAD tidak pernah mendeteksi apa pun **dan** merusak transmisi node sendiri). Keduanya diuraikan di `logserial.md`.

Satu hal yang **tidak** berhasil dibuktikan: `[DROP]` tetap nol di seluruh sesi. Dengan dua node, `MAX_ATTEMPT=5` selalu cukup. Untuk melihat paket benar-benar dibuang, perkecil `MAX_ATTEMPT` atau tambahkan node ketiga (CH-2).

## 7 · Pengukuran

**A. Beban kanal terhadap perilaku CSMA/CA**

Baris bertanda ✓ adalah hasil verifikasi 2026-08-23; baris kosong dijalankan sendiri.

| Interval kirim (ms) | Paket diterima gateway (3 menit) | `[BACKOFF]` total | `[DROP]` total | Tunda akses rata-rata (ms) |
|---|---|---|---|---|
| 2000–5000 (bawaan) ✓ | 98 dari 99 dikirim | 3 | 0 | 31,7 / 34,3 |
| 1000–2000 | | | | |
| 300–500 ✓ | 695 dari 700 dikirim | 99 | 0 | 37,2 / 46,1 |

**B. RSSI/SNR dan tunda akses per node**

Hasil verifikasi pada beban tinggi (interval 300–500 ms, sesi EXP-03):

| Node | RSSI rata-rata (dBm) | SNR rata-rata (dB) | Tunda akses rata-rata (ms) | `[GAP]` |
|---|---|---|---|---|
| Node 1 | −44,7 | 9,77 | 37,2 (maks 238) | 0 |
| Node 2 | −54,5 | 9,73 | 46,1 (maks 257) | 4 |

Selisih ±10 dB antar node murni posisi fisik di meja. Menarik: node yang sinyalnya lebih lemah di gateway (Node 2) justru yang lebih sering menemukan kanal sibuk dan paling banyak mundur — periksa apakah pola itu terulang pada pengukuran Anda.

**C. CSMA/CA vs kirim buta (dari EXP-04)**

| Metrik | Dengan CS | Tanpa CS | Selisih |
|---|---|---|---|
| Paket dikirim node | 700 | 757 | +57 tanpa CS |
| Paket tiba di gateway | 695 | 581 | **−114 tanpa CS** |
| Paket hilang (perkiraan dari SEQ) | 4 (0,6%) | 175 (23,1%) | 44× lebih banyak |
| Paket cacat di gateway | 0 | 37 | — |
| Tunda akses rata-rata | ~41 ms | 0 ms | harga yang dibayar |
| Paket dibuang sebelum berangkat | 0 | 0 | — |

## 8 · Analisis

1. Hitung waktu udara satu paket modul ini pada SF7/BW125 kHz/CR4/5, lalu bandingkan dengan `DIFS_MS` dan `SLOT_MS`. Apakah satu slot cukup panjang untuk membedakan kanal yang benar-benar bebas dari sela antar-simbol? Bila `SLOT_MS` dibuat 5 ms, apa yang Anda perkirakan terjadi?
2. Dari tabel C, hitung berapa milidetik tunda akses yang harus dibayar untuk setiap satu paket yang berhasil diselamatkan dari tabrakan. Menurut Anda, di aplikasi seperti apa harga itu murah, dan di aplikasi seperti apa terlalu mahal?
3. Pada verifikasi dengan dua node, `[DROP]` tidak pernah muncul sekali pun — lima percobaan selalu cukup. Perkirakan (dengan hitungan, bukan tebakan) berapa node atau berapa `MAX_ATTEMPT` yang diperlukan agar `[DROP]` mulai terjadi pada interval 300–500 ms, lalu uji perkiraan Anda. Jelaskan juga mengapa node lebih baik membuang paket daripada terus mencoba tanpa batas.
4. Node menaikkan `SEQ` juga untuk paket yang dibuangnya sendiri. Jelaskan apa yang akan hilang dari kemampuan analisis gateway seandainya `SEQ` hanya naik saat paket benar-benar terkirim.
6. Gateway menolak paket yang field-nya tidak lengkap. Baca `logserial.md` bagian EXP-04: tanpa pemeriksaan itu, satu paket rusak membuat perkiraan kehilangan melonjak dari ~30 menjadi 1177. Telusuri persis bagaimana satu paket cacat bisa menghasilkan angka sebesar itu, lalu usulkan satu pemeriksaan tambahan yang membuat statistik gateway lebih tahan banting.
5. Gateway modul ini tidak pernah memancar sama sekali. Bila kelak ia mulai mengirim ACK (modul berikutnya), sebutkan **dua** hal yang berubah bagi mekanisme carrier sense di node.

## 9 · Concept Check

1. Apa beda mendasar CSMA/CA di modul ini dengan polling terjadwal pada M05 — siapa yang memegang keputusan "kapan boleh bicara" pada masing-masing?
2. Mengapa radio tidak bisa memakai *collision detection* seperti Ethernet, sehingga harus puas dengan *collision avoidance*?
3. Mengapa backoff harus acak? Apa yang terjadi bila semua node memakai lama tunggu tetap yang sama?
4. Mengapa jendela kontensi dilebarkan setiap kali kanal ditemukan sibuk, alih-alih dipertahankan tetap?
5. Jelaskan masalah *hidden node*: dua node patuh mendengarkan, tetapi paketnya tetap bertabrakan di gateway. Bagaimana ini bisa terjadi, dan apakah menaikkan `MAX_ATTEMPT` menolong?
6. CAD dan RSSI sama-sama menjawab "kanal sibuk atau tidak". Sebutkan satu keadaan di mana keduanya memberi jawaban berbeda, dan mana yang lebih tepat pada keadaan itu.

## 10 · Challenge (tugas modifikasi)

- **CH-1 — Ambang adaptif.** Buat node mengukur lantai derau sendiri saat `setup()` (rata-rata puluhan sampel RSSI pada kanal kosong), lalu menetapkan `RSSI_THRESHOLD` sebagai lantai derau + margin tetap. Bandingkan hasilnya dengan ambang manual dari EXP-01.
- **CH-2 — Node ketiga.** Tambahkan environment `node3` dan jalankan EXP-03 dengan tiga node. Ukur bagaimana tunda akses rata-rata dan `[DROP]` berubah ketika jumlah peserta naik dari dua menjadi tiga pada beban yang sama.
- **CH-3 — Prioritas lewat DIFS.** Beri Node 1 rentang tunggu yang lebih pendek daripada Node 2 (misalnya DIFS 20 ms vs 40 ms), lalu buktikan dari data gateway bahwa Node 1 memperoleh porsi kanal yang lebih besar. Ini adalah versi sederhana dari mekanisme prioritas 802.11e.
- **CH-4 — Laporkan kesibukan.** Sisipkan jumlah backoff dan tunda akses paket ini ke dalam payload (`,BO=<n>,DLY=<ms>`), lalu buat gateway mencetak peta kesibukan kanal dari sudut pandang masing-masing node. Perhatikan bahwa parser gateway tidak perlu diubah untuk field yang tidak dikenalnya — buktikan klaim itu sebelum menambahkan pembacaannya.

## 11 · Laporan

**Deliverable**

1. Misi dan capaian pembelajaran
2. Dasar teori ringkas (CS/MA/CA, DIFS, contention window, exponential backoff, freeze, hidden node)
3. Konfigurasi — format payload, parameter CSMA/CA yang dipakai, ambang RSSI hasil kalibrasi EXP-01, parameter radio
4. Hasil eksperimen — log serial ketiga board (EXP-01…05 beserta checkpoint)
5. Data pengukuran — tabel A, B, dan C pada bagian Pengukuran
6. Analisis dan concept check
7. Challenge — minimal CH-1
8. Kesimpulan yang disusun sendiri, khususnya mengenai harga yang dibayar (tunda akses dan paket yang dibuang) untuk keandalan yang diperoleh, dan mengapa jaringan nyata tetap memilih membayarnya
