# Log Serial — Modul 10 (Slotted ALOHA & TDMA)

Hasil aktual dari perangkat. Baud **115200**, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `SLOT_COUNT`=2, `SLOT_DURATION_MS`=800, `SLOT_GUARD_MS`=50.

**Kedua mode direkam pada sesi yang sama**, masing-masing 120 detik / 72 siklus, dengan firmware gateway yang sama sekali tidak diubah di antaranya — hanya `[slot] mode` di `platformio.ini` yang diganti lalu kedua node di-flash ulang. Itu sebabnya angkanya boleh dibandingkan langsung.

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Gateway | `gateway` | `/dev/ttyACM0` | Uno asli (`2341:0043`) |
| Node 1 | `node1` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |
| Node 2 | `node2` | `/dev/ttyACM2` | Uno asli (`2341:0043`) |

## EXP-01 — Mode A (Random Slot) = Slotted ALOHA

Node mengundi slotnya tiap siklus, dan nomor `slot` di log ikut berubah-ubah:

```
[21:41:34] [   1.6] Mode : A (Random Slot) -- slot diundi tiap siklus
[21:41:35] [   2.6] [TX] cycle=0 slot=1 | NODE=1,SEQ=0,R1T=26.5,R1H=54,R2T=23.2,R2H=59
[21:41:36] [   3.3] [FAIL] Tidak ada ACK dalam slot ini | OK: 0 | FAIL: 1
[21:41:36] [   3.4] [TX] cycle=1 slot=0 | NODE=1,SEQ=1,R1T=27.4,R1H=57,R2T=23.6,R2H=57
[21:41:36] [   3.5] [OK] ACK diterima | OK: 1 | FAIL: 1
...
[21:41:54] [  22.1] [FAIL] Tidak ada ACK dalam slot ini | OK: 11 | FAIL: 2
[21:41:56] [  23.8] [TX] cycle=13 slot=1 | NODE=1,SEQ=13,...
[21:41:56] [  23.9] [OK] ACK diterima | OK: 12 | FAIL: 2
```

Gateway melihat akibatnya sebagai `SEQ` yang meloncat:

```
[21:41:46] [  13.3]   [GAP] SEQ meloncat 1 -- data hilang pada siklus tersebut (mis. tabrakan slot)
[21:41:53] [  20.6]   [GAP] SEQ meloncat 2 -- data hilang pada siklus tersebut (mis. tabrakan slot)
```

**Rekapitulasi 120 detik / 72 siklus**

| Parameter | Hasil |
|---|---|
| Siklus terekam di kedua node | 69 |
| Siklus kedua node mengundi slot **sama** | **31 (44,9 %)** — teori `1/SLOT_COUNT` = 50 % |
| Node 1: OK / FAIL | 58 / 15 |
| Node 2: OK / FAIL | 41 / 28 |
| `[GAP]` gateway | 30 |
| Paket diterima gateway | 101 dari 144 kemungkinan (70 %) |
| Slot yang dipilih Node 1 (slot 0 / slot 1) | 33 / 40 |
| Slot yang dipilih Node 2 (slot 0 / slot 1) | 35 / 35 |

**Tabrakan adalah satu-satunya penyebab kegagalan.** Hasil pencocokan slot kedua node siklus demi siklus:

| Kejadian | Jumlah | Keduanya sukses | N1 saja gagal | N2 saja gagal | Keduanya gagal |
|---|---|---|---|---|---|
| Slot **berbeda** | 38 | **38** | 0 | 0 | 0 |
| Slot **sama** | 31 | **0** | 3 | 16 | 12 |

Tidak ada satu pun kegagalan ketika slotnya berbeda, dan tidak pernah keduanya selamat ketika slotnya sama. Dari 31 tabrakan, 19 masih menyisakan satu paket yang selamat — dan pemenangnya hampir selalu Node 1 (16 : 3), yaitu **efek capture**: penerima mengunci sinyal yang lebih kuat.

**Dua paket cacat yang lolos.** Tabrakan tidak selalu berakhir sunyi; dua kali gateway menerima paket yang terbaca tetapi isinya rusak:

