```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
   MODUL 10 — Slot Terjadwal: Slotted ALOHA & TDMA

  Arduino Uno + Dragino LoRa Shield v1.2 · Advanced
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 10 dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat lanjut, dan menutup arc akses kanal yang dimulai di M08. Misinya mengganti akar masalah, bukan menambalnya lagi: M08C menaikkan keandalan dengan mencoba ulang setelah gagal, dan M09 menurunkan peluang tabrakan dengan mendengarkan kanal lebih dahulu — tetapi pada keduanya tabrakan tetap **mungkin** terjadi. Carrier sense pun tidak menjamin apa-apa bila dua node kebetulan mendapati kanal sepi pada saat yang sama, atau bila keduanya tidak saling mendengar. Modul ini justru **mencegah** tabrakan sejak awal dengan membagi waktu menjadi slot-slot tetap dan memberi tiap node jatah bicaranya sendiri — gagasan yang sama tuanya dengan Pure ALOHA, dikembangkan tak lama setelahnya dengan nama **Slotted ALOHA** (Roberts, 1972).

**Modul ini sebenarnya memuat dua protokol, dan namanya berbeda.** Mode Random (A) adalah Slotted ALOHA — lebih tepatnya **Framed Slotted ALOHA**, karena `SYNC` dari gateway membuka satu *frame* berisi `SLOT_COUNT` slot dan tiap node mengundi satu slot di dalamnya (varian yang sama dipakai anti-collision RFID EPC Gen2). Waktu sudah berslot, tetapi node masih **mengundi**, sehingga tabrakan berkurang tanpa pernah hilang. Mode Assigned (B) melangkah satu tingkat lebih jauh dan berhenti menjadi ALOHA sama sekali — begitu tiap node punya slot tetap miliknya sendiri, yang berlaku adalah **TDMA** (Time Division Multiple Access), dan tabrakan hilang secara struktural, bukan berkurang secara statistik. Perbedaan itulah yang diukur di EXP-01 dan EXP-02.

M05 dan M07 juga mencegah tabrakan, tetapi lewat **master yang memanggil satu per satu** (polling terpusat) — master harus aktif bertanya, node hanya menjawab. Modul ini mencegah tabrakan dengan cara yang berbeda: gateway hanya menyiarkan detak waktu bersama (`SYNC`), dan setiap node **sendiri** yang menghitung kapan gilirannya lalu mengirim tanpa diminta. Perbedaan ini penting — inilah yang membedakan penjadwalan **terpusat aktif** (M05/M07, gateway mengatur giliran tiap saat) dari penjadwalan **terdesentralisasi pasif** (M10, gateway hanya menjaga detak, node yang menghitung sendiri). Dua percobaan pada modul ini, Mode Assigned dan Mode Random, menunjukkan bahwa slot saja tidak otomatis menghapus tabrakan — **kepastian** jadwal itulah yang menghapusnya, dan Mode Random sengaja dibiarkan tanpa kepastian itu untuk membuktikannya.

Prasyaratnya adalah M08C untuk kontrak `NODE=`/`ACK=` dan pola tunggu-ACK-dengan-timeout, serta M05 untuk gagasan bahwa penjadwalan (bukan retry) adalah solusi struktural terhadap tabrakan pada kanal bersama. Yang dibangun di sini adalah siaran waktu bersama (`SYNC=<cycle>`), penghitungan slot di sisi node berdasarkan saat `SYNC` diterima, dan dua mode pemilihan slot yang dibandingkan langsung. **Retry dan random backoff dari M08C sengaja dihapus** — bukan lupa, melainkan digantikan sepenuhnya oleh slot: satu percobaan per siklus, dan siklus berikutnya yang mengambil alih peran "coba lagi".

**Peta modul LoRa**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 05 | Tabrakan dicegah lewat polling terpusat — master memanggil satu per satu |
| 08 | Penjadwalan dilepas — node kirim bebas, tabrakan senyap diamati |
| 08B | ACK ditempelkan di atas M08 — node tahu SUCCESS/FAILED, belum ada retry |
| 08C | Random backoff + retry — kegagalan dipulihkan, dan Pure ALOHA menjadi lengkap |
| 09 | Carrier sense — dengar dulu sebelum bicara, tabrakan dihindari sebelum terjadi |
| **10 (ini)** | **Slot waktu bersama — Slotted ALOHA bila slot diundi, TDMA bila slot tetap** |

**Kontrak data lab ini.** Payload data dan format ACK **identik** dengan M08B/M08C: `NODE=<id>,SEQ=<n>,R1T=..,R1H=..,R2T=..,R2H=..` dibalas `ACK=<id>,SEQ=<n>`. Yang baru adalah siaran `SYNC=<cycle>` dari gateway di awal tiap siklus, dan **hilangnya** retry: `SEQ` kini naik di **setiap** siklus tanpa peduli hasilnya — persis seperti M08B, bukan seperti M08C yang menahan `SEQ` selama retry berlangsung. Alasannya sederhana: pada modul ini tidak ada lagi retry dalam satu siklus untuk ditahan-tahankan; data yang gagal pada satu slot betul-betul dianggap selesai, dan pembacaan sensor berikutnya sudah menunggu di siklus sesudahnya.

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Menjelaskan mekanisme slot waktu: waktu dibagi slot tetap, tiap node mengirim hanya di dalam jatah slotnya, dihitung dari referensi waktu bersama (`SYNC`).
2. Membedakan penjadwalan terpusat aktif (M05, master memanggil) dari penjadwalan terdesentralisasi pasif (M10, gateway hanya menyiarkan detak waktu).
3. Menerapkan dan membandingkan dua strategi pemilihan slot: **Assigned** (tetap, Mode B → TDMA) dan **Random** (diundi tiap siklus, Mode A → Slotted ALOHA), serta menjelaskan mengapa hanya salah satunya yang menghapus tabrakan secara struktural.
4. Menjelaskan mengapa vulnerable period Slotted ALOHA hanya **satu kali** waktu udara paket, bukan dua kali seperti Pure ALOHA (M08), dan menghubungkannya dengan throughput teoretis puncak 36,8%.
5. Menjelaskan mengapa retry dan random backoff (M08C) tidak lagi diperlukan begitu slot terjadwal dengan pasti, dan kapan kombinasi keduanya (slot + retry) tetap masuk akal.

**Kriteria keberhasilan**

- ☐ Kedua node menerima `SYNC` dan mencetak `[TX] cycle=... slot=...` pada waktu yang konsisten relatif terhadap `SYNC` yang diterima.
- ☐ Pada Mode A (Random / Slotted ALOHA), `[FAIL]` dan `[GAP]` **muncul**, dan proporsi siklus "slot sama" mendekati `1/SLOT_COUNT`.
- ☐ Pada Mode B (Assigned / TDMA), `[GAP]` nihil dan tiap node konsisten memakai slotnya sendiri.
- ☐ Kedua mode diukur pada sesi yang sama sehingga angkanya dapat dibandingkan langsung.
- ☐ Gateway mencetak ringkasan `--- Cycle N selesai ---` di akhir tiap siklus dengan statistik per node.

## 3 · Dasar Teori (secukupnya)

| Istilah | Definisi kerja di lab ini |
|---|---|
| Slot | Jendela waktu tetap (`SLOT_DURATION_MS`) tempat satu node boleh mengirim. Modul ini memakai 2 slot per siklus. |
| SYNC | Siaran gateway di awal siklus, menjadi referensi waktu bersama bagi seluruh node. |
| Mode Assigned (B) = **TDMA** | Tiap node memakai slot **tetap** (`NODE_ID - 1`). Tidak ada dua node berbagi slot yang sama, sehingga skema ini bukan lagi ALOHA. |
| Mode Random (A) = **Slotted ALOHA** | Tiap node **mengundi ulang** slotnya setiap siklus. Dua node bisa kebetulan memilih slot yang sama — inilah ALOHA berslot yang sesungguhnya. |
| Vulnerable period (slotted) | Hanya **satu kali** waktu udara paket — sebab paket lain yang boleh mengirim wajib menunggu batas slot berikutnya, tidak bisa mulai di tengah slot yang sedang berjalan. |
| Throughput teoretis | `S = G × e^(-G)`, puncak ≈ 36,8% pada G = 1 — dua kali lipat Pure ALOHA (18,4%) karena vulnerable period lebih sempit. |

**Mengapa vulnerable period Slotted ALOHA setengah dari Pure ALOHA.** Pada M08, paket B dapat mulai kapan saja selama paket A mengudara, sehingga rentang rawan selebar dua kali waktu udara (lihat README M08). Pada Slotted ALOHA, setiap node **wajib** menunggu batas slot berikutnya sebelum boleh mengirim — tidak ada yang bisa "menyela di tengah". Akibatnya, dua paket hanya bertabrakan bila keduanya mulai pada **slot yang sama persis**, bukan pada rentang waktu mana pun yang saling tumpang tindih. Itulah sebabnya throughput puncaknya dua kali lipat Pure ALOHA meski sama-sama tanpa carrier sense.

**Satu hal yang tetap hilang di kedua mode: retransmisi.** Slotted ALOHA klasik mengirim ulang paket yang bertabrakan pada slot berikutnya; modul ini sengaja menghapus retry M08C sepenuhnya, sehingga paket yang gagal betul-betul hilang dan digantikan pembacaan baru pada siklus berikutnya. Jadi Mode A adalah Slotted ALOHA **tanpa** pemulihan — sejajar dengan M08 yang ALOHA tanpa umpan balik. Menambahkan retry ke dalamnya adalah bahan Challenge CH-2.

**Kapan sebuah skema berhenti disebut ALOHA.** Ciri keluarga ALOHA adalah **keacakan**: node memutuskan sendiri kapan mengirim, dan tabrakan ditangani setelah terjadi, bukan dicegah. Slotted ALOHA mempersempit peluang tabrakan dengan menyerempakkan awal pengiriman, tetapi tetap mengundi — itu sebabnya throughput puncaknya berhenti di 36,8 %. Begitu undian diganti jadwal tetap, tidak ada lagi yang diacak, tidak ada lagi tabrakan yang perlu ditangani, dan namanya berubah menjadi TDMA. Jadi tabel Pengukuran modul ini sebenarnya membandingkan **dua protokol berbeda**, bukan dua setelan dari protokol yang sama.

**Mengapa Mode Assigned menghapus tabrakan, sedangkan Mode Random tidak.** Dengan `SLOT_COUNT` sama dengan jumlah node (2 slot, 2 node) dan tiap node memakai slot tetap yang berbeda, **tidak ada** kombinasi kejadian yang membuat keduanya memilih slot sama — tabrakan antar-node dihapus secara struktural, selama SYNC diterima dengan benar oleh keduanya. Mode Random sengaja meniadakan kepastian itu: tiap siklus, node kedua punya peluang `1 / SLOT_COUNT` menabrak pilihan node pertama — **50 %** pada modul ini yang hanya punya 2 slot, dan pengukuran EXP-01 mendapat 44,9 %. Peluang itu turun begitu slot diperbanyak (33 % untuk 3 slot, 25 % untuk 4), tetapi tidak pernah menjadi nol selama slotnya masih diundi. Perbandingan Mode A dan Mode B inilah inti modul ini.

**Mengapa retry M08C dihapus, bukan digabung begitu saja.** Menggabungkan retry-dengan-backoff ke dalam slot yang sudah terjadwal akan merusak jadwal itu sendiri — backoff acak bisa mendorong pengiriman ulang melampaui batas slot node itu sendiri dan masuk ke slot node lain. Solusi yang benar bukan memaksakan retry ke dalam slot, melainkan membiarkan slot berikutnya (siklus SYNC berikutnya) mengambil alih perannya: data yang gagal di slot ini digantikan pembacaan baru pada siklus berikutnya, tanpa mengganggu slot siapa pun.

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
Modul10_lora_slotted_aloha_tdma/
├── platformio.ini         ← [slot] mode = 1 (Slotted ALOHA) / 0 (TDMA)
├── lora_monitor.py        ← dashboard 3-panel live (Gateway/Node1/Node2) + logging CSV
├── logserial.md           ← cuplikan log serial aktual dari pengujian perangkat
└── src/
    ├── node/main.cpp      ← dummy Ruang 1+2, hitung slot dari SYNC (env node1, node2)
    └── gateway/main.cpp   ← siarkan SYNC, terima tiap slot, balas ACK (env gateway)
```

