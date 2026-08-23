# Log Serial — Modul 04 (Keandalan Terukur dengan ACK)

Hasil aktual dari perangkat. Baud 9600, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm, `ACK_TIMEOUT` 3000 ms. Jarak antar-board ±30 cm.

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Sender | `sender` | `/dev/ttyUSB0` | Uno klon, bridge CH340 (`1a86:7523`) |
| Receiver | `receiver` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |

Board Uno asli di `/dev/ttyACM0` tidak dipakai: shield-nya gagal `LoRa.begin()` (lihat `../Modul01_lora_uart/logserial.md`).

## EXP-01 — Siklus ACK yang Sehat (45 detik)

```
[   1.812] RX | === LoRa ACK RECEIVER ===
[   1.812] RX | Init LoRa ... OK
[   1.812] RX | Freq: 433.00 MHz
[   1.812] RX | Menunggu paket DATA...
[   1.822] TX | Freq: 433.00 MHz | SF7 | ACK timeout: 3000 ms
[   1.822] TX | [TX] Kirim: DATA:0 ... selesai
[   2.012] RX |   Data  : DATA:0
[   2.012] RX |   RSSI  : -32.00 dBm
[   2.012] RX |   SNR   : 9.00 dB
[   2.012] RX |   Total : 1
```

| Parameter | Hasil |
|---|---|
| DATA dikirim | 14 (nomor 0..13) |
| DATA tiba di penerima | 14 |
| ACK dibalas penerima | 14 |
| ACK kembali ke pengirim | 14 |
| Keberhasilan menurut pengirim | **100 %** |
| Keberhasilan menurut penerima | **100 %** |
| Penghitung firmware | OK 14 / FAIL 0 |
| Waktu DATA→ACK min/maks/rata-rata | 0 / 201 / **143 ms** |
| RSSI rata-rata | −33,4 dBm |
| SNR rata-rata | 9,07 dB |
| Flash sender / receiver | 23,0 % (7.424 B) / 26,9 % (8.686 B) |

Waktu pulang-pergi DATA→ACK sebesar 143 ms adalah **4,8 %** dari `ACK_TIMEOUT` 3000 ms — batas waktu bawaan sangat longgar untuk jarak sedekat ini. Angka inilah bahan tabel C bagian Pengukuran.

## EXP-02 — Batas Waktu Bekerja

Ketiadaan penerima ditirukan dengan mengunggah **sketsa diam** (radio tidak pernah diinisialisasi), bukan mencabut USB, agar waktunya tercatat tepat.

```
[  11.90] *  | >>> receiver kini diam
[  11.20] TX | [TX] Kirim: DATA:3 ... selesai
[  14.25] TX | [FAIL] Tidak ada ACK! | OK: 3 | FAIL: 1
[  17.23] TX | [TX] Kirim: DATA:4 ... selesai
[  20.28] TX | [FAIL] Tidak ada ACK! | OK: 3 | FAIL: 2
[  23.27] TX | [TX] Kirim: DATA:5 ... selesai
[  26.31] TX | [FAIL] Tidak ada ACK! | OK: 3 | FAIL: 3
[  29.30] TX | [TX] Kirim: DATA:6 ... selesai
[  32.34] TX | [FAIL] Tidak ada ACK! | OK: 3 | FAIL: 4
[  35.33] TX | [TX] Kirim: DATA:7 ... selesai
[  38.24] *  | >>> receiver kembali aktif
[  38.38] TX | [FAIL] Tidak ada ACK! | OK: 3 | FAIL: 5
[  41.37] TX | [TX] Kirim: DATA:8 ... selesai
[  41.52] TX | [OK] ACK diterima! | OK: 4 | FAIL: 5
```

| Parameter | Hasil |
|---|---|
| Selang `[TX]` → `[FAIL]` | **3,05 s** — sesuai `ACK_TIMEOUT 3000` |
| Selang `[TX]` → `[OK]` saat sehat | 0,12–0,18 s |
| Lama satu siklus saat sehat | **3,10 s** (0,1 s ACK + `delay(3000)`) |
| Lama satu siklus saat gagal | **6,03 s** (3,0 s timeout + `delay(3000)`) |
| Jumlah `FAIL` selama 26 detik sunyi | 5 |
| Apakah pengirim tetap melanjutkan? | **ya**, tanpa membeku |
| Siklus sampai pulih setelah penerima kembali | **1 siklus** (3,1 s) |

Temuan penting: satu kegagalan **menggandakan lama siklus**, dari 3,1 detik menjadi 6,0 detik. Pada sistem yang menjadwalkan banyak node — seperti Modul 05 — pelipatan ini langsung memperlambat pembacaan seluruh node lain.

## EXP-03 — Nomor Urut Harus Cocok

Penerima diubah agar membalas dengan isi yang keliru, pengirim tidak disentuh.

### 03-a — penerima selalu membalas `ACK:99`

```
[  1.91] [RX] Balasan: ACK:99
[  1.97] [RX] WARN: bukan ACK yang diharapkan, tetap tunggu...
[  4.83] [FAIL] Tidak ada ACK! | OK: 0 | FAIL: 1
```

### 03-b — penerima membalas `OKE`

```
[  1.90] [RX] Balasan: OKE
[  1.96] [RX] WARN: bukan ACK yang diharapkan, tetap tunggu...
[  4.83] [FAIL] Tidak ada ACK! | OK: 0 | FAIL: 1
```

| Uji | Balasan tiba? | Diterima sebagai ACK? | `OK` bertambah? | Hasil akhir |
|---|---|---|---|---|
| baseline | ya | ya | ya | `[OK]` dalam 0,15 s |
| 03-a `ACK:99` | ya | **tidak** | tidak | `WARN` lalu `[FAIL]` setelah timeout |
| 03-b `OKE` | ya | **tidak** | tidak | `WARN` lalu `[FAIL]` setelah timeout |

Kedua uji berperilaku identik: paket **sampai** ke pengirim, dibaca, dicetak, lalu ditolak karena nomornya tidak cocok dengan yang sedang ditunggu. Pengirim tidak langsung menyerah — ia mencetak peringatan dan **tetap menunggu** sampai batas waktu habis, sesuai rancangan `while` di dalamnya. Perilaku ini yang membuat sistem kebal terhadap balasan basi maupun balasan milik pasangan board lain.

Perhatikan juga selisih waktunya: uji baseline selesai dalam 0,15 detik, sedangkan kedua uji ini menghabiskan 3,0 detik penuh sebelum menyatakan gagal — biaya menunggu balasan yang tidak akan pernah cocok.

### 03-c — pasangan board lain berdekatan

**Belum diuji.** Hanya tersedia dua shield LoRa yang berfungsi (satu shield gagal init), sehingga tidak ada pasangan board kedua untuk dijalankan berdampingan.

## Catatan pengambilan log

- Seluruh perubahan sumber pada EXP-03 dikembalikan ke kondisi semula setelah pengujian, dan firmware baku diunggah ulang.
- Kolom "keberhasilan menurut pengirim" dan "menurut penerima" dihitung dari nomor `DATA:n` dan `ACK:n` yang benar-benar terlihat pada kedua aliran serial, bukan dari penghitung firmware saja. Pada jarak dekat keduanya sama; ketidaksepakatan baru muncul pada jarak jauh, dan itulah yang diminta tabel B bagian Pengukuran.
- Tabel pengukuran jarak dan pengaruh nilai timeout pada README belum terisi: percobaan ini dijalankan di satu meja pada jarak tetap ±30 cm.
