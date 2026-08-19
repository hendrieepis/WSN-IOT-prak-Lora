# Log Serial — Modul 03 (Peer-to-Peer Ping-Pong)

Hasil aktual dari perangkat. Baud 9600, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm. Jarak antar-board ±30 cm.

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Device A — initiator | `devicea` | `/dev/ttyUSB0` | Uno klon, bridge CH340 (`1a86:7523`) |
| Device B — responder | `deviceb` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |

Board Uno asli di `/dev/ttyACM0` tidak dipakai: shield-nya gagal `LoRa.begin()` (lihat `../week01_lora_uart/logserial.md`).

## EXP-01 — Percakapan Berkelanjutan

```
[   1.811] B | === LoRa PEER-TO-PEER ===
[   1.811] B | Init LoRa ... OK
[   1.811] B | Freq  : 433.00 MHz
[   1.811] B | Peran : RESPONDER  (Device B, env deviceb)
[   1.811] B | Menunggu paket...
[   1.822] A | Peran : INITIATOR (Device A, env devicea)
[   2.824] A | [TX] DeviceA:Ping
[   3.013] B | [RX] Pesan  : DeviceA:Ping
[   3.013] B | [RX] RSSI   : -41 dBm
[   3.013] B | [RX] SNR    : 9.75 dB
[   3.013] B | [TX] DeviceB:Pong
```

Device A menunggu 1 detik sesudah init sebelum mengirim Ping pertama, sesuai `delay(1000)` di `setup()` yang memberi waktu responder bersiap.

## EXP-02 — Waktu Pulang-Pergi (30 detik)

Diukur dengan `monitor_serial.py`, yang menghitung selang antara `[TX]` sebuah node dan `[RX]` berikutnya pada node yang sama.

| Parameter | Hasil |
|---|---|
| Siklus Ping-Pong selesai | **156 dalam 30 detik** (±5,2 siklus/detik) |
| Waktu pulang-pergi min / maks / rata-rata | 200 / 401 / **220 ms** |
| Device A: kirim / terima / retry | 79 / 78 / **0** |
| Device B: kirim / terima / retry | 78 / 78 / — |
| RSSI di A (dari B) min/maks/rata-rata | −46 / −40 / −40,2 dBm |
| RSSI di B (dari A) min/maks/rata-rata | −41 / −40 / −40,7 dBm |
| SNR di A / di B (rata-rata) | 9,86 dB / 9,35 dB |
| Flash devicea / deviceb | 26,3 % (8.486 B) / 25,4 % (8.206 B) |

Percakapan berjalan **tanpa satu pun retry** selama 30 detik. Waktu pulang-pergi 220 ms terdiri dari dua kali waktu udara paket SF7 ditambah waktu proses kedua board — jauh lebih besar daripada `delay(50)` yang disisipkan sebelum membalas.

Tautan bersifat hampir simetris: RSSI yang dilihat A (−40,2 dBm) dan yang dilihat B (−40,7 dBm) berselisih di bawah 1 dB.

## EXP-03 — Percakapan Terputus dan Pulih

Ketiadaan node ditirukan dengan mengunggah **sketsa diam** (`setup()` dan `loop()` kosong, radio tidak pernah diinisialisasi), bukan dengan mencabut USB — agar seluruh rangkaian percobaan dapat diulang tanpa campur tangan tangan dan waktunya tercatat tepat.

### Skenario 1–2: responder hilang lalu kembali

Device A dipantau terus-menerus; hanya Device B yang dimatikan dan dinyalakan.

```
[  13.90] * | >>> Device B kini diam
[  17.42] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  22.46] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  27.49] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  32.54] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  37.60] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  42.64] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  47.68] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  48.07] * | >>> Device B kembali aktif
[  52.72] A | [RETRY] Tidak ada balasan, kirim ulang Ping...
[  52.72] A | [TX] DeviceA:Ping
[  52.93] A | [RX] Pesan  : DeviceB:Pong        <-- percakapan pulih
[  52.96] A | [RX] RSSI   : -45 dBm
```

| Parameter | Hasil |
|---|---|
| Selang B diam → `[RETRY]` pertama | 3,5 s |
| Selang antar-`[RETRY]` | **5,04 s** (sesuai `PING_INTERVAL 5000`) |
| Jumlah retry selama 34 detik sunyi | 8 |
| Waktu pemulihan setelah B kembali | **4,86 s** |
| Perlu mereset Device A? | **tidak** |
| Perlu mereset Device B? | tidak |

Pemulihan memakan 4,86 detik bukan karena tautan lambat, melainkan karena Device A hanya mencoba lagi **pada jadwal retry berikutnya**. Batas atas waktu pemulihan sistem ini adalah satu `PING_INTERVAL`, yaitu 5 detik.

### Skenario 3–4: initiator hilang lalu kembali

Kebalikannya: Device B dipantau, Device A yang dimatikan.

| Parameter | Hasil |
|---|---|
| Baris yang dicetak B selama 23,5 detik tanpa initiator | **0 baris** |
| Pesan kesalahan dari B | **tidak ada** |
| Waktu pemulihan setelah A kembali | 1,1 s |

Inilah temuan terpenting modul ini: ketika **initiator** yang hilang, responder tidak mencetak apa pun sama sekali — tidak ada peringatan, tidak ada retry, hanya sunyi. Dari sisi Device B, keadaan "lawan bicara mati" tidak dapat dibedakan dari "belum ada yang mengajak bicara". Responder memang dirancang hanya membalas, dan tidak memiliki pewaktu apa pun untuk menyadari kesunyian.

Perbandingan kedua arah kegagalan:

| Yang hilang | Yang terjadi | Terdeteksi? | Waktu pemulihan |
|---|---|---|---|
| Responder (B) | A mencetak `[RETRY]` tiap 5 detik | **ya** | ≤ 5 s (terukur 4,86 s) |
| Initiator (A) | B diam total tanpa pesan | **tidak** | 1,1 s setelah A kembali |

## Catatan pengambilan log

- Percobaan pertama EXP-03 gagal karena `monitor_serial.py` menahan `/dev/ttyACM1`, sehingga unggah pemulihan ke Device B tidak dapat membuka port itu dan Device B tetap diam. Rangkaian diulang dengan hanya memantau node yang datanya dibutuhkan, sehingga port node lainnya bebas untuk diunggah. Ini juga berlaku saat praktikum: jangan menjalankan monitor pada port board yang hendak diunggah.
- Payload modul ini tidak bernomor, sehingga paket hilang tidak dapat dihitung dari lompatan angka seperti Modul 01. Yang diukur adalah waktu pulang-pergi dan jumlah retry. Penomoran payload menjadi bahan CH-2.
- Kode sumber sempat memuat sisa penamaan port Windows (`COM8`, `COM9`) pada pesan `setup()`, warisan dari repositori asal. Keduanya diganti nama environment PlatformIO agar tidak menyesatkan.
- Tabel pengukuran jarak, tautan asimetris, dan spreading factor pada README belum terisi: percobaan ini dijalankan di satu meja pada jarak tetap ±30 cm.
