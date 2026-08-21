```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
      MODUL 08B — Pure ALOHA + ACK: Kini Tahu

  Arduino Uno + Dragino LoRa Shield v1.2 · Intermediate
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 08B dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat menengah, dan **hanya** pengembangan dari M08 — bukan modul berdiri sendiri. Misinya menjawab satu pertanyaan yang M08 sengaja dibiarkan terbuka: **bagaimana node tahu paketnya diterima?** Jawabannya adalah mekanisme paling tua untuk itu, ACK, ditempelkan tepat di atas kode M08 tanpa mengubah cara data dibangkitkan maupun kapan node boleh mengirim.

M08 menunjukkan bahwa tabrakan pada Pure ALOHA bersifat senyap — kedua sisi sama-sama tidak sadar. Modul ini menutup separuh dari kebutaan itu: node pengirim kini menunggu balasan `ACK=<id>,SEQ=<n>` dan mencatat `[OK]` atau `[FAIL]` secara eksplisit. Yang **belum** dikerjakan modul ini secara sengaja adalah kirim ulang otomatis — begitu `[FAIL]` tercatat, node tetap lanjut ke data berikutnya. Retry, timeout adaptif, dan random backoff baru datang di M09, sehingga peningkatan setiap pertemuan tetap dapat diukur satu-per-satu, bukan tercampur dalam satu lompatan besar.

Prasyaratnya adalah M08 untuk payload dua ruangan dan pembangkitan dummy, serta M04 untuk pola tunggu-ACK-dengan-timeout dan pencocokan nomor urut. Yang ditambahkan di sini adalah balasan ACK dari gateway yang membawa `NODE` **dan** `SEQ` sekaligus (M04 hanya membawa nomor urut, sebab modulnya cuma satu pasang board — di sini gateway melayani dua node, sehingga ACK wajib menyebut untuk siapa balasan itu ditujukan), serta statistik OK/FAIL berjalan di sisi node. Kontrak ACK ini dipakai lagi apa adanya di M09, hanya ditambah logika retry di atasnya.

**Peta modul LoRa**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 04 | Satu pasang board — setiap kirim diketahui hasilnya lewat ACK bernomor |
| 08 | Penjadwalan dilepas — node kirim bebas, tabrakan senyap diamati |
| **08B (ini)** | **ACK ditempelkan di atas M08 — node tahu SUCCESS/FAILED, belum ada retry** |
| 09 | Tambah timeout adaptif, random backoff, dan retry otomatis di atas M08B |
| 10 | Tambah SYNC dan slot waktu — tabrakan dihindari lewat penjadwalan terdesentralisasi |

**Kontrak data lab ini.** Payload data **identik** dengan M08: `NODE=<id>,SEQ=<n>,R1T=<suhu>,R1H=<lembab>,R2T=<suhu>,R2H=<lembab>`. Yang baru hanyalah balasan gateway, `ACK=<id>,SEQ=<n>` — dua field, karena gateway melayani lebih dari satu node dan ACK yang hanya membawa `SEQ` (seperti M04) berisiko dianggap milik node lain yang kebetulan memakai nomor urut sama. Node menolak ACK yang `id` atau `SEQ`-nya tidak cocok persis, mengikuti prinsip pencocokan permintaan-balasan dari M04.

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Menjelaskan mengapa ACK pada topologi banyak-node harus membawa identitas pengirim, bukan sekadar nomor urut seperti pada M04.
2. Menerapkan penungguan ACK berbatas waktu tanpa memblokir interrupt, memakai pola yang sama dengan M04.
3. Membedakan kegagalan yang **diketahui** (M08B, lewat `[FAIL]`) dari kegagalan yang **senyap** (M08, lewat lompatan `SEQ`), dan menjelaskan mengapa keduanya seharusnya menghasilkan angka yang mirip pada kondisi kanal yang sama.
4. Mengukur tingkat keberhasilan (`OK / (OK+FAIL) × 100%`) dua node yang berbagi satu kanal, dan membandingkannya dengan tingkat keberhasilan satu pasang board pada M04.
5. Menjelaskan mengapa modul ini **belum** mengirim ulang paket yang gagal, dan risiko apa yang muncul bila retry ditambahkan sembarangan tanpa mempertimbangkan duplikasi.

**Kriteria keberhasilan**

- ☐ Kedua node mencetak `[OK]` atau `[FAIL]` setelah setiap pengiriman, tidak pernah membeku menunggu ACK.
- ☐ Gateway membalas **setiap** paket data valid dengan ACK yang menyebut `NODE` dan `SEQ` yang benar.
- ☐ Statistik `diterima` (gateway) dan `OK` (node) pada node yang sama saling mendekati pada jarak dekat.
- ☐ `[GAP]` di gateway dan `[FAIL]` di node sama-sama meningkat ketika interval kirim dipersempit (EXP-02 M08 masih berlaku di sini).

## 3 · Dasar Teori (secukupnya)

| Istilah | Definisi kerja di lab ini |
|---|---|
| ACK beralamat | Balasan yang menyebut **untuk siapa** ia ditujukan (`ACK=<id>,SEQ=<n>`), diperlukan begitu gateway melayani lebih dari satu pengirim. |
| SUCCESS / FAILED | Hasil satu siklus kirim-tunggu-ACK di sisi node: `[OK]` bila ACK yang sesuai tiba sebelum timeout, `[FAIL]` bila tidak. |
| Kegagalan diketahui vs senyap | M08B membuat kegagalan **diketahui node** lewat timeout; kegagalan tetap **senyap bagi gateway** karena paket yang bertabrakan tidak pernah tiba untuk diketahui apa pun. |
| Retry (belum ada di sini) | Mengirim ulang paket yang gagal. Sengaja ditunda ke M09 agar efeknya (dan risiko duplikasi) dapat diukur terpisah. |
| Overhead ACK | Setiap paket data kini diikuti satu paket ACK dan satu jendela tunggu — menambah waktu udara total dibanding M08. |

**Mengapa ACK di sini harus menyebut `NODE`, sedangkan M04 cukup `ACK:n`.** M04 hanya punya satu pasang board, sehingga nomor urut saja sudah cukup unik untuk mencocokkan balasan dengan permintaan. Begitu gateway melayani dua node sekaligus, dua kondisi rawan bisa muncul: (a) `SEQ` kedua node kebetulan bernilai sama di waktu yang berdekatan, dan (b) ACK milik Node 1 terdengar oleh Node 2 karena LoRa mentah tidak memiliki alamat radio. Menyisipkan `NODE` ke dalam ACK menutup keduanya — node menolak ACK yang `NODE`-nya bukan miliknya, persis seperti slave M05 menolak `POLL` yang bukan nomornya.

**Mengapa belum ada retry.** Menambahkan retry sekarang akan mencampur dua pertanyaan berbeda dalam satu percobaan: "apakah node tahu paketnya gagal?" (pertanyaan M08B) dan "apa yang terjadi kalau node mencoba lagi?" (pertanyaan M09, lengkap dengan risiko gateway menerima data yang sama dua kali). Memisahkan keduanya membuat setiap pertemuan mengukur **satu** variabel baru.

**Sekuens yang diamati**

```
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
```

## 4 · Topologi

```
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
```

| Node | Environment | Peran | Mekanisme TX/RX | Timeout ACK |
|---|---|---|---|---|
| Node 1 | `node1` | Kirim dummy Ruang 1+2, tunggu ACK | TX blocking + RX interrupt | 2000 ms |
| Node 2 | `node2` | Kirim dummy Ruang 1+2, tunggu ACK | TX blocking + RX interrupt | 2000 ms |
| Gateway | `gateway` | Terima, cetak, balas ACK beralamat | RX interrupt + TX blocking | — |

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
week08b_lora_aloha_ack/
├── platformio.ini
└── src/
    ├── node/main.cpp      ← dummy Ruang 1+2, kirim + tunggu ACK (env node1, node2)
    └── gateway/main.cpp   ← terima, cetak, balas ACK beralamat (env gateway)
```

