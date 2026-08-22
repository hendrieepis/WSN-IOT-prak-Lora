```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
        MODUL 08 — Pure ALOHA: Bebas Bicara

  Arduino Uno + Dragino LoRa Shield v1.2 · Intermediate
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 08 dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat menengah. Misinya membalik total pelajaran M05: alih-alih menjadwalkan siapa yang boleh bicara, modul ini justru **melepas** seluruh penjadwalan dan membiarkan setiap node mengirim data kapan pun ia mau. Sistemnya sederhana — dua node dan satu gateway — tetapi pertanyaannya tajam: **apa yang terjadi kalau semua node bebas mengirim tanpa koordinasi sama sekali?**

M05 dan M07 menghabiskan seluruh usahanya menghindari tabrakan lewat penjadwalan terpusat. Modul ini sengaja mundur satu langkah untuk **menunjukkan** tabrakan itu, bukan menghindarinya — sebab protokol paling tua dalam sejarah jaringan paket radio, ALOHAnet (Universitas Hawaii, 1971), justru dimulai dari titik ini: kirim saja, dan terima risikonya. Memahami kegagalan protokol paling sederhana ini adalah prasyarat untuk menghargai setiap lapisan yang ditambahkan sesudahnya — ACK pada M08B, retry dengan backoff pada M09, dan penjadwalan slot pada M10.

Prasyaratnya adalah M01 untuk format payload dan penghitungan loss lewat nomor urut, serta M04 untuk pembacaan RSSI/SNR per paket. Yang dibangun di sini adalah pembangkitan data dummy multi-sensor (suhu & kelembaban, dua ruangan per node), pengiriman tanpa koordinasi kanal (tanpa *carrier sense*, tanpa ACK, tanpa retry), dan deteksi kehilangan lewat lompatan nomor urut di sisi gateway. Payload dan pola nomor urut ini dipakai lagi persis di M08B, M09, dan M10 — hanya lapisan kendalinya yang bertambah.

**Peta modul LoRa**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 05 | Banyak node — satu master menjadwalkan giliran bicara (polling terpusat) |
| 07 | Master pindah ke Raspberry Pi, penjadwalan tetap sama |
| **08 (ini)** | **Penjadwalan dilepas — node kirim bebas, tabrakan diamati apa adanya** |
| 08B | Tambah ACK di atas M08 — node tahu apakah paketnya sampai |
| 09 | Tambah timeout, random backoff, dan retry di atas M08B |
| 10 | Tambah SYNC dan slot waktu — collision dihindari lewat penjadwalan terdesentralisasi |

**Kontrak data lab ini.** Setiap node mengirim satu paket berisi **dua ruangan sekaligus**: `NODE=<id>,SEQ=<n>,R1T=<suhu>,R1H=<lembab>,R2T=<suhu>,R2H=<lembab>`. Bentuk `KEY=VALUE` dipisah koma dipilih alih-alih format multi-baris (`NODE_ID=1\nROOM1_TEMP=...`) yang sering dipakai pada contoh IoT berbasis teks — pada AVR dengan RAM 2 KB dan payload LoRa yang dibaca byte demi byte, satu baris tunggal jauh lebih murah untuk di-parse dengan `indexOf`/`substring` tanpa risiko pemisahan baris yang keliru. Nomor urut `SEQ` naik di setiap pengiriman node, **tanpa** kaitan dengan ada-tidaknya balasan — sebab pada Pure ALOHA memang tidak ada balasan. Gateway memakai lompatan pada `SEQ` untuk memperkirakan berapa paket yang hilang, gagasan yang sama dengan penghitungan loss `Hello LoRa #n` pada M01.

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Menjelaskan mekanisme Pure ALOHA: kirim tanpa dengar-dahulu (*no carrier sense*), tanpa ACK, tanpa retry.
2. Membangkitkan data dummy multi-sensor (dua besaran, dua ruangan) dan mengemasnya dalam satu payload ringkas.
3. Menunjukkan secara empiris bahwa dua node yang mengirim bebas pada kanal yang sama dapat bertabrakan, dan menjelaskan mengapa tabrakan itu **tidak muncul sebagai pesan galat** di kedua sisi.
4. Memakai lompatan nomor urut sebagai alat ukur kehilangan paket tanpa perlu balasan apa pun dari penerima.
5. Menghitung *throughput* efektif Pure ALOHA dan membandingkannya dengan hasil teoretis (puncak ~18,4% pada beban G=0,5).

