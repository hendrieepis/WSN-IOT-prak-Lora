```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
    MODUL 10 — Slotted ALOHA: Giliran, Bukan Untung

  Arduino Uno + Dragino LoRa Shield v1.2 · Advanced
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 10 dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat lanjut, dan menutup arc ALOHA yang dimulai di M08. Misinya mengganti akar masalah, bukan menambalnya lagi: M09 menaikkan keandalan dengan mencoba ulang setelah gagal, tetapi tabrakan itu sendiri tetap terjadi. Modul ini justru **mencegah** tabrakan sejak awal dengan membagi waktu menjadi slot-slot tetap dan memberi tiap node jatah bicaranya sendiri — gagasan yang sama tuanya dengan Pure ALOHA, dikembangkan tak lama setelahnya dengan nama **Slotted ALOHA** (Roberts, 1972).

M05 dan M07 juga mencegah tabrakan, tetapi lewat **master yang memanggil satu per satu** (polling terpusat) — master harus aktif bertanya, node hanya menjawab. Modul ini mencegah tabrakan dengan cara yang berbeda: gateway hanya menyiarkan detak waktu bersama (`SYNC`), dan setiap node **sendiri** yang menghitung kapan gilirannya lalu mengirim tanpa diminta. Perbedaan ini penting — inilah yang membedakan penjadwalan **terpusat aktif** (M05/M07, gateway mengatur giliran tiap saat) dari penjadwalan **terdesentralisasi pasif** (M10, gateway hanya menjaga detak, node yang menghitung sendiri). Dua percobaan pada modul ini, Mode Assigned dan Mode Random, menunjukkan bahwa slot saja tidak otomatis menghapus tabrakan — **kepastian** jadwal itulah yang menghapusnya, dan Mode Random sengaja dibiarkan tanpa kepastian itu untuk membuktikannya.

Prasyaratnya adalah M09 untuk kontrak `NODE=`/`ACK=` dan pola tunggu-ACK-dengan-timeout, serta M05 untuk gagasan bahwa penjadwalan (bukan retry) adalah solusi struktural terhadap tabrakan pada kanal bersama. Yang dibangun di sini adalah siaran waktu bersama (`SYNC=<cycle>`), penghitungan slot di sisi node berdasarkan saat `SYNC` diterima, dan dua mode pemilihan slot yang dibandingkan langsung. **Retry dan random backoff dari M09 sengaja dihapus** — bukan lupa, melainkan digantikan sepenuhnya oleh slot: satu percobaan per siklus, dan siklus berikutnya yang mengambil alih peran "coba lagi".

**Peta modul LoRa**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 05 | Tabrakan dicegah lewat polling terpusat — master memanggil satu per satu |
| 08 | Penjadwalan dilepas total — node kirim bebas, tabrakan senyap diamati |
| 08B | ACK ditempelkan di atas M08 — node tahu SUCCESS/FAILED |
| 09 | Random backoff + retry — kegagalan diperbaiki lewat percobaan ulang |
| **10 (ini)** | **Tabrakan dicegah lagi, tapi terdesentralisasi — SYNC + slot, retry dihapus** |

**Kontrak data lab ini.** Payload data dan format ACK **identik** dengan M08B/M09: `NODE=<id>,SEQ=<n>,R1T=..,R1H=..,R2T=..,R2H=..` dibalas `ACK=<id>,SEQ=<n>`. Yang baru adalah siaran `SYNC=<cycle>` dari gateway di awal tiap siklus, dan **hilangnya** retry: `SEQ` kini naik di **setiap** siklus tanpa peduli hasilnya — persis seperti M08B, bukan seperti M09 yang menahan `SEQ` selama retry berlangsung. Alasannya sederhana: pada modul ini tidak ada lagi retry dalam satu siklus untuk ditahan-tahankan; data yang gagal pada satu slot betul-betul dianggap selesai, dan pembacaan sensor berikutnya sudah menunggu di siklus sesudahnya.

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Menjelaskan mekanisme Slotted ALOHA: waktu dibagi slot tetap, tiap node mengirim hanya di dalam jatah slotnya, dihitung dari referensi waktu bersama (`SYNC`).
2. Membedakan penjadwalan terpusat aktif (M05, master memanggil) dari penjadwalan terdesentralisasi pasif (M10, gateway hanya menyiarkan detak waktu).
3. Menerapkan dan membandingkan dua strategi pemilihan slot: **Assigned** (tetap, Mode B) dan **Random** (diundi tiap siklus, Mode A), serta menjelaskan mengapa hanya salah satunya yang menghapus tabrakan secara struktural.
4. Menjelaskan mengapa vulnerable period Slotted ALOHA hanya **satu kali** waktu udara paket, bukan dua kali seperti Pure ALOHA (M08), dan menghubungkannya dengan throughput teoretis puncak 36,8%.
5. Menjelaskan mengapa retry dan random backoff (M09) tidak lagi diperlukan begitu slot terjadwal dengan pasti, dan kapan kombinasi keduanya (slot + retry) tetap masuk akal.

**Kriteria keberhasilan**

- ☐ Kedua node menerima `SYNC` dan mencetak `[TX] cycle=... slot=...` pada waktu yang konsisten relatif terhadap `SYNC` yang diterima.
- ☐ Pada Mode B (Assigned), `[GAP]` di gateway nihil atau mendekati nihil selama pengujian berjalan wajar.
- ☐ Pada Mode A (Random), `[GAP]` mulai muncul karena kedua node kadang memilih slot yang sama.
- ☐ Gateway mencetak ringkasan `--- Cycle N selesai ---` di akhir tiap siklus dengan statistik per node.

## 3 · Dasar Teori (secukupnya)

| Istilah | Definisi kerja di lab ini |
|---|---|
| Slot | Jendela waktu tetap (`SLOT_DURATION_MS`) tempat satu node boleh mengirim. Modul ini memakai 2 slot per siklus. |
| SYNC | Siaran gateway di awal siklus, menjadi referensi waktu bersama bagi seluruh node. |
| Mode Assigned (B) | Tiap node memakai slot **tetap** (`NODE_ID - 1`). Tidak ada dua node berbagi slot yang sama. |
| Mode Random (A) | Tiap node **mengundi ulang** slotnya setiap siklus. Dua node bisa kebetulan memilih slot yang sama. |
| Vulnerable period (slotted) | Hanya **satu kali** waktu udara paket — sebab paket lain yang boleh mengirim wajib menunggu batas slot berikutnya, tidak bisa mulai di tengah slot yang sedang berjalan. |
| Throughput teoretis | `S = G × e^(-G)`, puncak ≈ 36,8% pada G = 1 — dua kali lipat Pure ALOHA (18,4%) karena vulnerable period lebih sempit. |

**Mengapa vulnerable period Slotted ALOHA setengah dari Pure ALOHA.** Pada M08, paket B dapat mulai kapan saja selama paket A mengudara, sehingga rentang rawan selebar dua kali waktu udara (lihat README M08). Pada Slotted ALOHA, setiap node **wajib** menunggu batas slot berikutnya sebelum boleh mengirim — tidak ada yang bisa "menyela di tengah". Akibatnya, dua paket hanya bertabrakan bila keduanya mulai pada **slot yang sama persis**, bukan pada rentang waktu mana pun yang saling tumpang tindih. Itulah sebabnya throughput puncaknya dua kali lipat Pure ALOHA meski sama-sama tanpa carrier sense.

**Mengapa Mode Assigned menghapus tabrakan, sedangkan Mode Random tidak.** Dengan `SLOT_COUNT` sama dengan jumlah node (2 slot, 2 node) dan tiap node memakai slot tetap yang berbeda, **tidak ada** kombinasi kejadian yang membuat keduanya memilih slot sama — tabrakan antar-node dihapus secara struktural, selama SYNC diterima dengan benar oleh keduanya. Mode Random sengaja meniadakan kepastian itu: tiap siklus, peluang kedua node memilih slot yang sama adalah `1 / SLOT_COUNT` (25% pada modul ini dengan 2 slot) — jauh lebih kecil daripada peluang tabrakan pada Pure ALOHA yang praktis tanpa batas, tetapi tetap bukan nol. Perbandingan ini adalah inti EXP-02.

**Mengapa retry M09 dihapus, bukan digabung begitu saja.** Menggabungkan retry-dengan-backoff ke dalam slot yang sudah terjadwal akan merusak jadwal itu sendiri — backoff acak bisa mendorong pengiriman ulang melampaui batas slot node itu sendiri dan masuk ke slot node lain. Solusi yang benar bukan memaksakan retry ke dalam slot, melainkan membiarkan slot berikutnya (siklus SYNC berikutnya) mengambil alih perannya: data yang gagal di slot ini digantikan pembacaan baru pada siklus berikutnya, tanpa mengganggu slot siapa pun.

**Sekuens yang diamati (Mode B, dua siklus)**

```
   Gateway                          (udara)                    Node 1 / Node 2
     |
  "SYNC=0" ------------------------------------------------->  syncTime dicatat
     |                                                          slot1=0, slot2=1
     |                              (tunggu txTime slot 0)          |
     |   <---------------------- "NODE=1,SEQ=0,..." -------------- Node 1 kirim
  cetak DATA, kirim ACK          "ACK=1,SEQ=0" ---------------->  [OK]
     |                                                              |
     |                              (tunggu txTime slot 1)          |
     |   <---------------------- "NODE=2,SEQ=0,..." -------------- Node 2 kirim
  cetak DATA, kirim ACK          "ACK=2,SEQ=0" ---------------->  [OK]
     |
  --- Cycle 0 selesai --- N1: diterima=1 hilang=0  N2: diterima=1 hilang=0
     |
  "SYNC=1" ---------------------------------------------------> siklus berikutnya
