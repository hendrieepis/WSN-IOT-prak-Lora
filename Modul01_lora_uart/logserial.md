# Log Serial — Modul 01 (Tautan LoRa Satu Arah)

Hasil aktual dari perangkat. Baud 9600, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm. Jarak antar-board ±30 cm.

## Board & Port

| Peran | Environment | Port | Board | Status radio |
|---|---|---|---|---|
| Sender | `sender` | `/dev/ttyACM0` | Uno asli (`2341:0043`) | ✅ init berhasil |
| Receiver | `receiver` | `/dev/ttyACM1` | Uno asli (`2341:0043`) | ✅ init berhasil |

Pemetaan ini sesuai `platformio.ini` apa adanya, sehingga `--upload-port` tidak diperlukan. Kedua aliran serial direkam bersamaan memakai `monitor_serial.py`, sehingga stempel waktunya berasal dari satu sumbu yang sama dan hitungan paket hilang berasal dari selisih nomor urut, bukan perkiraan.

## EXP-01 — Inisialisasi Radio

```
[   5.049] RX | -- tersambung ke /dev/ttyACM1 @ 9600 --
[   5.050] TX | -- tersambung ke /dev/ttyACM0 @ 9600 --
[   5.851] TX | [TX] "Hello LoRa #2" ... terkirim
[   6.051] RX | --- Paket Diterima ---
[   6.051] RX |   Data  : "Hello LoRa #2"
[   6.051] RX |   RSSI  : -55 dBm
[   6.051] RX |   SNR   : 9.50 dB
[   8.054] TX | [TX] "Hello LoRa #3" ... terkirim
[   8.056] RX | --- Paket Diterima ---
[   8.056] RX |   Data  : "Hello LoRa #3"
[   8.056] RX |   RSSI  : -54 dBm
[   8.056] RX |   SNR   : 9.00 dB
```

Pesan awal kedua board saat reset:

```
=== LoRa SENDER ===              === LoRa RECEIVER ===
Init LoRa ... OK                 Init LoRa ... OK
Frekuensi : 433.00 MHz           Frekuensi : 433.00 MHz
SF=7, BW=125kHz, CR=4/5,         SF=7, BW=125kHz, CR=4/5
        Power=17dBm              Menunggu paket...
Kirim tiap 2 detik...
```

| Parameter | Hasil |
|---|---|
| Pesan init sender | `OK` |
| Pesan init receiver | `OK` |
| Frekuensi yang tercetak | 433.00 MHz di kedua board |
| Selang `[TX]` → paket tercetak di penerima | 0,002–0,200 s |
| Flash sender / receiver | 18,3 % (5.890 B) / 22,7 % (7.312 B) |

> **CHECKPOINT terpenuhi.** Kedua board mencetak `OK`.

## EXP-02 — Aliran Data Satu Arah (62 detik)

| Parameter | Hasil |
|---|---|
| Paket dikirim / diterima | **28 / 28** (nomor 2..29) |
| Paket hilang | **0 (loss 0 %)** |
| RSSI: min / maks / rata-rata | −56 / −43 / **−53,9 dBm** |
| SNR: min / maks / rata-rata | 9,00 / 9,75 / **9,45 dB** |
| Interval kirim terukur | 2,00–2,01 s (sesuai `delay(2000)`) |

RSSI pada sesi ini (−53,9 dBm) lebih lemah daripada sesi sebelumnya yang memakai board berbeda (−41,6 dBm), meskipun jaraknya sama. Selisih ±12 dB itu berasal dari perbedaan antena dan posisi board di meja, bukan dari jarak — pengingat bahwa RSSI hanya dapat dibandingkan bila kondisi ukurnya benar-benar sama. SNR keduanya praktis identik (9,45 dB vs 9,53 dB), karena derau lingkungannya sama.

## EXP-03 — Parameter Harus Seragam

Satu parameter diubah **di penerima saja**, diunggah ulang, lalu penerimaan diamati 16 detik. Pengirim tidak disentuh.

| Uji | Perubahan di receiver | Paket diterima / 16 s | Hasil |
|---|---|---|---|
| baseline | SF7, BW 125 kHz, CR 4/5, 433 MHz | 5 | tautan normal |
| 03-a | `setSpreadingFactor(8)` | **0** | komunikasi berhenti total |
| 03-b | `setSignalBandwidth(250E3)` | **0** | komunikasi berhenti total |
| 03-c | `setCodingRate4(6)` | **5** | **tetap diterima normal** |
| 03-d | `FREQUENCY 868E6` | **0** | komunikasi berhenti total |

### Temuan: coding rate tidak harus sama

Uji 03-c membantah dugaan awal bahwa keempat parameter sama-sama wajib seragam. Coding rate yang berbeda **tidak** menghentikan penerimaan — jumlah paket yang tertangkap sama persis dengan baseline.

Hasil ini **tereplikasi pada dua pasangan board yang berbeda**: pengujian pertama memakai Uno klon ber-bridge CH340 sebagai pengirim, pengujian kedua memakai dua Uno asli. Keduanya memberi pola yang sama persis, sehingga temuan ini bukan sifat satu perangkat tertentu.