**Build & flash** — **gateway lebih dahulu**, supaya paket pertama dari node langsung dibalas.

```bash
pio run -d week08b_lora_aloha_ack -e gateway -t upload -t monitor
pio run -d week08b_lora_aloha_ack -e node1   -t upload -t monitor
pio run -d week08b_lora_aloha_ack -e node2   -t upload -t monitor
```

**Pre-flight checklist**

- ☐ Antena terpasang pada ketiga shield.
- ☐ Port ketiga board dicatat lewat `pio device list` (atau `python3 ../tools/deteksi_port.py`) dan diisikan ke `platformio.ini`.
- ☐ Tiga Serial Monitor 115200 baud siap, ketiganya terlihat bersamaan.
- ☐ Penghitung `OK`/`FAIL` pada kedua node diamati sejak baris pertama.

## 6 · Percobaan

### EXP-01 — Siklus ACK Sehat, Dua Node

Nyalakan ketiga board dan amati sepuluh siklus pertama pada kedua node.

**Expected output — node**

```
=== LoRa ALOHA+ACK - NODE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
ACK timeout: 2000 ms
Peran: NODE (ALOHA + ACK) -- masih tanpa retry, lihat M09

[TX] NODE=1,SEQ=0,R1T=28.4,R1H=63,R2T=24.7,R2H=71
[OK] ACK diterima | OK: 1 | FAIL: 0
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
  [TX] ACK=1,SEQ=0
=====================
```