```

## 4 · Topologi

```
                +---------------------------+
                |   Node 1 (slot 0)         |
                |   Arduino Uno + Shield    |
                |   Ruang 1: T, H (dummy)   |
                |   Ruang 2: T, H (dummy)   |
                +-------------+-------------+
                     ^  SYNC        |  DATA di slot 0 + ACK
                     |              v
                      +-------------------+
                      |     Gateway       |
                      | Uno + Shield      |
                      | siarkan SYNC tiap |
                      | awal siklus       |
                      +-------------------+
                     ^  SYNC        |  DATA di slot 1 + ACK
                     |              v
                +-------------+-------------+
                |   Node 2 (slot 1)         |
                |   Arduino Uno + Shield    |
                |   Ruang 1: T, H (dummy)   |
                |   Ruang 2: T, H (dummy)   |
                +---------------------------+
```

| Node | Environment | Peran | Slot (Mode B) | Slot (Mode A) |
|---|---|---|---|---|
| Node 1 | `node1` | Kirim dummy Ruang 1+2 pada slotnya | tetap 0 | diundi tiap siklus |
| Node 2 | `node2` | Kirim dummy Ruang 1+2 pada slotnya | tetap 1 | diundi tiap siklus |
| Gateway | `gateway` | Siarkan SYNC, dengarkan tiap slot, balas ACK | — | — |

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
week10_lora_slotted_aloha/
├── platformio.ini
├── lora_monitor.py        ← dashboard 3-panel live (Gateway/Node1/Node2) + logging CSV
├── logserial.md           ← cuplikan log serial aktual dari pengujian perangkat
└── src/
    ├── node/main.cpp      ← dummy Ruang 1+2, hitung slot dari SYNC (env node1, node2)
    └── gateway/main.cpp   ← siarkan SYNC, terima tiap slot, balas ACK (env gateway)
```