**Kriteria keberhasilan**

- ☐ Kedua node mengirim data dummy dua ruangan secara mandiri, dengan interval acak yang berbeda satu sama lain.
- ☐ Gateway mencetak setiap paket yang diterima lengkap dengan RSSI, SNR, dan isi kedua ruangan.
- ☐ Ketika interval pengiriman dipersempit, gateway mencatat kemunculan `[GAP]` — tanda tabrakan/kehilangan mulai terjadi.
- ☐ Statistik `diterima` dan `perkiraan hilang` per node terpisah dan bertambah wajar seiring waktu.

## 3 · Dasar Teori (secukupnya)

| Istilah | Definisi kerja di lab ini |
|---|---|
| Pure ALOHA | Protokol akses kanal paling sederhana: kirim kapan saja data siap, tanpa mendengarkan kanal lebih dulu. |
| Tabrakan (collision) | Dua paket menempati udara pada waktu yang tumpang tindih sehingga radio penerima tidak dapat mendekode keduanya. |
| Kegagalan senyap | Paket yang bertabrakan tidak pernah lolos `parsePacket()` di penerima — tidak ada galat, hanya ketiadaan. |
| Vulnerable period | Rentang waktu selebar **dua kali** waktu udara satu paket, tempat paket lain yang mulai mengirim akan menabrak paket yang sedang berjalan. |
| Throughput teoretis | `S = G × e^(-2G)`, puncak ≈ 18,4% pada G = 0,5 — jauh di bawah Slotted ALOHA (M10) yang mencapai 36,8%. |
| Nomor urut sebagai pengganti ACK | Tanpa balasan, satu-satunya cara mengetahui ada paket hilang adalah melihat lompatan pada `SEQ` di penerima. |

**Mengapa vulnerable period-nya dua kali waktu udara, bukan satu kali.** Paket A yang sedang mengudara akan tertabrak oleh paket B yang mulai mengirim **kapan saja** selama durasi transmisi A itu sendiri (B mulai di tengah A), maupun oleh B yang sudah mulai lebih dulu dan masih berlangsung ketika A mulai (A mulai di tengah B). Kedua kemungkinan itu menjumlahkan rentang rawan menjadi dua kali waktu udara satu paket — inilah yang membuat Pure ALOHA hanya mencapai separuh throughput Slotted ALOHA, meski keduanya sama-sama tanpa carrier sense.

**Mengapa modul ini tidak memakai ACK sama sekali.** Menambahkan ACK sekarang akan mengaburkan pelajaran utamanya: bahwa kegagalan pada kanal bersama itu **nyata dan senyap** sebelum ada mekanisme apa pun yang mendeteksinya. M08B menambahkan ACK persis di atas kode ini, sehingga perbandingan before/after menjadi jelas — bukan dibangun dari nol lagi.

**Sekuens yang diamati (kasus tabrakan)**

```
   Node 1                      (udara)                      Gateway
     |
  "NODE=1,SEQ=5,..." ------------------------------------->  tiba, dicetak
     |                                                             |
                    Node 2                                        |
                      |                                            |
                   "NODE=2,SEQ=8,..." ------X (tabrakan)---->  TIDAK tiba
                      |                                            |
     |  (Node 1 tidak tahu, tidak menunggu apa pun)                |
     |  (Node 2 tidak tahu, tidak menunggu apa pun)                |
                                                        SEQ Node 2 berikutnya
                                                        meloncat -> [GAP]
```

## 4 · Topologi

```
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
```