**Monitor dashboard** — `python3 lora_monitor.py` membaca ketiga port sekaligus dan menampilkan panel Gateway/Node 1/Node 2 (diterima/hilang per node, cycle terakhir, RSSI/SNR) di terminal, plus logging CSV otomatis. Butuh `pip install pyserial rich`. Jalankan setelah ketiga board selesai di-*upload*.

**Build & flash** — **gateway lebih dahulu**, supaya kedua node langsung mendapat `SYNC` pertama begitu menyala.

```bash
pio run -d Modul10_lora_slotted_aloha_tdma -e gateway -t upload -t monitor
pio run -d Modul10_lora_slotted_aloha_tdma -e node1   -t upload -t monitor
pio run -d Modul10_lora_slotted_aloha_tdma -e node2   -t upload -t monitor
```

**Pre-flight checklist**

- ☐ Antena terpasang pada ketiga shield.
- ☐ Port ketiga board dicatat lewat `pio device list` (atau `python3 ../tools/deteksi_port.py`) dan diisikan ke `platformio.ini`.
- ☐ Tiga Serial Monitor 115200 baud siap, ketiganya terlihat bersamaan.
- ☐ `[slot] mode` di `platformio.ini` bernilai `1` (Mode A / Slotted ALOHA) untuk EXP-01 — tidak perlu menyentuh `src/node/main.cpp`.
- ☐ `SLOT_COUNT` dan `SLOT_DURATION_MS` sama persis di gateway dan node (bawaan: 2 dan 800).