**Monitor dashboard** — `python3 lora_monitor.py` membaca ketiga port sekaligus dan menampilkan panel Gateway/Node 1/Node 2 (diterima/hilang per node, cycle terakhir, RSSI/SNR) di terminal, plus logging CSV otomatis. Butuh `pip install pyserial rich`. Jalankan setelah ketiga board selesai di-*upload*.

**Build & flash** — **gateway lebih dahulu**, supaya kedua node langsung mendapat `SYNC` pertama begitu menyala.

```bash
pio run -d week10_lora_slotted_aloha -e gateway -t upload -t monitor
pio run -d week10_lora_slotted_aloha -e node1   -t upload -t monitor
pio run -d week10_lora_slotted_aloha -e node2   -t upload -t monitor
```

**Pre-flight checklist**

- ☐ Antena terpasang pada ketiga shield.
- ☐ Port ketiga board dicatat lewat `pio device list` (atau `python3 ../tools/deteksi_port.py`) dan diisikan ke `platformio.ini`.
- ☐ Tiga Serial Monitor 115200 baud siap, ketiganya terlihat bersamaan.
- ☐ `SLOT_MODE_RANDOM` bernilai `0` (Mode B) pada **kedua** node untuk EXP-01.
- ☐ `SLOT_COUNT` dan `SLOT_DURATION_MS` sama persis di gateway dan node (bawaan: 2 dan 800).

