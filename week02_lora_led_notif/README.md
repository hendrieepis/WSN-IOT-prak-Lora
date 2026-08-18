```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
   MODUL 02 — Penerimaan Non-Blocking & Indikator LED

   Arduino Uno + Dragino LoRa Shield v1.2 · Basic
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 02 dirancang untuk dua pertemuan (2 × 50 menit) pada tingkat dasar. Misinya membebaskan `loop()` penerima dari tugas menunggu: paket dikabarkan oleh interrupt, bukan dicari terus-menerus. Sebagai bukti visual bahwa radio benar-benar bekerja, kedua board menyalakan LED saat mengirim dan menerima. Percobaan memakai dua Arduino Uno bershield Dragino LoRa v1.2, diamati melalui dua Serial Monitor pada 9600 baud.

M01 memakai polling: penerima memanggil `parsePacket()` berulang kali, sehingga seluruh waktu prosesor habis untuk bertanya "sudah ada paket belum". Selama `loop()` sibuk mengerjakan hal lain, paket yang tiba akan terlewat. Modul ini memindahkan pemberitahuan ke jalur perangkat keras: pin DIO0 SX1276 menarik interrupt INT0 Arduino begitu paket selesai diterima, dan `loop()` cukup memeriksa sebuah penanda. Pola inilah yang membuat penerima tetap responsif sambil mengerjakan tugas lain — dan menjadi dasar M04, tempat penerima harus menunggu ACK sambil menghitung waktu.

Prasyaratnya adalah M01: inisialisasi SX1276, parameter radio, serta pembacaan RSSI dan SNR. Yang dibangun di sini adalah pemasangan callback `LoRa.onReceive()`, pemakaian variabel `volatile` sebagai jembatan antara ISR dan `loop()`, pemahaman mengapa pekerjaan berat tidak boleh dilakukan di dalam ISR, serta indikator LED yang tidak mengganggu jalur SPI. Semuanya dipakai lagi pada M04 ketika ACK ditunggu dengan batas waktu, dan M05 ketika master menjadwalkan giliran bicara.

**Peta modul LoRa**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 01 | Tautan satu arah terbentuk; RSSI dan SNR terbaca |
| **02 (ini)** | **Penerimaan lewat interrupt — `loop()` tidak lagi menunggu** |
| 03 | Dua arah — kedua board bergantian mengirim dan menerima |
| 04 | Keandalan diukur: ACK, timeout, dan hitungan gagal |
| 05 | Banyak node — satu master menjadwalkan giliran bicara |

**Kontrak data lab ini.** Payload tetap bernomor (`Hello #n`), sama seperti M01, sehingga hasil pengukuran kedua modul dapat dibandingkan langsung. Yang berubah bukan datanya, melainkan **cara penerima mengetahui data itu tiba**.

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Menjelaskan perbedaan polling dan interrupt pada penerimaan paket LoRa, beserta jalur perangkat kerasnya (DIO0 → D2/INT0).
2. Memasang `LoRa.onReceive()` dan `LoRa.receive()` dengan benar, serta menjelaskan mengapa `LoRa.receive()` harus dipanggil ulang setelah sebuah paket diolah.
3. Menjelaskan fungsi kata kunci `volatile` dan akibatnya bila dihilangkan.
4. Menyebutkan pekerjaan yang tidak boleh dilakukan di dalam ISR beserta alasannya.
5. Menjelaskan mengapa LED indikator sebaiknya tidak memakai D13 pada board bershield LoRa.

**Kriteria keberhasilan**

- ☐ Penerima mencetak paket tanpa memanggil `parsePacket()` sama sekali di `loop()`.
- ☐ LED berkedip pada pengirim setiap kali TX selesai, dan pada penerima setiap kali paket tiba.
- ☐ Penerima tetap menerima paket meskipun `loop()` diberi pekerjaan tambahan (EXP-03).
- ☐ Perbedaan perilaku polling dan interrupt dibuktikan dengan data, bukan sekadar dijelaskan.

## 3 · Dasar Teori (secukupnya)

