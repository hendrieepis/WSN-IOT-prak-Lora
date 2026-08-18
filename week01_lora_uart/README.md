```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
       MODUL 01 — Tautan LoRa Satu Arah

   Arduino Uno + Dragino LoRa Shield v1.2 · Basic
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 01 dirancang untuk dua pertemuan (2 × 50 menit) pada tingkat dasar. Misinya membentuk tautan LoRa satu arah yang stabil: satu board mengirim pesan berkala, satu board lain menerimanya beserta ukuran kualitas sinyal. Percobaan memakai dua Arduino Uno bershield Dragino LoRa v1.2, diamati melalui dua Serial Monitor pada 9600 baud.

LoRa berbeda mendasar dari BLE, Zigbee, maupun Thread yang berbasis jaringan. Di sini **tidak ada jaringan sama sekali** — tidak ada proses join, tidak ada alamat, tidak ada koneksi. Yang ada hanya modulasi radio: siapa pun yang menyetel frekuensi, spreading factor, bandwidth, dan coding rate yang sama akan mendengar apa yang dikirim. Semua yang biasanya disediakan protokol — identitas, penyaringan tujuan, konfirmasi, penanganan tabrakan — harus dibangun sendiri di lapisan aplikasi, dan itulah yang dikerjakan modul-modul berikutnya.

Prasyaratnya hanya dasar bahasa C dan alur build PlatformIO; tidak ada modul LoRa yang mendahuluinya. Yang dibangun di sini adalah inisialisasi SX1276 melalui SPI, penyetelan empat parameter radio yang menentukan tautan, pengiriman paket secara blocking, penerimaan dengan cara polling, serta pembacaan RSSI dan SNR sebagai instrumen ukur. Semuanya dipakai lagi pada M02 ketika penerimaan berpindah ke interrupt, M03 ketika arah data menjadi dua arah, M04 ketika keandalan diukur dengan ACK, dan M05 ketika jumlah node bertambah.

**Peta modul LoRa**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| **01 (ini)** | **Tautan satu arah terbentuk; RSSI dan SNR terbaca** |
| 02 | Penerimaan tanpa memblokir loop (interrupt) + indikator LED |
| 03 | Dua arah — kedua board bergantian mengirim dan menerima |
| 04 | Keandalan diukur: ACK, timeout, dan hitungan gagal |
| 05 | Banyak node — satu master menjadwalkan giliran bicara |

**Kontrak data lab ini.** Payload berupa string ASCII pendek dengan **nomor urut** di dalamnya (`Hello LoRa #7`). Nomor itulah yang membuat paket hilang dapat dihitung — cukup mencari lompatan angka di log penerima. Format bernomor yang sama dipertahankan sampai M05 (`DATA:n`, `S1:DATA:n`), sehingga hasil pengukuran antar-modul dapat dibandingkan.

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Menjelaskan peran empat parameter radio LoRa — frekuensi, spreading factor, bandwidth, dan coding rate — serta akibatnya bila salah satu berbeda antara pengirim dan penerima.
2. Menginisialisasi SX1276 melalui SPI dengan pemetaan pin shield yang benar, dan mendiagnosis kegagalan `LoRa.begin()`.
3. Menjelaskan perbedaan pengiriman blocking dan penerimaan berbasis polling, beserta konsekuensinya pada `loop()`.
4. Membaca RSSI dan SNR sebagai dua besaran yang berbeda, dan menjelaskan mengapa keduanya perlu dicatat bersama.
5. Menghitung packet loss dari nomor urut pada payload.

**Kriteria keberhasilan**

- ☐ Kedua board mencetak `Init LoRa ... OK` setelah reset.
- ☐ Penerima mencetak setiap paket beserta RSSI dan SNR.
- ☐ Nomor urut yang diterima berurutan tanpa lompatan pada jarak dekat.
- ☐ Tabel jarak–RSSI–SNR–loss terisi dari pengukuran sendiri, minimal empat jarak.

## 3 · Dasar Teori (secukupnya)

Teori dibatasi pada apa yang dipakai di percobaan.