## 6 · Percobaan

### EXP-01 — Mode B (Assigned Slot): Tabrakan Praktis Hilang

Nyalakan ketiga board dengan `SLOT_MODE_RANDOM 0` (bawaan) pada kedua node, lalu amati sepuluh siklus.

**Expected output — node**

```
=== LoRa SLOTTED ALOHA - NODE 1 ===
Init LoRa ... OK
Freq: 433.00 MHz
Slot: 2 x 800 ms
Mode : B (Assigned Slot) -- tetap di slot 0
Menunggu SYNC pertama dari gateway...

[TX] cycle=0 slot=0 | NODE=1,SEQ=0,R1T=28.4,R1H=63,R2T=24.7,R2H=71
[OK] ACK diterima | OK: 1 | FAIL: 0
```

**Expected output — gateway**

```
[TX] SYNC=0
=== PAKET DITERIMA ===
  Node    : 1
  Slot    : 0
  SEQ     : 0
  ...
  [TX] ACK=1,SEQ=0
=====================

=== PAKET DITERIMA ===
  Node    : 2
  Slot    : 1
  ...
--- Cycle 0 selesai | N1: diterima=1 hilang=0  N2: diterima=1 hilang=0 ---
```

**Data capture** — diukur 90 detik / 56 siklus (bukan 10 siklus; lihat `logserial.md`)

| Parameter | Hasil |
|---|---|
| Diterima gateway per siklus, Node 1 / Node 2 (di akhir Cycle 55) | **56 / 56** (sama persis dengan jumlah siklus) |
| `hilang` (gagal permanen) — Node 1 / Node 2 (data gateway) | **0 / 0** |
| Jumlah `[GAP]` di gateway | **0** |
| Slot yang tercatat gateway untuk Node 1 / Node 2 (konsisten 0 / 1?) | **ya — 111/111 paket, tanpa satu pun ketidakcocokan** |

> **CHECKPOINT terpenuhi.** Pada Mode B, `[GAP]` benar-benar **nihil** selama 56 siklus penuh (90 detik) — nol kehilangan untuk kedua node, jauh lebih bersih dibanding M08/M08B/M09 pada kondisi radio yang sama.

### EXP-02 — Mode A (Random Slot): Tabrakan Bisa Kembali

Ubah `#define SLOT_MODE_RANDOM 0` menjadi `1` pada **kedua** node di `src/node/main.cpp`, unggah ulang keduanya, lalu amati sepuluh siklus.

**Data capture**

| Parameter | Mode B (EXP-01) | Mode A (EXP-02) |
|---|---|---|
| Jumlah `[GAP]` per 10 siklus | | |
| Peluang tabrakan teoretis per siklus (1/SLOT_COUNT) | 0% (terjamin beda slot) | 25% |
| Slot yang dipilih Node 1 pada 10 siklus berturut-turut | tetap 0 | acak, catat urutannya |
| Slot yang dipilih Node 2 pada 10 siklus berturut-turut | tetap 1 | acak, catat urutannya |