| Istilah | Definisi kerja di lab ini |
|---|---|
| Interrupt | Sinyal perangkat keras yang menghentikan sementara program utama untuk menjalankan fungsi khusus. |
| ISR | *Interrupt Service Routine* — fungsi yang dijalankan saat interrupt terjadi. Harus sangat singkat. |
| DIO0 | Pin keluaran SX1276 yang berubah keadaan saat paket selesai diterima atau dikirim. Tersambung ke D2 (INT0) Arduino. |
| `volatile` | Penanda bagi compiler bahwa sebuah variabel dapat berubah di luar alur program utama, sehingga nilainya tidak boleh disimpan di register. |
| Mode receive kontinu | Keadaan SX1276 setelah `LoRa.receive()`: radio terus mendengarkan tanpa campur tangan prosesor. |
| Flag pattern | Pola baku: ISR hanya menyalakan penanda, seluruh pekerjaan berat dikerjakan `loop()`. |

**Mengapa ISR harus singkat.** Selama ISR berjalan, interrupt lain tertunda dan `millis()` berhenti bertambah pada AVR. Mencetak ke Serial di dalam ISR — operasi yang memakan milidetik — dapat membuat pewaktuan kacau, paket berikutnya terlewat, bahkan program membeku. Karena itu `onReceive()` pada modul ini hanya mengerjakan satu hal: `rxFlag = true`. Pembacaan isi paket, pencetakan, dan penyalaan LED semuanya dikerjakan `loop()` setelah interrupt selesai.

**Mengapa bukan D13 untuk LED.** D13 berbagi jalur dengan SCK, denyut clock SPI menuju SX1276. Setiap kali radio berkomunikasi, LED bawaan ikut berkedip dengan sendirinya, sehingga tidak dapat dipercaya sebagai indikator kejadian. Program ini memakai `LED_BUILTIN` agar dapat langsung dijalankan tanpa komponen tambahan, tetapi untuk indikator yang bersih ganti `LED_PIN` menjadi **D3** dan pasang LED dengan resistor 220 Ω ke GND — hal ini menjadi bagian dari EXP-02.

**Sekuens yang diamati**

```
   Sender                      (udara)                    Receiver
     |                                              LoRa.receive() aktif
  endPacket() ------------------------------------->  paket tiba
  LED nyala 150 ms                                    DIO0 memicu INT0
     |                                                ISR: rxFlag = true
     |                                                     |
  delay(1850)                                         loop(): rxFlag terbaca
     |                                                baca isi, cetak, LED 200 ms
     |                                                LoRa.receive() dipanggil lagi
```

## 4 · Topologi

```
        BOARD #1                                  BOARD #2
  +------------------+                      +------------------+
  |   Arduino Uno    |                      |   Arduino Uno    |
  | + LoRa Shield    |  ~~~~ 920 MHz ~~~~>  | + LoRa Shield    |
  |     SENDER       |     satu arah        |    RECEIVER      |
  | LED 150 ms       |                      | LED 200 ms       |
  | setelah TX       |                      | interrupt DIO0   |
  +------------------+                      +------------------+
     env: sender                              env: receiver
```

| Node | Environment | Peran | Mekanisme RX | LED |
|---|---|---|---|---|
| Sender | `sender` | Pengirim, `Hello #n` tiap 2 detik | — | Kedip 150 ms setelah TX |
| Receiver | `receiver` | Penerima | Interrupt DIO0 + `rxFlag` | Kedip 200 ms saat RX |

## 5 · Alat yang Digunakan

Modul ini dijalankan di atas Arduino Uno (ATmega328P) dengan Dragino LoRa Shield v1.2 (SX1276), memakai PlatformIO dan library LoRa karya sandeepmistry.

| No | Peralatan | Spesifikasi | Jumlah |
|---|---|---|---|
| 1 | Arduino Uno | ATmega328P | 2 |
| 2 | Dragino LoRa Shield | v1.2, SX1276, 920 MHz | 2 |
| 3 | Antena SMA | **wajib terpasang sebelum diberi daya** | 2 |
| 4 | LED + resistor 220 Ω | opsional, untuk indikator bersih di D3 | 2 |
| 5 | Kabel USB tipe B | kabel data | 2 |

**Pin yang dipakai**