| Istilah | Definisi kerja di lab ini |
|---|---|
| LoRa | Teknik modulasi *chirp spread spectrum* untuk jangkauan jauh dengan laju data rendah. Modul ini memakai LoRa mentah, bukan LoRaWAN. |
| SX1276 | Chip radio pada shield Dragino, dikendalikan mikrokontroler lewat SPI. |
| Frekuensi kerja | Kanal radio yang dipakai. Program disetel **920 MHz**; kedua board wajib sama persis. |
| Spreading Factor (SF) | Lama satu simbol. SF besar menambah jangkauan dan ketahanan, tetapi memperlambat data dan memperpanjang waktu udara. Modul ini memakai SF7. |
| Bandwidth (BW) | Lebar kanal. Semakin sempit semakin sensitif, tetapi semakin lambat. Modul ini memakai 125 kHz. |
| Coding Rate (CR) | Rasio kode koreksi galat. 4/5 berarti tiap 4 bit data disertai 1 bit koreksi. |
| RSSI | Kuat sinyal terima dalam dBm — seberapa **keras** sinyal terdengar. Semakin mendekati nol semakin kuat. |
| SNR | Selisih sinyal terhadap derau dalam dB — seberapa **jernih** sinyal terdengar. LoRa masih dapat memecahkan sinyal pada SNR negatif. |
| Polling | Penerima memeriksa sendiri secara berulang apakah ada paket (`LoRa.parsePacket()`). |

**Mengapa RSSI saja tidak cukup.** RSSI mengukur daya yang tiba di penerima, termasuk derau. Sebuah sinyal bisa terdengar keras (RSSI −70 dBm) tetapi tenggelam dalam gangguan sehingga gagal dipecahkan, dan sebaliknya sinyal lemah (RSSI −120 dBm) tetap terbaca jika lingkungan sunyi. Keunggulan LoRa justru terletak di sana: modulasinya sanggup bekerja pada **SNR negatif**, yaitu ketika sinyal lebih lemah daripada derau di sekitarnya. Karena itu kedua angka dicatat bersama, dan pada M05 keduanya dipakai untuk menjelaskan mengapa sebuah node tidak menjawab.

**Sekuens yang diamati**

```
   Sender                          (udara 920 MHz)                    Receiver
     |                                                                   |
  beginPacket()                                                    parsePacket()
  print("Hello LoRa #7")                                            (polling terus)
  endPacket()  --- blocking sampai seluruh paket mengudara --->        |
     |                                                           paket terdeteksi
     |                                                           baca isi + RSSI + SNR
  delay(2000)                                                          |
     |                                                           cetak ke Serial
```

## 4 · Topologi

```
        BOARD #1                                  BOARD #2
  +------------------+                      +------------------+
  |   Arduino Uno    |                      |   Arduino Uno    |
  | + LoRa Shield    |  ~~~~ 920 MHz ~~~~>  | + LoRa Shield    |
  |     SENDER       |     satu arah        |    RECEIVER      |
  | "Hello LoRa #n"  |                      | cetak + RSSI/SNR |
  +------------------+                      +------------------+
     env: sender                              env: receiver
```

| Node | Environment | Peran | Payload / interval |
|---|---|---|---|
| Sender | `sender` | Pengirim | `Hello LoRa #n` tiap 2000 ms |
| Receiver | `receiver` | Penerima (polling) | — |

Tidak ada alamat maupun identitas node pada modul ini. Setiap penerima yang menyetel parameter radio sama akan menerima paket yang sama — sifat yang akan menjadi masalah nyata di M05, dan diselesaikan di sana dengan penomoran di lapisan aplikasi.

## 5 · Alat yang Digunakan

Modul ini dijalankan di atas Arduino Uno (ATmega328P) dengan Dragino LoRa Shield v1.2 (SX1276), memakai PlatformIO dan library LoRa karya sandeepmistry.

| No | Peralatan | Spesifikasi | Jumlah |
|---|---|---|---|
| 1 | Arduino Uno | ATmega328P, flash 32 KB | 2 |
| 2 | Dragino LoRa Shield | v1.2, SX1276, 920 MHz | 2 |
| 3 | Antena SMA | sesuai band shield — **wajib terpasang sebelum diberi daya** | 2 |
| 4 | Kabel USB tipe B | kabel data | 2 |
| 5 | PC/Laptop | PlatformIO Core/IDE, 2 port USB bebas | 1 |

> **Jangan menyalakan shield tanpa antena.** Daya pancar yang tidak menemukan beban akan dipantulkan kembali ke penguat SX1276 dan dapat merusaknya secara permanen. Pasang antena lebih dahulu, baru sambungkan USB.

**Pin yang dipakai shield (tidak boleh dipakai program)**

| Pin Arduino | Fungsi LoRa | Keterangan |
|---|---|---|
| D10 | NSS / CS | Chip select SX1276, ditentukan jumper R9 (0 ohm, terpasang dari pabrik) |
| D11 | MOSI | SPI data keluar |
| D12 | MISO | SPI data masuk |
| D13 | SCK | SPI clock — **juga LED bawaan Arduino** |
| D9 | RST | Reset SX1276 |
| D2 | DIO0 | Interrupt TX-done / RX-done (INT0) |