**Buka abstraksinya** — di `src/node/main.cpp`, `waitForSync()` membaca **setiap** paket yang tiba sebelum memutuskan apakah itu `SYNC=` atau bukan, termasuk paket `DATA`/`ACK` milik node lain yang kebetulan masih terdengar. Jelaskan mengapa filter ini penting pada radio LoRa yang tidak beralamat, lalu telusuri: apa yang terjadi bila `waitForSync()` langsung menganggap paket **pertama** yang tiba sebagai SYNC tanpa memeriksa isinya?

> **CHECKPOINT** — Pada Mode A, `[GAP]` harus mulai muncul (walau tidak di setiap siklus), berbeda nyata dari Mode B. Bila jumlahnya sama persis dengan Mode B, periksa apakah kedua node benar-benar sudah ter-flash ulang dengan `SLOT_MODE_RANDOM=1`.

### EXP-03 — Slot Observed vs Assigned

Bandingkan kolom `Slot` yang dicetak gateway dengan slot yang seharusnya (0 untuk Node 1, 1 untuk Node 2 pada Mode B).

**Data capture**

| Parameter | Hasil |
|---|---|
| Apakah `Slot` yang tercatat gateway selalu cocok dengan slot yang di-assign (Mode B)? | **ya, 111/111 paket** (0 di Node 1, 1 di Node 2, tanpa kecuali) |
| Durasi rata-rata satu siklus (dari `Cycle 0 selesai` s.d. `Cycle 55 selesai`) | **≈1633 ms** — dekat teori (`SLOT_COUNT × SLOT_DURATION_MS` = 1600 ms), selisih ~33 ms adalah overhead pemrosesan gateway |
| Apakah durasi siklus stabil dari siklus ke siklus? | **ya** — 56 siklus berturut-turut tanpa pelebaran nyata dalam jendela 90 detik ini |

> **CHECKPOINT terpenuhi.** `Slot` yang tercatat gateway selalu cocok dengan assignment (Node 1 → 0, Node 2 → 1), dan durasi siklus stabil sepanjang sesi.

### Verifikasi hardware

**Diuji di perangkat pada 2026-08-22** — 3× Arduino Uno asli + Dragino LoRa Shield v1.2 (gateway + node1 + node2, port `/dev/ttyACM0/1/2`). Build dan upload ketiga environment sukses tanpa modifikasi kode. EXP-01 dan EXP-03 dijalankan (90 detik / 56 siklus) dan datanya nyata — lihat `logserial.md`: `SLOT_DURATION_MS=800` bawaan terbukti cukup lapang di kondisi nyata (nol `[GAP]`, nol `hilang`, slot selalu tepat). EXP-02 (Mode A / Random Slot, `SLOT_MODE_RANDOM=1`) **belum dijalankan** pada sesi ini — memerlukan mengubah kode dan unggah ulang kedua node, diserahkan sebagai latihan praktikum.

## 7 · Pengukuran

**A. Mode B vs Mode A** (90 detik / 56 siklus untuk Mode B)

| Mode | Diterima gateway Node 1 | Hilang Node 1 | Diterima gateway Node 2 | Hilang Node 2 | `[GAP]` total (gateway) |
|---|---|---|---|---|---|
| B (Assigned) | 56 | 0 | 56 | 0 | 0 |
| A (Random) | *(belum diuji — ubah `SLOT_MODE_RANDOM` ke 1 dan unggah ulang kedua node)* | | | | |

**B. Distribusi slot Mode A (20 siklus)**

| Slot terpilih | Jumlah — Node 1 | Jumlah — Node 2 | Jumlah siklus keduanya sama (tabrakan berpotensi) |
|---|---|---|---|
| 0 | *(belum diuji — EXP-02)* | | |
| 1 | | | |

**C. Slot observed vs assigned (Mode B, 10 siklus)**

| Siklus | Slot Node 1 (assigned=0) | Slot Node 2 (assigned=1) | Cocok? |
|---|---|---|---|
| 0 | | | |
| ... | | | |

## 8 · Analisis