**Data capture**

| Parameter | Hasil |
|---|---|
| `OK`/`FAIL` Node 1 setelah 10 siklus | |
| `OK`/`FAIL` Node 2 setelah 10 siklus | |
| Tingkat keberhasilan (%) kedua node | |
| RSSI/SNR arah DATA vs arah ACK | |

> **CHECKPOINT** — Pada jarak satu meter, `FAIL` harus tetap nol di kedua node selama sepuluh siklus. Bandingkan hasil ini dengan `[GAP]` M08 pada kondisi serupa — keduanya seharusnya sama-sama nihil di jarak dekat.

### EXP-02 — Dibandingkan dengan M08 (Kegagalan Senyap vs Diketahui)

Jalankan M08 dan M08B berturut-turut pada interval kirim yang dipersempit (300–500 ms, seperti EXP-02 M08), lalu bandingkan.

**Data capture**

| Parameter | M08 (Pure ALOHA) | M08B (ALOHA + ACK) |
|---|---|---|
| Cara kegagalan terlihat | `[GAP]` di gateway saja | `[FAIL]` di node + `[GAP]` di gateway |
| Jumlah kegagalan per menit — Node 1 | | |
| Jumlah kegagalan per menit — Node 2 | | |
| Lalu lintas radio tambahan (paket ACK) | — | |

**Buka abstraksinya** — di `src/gateway/main.cpp`, ACK dikirim **setelah** statistik `[GAP]` dicetak, bukan sebelumnya. Jelaskan mengapa urutan ini tidak memengaruhi kebenaran ACK (radio tetap half-duplex, hanya satu arah aktif pada satu waktu), lalu telusuri: apa yang terjadi bila `LoRa.receive()` di akhir `loop()` gateway dihapus?

> **CHECKPOINT** — Jumlah `[FAIL]` di node dan jumlah `[GAP]` di gateway untuk node yang sama seharusnya **mendekati**, bukan identik persis — sebab `[FAIL]` juga mencakup kasus DATA sampai tapi ACK-nya yang hilang (lihat Analisis, soal 3).

### EXP-03 — Node Tanpa Retry Tetap Berjalan

Matikan gateway sesaat, amati kedua node, lalu nyalakan kembali.

**Data capture**

| Parameter | Hasil |
|---|---|
| Selang `[TX]` → `[FAIL]` saat gateway mati (detik) | |
| Apakah node melanjutkan ke `SEQ` berikutnya walau gagal? | |
| Berapa siklus sampai `[OK]` kembali muncul setelah gateway hidup? | |

> **CHECKPOINT** — Node harus **tetap melanjutkan** ke `SEQ` berikutnya setelah `[FAIL]`, bukan mengulang `SEQ` yang sama. Perilaku "coba lagi" baru boleh muncul di M09 — di modul ini, `[FAIL]` berarti data hilang permanen.

### Verifikasi hardware

Modul ini **belum diuji ulang di perangkat keras** pada revisi ini. Pola tunggu-ACK-dengan-timeout mengikuti M04 yang sudah terverifikasi, dan payload dua ruangan mengikuti M08. Tabel Pengukuran dan sel "Verifikasi hardware" dibiarkan kosong untuk diisi lewat pengujian langsung.

## 7 · Pengukuran

**A. Tingkat keberhasilan per node**