Pin D6, D7, dan D8 tersambung ke DIO1, DIO2, dan DIO5 pada shield. Ketiganya tidak dipakai program ini, tetapi jangan dijadikan output agar tidak beradu dengan keluaran chip. Pin yang bebas dipakai: **D3, D4, D5, dan A0–A5**.

**Struktur proyek**

```
week01_lora_uart/
├── platformio.ini
└── src/
    ├── sender/main.cpp     ← kirim "Hello LoRa #n" tiap 2 detik
    └── receiver/main.cpp   ← terima, cetak isi + RSSI + SNR
```

**Build & flash** — penerima lebih dahulu, agar paket pertama pengirim tidak terbuang.

```bash
pio run -d week01_lora_uart -e receiver -t upload -t monitor
pio run -d week01_lora_uart -e sender   -t upload -t monitor
```

**Pre-flight checklist**

- ☐ Antena terpasang pada kedua shield.
- ☐ `pio device list` dijalankan, port kedua board dicatat dan diisikan ke `platformio.ini`.
- ☐ Nilai `FREQUENCY` pada kedua source **sama persis** dan sesuai band shield yang dipakai.
- ☐ Dua Serial Monitor 9600 baud siap.

## 6 · Percobaan

### EXP-01 — Inisialisasi Radio

Unggah kedua firmware, buka Serial Monitor keduanya, dan amati pesan awal.

**Expected output — sender**

```
=== LoRa SENDER ===
Init LoRa ... OK
Frekuensi : 920.00 MHz
SF=7, BW=125kHz, CR=4/5, Power=17dBm
Kirim tiap 2 detik...
```

**Data capture**

| Parameter | Hasil |
|---|---|
| Pesan init pada sender | |
| Pesan init pada receiver | |
| Frekuensi yang tercetak (MHz) | |
| Pemakaian Flash dari ringkasan build | |

> **CHECKPOINT** — Kedua board mencetak `OK`. Munculnya `GAGAL! Cek kabel/modul.` berarti SX1276 tidak menjawab lewat SPI: periksa shield benar-benar duduk di header, jumper R9 terpasang, dan tidak ada program lain memakai D10.

### EXP-02 — Aliran Data Satu Arah

Biarkan sistem berjalan dua menit, lalu amati keterhubungan antara nomor urut di kedua sisi.

**Expected output — receiver**

```
--- Paket Diterima ---
  Data  : "Hello LoRa #12"
  RSSI  : -43 dBm
  SNR   : 9.75 dB
```

**Data capture**

| Parameter | Hasil |
|---|---|
| Nomor urut terakhir di sender | |
| Nomor urut terakhir di receiver | |
| Paket hilang (selisih) | |
| RSSI rata-rata (dBm) | |
| SNR rata-rata (dB) | |

**Buka abstraksinya** — di `src/receiver/main.cpp`, `LoRa.parsePacket()` dipanggil pada setiap putaran `loop()` tanpa jeda sama sekali. Tambahkan `delay(1000)` di akhir `loop()` penerima, unggah ulang, lalu amati apa yang terjadi pada paket yang tiba selama penerima sedang tertidur. Jelaskan hasilnya, lalu kembalikan kodenya. Pengamatan ini adalah alasan M02 berpindah ke interrupt.

> **CHECKPOINT** — Nomor urut yang diterima naik satu per satu tanpa lompatan pada jarak dekat. Lompatan angka pada jarak 1 meter menandakan gangguan atau parameter yang tidak seragam, bukan keterbatasan jangkauan — telusuri sebelum melanjutkan ke pengukuran jarak.

### EXP-03 — Parameter Harus Seragam

Ubah **satu** parameter di penerima saja, unggah ulang, dan amati akibatnya. Kembalikan ke nilai semula setelah tiap uji.

| Uji | Perubahan di receiver | Hasil yang teramati |
|---|---|---|
| 03-a | `setSpreadingFactor(8)` | |
| 03-b | `setSignalBandwidth(250E3)` | |
| 03-c | `setCodingRate4(6)` | |
| 03-d | `FREQUENCY 923E6` | |

> **CHECKPOINT** — Keempat uji harus menghentikan penerimaan sepenuhnya, bukan sekadar memperburuknya. Radio LoRa tidak mengenal "hampir cocok": parameter yang berbeda membuat paket tidak pernah dikenali sebagai paket.