| Node | Environment | Peran | Mekanisme TX/RX | Interval kirim |
|---|---|---|---|---|
| Node 1 | `node1` | Bangkitkan & kirim dummy Ruang 1+2 | TX blocking, tanpa RX | acak 2000–5000 ms |
| Node 2 | `node2` | Bangkitkan & kirim dummy Ruang 1+2 | TX blocking, tanpa RX | acak 2000–5000 ms |
| Gateway | `gateway` | Terima & cetak dari kedua node | Interrupt DIO0 + flag, tanpa TX | — |

## 5 · Alat yang Digunakan

Modul ini dijalankan di atas Arduino Uno (ATmega328P) dengan Dragino LoRa Shield v1.2 (SX1276), memakai PlatformIO dan library LoRa karya sandeepmistry.

| No | Peralatan | Spesifikasi | Jumlah |
|---|---|---|---|
| 1 | Arduino Uno | ATmega328P | 3 |
| 2 | Dragino LoRa Shield | v1.2, SX1276, 433 MHz | 3 |
| 3 | Antena SMA | **wajib terpasang sebelum diberi daya** | 3 |
| 4 | Kabel USB tipe B | kabel data | 3 |

**Struktur proyek**

```
week08a_lora_pure_aloha/
├── platformio.ini
├── lora_monitor.py        ← dashboard 3-panel live (Gateway/Node1/Node2) + logging CSV
├── logserial.md           ← cuplikan log serial aktual dari pengujian perangkat
└── src/
    ├── node/main.cpp      ← dummy Ruang 1+2, kirim bebas (env node1, node2)
    └── gateway/main.cpp   ← terima & cetak, deteksi gap SEQ (env gateway)
```

**Monitor dashboard** — `python3 lora_monitor.py` membaca ketiga port sekaligus dan menampilkan panel Gateway/Node 1/Node 2 (statistik diterima, RSSI/SNR, deteksi `[GAP]`) di terminal, plus logging CSV otomatis. Butuh `pip install pyserial rich`. Jalankan setelah ketiga board selesai di-*upload*.

**Build & flash** — **gateway lebih dahulu**, supaya paket pertama dari node langsung tertangkap.

```bash
pio run -d week08_lora_pure_aloha -e gateway -t upload -t monitor
pio run -d week08_lora_pure_aloha -e node1   -t upload -t monitor
pio run -d week08_lora_pure_aloha -e node2   -t upload -t monitor
```

**Pre-flight checklist**

- ☐ Antena terpasang pada ketiga shield.
- ☐ Port ketiga board dicatat lewat `pio device list` (atau `python3 ../tools/deteksi_port.py`) dan diisikan ke `platformio.ini`.
- ☐ Tiga Serial Monitor 115200 baud siap, ketiganya terlihat bersamaan.
- ☐ `NODE_ID` pada `node1`/`node2` sudah benar (dicek dari baris pembuka `NODE 1`/`NODE 2` di Serial Monitor).

## 6 · Percobaan

### EXP-01 — Dua Node Mengirim Bebas

Nyalakan ketiga board dan amati gateway selama beberapa menit tanpa mengubah apa pun.

**Expected output — node**

```
=== LoRa PURE ALOHA - NODE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
Peran: NODE (Pure ALOHA) -- kirim bebas, tanpa ACK, tanpa retry

[TX] NODE=1,SEQ=0,R1T=28.4,R1H=63,R2T=24.7,R2H=71 | total dikirim: 1
```

**Expected output — gateway**

```
=== PAKET DITERIMA ===
  Node    : 1
  SEQ     : 0
  Ruang 1 : 28.4 C, 63 %
  Ruang 2 : 24.7 C, 71 %
  RSSI    : -41.00 dBm
  SNR     : 9.50 dB
  Statistik Node 1: diterima=1 | perkiraan hilang=0
=====================
```

**Data capture** — diukur 90 detik (bukan 5 menit; lihat `logserial.md` untuk cuplikan log dan metodologi rekam)