| Pin | Fungsi | Keterangan |
|---|---|---|
| D10, D11, D12, D13 | SPI ke SX1276 | NSS, MOSI, MISO, SCK |
| D9 | RST | Reset SX1276 |
| **D2** | **DIO0** | Interrupt RX-done — inti modul ini |
| D13 | LED bawaan | Dipakai program sebagai indikator awal, berbagi jalur dengan SCK |
| **D3** | LED eksternal | Pin bebas yang direkomendasikan untuk indikator bersih |

**Struktur proyek**

```
week02_lora_led_notif/
├── platformio.ini
└── src/
    ├── sender/main.cpp     ← kirim + kedip LED setelah TX
    └── receiver/main.cpp   ← interrupt DIO0, rxFlag, kedip LED saat RX
```

**Build & flash** — penerima lebih dahulu.

```bash
pio run -d week02_lora_led_notif -e receiver -t upload -t monitor
pio run -d week02_lora_led_notif -e sender   -t upload -t monitor
```

**Pre-flight checklist**

- ☐ Antena terpasang pada kedua shield.
- ☐ Port kedua board dicatat lewat `pio device list` dan diisikan ke `platformio.ini`.
- ☐ Dua Serial Monitor 9600 baud siap.
- ☐ Bila memakai LED eksternal: kaki panjang ke D3 lewat resistor 220 Ω, kaki pendek ke GND.

## 6 · Percobaan

### EXP-01 — Penerimaan Tanpa Polling

Unggah kedua firmware dan amati aliran data seperti pada M01.

**Expected output — receiver**

```
=== LoRa RECEIVER (Dragino) ===
Init LoRa ... OK
Freq: 920.00 MHz | BW: 125.00 kHz | SF7
Menunggu paket (non-blocking)...

================================
[RX] Pesan : Hello #5
[RX] RSSI  : -41 dBm
[RX] SNR   : 9.50 dB
================================
```

**Data capture**

| Parameter | Hasil |
|---|---|
| Apakah `parsePacket()` ada di `loop()` penerima? | |
| Nomor urut terakhir sender / receiver | |
| RSSI rata-rata (dBm) | |
| Lama kedip LED penerima (ms) | |

**Buka abstraksinya** — di `src/receiver/main.cpp`, cari fungsi `onReceive()`. Isinya hanya satu baris pemberian nilai. Jawab: mengapa pembacaan `LoRa.available()` dan pencetakan Serial tidak diletakkan di sana padahal itu terasa lebih ringkas? Lalu telusuri di mana `LoRa.receive()` dipanggil untuk kedua kalinya, dan jelaskan apa yang terjadi bila baris itu dihapus.

> **CHECKPOINT** — Penerima mencetak paket **tanpa** satu pun panggilan `parsePacket()` di `loop()`. Bila baris itu masih ada, yang diuji bukan mekanisme interrupt.

### EXP-02 — LED Sebagai Instrumen

Amati LED bawaan (D13) pada kedua board, lalu ganti `LED_PIN` menjadi `3`, pasang LED eksternal, dan bandingkan.

**Data capture**

| Parameter | LED bawaan (D13) | LED eksternal (D3) |
|---|---|---|
| Berkedip saat paket tiba? | | |
| Berkedip juga saat radio diam? | | |
| Dapat dipercaya sebagai indikator kejadian? | | |

> **CHECKPOINT** — LED di D13 berkedip tidak beraturan mengikuti lalu lintas SPI, sedangkan LED di D3 hanya berkedip saat kejadian yang dimaksud. Pengamatan inilah alasan pin indikator dipisahkan dari jalur komunikasi.

### EXP-03 — Bukti Non-Blocking

Tambahkan pekerjaan tiruan pada `loop()` penerima, tepat sebelum pemeriksaan `rxFlag`:

```cpp
  // pekerjaan tiruan: seolah-olah penerima sedang mengolah sensor
  delay(1500);
```

Unggah ulang, amati 2 menit, lalu ulangi percobaan yang sama pada penerima **M01** yang berbasis polling.

**Data capture**

| Firmware | Paket dikirim | Paket diterima | Loss (%) |
|---|---|---|---|
| M02 (interrupt) + `delay(1500)` | | | |
| M01 (polling) + `delay(1500)` | | | |