1. Dari tabel A, bandingkan tingkat keberhasilan Mode B dan Mode A. Apakah selisihnya sesuai dengan peluang tabrakan teoretis 25% pada Mode A?
2. Dari tabel B, hitung proporsi siklus yang kedua node kebetulan memilih slot sama, lalu bandingkan dengan `1/SLOT_COUNT` yang diprediksi teori.
3. Bandingkan `[GAP]` Mode A modul ini dengan `[GAP]` M08 (Pure ALOHA) pada kepadatan kirim yang sebanding. Jelaskan mengapa Slotted ALOHA — bahkan pada Mode Random — tetap menghasilkan tabrakan yang lebih jarang.
4. Modul ini menghapus retry M09 sepenuhnya. Hitung dari data Anda: pada Mode B, apakah keandalan yang dicapai tanpa retry ini sama atau lebih baik daripada M09 (dengan retry) pada kondisi kanal yang sebanding? Jelaskan.
5. Rancang, tanpa menulis kodenya, cara menambah node ketiga pada Mode B tanpa membuatnya berbagi slot dengan Node 1 atau Node 2. Apa yang harus berubah pada `SLOT_COUNT`, dan apa akibatnya terhadap panjang satu siklus penuh?

## 9 · Concept Check

1. Apa bedanya penjadwalan M05 (master memanggil) dengan penjadwalan M10 (gateway hanya menyiarkan SYNC)?
2. Mengapa vulnerable period Slotted ALOHA hanya satu kali waktu udara, sedangkan Pure ALOHA dua kali?
3. Mengapa Mode Assigned menghapus tabrakan struktural, sedangkan Mode Random tidak — walau keduanya sama-sama memakai slot?
4. Mengapa retry dan random backoff M09 dihapus pada modul ini, bukan digabungkan begitu saja ke dalam slot?
5. Apa yang terjadi pada seluruh sistem bila SYNC dari gateway hilang di jalan pada satu siklus?

## 10 · Challenge (tugas modifikasi)

- **CH-1 — Node ketiga.** Tambahkan environment `node3`, naikkan `SLOT_COUNT` menjadi 3 pada gateway dan ketiga node, lalu ukur ulang tabel A/B pada Mode B dan Mode A dengan tiga node.
- **CH-2 — Backoff hanya untuk Mode Random.** Tambahkan random backoff **kecil** (dalam batas satu slot, bukan lintas-slot) khusus untuk Mode A: bila ACK tidak diterima, node mengundi ulang slot untuk siklus berikutnya alih-alih memakai slot terakhir yang gagal. Bandingkan hasilnya dengan Mode A tanpa strategi ini.
- **CH-3 — Deteksi drift.** Tambahkan pencatatan selisih waktu kedatangan tiap paket terhadap awal slot yang diharapkan di gateway, lalu jalankan modul selama beberapa menit untuk melihat apakah selisih itu melebar seiring waktu antar-SYNC.
- **CH-4 — SLOT_COUNT lebih besar dari jumlah node.** Ubah `SLOT_COUNT` menjadi 4 sementara jumlah node tetap 2 (slot 2 dan 3 menganggur), lalu jelaskan efeknya terhadap panjang siklus dan throughput dibanding `SLOT_COUNT=2`.

## 11 · Laporan

**Deliverable**

1. Misi dan capaian pembelajaran
2. Dasar teori ringkas (slot, SYNC, vulnerable period slotted vs pure, Mode Assigned vs Random)
3. Konfigurasi — `SLOT_COUNT`, `SLOT_DURATION_MS`, `SLOT_GUARD_MS`, kontrak `SYNC=`/`NODE=`/`ACK=`
4. Hasil eksperimen — log serial ketiga board (EXP-01…03 beserta checkpoint)
5. Data pengukuran — tabel A, B, C pada bagian Pengukuran
6. Analisis dan concept check
7. Challenge — minimal CH-1
8. Kesimpulan yang disusun sendiri: rangkuman seluruh arc M08→M10 — apa yang diperbaiki tiap modul, dan pilihan mana (retry vs slot) yang lebih tepat untuk skenario nyata seperti apa