## 6 · Percobaan

Kedua percobaan pertama memakai **infrastruktur yang sama persis** — SYNC, slot, guard time, firmware gateway yang identik. Yang berganti hanya satu baris di `platformio.ini`:

```ini
[slot]
mode = 1     ; EXP-01: Mode A, slot diundi   -> Slotted ALOHA
mode = 0     ; EXP-02: Mode B, slot tetap    -> TDMA
```

Urutannya sengaja mengikuti sejarah: undian dulu, kepastian belakangan. Gateway **tidak perlu** di-flash ulang saat berpindah mode — ia tidak tahu-menahu bagaimana node memilih slotnya.

### EXP-01 — Mode A (Random Slot) = Slotted ALOHA

Pastikan `mode = 1`, unggah gateway lalu kedua node, dan rekam minimal 60 siklus.

**Expected output — node**

```
=== LoRa SLOTTED ALOHA - NODE 1 ===
Slot: 2 x 800 ms
Mode : A (Random Slot) -- slot diundi tiap siklus

[TX] cycle=0 slot=1 | NODE=1,SEQ=0,R1T=26.5,R1H=54,R2T=23.2,R2H=59
[FAIL] Tidak ada ACK dalam slot ini | OK: 0 | FAIL: 1
[TX] cycle=1 slot=0 | NODE=1,SEQ=1,R1T=27.4,R1H=57,R2T=23.6,R2H=57
[OK] ACK diterima | OK: 1 | FAIL: 1
```