### Verifikasi build (referensi)

```
Environment    Status    Flash              RAM
sender         SUCCESS   18.3% (5890 B)     ~14%
receiver       SUCCESS   22.7% (7312 B)     ~15%
```

Keduanya jauh di bawah batas 32 KB Arduino Uno — inilah alasan library sandeepmistry dipilih alih-alih RadioLib yang melampaui kapasitas flash.

## 7 · Pengukuran

**A. Jarak terhadap kualitas tautan** — sender dan receiver dipisahkan pada empat jarak, masing-masing diamati 60 detik.

| Jarak | RSSI (dBm) | SNR (dB) | Paket dikirim | Paket diterima | Loss (%) |
|---|---|---|---|---|---|
| 1 m | | | | | |
| 10 m | | | | | |
| 50 m | | | | | |
| 100 m | | | | | |

**B. Pengaruh penghalang** — pada jarak tetap 10 m.

| Kondisi | RSSI (dBm) | SNR (dB) | Loss (%) |
|---|---|---|---|
| Garis pandang bebas | | | |
| Terhalang satu dinding | | | |
| Terhalang dua dinding | | | |
| Antena menempel di logam | | | |

**C. Pengaruh spreading factor** — ubah SF pada **kedua** board, ukur pada jarak yang sama.

| SF | Waktu udara per paket (perkiraan) | RSSI (dBm) | SNR (dB) | Loss (%) |
|---|---|---|---|---|
| 7 | | | | |
| 9 | | | | |
| 12 | | | | |

## 8 · Analisis

1. Bagaimana hubungan jarak terhadap RSSI pada data tabel A? Apakah penurunannya sebanding dengan jarak, dan mengapa demikian?
2. Pada baris mana RSSI masih baik tetapi SNR sudah memburuk? Jelaskan apa yang terjadi secara fisik pada kondisi itu.
3. Dari tabel C, apa yang dipertukarkan ketika spreading factor dinaikkan? Kaitkan dengan waktu udara dan konsumsi energi.
4. Mengapa perbedaan satu parameter saja (EXP-03) membuat komunikasi gagal total, bukan sekadar menurun kualitasnya?
5. Modul ini tidak memiliki alamat maupun identitas node. Sebutkan dua masalah yang pasti muncul bila ada tiga board menyala bersamaan dengan firmware yang sama.

## 9 · Concept Check

1. Apa perbedaan RSSI dan SNR, dan mengapa keduanya dicatat bersama?
2. Mengapa antena wajib terpasang sebelum shield diberi daya?
3. Apa arti "TX blocking" pada `LoRa.endPacket()`, dan apa yang tidak dapat dikerjakan Arduino selama pengiriman berlangsung?
4. D13 dipakai sebagai SCK sekaligus LED bawaan. Apa akibatnya bila LED bawaan dipakai sebagai indikator komunikasi?
5. Mengapa LoRa pada modul ini disebut LoRa mentah dan bukan LoRaWAN? Sebutkan satu hal yang disediakan LoRaWAN tetapi tidak ada di sini.

## 10 · Challenge (tugas modifikasi)

- **CH-1 — Hitung loss otomatis.** Uraikan nomor urut dari payload di penerima, bandingkan dengan nomor sebelumnya, dan cetak `LOSS: n paket` setiap kali terjadi lompatan.
- **CH-2 — Statistik berjalan.** Tampilkan RSSI minimum, maksimum, dan rata-rata pada penerima setiap 10 paket.
- **CH-3 — Uji jangkauan maksimum.** Turunkan `setTxPower()` bertahap dari 17 dBm ke 2 dBm pada jarak tetap, catat pada daya berapa paket mulai hilang, lalu bandingkan dengan hasil menaikkan SF.
- **CH-4 — Payload lebih besar.** Naikkan panjang payload bertahap sampai 200 byte, ukur pengaruhnya terhadap loss dan waktu kirim. Jelaskan mengapa paket panjang lebih rapuh.

## 11 · Laporan

**Deliverable**

1. Misi dan capaian pembelajaran
2. Dasar teori ringkas (parameter radio, RSSI vs SNR, polling)
3. Konfigurasi — pemetaan pin shield, nilai SF/BW/CR/frekuensi, environment PlatformIO
4. Hasil eksperimen — log serial kedua board (EXP-01…03 beserta checkpoint)
5. Data pengukuran — tabel A, B, dan C pada bagian Pengukuran
6. Analisis dan concept check
7. Challenge — minimal CH-1
8. Kesimpulan yang disusun sendiri berdasarkan hasil pengujian