Penjelasannya ada pada struktur paket LoRa. Program memakai *explicit header mode*, bawaan library. Pada mode itu setiap paket membawa **header PHY** berisi panjang payload dan **coding rate yang dipakai**, dan header itu sendiri selalu dikirim dengan CR 4/8. Penerima membaca coding rate dari header lalu menyesuaikan diri untuk memecahkan payload. Nilai `setCodingRate4()` di sisi penerima karena itu hanya menentukan CR ketika penerima **mengirim**, bukan ketika menerima.

Berbeda halnya dengan SF, bandwidth, dan frekuensi. Ketiganya menentukan bentuk gelombang secara fisik: penerima yang menyetel SF atau bandwidth berbeda tidak akan mengenali sinyal sebagai paket LoRa sama sekali, sehingga header pun tidak pernah terbaca. Itulah alasan uji 03-a, 03-b, dan 03-d berhenti total sementara 03-c berjalan seperti biasa.

Konsekuensi praktisnya: bila suatu saat *implicit header mode* dipakai — biasanya untuk menghemat waktu udara pada payload tetap — coding rate wajib disepakati kedua sisi, karena tidak ada lagi header yang mengabarkannya.

## Riwayat: satu shield sempat gagal init

Pada sesi pengujian sebelumnya, board Uno di `/dev/ttyACM0` konsisten gagal:

```
=== LoRa SENDER ===
Init LoRa ... GAGAL! Cek kabel/modul.
```

Firmware kedua board ditukar untuk memastikan penyebabnya:

| Board fisik | Sebagai sender | Sebagai receiver |
|---|---|---|
| di `/dev/ttyACM0` | GAGAL | **GAGAL** |
| di `/dev/ttyACM1` | OK | **OK** |

Kegagalan mengikuti **board fisik**, bukan firmware, bukan port, dan bukan pengaturan frekuensi — `LoRa.begin()` memeriksa register versi SX1276 **sebelum** frekuensi diterapkan, sehingga perubahan 920 MHz ke 433 MHz tidak mengubah gejalanya. Setelah shield diperbaiki, board yang sama menginisialisasi dengan normal dan dipakai pada seluruh pengukuran di atas.

Catatan ini dipertahankan karena gejalanya khas dan langkah diagnosisnya — menukar firmware untuk memisahkan kesalahan perangkat dari kesalahan program — berlaku untuk seluruh modul dalam seri ini.

## Uji kompatibilitas board asli vs klon

Lab memakai Uno asli dan klon bercampur, sehingga perlu dipastikan firmware yang sama benar-benar berjalan di keduanya.

| Yang diperiksa | Hasil |
|---|---|
| `Device signature` board asli (`ttyACM0`) | `0x1e950f (m328p)` |
| `Device signature` board klon (`ttyUSB0`) | `0x1e950f (m328p)` — sama |
| Protokol unggah | `arduino` pada keduanya |
| md5 `.hex` saat `upload_port` diubah | `f263400e…` pada keduanya — **identik** |

Perilaku dengan peran ditukar antar-jenis board, 26 detik per konfigurasi:

| Konfigurasi | Paket | Hilang | RSSI rata-rata |
|---|---|---|---|
| TX asli (`ttyACM0`) → RX klon (`ttyUSB0`) | 12 | 1 (nomor **0**) | −54,0 dBm |
| TX klon (`ttyUSB0`) → RX asli (`ttyACM0`) | 12 | 0 | −53,8 dBm |

Satu-satunya paket hilang adalah **#0**, yaitu paket yang dikirim ketika penerima masih menyelesaikan boot — bukan gejala ketidakcocokan board. Membuka port menyebabkan kedua board reset bersamaan, dan pengirim siap ±0,2 detik lebih cepat daripada penerima. Inilah alasan README meminta penerima diunggah lebih dahulu, dan alasan paket pertama sebaiknya tidak dihitung dalam pengukuran.

Kesimpulan: **tidak ada penyesuaian kode apa pun** yang diperlukan untuk board klon. Yang berbeda hanya nama port di sistem operasi.

## Catatan pengambilan log

- Arduino Uno melakukan reset otomatis setiap kali port serial dibuka, karena jalur DTR terhubung ke pin RESET lewat kapasitor. Sifat ini dipakai agar pesan `setup()` ikut terekam tanpa menekan tombol reset.
- `monitor_serial.py` sempat gagal membuka port kedua Uno asli dengan `[Errno 110] Connection timed out`. Penyebabnya, skrip menyetel DTR/RTS **sebelum** `open()` — hal yang ditolak CDC ATmega16U2 pada Uno asli, tetapi kebetulan lolos pada klon ber-bridge CH340 yang dipakai di sesi sebelumnya. Skrip diperbaiki agar tidak menyentuh jalur itu sama sekali, dan perbaikannya diterapkan ke seluruh salinan monitor pada Modul 01–04.
- Baris `[TX] ... terkirim` **bukan** bukti paket mengudara. Program mencetaknya setelah `LoRa.endPacket()` kembali, tanpa memeriksa status radio. Pada board yang `LoRa.begin()`-nya gagal, baris itu tetap muncul.
- Seluruh perubahan sumber pada EXP-03 dikembalikan ke kondisi semula setelah pengujian, dan baseline diukur ulang untuk memastikannya.
- Tabel pengukuran jarak, penghalang, dan spreading factor pada README belum terisi: percobaan ini dijalankan di satu meja pada jarak tetap ±30 cm.