Nomor `slot` berubah-ubah tiap siklus — itulah undiannya. `[FAIL]` yang muncul sesekali adalah tabrakan: kedua node kebetulan mengundi slot yang sama.

**Data capture** — diukur 120 detik / 72 siklus

| Parameter | Hasil |
|---|---|
| Siklus yang terekam di kedua node | **69** |
| Siklus kedua node mengundi slot **sama** | **31 (44,9 %)** — teori `1/SLOT_COUNT` = **50 %** |
| Node 1: OK / FAIL | **58 / 15** |
| Node 2: OK / FAIL | **41 / 28** |
| `[GAP]` di gateway | **30** |
| Paket diterima gateway | **101** dari 144 kemungkinan (**70 %**) |

**Hubungan tabrakan dengan kegagalan** — inilah inti EXP-01, dan datanya tidak menyisakan keraguan:

| Kejadian | Keduanya sukses | N1 saja gagal | N2 saja gagal | Keduanya gagal |
|---|---|---|---|---|
| Slot **berbeda** (38 siklus) | **38** | 0 | 0 | 0 |
| Slot **sama** (31 siklus) | **0** | 3 | 16 | 12 |

Dibaca begini: selama kedua node mengundi slot yang berbeda, **tidak ada satu pun kegagalan** — 38 dari 38 siklus mulus. Begitu keduanya mengundi slot yang sama, **tidak pernah keduanya selamat**. Jadi di modul ini tabrakan bukan salah satu penyebab kegagalan, melainkan **satu-satunya** penyebabnya.