```
[21:43:21] [ 108.8] === PAKET DITERIMA ===
[21:43:21] [ 108.8]   Node    : 2
[21:43:21] [ 108.8]   SEQ     : 0
[21:43:21] [ 108.8]   Ruang 1 : 0.0 C, 0 %
[21:43:21] [ 108.8]   Ruang 2 : 0.0 C, 57 %
[21:43:21] [ 108.8]   RSSI    : -34 dBm
[21:43:21] [ 108.8]   SNR     : -4.50 dB
```

Paket itu lolos karena modul ini tidak memanggil `LoRa.enableCrc()` (bandingkan M07B yang mengaktifkannya). Akibatnya tidak berhenti di satu baris aneh: `SEQ` terbaca `0` padahal aslinya sudah puluhan, dan penghitung `hilang` untuk Node 2 melonjak dari **24** (siklus 60) menjadi **89** di akhir sesi — jauh melebihi jumlah paket yang benar-benar dikirim. **Angka `FAIL` di sisi node adalah ukuran kegagalan yang jujur di sesi ini, bukan `hilang` di gateway.** Perbaikannya ada di Challenge CH-5.

## EXP-02 — Mode B (Assigned Slot) = TDMA

Slot tidak lagi diundi; tiap node terkunci di slotnya sendiri sepanjang sesi.

```
[21:45:08] [   1.6] Mode : B (Assigned Slot) -- tetap di slot 0
[21:47:06] [ 117.6] --- Cycle 70 selesai | N1: diterima=71 hilang=0  N2: diterima=70 hilang=0  ---
[21:47:08] [ 119.2] --- Cycle 71 selesai | N1: diterima=72 hilang=0  N2: diterima=71 hilang=0  ---
```

**Rekapitulasi 120 detik / 72 siklus**

| Parameter | Hasil |
|---|---|
| Siklus kedua node memakai slot sama | **0** |
| Slot yang dipakai Node 1 / Node 2 | selalu 0 / selalu 1 |
| Node 1: OK / FAIL | **73 / 0** |
| Node 2: OK / FAIL | **69 / 2** |
| `[GAP]` gateway | **0** |
| Paket diterima gateway | **146** (N1 = 72, N2 = 71) |
| `hilang` menurut gateway | 0 untuk kedua node |

**Dua `[FAIL]` yang bukan tabrakan.** Node 2 mencatat 2 kegagalan, tetapi gateway mencatat **nol** paket hilang untuk Node 2 — datanya sampai, yang hilang adalah **ACK balasannya**. Kegagalan jenis ini tidak dapat dihapus oleh penjadwalan slot, sebab penyebabnya link arah balik, bukan tabrakan. Kasus yang sama pernah tertangkap di M08B.

## Perbandingan langsung

| Ukuran | Mode A — Slotted ALOHA | Mode B — TDMA |
|---|---|---|
| Siklus "slot sama" | 31 dari 69 (44,9 %) | 0 |
| Node 1 OK / FAIL | 58 / 15 | 73 / 0 |
| Node 2 OK / FAIL | 41 / 28 | 69 / 2 |
| `[GAP]` gateway | 30 | 0 |
| Paket diterima gateway | 101 | 146 |
| Keberhasilan keseluruhan | **70 %** | **≈99 %** |

Selisihnya bukan soal setelan, melainkan soal protokol: mengundi slot menyisakan peluang tabrakan `1/SLOT_COUNT` yang tidak pernah nol, sedangkan slot tetap menghapusnya secara konstruksi. Yang tersisa di Mode B hanyalah kegagalan yang memang di luar jangkauan penjadwalan — ACK yang hilang di udara.

## Ringkasan Verifikasi Hardware

Diuji di perangkat pada **2026-08-23**: 3× Arduino Uno asli + Dragino LoRa Shield v1.2 (`/dev/ttyACM0/1/2`). Kedua mode dijalankan berurutan pada sesi yang sama, masing-masing 120 detik / 72 siklus. Perpindahan mode dilakukan lewat `[slot] mode` di `platformio.ini` (build flag `SLOT_MODE_RANDOM`), tanpa menyentuh `src/node/main.cpp` dan tanpa mem-flash ulang gateway. Seluruh angka pada README bagian Percobaan dan Pengukuran berasal dari sesi ini.

Yang **belum** dijalankan dan diserahkan sebagai pekerjaan praktikum: tabel D (variasi `SLOT_COUNT` 3 dan 4) serta seluruh Challenge, termasuk CH-5 (`LoRa.enableCrc()`) yang lahir dari temuan paket cacat di EXP-01.