| Parameter | Hasil |
|---|---|
| Jumlah paket diterima gateway (90 detik) — Node 1 | **27** |
| Jumlah paket diterima gateway (90 detik) — Node 2 | **24** |
| Jumlah `[GAP]` muncul — Node 1 / Node 2 | **0 / 0** |
| RSSI & SNR rata-rata kedua node | Node 1: -45,9 dBm / 10,00 dB — Node 2: -57,9 dBm / 9,79 dB |

> **CHECKPOINT terpenuhi.** Pada jarak dekat dan interval kirim standar (2–5 detik), `[GAP]` **tidak muncul sama sekali** selama 90 detik (51 paket total) — sesuai prediksi teoretis: pada beban rendah, peluang tumpang-tindih dua node sangat kecil meski tanpa carrier-sense. Beda RSSI ±12 dB antar node murni posisi fisik di meja pengujian, bukan indikasi masalah.

### EXP-02 — Memaksa Tabrakan

Perkecil `SEND_INTERVAL_MIN`/`SEND_INTERVAL_MAX` pada **kedua** node menjadi mendekati sama (misalnya 300–500 ms untuk keduanya), unggah ulang, lalu amati gateway.

**Data capture**

| Parameter | Hasil |
|---|---|
| Interval kirim yang dipakai (ms) | |
| Jumlah `[GAP]` per menit — Node 1 / Node 2 | |
| Perkiraan *throughput* gateway (paket diterima / total seharusnya dikirim) | |
| Bandingkan dengan prediksi teoretis Pure ALOHA (~18,4% pada beban puncak) | |

**Buka abstraksinya** — di `src/node/main.cpp`, node **tidak pernah** memanggil `LoRa.receive()` atau menunggu apa pun setelah `endPacket()`. Jelaskan mengapa hal ini membuat node tidak pernah bisa tahu apakah paketnya bertabrakan, lalu telusuri: informasi apa yang **hilang total** dibanding modul ACK (M04, M08B) pada titik ini?

> **CHECKPOINT** — Interval yang dipersempit harus menaikkan jumlah `[GAP]` di gateway secara terlihat. Bila tidak ada perubahan sama sekali, periksa apakah kedua node benar-benar terunggah ulang dengan interval baru.

### EXP-03 — Payload Dua Ruangan

Bandingkan isi payload dua node dan pastikan keduanya membawa data Ruang 1 **dan** Ruang 2 dalam satu paket, bukan dua paket terpisah.

**Data capture**

| Parameter | Hasil |
|---|---|
| Jumlah field dalam satu payload | **6** (`NODE`, `SEQ`, `R1T`, `R1H`, `R2T`, `R2H`) |
| Apakah Ruang 1 dan Ruang 2 selalu tiba bersamaan (satu paket)? | **ya** — tidak pernah terpisah pada 51 paket yang diamati |
| Ukuran payload (jumlah karakter) | **45** (mis. `NODE=1,SEQ=2,R1T=29.8,R1H=59,R2T=25.4,R2H=68`) |

> **CHECKPOINT terpenuhi.** Satu paket selalu membawa **kedua** ruangan sekaligus. Ini yang membuat modul ini lebih hemat lalu lintas radio dibanding mengirim empat paket terpisah (Suhu R1, Lembab R1, Suhu R2, Lembab R2) untuk data yang sama.

### Verifikasi hardware

**Diuji di perangkat pada 2026-08-22** — 3× Arduino Uno asli + Dragino LoRa Shield v1.2 (gateway + node1 + node2, port `/dev/ttyACM0/1/2`, sudah cocok dengan `platformio.ini` bawaan). Build dan upload ketiga environment sukses tanpa modifikasi kode. EXP-01 dan EXP-03 dijalankan dan datanya nyata (lihat tabel di atas serta `logserial.md`). EXP-02 (memaksa tabrakan dengan interval sempit) memerlukan mengubah `SEND_INTERVAL_MIN/MAX` di kode dan unggah ulang kedua node — **belum dijalankan pada sesi verifikasi ini**, diserahkan sebagai latihan praktikum sesuai instruksi modul.

## 7 · Pengukuran

**A. Tingkat kedatangan paket terhadap kepadatan kirim**