**Efek capture.** Dari 31 tabrakan, 19 di antaranya masih menyelamatkan satu paket — dan yang selamat hampir selalu Node 1 (16 : 3). Penerima LoRa mampu mengunci sinyal yang lebih kuat dan mengabaikan yang lebih lemah, sehingga tabrakan tidak selalu berarti dua-duanya hancur. Catat RSSI kedua node di gateway, lalu jelaskan mengapa pemenangnya konsisten.

> **CHECKPOINT** — `[FAIL]` **harus** muncul di kedua node, dan proporsi siklus "slot sama" harus mendekati 50 % (bukan 25 %: dengan 2 slot, peluang node kedua menabrak pilihan node pertama adalah 1 dari 2). Kalau `[FAIL]` nihil sama sekali, hampir pasti `mode` masih 0 — periksa baris `Mode :` di pembuka serial node.

**Buka abstraksinya** — dua kali sepanjang sesi, gateway mencetak paket yang **terbaca tapi isinya cacat**:

```
  Node    : 2
  SEQ     : 0
  Ruang 1 : 0.0 C, 0 %
  RSSI    : -34 dBm   SNR : -4.50 dB
```

Paket itu lolos karena `LoRa.enableCrc()` **tidak** dipanggil di modul ini, sehingga radio tidak membuang payload yang rusak (bandingkan dengan M07B yang mengaktifkannya). Akibatnya bukan sekadar satu baris aneh: `SEQ` terbaca `0` padahal aslinya sudah puluhan, dan penghitung `hilang` milik gateway langsung melonjak dari 24 menjadi 89. Telusuri di `src/gateway/main.cpp` bagaimana `hilang` dihitung, jelaskan mengapa satu paket cacat bisa merusak seluruh statistik, lalu tentukan: angka mana yang layak dipercaya sebagai ukuran kegagalan — `hilang` di gateway, atau `FAIL` di node?

### EXP-02 — Mode B (Assigned Slot) = TDMA

Ubah `mode` menjadi `0`, unggah ulang **kedua node** (gateway biarkan), lalu rekam dengan durasi yang sama.

**Expected output — node**

```
Mode : B (Assigned Slot) -- tetap di slot 0

[TX] cycle=0 slot=0 | NODE=1,SEQ=0,R1T=28.4,R1H=63,R2T=24.7,R2H=71
[OK] ACK diterima | OK: 1 | FAIL: 0
```

**Data capture** — diukur 120 detik / 72 siklus, sesi yang sama dengan EXP-01