| Node | OK | FAIL | Keberhasilan (%) | RSSI rata-rata (dBm) |
|---|---|---|---|---|
| Node 1 | | | | |
| Node 2 | | | | |

**B. Ketidaksepakatan node vs gateway** (lihat Analisis soal 3)

| Node | `OK` di node | `diterima` di gateway | Selisih | Tafsiran |
|---|---|---|---|---|
| Node 1 | | | | |
| Node 2 | | | | |

**C. M08 vs M08B pada interval kirim sama**

| Interval kirim (ms) | `[GAP]` M08 (per menit) | `[FAIL]` M08B (per menit) |
|---|---|---|
| 2000–5000 (bawaan) | | |
| 300–500 | | |

## 8 · Analisis

1. Bandingkan tabel A dengan tingkat keberhasilan M04 (satu pasang board). Jelaskan mengapa dua node yang berbagi kanal cenderung menghasilkan tingkat keberhasilan yang lebih rendah pada beban kirim yang sama.
2. Dari tabel C, apakah `[FAIL]` M08B selalu lebih besar atau sama dengan `[GAP]` M08 pada interval yang sama? Jelaskan mengapa secara teori seharusnya begitu.
3. Tabel B dapat menunjukkan `diterima` di gateway lebih besar daripada `OK` di node untuk node yang sama. Jelaskan mekanisme yang membuat itu mungkin — kaitkan dengan arah mana (DATA atau ACK) yang hilang.
4. Modul ini menambah satu paket ACK untuk setiap DATA dibanding M08. Hitung tambahan lalu lintas radio dalam persen, lalu jelaskan mengapa tambahan itu tidak menaikkan *jumlah* tabrakan DATA antar-node secara langsung, meski menambah total waktu kanal terpakai.
5. Rancang, tanpa menulis kodenya, bagaimana M09 seharusnya membedakan retry dari kiriman baru di sisi gateway — mengapa `SEQ` yang sama harus **tidak** dihitung dua kali sebagai data baru?

## 9 · Concept Check

1. Mengapa ACK pada modul ini harus menyebut `NODE`, sedangkan ACK M04 cukup nomor urut saja?
2. Apa bedanya kegagalan yang "diketahui" (M08B) dengan kegagalan yang "senyap" (M08)? Sisi mana yang mengetahuinya masing-masing?
3. Mengapa `[FAIL]` tidak lantas berarti gateway tidak menerima apa-apa?
4. Mengapa modul ini sengaja belum mengirim ulang paket yang gagal?
5. Apa risiko yang harus diantisipasi **sebelum** retry ditambahkan di M09?

## 10 · Challenge (tugas modifikasi)

- **CH-1 — Persentase langsung.** Tampilkan tingkat keberhasilan berjalan (`OK / (OK+FAIL) × 100%`) di setiap baris statistik node, seperti CH-2 pada M04.
- **CH-2 — RSSI di ACK.** Sisipkan RSSI yang diterima gateway ke dalam ACK (`ACK=1,SEQ=5,RSSI=-45`), sehingga node mengetahui kualitas tautan dari sisi gateway tanpa paket tambahan.
- **CH-3 — Bandingkan overhead.** Ukur total waktu kanal terpakai (waktu udara DATA + waktu udara ACK + waktu tunggu) per siklus sukses, lalu bandingkan dengan waktu satu siklus M08 (tanpa ACK sama sekali).
- **CH-4 — Tiga node.** Tambahkan environment `node3`, sesuaikan `NODE_COUNT` di gateway, dan amati apakah tingkat keberhasilan turun ketika jumlah node bertambah pada interval kirim yang sama.

## 11 · Laporan

**Deliverable**

1. Misi dan capaian pembelajaran
2. Dasar teori ringkas (ACK beralamat, kegagalan diketahui vs senyap, overhead ACK)
3. Konfigurasi — format `NODE=...`/`ACK=...`, nilai `ACK_TIMEOUT`, parameter radio
4. Hasil eksperimen — log serial ketiga board (EXP-01…03 beserta checkpoint)
5. Data pengukuran — tabel A, B, C pada bagian Pengukuran
6. Analisis dan concept check
7. Challenge — minimal CH-1
8. Kesimpulan yang disusun sendiri, khususnya mengenai apa yang sudah diketahui sekarang dibanding M08, dan apa yang masih belum (retry — lihat M09)