| Interval kirim (ms) | Total dikirim (kedua node, 90 detik) | Total diterima gateway | Throughput (%) |
|---|---|---|---|
| 2000–5000 (bawaan) | 51 (27+24, tanpa hilang di jendela rekam) | 51 | ~100 (beban rendah, jauh dari puncak G=0,5) |
| 1000–2000 | *(belum diuji — jalankan EXP-02 dengan interval ini)* | | |
| 300–500 | *(belum diuji — jalankan EXP-02 dengan interval ini)* | | |

**B. RSSI/SNR per node**

| Node | RSSI rata-rata (dBm) | SNR rata-rata (dB) | Jumlah `[GAP]` |
|---|---|---|---|
| Node 1 | -45,9 | 10,00 | 0 |
| Node 2 | -57,9 | 9,79 | 0 |

## 8 · Analisis

1. Dari tabel A, pada interval berapa throughput mulai menurun tajam? Bandingkan pola penurunannya dengan kurva teoretis `S = G × e^(-2G)`.
2. Jelaskan mengapa node yang mengirim tidak pernah tahu paketnya bertabrakan pada modul ini — telusuri baris kode yang membuktikannya.
3. Gateway memperkirakan kehilangan lewat lompatan `SEQ`. Sebutkan satu skenario di mana metode ini **melebih-lebihkan** jumlah paket hilang, dan satu skenario di mana ia **meremehkannya**.
4. Bandingkan jumlah `[GAP]` Node 1 vs Node 2. Bila berbeda jauh padahal intervalnya sama, apa penjelasan yang mungkin?
5. Hitung *vulnerable period* untuk payload modul ini pada SF7/BW125kHz, lalu jelaskan hubungannya dengan interval kirim minimum yang masih aman dari tabrakan berlebihan.

## 9 · Concept Check

1. Apa perbedaan mendasar Pure ALOHA dengan polling terjadwal pada M05?
2. Mengapa vulnerable period Pure ALOHA dua kali lipat waktu udara satu paket, bukan sama dengan waktu udara itu sendiri?
3. Mengapa gateway pada modul ini tidak pernah mengirim balasan apa pun?
4. Apa kelemahan memakai lompatan `SEQ` sebagai satu-satunya alat ukur kehilangan paket?
5. Sebutkan satu keadaan nyata di mana Pure ALOHA (kirim bebas, tanpa koordinasi) tetap menjadi pilihan yang masuk akal walau throughput-nya rendah.

## 10 · Challenge (tugas modifikasi)

- **CH-1 — Hitung throughput otomatis.** Tambahkan penghitung total `SEQ` maksimum yang terlihat per node di gateway, lalu hitung dan cetak persentase throughput setiap 30 detik tanpa perlu dihitung manual dari log.
- **CH-2 — Tiga node.** Tambahkan environment `node3` dan amati apakah `[GAP]` bertambah ketika jumlah node naik dari dua menjadi tiga pada interval kirim yang sama.
- **CH-3 — RSSI di payload.** Sisipkan estimasi RSSI terakhir yang diterima node dari paket node lain (bila node ikut mendengarkan) ke dalam payloadnya sendiri, sebagai langkah awal menuju *carrier sense*.
- **CH-4 — Simulasikan G.** Buat mode di gateway yang menghitung `G` (beban tawar, dalam paket per vulnerable period) dari data yang teramati, lalu bandingkan throughput terukur dengan prediksi `S = G × e^(-2G)`.

## 11 · Laporan

**Deliverable**

1. Misi dan capaian pembelajaran
2. Dasar teori ringkas (Pure ALOHA, vulnerable period, throughput teoretis)
3. Konfigurasi — format payload dua ruangan, interval kirim tiap node, parameter radio
4. Hasil eksperimen — log serial ketiga board (EXP-01…03 beserta checkpoint)
5. Data pengukuran — tabel A dan B pada bagian Pengukuran
6. Analisis dan concept check
7. Challenge — minimal CH-1
8. Kesimpulan yang disusun sendiri, khususnya mengenai harga throughput yang dibayar demi kesederhanaan protokol