> **CHECKPOINT** — Penerima M02 tetap menangkap sebagian besar paket meskipun `loop()` sibuk, sedangkan penerima M01 kehilangan hampir semuanya. Selisih inilah nilai sesungguhnya dari mekanisme interrupt. Hapus `delay()` setelah percobaan selesai.

### Verifikasi build (referensi)

```
Environment    Status    Flash
sender         SUCCESS   22.9% (7380 B)
receiver       SUCCESS   24.5% (7916 B)
```

Penerima berbasis interrupt hanya menambah ±600 byte dibanding penerima polling M01 (7312 B) — biaya yang sangat kecil dibanding manfaatnya.

## 7 · Pengukuran

**A. Ketahanan terhadap kesibukan `loop()`** — ulangi EXP-03 dengan beberapa lama pekerjaan tiruan.

| `delay()` pada loop | Loss M01 polling (%) | Loss M02 interrupt (%) |
|---|---|---|
| 0 ms | | |
| 500 ms | | |
| 1500 ms | | |
| 3000 ms | | |

**B. Jarak terhadap kualitas tautan** — untuk dibandingkan langsung dengan tabel A pada M01.

| Jarak | RSSI (dBm) | SNR (dB) | Loss (%) |
|---|---|---|---|
| 1 m | | | |
| 10 m | | | |
| 50 m | | | |

## 8 · Analisis

1. Dari tabel A, pada lama `delay()` berapa perbedaan polling dan interrupt mulai menonjol? Jelaskan mengapa interrupt pun akhirnya ikut kehilangan paket.
2. Mengapa ISR hanya boleh mengubah penanda? Sebutkan dua akibat konkret bila `Serial.println()` dipanggil di dalamnya.
3. Apa yang terjadi bila kata kunci `volatile` dihapus dari `rxFlag`? Jelaskan dari sisi optimasi compiler.
4. Bandingkan hasil tabel B dengan tabel A pada M01. Apakah mekanisme penerimaan memengaruhi jangkauan? Jelaskan alasannya.
5. LED penerima menyala 200 ms dengan `delay()`. Sebutkan kelemahan cara itu, dan pada kondisi apa kelemahannya menjadi nyata.

## 9 · Concept Check

1. Apa perbedaan polling dan interrupt dalam menerima paket?
2. Jalur perangkat keras apa yang menghubungkan SX1276 ke interrupt Arduino, dan lewat pin mana?
3. Mengapa `LoRa.receive()` harus dipanggil lagi setelah sebuah paket selesai diolah?
4. Mengapa `rxFlag` harus `volatile`?
5. Mengapa D13 kurang tepat dijadikan indikator kejadian pada board bershield LoRa?

## 10 · Challenge (tugas modifikasi)

- **CH-1 — LED tanpa `delay()`.** Ganti kedip LED penerima dengan penjadwalan berbasis `millis()`, lalu buktikan dengan EXP-03 bahwa penerima menjadi lebih tahan terhadap paket yang datang beruntun.
- **CH-2 — Dua LED.** Pakai D3 untuk paket diterima dan D4 untuk paket ditolak (misalnya payload yang tidak diawali `Hello`). Jelaskan mengapa penyaringan seperti ini akan diperlukan pada M05.
- **CH-3 — Intensitas mengikuti sinyal.** Kedipkan LED dengan PWM yang terangnya mengikuti RSSI, sehingga kualitas tautan terlihat tanpa membaca Serial Monitor.
- **CH-4 — Hitung paket terlewat.** Uraikan nomor urut dari payload, dan tampilkan jumlah paket yang hilang secara berjalan pada penerima.

## 11 · Laporan

**Deliverable**

1. Misi dan capaian pembelajaran
2. Dasar teori ringkas (interrupt, ISR, `volatile`, mode receive kontinu)
3. Konfigurasi — pin DIO0, pilihan pin LED, parameter radio
4. Hasil eksperimen — log serial kedua board (EXP-01…03 beserta checkpoint), foto atau video LED
5. Data pengukuran — tabel A dan B pada bagian Pengukuran
6. Analisis dan concept check
7. Challenge — minimal CH-1
8. Kesimpulan yang disusun sendiri, khususnya mengenai kapan interrupt sepadan dengan tambahan kerumitannya