| Parameter | Hasil |
|---|---|
| Siklus kedua node memakai slot **sama** | **0** — mustahil secara konstruksi |
| Node 1: OK / FAIL | **73 / 0** |
| Node 2: OK / FAIL | **69 / 2** |
| `[GAP]` di gateway | **0** |
| Paket diterima gateway | **146** (N1 = 72, N2 = 71) |

> **CHECKPOINT terpenuhi.** Nol `[GAP]`, nol paket hilang di gateway, sepanjang 72 siklus penuh.

**Dua `[FAIL]` yang bukan tabrakan.** Node 2 mencatat 2 kegagalan, tetapi gateway mencatat **nol** paket hilang untuk Node 2 — jadi datanya sampai, dan yang hilang adalah **ACK balasannya**. Kegagalan jenis ini tidak bisa dihapus oleh penjadwalan slot secanggih apa pun, sebab penyebabnya bukan tabrakan melainkan link radio arah balik. Bandingkan dengan kasus serupa di M08B.

### EXP-03 — Slot Observed vs Assigned

Bandingkan kolom `Slot` yang dicetak gateway dengan slot yang seharusnya (0 untuk Node 1, 1 untuk Node 2 pada Mode B).

**Data capture**

| Parameter | Hasil |
|---|---|
| Apakah `Slot` yang tercatat gateway selalu cocok dengan assignment (Mode B)? | **ya** — Node 1 selalu slot 0, Node 2 selalu slot 1, tanpa kecuali |
| Durasi rata-rata satu siklus | **≈1,63 detik** — dekat teori (`SLOT_COUNT × SLOT_DURATION_MS` = 1600 ms) |
| Apakah durasi siklus stabil? | **ya** — 72 siklus berturut-turut dalam 120 detik, tanpa pelebaran nyata |

> **CHECKPOINT terpenuhi.** Slot yang teramati selalu sama dengan slot yang di-assign, dan panjang siklus stabil.

### Verifikasi hardware

**Diuji di perangkat pada 2026-08-23** — 3× Arduino Uno asli + Dragino LoRa Shield v1.2 (gateway `/dev/ttyACM0`, node1 `/dev/ttyACM1`, node2 `/dev/ttyACM2`). **Kedua mode dijalankan pada sesi yang sama**, masing-masing 120 detik / 72 siklus, dengan firmware gateway yang tidak diubah di antaranya — hanya `[slot] mode` di `platformio.ini` yang diganti lalu kedua node di-flash ulang. Seluruh angka pada EXP-01, EXP-02, EXP-03, dan bagian Pengukuran berasal dari sesi itu; log mentahnya ada di `logserial.md`.

## 7 · Pengukuran

**A. Slotted ALOHA vs TDMA** (120 detik / 72 siklus, sesi yang sama)

| Ukuran | Mode A — Slotted ALOHA | Mode B — TDMA |
|---|---|---|
| Siklus "slot sama" | 31 dari 69 (44,9 %) | 0 |
| Node 1 OK / FAIL | 58 / 15 | 73 / 0 |
| Node 2 OK / FAIL | 41 / 28 | 69 / 2 |
| Paket diterima gateway | 101 | 146 |
| `[GAP]` gateway | 30 | 0 |
| Keberhasilan keseluruhan | **70 %** | **≈99 %** |

**B. Distribusi slot Mode A**

| Slot terpilih | Node 1 | Node 2 |
|---|---|---|
| 0 | 33 | 35 |
| 1 | 40 | 35 |

Undian yang seimbang: masing-masing mendekati 50/50 dari ±70 siklus, seperti yang diharapkan dari `random(0, SLOT_COUNT)`.

**C. Tabrakan dan akibatnya (Mode A)**

| Kejadian | Jumlah | Keduanya sukses | Satu selamat (capture) | Keduanya gagal |
|---|---|---|---|---|
| Slot berbeda | 38 | 38 | — | 0 |
| Slot sama | 31 | 0 | 19 | 12 |

**D. Isi sendiri** — ulangi EXP-01 dengan `SLOT_COUNT` dinaikkan menjadi 3 dan 4 (ubah di gateway **dan** kedua node), lalu bandingkan proporsi tabrakan terukur dengan teori `1/SLOT_COUNT`:

| `SLOT_COUNT` | Teori tabrakan | Terukur | Keberhasilan keseluruhan |
|---|---|---|---|
| 2 | 50 % | 44,9 % | 70 % |
| 3 | 33 % | | |
| 4 | 25 % | | |

## 8 · Analisis

1. Dari tabel A dan C, hitung: berapa persen kegagalan Mode A yang dapat dijelaskan oleh tabrakan slot semata? Bandingkan dengan Mode B yang tabrakannya nol. Apakah tersisa kegagalan yang **bukan** akibat tabrakan — dan dari mana asalnya?
2. Dari tabel B, hitung proporsi siklus yang kedua node kebetulan memilih slot sama, lalu bandingkan dengan `1/SLOT_COUNT` yang diprediksi teori.
3. Bandingkan `[GAP]` Mode A modul ini dengan `[GAP]` M08 (Pure ALOHA) pada kepadatan kirim yang sebanding. Jelaskan mengapa Slotted ALOHA — bahkan pada Mode Random — tetap menghasilkan tabrakan yang lebih jarang.
4. Modul ini menghapus retry M08C sepenuhnya. Hitung dari data Anda: pada Mode B, apakah keandalan yang dicapai tanpa retry ini sama atau lebih baik daripada M08C (dengan retry) pada kondisi kanal yang sebanding? Jelaskan.
5. Rancang, tanpa menulis kodenya, cara menambah node ketiga pada Mode B tanpa membuatnya berbagi slot dengan Node 1 atau Node 2. Apa yang harus berubah pada `SLOT_COUNT`, dan apa akibatnya terhadap panjang satu siklus penuh?

## 9 · Concept Check

1. Apa bedanya penjadwalan M05 (master memanggil) dengan penjadwalan M10 (gateway hanya menyiarkan SYNC)?
2. Mengapa vulnerable period Slotted ALOHA hanya satu kali waktu udara, sedangkan Pure ALOHA dua kali?
3. Mengapa Mode Assigned menghapus tabrakan struktural, sedangkan Mode Random tidak — walau keduanya sama-sama memakai slot?
4. Mengapa retry dan random backoff M08C dihapus pada modul ini, bukan digabungkan begitu saja ke dalam slot?
5. Apa yang terjadi pada seluruh sistem bila SYNC dari gateway hilang di jalan pada satu siklus?

## 10 · Challenge (tugas modifikasi)

- **CH-1 — Node ketiga.** Tambahkan environment `node3`, naikkan `SLOT_COUNT` menjadi 3 pada gateway dan ketiga node, lalu ukur ulang tabel A/B pada Mode B dan Mode A dengan tiga node.
- **CH-2 — Backoff hanya untuk Mode Random.** Tambahkan random backoff **kecil** (dalam batas satu slot, bukan lintas-slot) khusus untuk Mode A: bila ACK tidak diterima, node mengundi ulang slot untuk siklus berikutnya alih-alih memakai slot terakhir yang gagal. Bandingkan hasilnya dengan Mode A tanpa strategi ini.
- **CH-3 — Deteksi drift.** Tambahkan pencatatan selisih waktu kedatangan tiap paket terhadap awal slot yang diharapkan di gateway, lalu jalankan modul selama beberapa menit untuk melihat apakah selisih itu melebar seiring waktu antar-SYNC.
- **CH-5 — Buang paket cacat dengan CRC.** Tambahkan `LoRa.enableCrc()` di gateway **dan** kedua node (lihat M07B yang sudah memakainya), lalu ulangi EXP-01. Hitung: berapa paket yang tadinya "diterima" kini hilang sama sekali, apakah baris `Ruang 1 : 0.0 C` masih muncul, dan apakah penghitung `hilang` di gateway berhenti melonjak. Jelaskan mengapa membuang paket cacat justru membuat statistiknya lebih jujur.
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
