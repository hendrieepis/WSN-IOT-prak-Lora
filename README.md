```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
                  LAB HANDBOOK


         KOMUNIKASI JARAK JAUH
              DENGAN LoRa


   Arduino Uno + Dragino Shield  •  5 MODUL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Yang dikerjakan:** LoRa mentah (SX1276) · RSSI & SNR · interrupt · ACK · master-slave multi-node

## Tentang lab ini

Ini bukan kumpulan tutorial Arduino. Ini buku kerja laboratorium: setiap modul adalah satu **misi rekayasa** dengan target sukses terukur, prosedur eksperimen, dan data yang harus dikumpulkan sendiri.

Fokusnya **LoRa mentah** — modulasi radio tanpa lapisan jaringan di atasnya. Tidak ada join, tidak ada alamat, tidak ada koneksi, tidak ada penjadwalan. Semua yang biasanya disediakan protokol harus dibangun sendiri di lapisan aplikasi, satu per satu, dan setiap penambahan diukur akibatnya. Justru di situlah nilai seri ini: praktikan menyaksikan sendiri masalah yang selama ini disembunyikan protokol, sebelum memakai protokol yang menyembunyikannya.

Seri ini melengkapi lab [WSN-IOT-prak](../WSN-IOT-prak) yang membahas BLE, Zigbee, dan Thread. Perbandingannya disengaja: di sana jaringan mengurus dirinya sendiri, di sini tidak ada jaringan sama sekali.

## Struktur setiap modul

Seluruh modul memakai format yang sama, 11 bagian:

| # | Bagian | Isi |
|---|---|---|
| 1 | **Pendahuluan** | Identitas modul, keterkaitan dengan modul lain, prasyarat, dan apa yang dipakai lagi sesudahnya — seluruhnya dalam bentuk kalimat, ditutup peta modul dan kontrak data |
| 2 | **Capaian Pembelajaran** | 5 capaian **terukur** + kriteria keberhasilan |
| 3 | **Dasar Teori (secukupnya)** | Hanya istilah yang dipakai di percobaan + sekuens yang diamati |
| 4 | **Topologi** | Diagram bernama board, peran tiap node |
| 5 | **Alat yang Digunakan** | Platform, alat & bahan, pemetaan pin, `platformio.ini`, pre-flight, perintah deploy |
| 6 | **Percobaan** | EXP-01…04 dengan **CHECKPOINT** di tiap tahap |
| 7 | **Pengukuran** | Tabel yang diisi sendiri |
| 8 | **Analisis** | Pertanyaan yang hanya bisa dijawab dari tabel Pengukuran |
| 9 | **Concept Check** | Pertanyaan konseptual, bukan hafalan |
| 10 | **Challenge** | Tugas **modifikasi kode**, bukan "jelaskan hasilnya" |
| 11 | **Laporan** | Daftar deliverable |

Tiga hal yang membedakan format ini dari panduan praktikum biasa:

- **CHECKPOINT di tengah percobaan.** Praktikan memverifikasi progres sebelum lanjut, bukan baru ketahuan salah di akhir sesi.
- **"Buka abstraksinya".** Satu kotak per modul yang menyuruh praktikan membongkar satu baris kode yang tampak sepele — menghubungkan API dengan apa yang sebenarnya terjadi di udara.
- **Percobaan yang sengaja dirusak.** Beberapa modul meminta parameter diubah sampai komunikasi gagal (M01 EXP-03, M05 EXP-04), karena kegagalan yang terkendali mengajarkan lebih banyak daripada keberhasilan yang mulus.

## Keterkaitan antar-modul

Tiap modul menambahkan **satu** kemampuan yang hilang dari modul sebelumnya:

```
M01 tautan terbentuk ─► M02 penerimaan tak memblokir ─► M03 dua arah
                                                            │
                            ┌───────────────────────────────┘
                            ▼
                    M04 hasil kirim diketahui ─► M05 banyak node dijadwalkan
```

| Modul | Yang hilang di modul sebelumnya | Yang ditambahkan |
|---|---|---|
| 01 | — | Tautan radio, parameter, RSSI & SNR |
| 02 | Penerima sibuk menunggu, paket terlewat | Interrupt DIO0 + flag pattern |
| 03 | Data hanya mengalir satu arah | Percakapan bergantian + auto-retry |
| 04 | Nasib paket tidak pernah diketahui | ACK, timeout, statistik keberhasilan |
| 05 | Dua node tidak pernah berebut bicara | Pengalamatan aplikasi + penjadwalan |

**Kontrak data yang konsisten.** Beberapa keputusan sengaja dipertahankan lintas modul supaya datanya dapat dibandingkan:

| Kontrak | Diperkenalkan | Dipakai lagi di |
|---|---|---|
| Nomor urut di dalam payload untuk menghitung loss | M01 (`Hello LoRa #n`) | M03, M04 (`DATA:n`), M05 (`S1:DATA:n`) |
| Parameter radio baku SF7 / BW 125 kHz / CR 4/5 / 17 dBm | M01 | M02–M05 |
| Identitas pengirim di dalam payload | M03 (`DeviceA:`) | M05 (`S1:`, `S2:`) |
| Pencocokan permintaan dengan balasan | M04 (`DATA:n` ↔ `ACK:n`) | M05 (`POLL:n` ↔ `S<n>:DATA:m`) |
| RSSI dan SNR dicatat berpasangan | M01 | seluruh modul |

Konsekuensinya: **angka pengukuran modul awal dipakai lagi di modul akhir.** Loss terhadap jarak dari M01 menjadi pembanding tingkat keberhasilan ACK di M04; waktu pulang-pergi M03 menjadi dasar penentuan batas waktu di M04 dan M05.

## Mission roster

| Modul | Folder | MISSION | Arah data | Mekanisme RX | Level |
|---|---|---|---|---|---|
| 01 | `week01_lora_uart` | Establish the Link | satu arah | polling | Basic |
| 02 | `week02_lora_led_notif` | Stop Waiting for Packets | satu arah | interrupt + flag | Basic |
| 03 | `week03_lora_p2p` | Take Turns Talking | dua arah | polling | Intermediate |
| 04 | `week04_lora_ack` | Know If It Arrived | dua arah | interrupt + timeout | Intermediate |
| 05 | `week05_lora_master_slave` | Schedule the Airwaves | bintang, 3 node | polling terjadwal | Advanced |

## Perangkat keras

| Parameter | Nilai |
|---|---|
| Board | Arduino Uno (ATmega328P), flash 32 KB, RAM 2 KB |
| Shield | Dragino LoRa Shield v1.2 |
| Chip radio | Semtech SX1276 |
| Frekuensi | 920 MHz (tersedia juga varian 433 / 868 / 915 MHz) |
| Daya pancar | maksimum +20 dBm; program memakai 17 dBm |
| Sensitivitas | hingga −148 dBm |
| Antarmuka | SPI perangkat keras + 3 pin kendali (NSS, RST, DIO0) |
| Antena | konektor SMA eksternal — **wajib terpasang** |

> **Jangan menyalakan shield tanpa antena.** Daya pancar yang tidak menemukan beban dipantulkan kembali ke penguat SX1276 dan dapat merusaknya permanen.

**Pemetaan pin**

| Pin | Fungsi | Boleh dipakai program? |
|---|---|---|
| D10 | NSS / CS (jumper R9) | Tidak |
| D11, D12, D13 | MOSI, MISO, SCK | Tidak — D13 juga LED bawaan |
| D9 | RST SX1276 | Tidak |
| D2 | DIO0 (interrupt) | Tidak |
| D6, D7, D8 | DIO1, DIO2, DIO5 | Jangan dijadikan output |
| **D3, D4, D5, A0–A5** | bebas | **Ya** — D3 direkomendasikan untuk LED indikator |

Skematik resmi shield ada di [`skematik/`](skematik/).

## Library

| Library | Versi | Fungsi |
|---|---|---|
| **LoRa** (sandeepmistry) | 0.8.x | Driver SX1276: init, TX blocking, RX polling/interrupt, RSSI, SNR |
| **SPI** | bawaan framework | Komunikasi SPI ke SX1276 |

PlatformIO mengunduh keduanya otomatis lewat `lib_deps`; tidak ada pemasangan manual.

> **Mengapa bukan RadioLib?** RadioLib terkompilasi menjadi lebih dari 33 KB pada Arduino Uno — melampaui flash 32 KB yang tersedia. Library sandeepmistry hanya memakai 18–30 % flash pada seluruh modul seri ini, sebagaimana terlihat pada tabel verifikasi di bawah.

## Menjalankan

```bash
pio device list                                      # catat port tiap board
pio run -d week01_lora_uart -e receiver -t upload    # penerima dahulu
pio run -d week01_lora_uart -e sender   -t upload -t monitor
```

Port di tiap `platformio.ini` masih memakai nilai contoh. Arduino Uno asli muncul sebagai `/dev/ttyACM*`, klon berbasis CH340 sebagai `/dev/ttyUSB*`, dan Windows memakai `COMx` — sesuaikan sebelum mengunggah.

**Urutan unggah** penting di sebagian besar modul: pihak yang **menunggu** diunggah lebih dahulu, pihak yang **memulai** belakangan. Tiap README menyebutkan urutannya.

**Baud Serial Monitor**: 9600 untuk M01–M04, **115200 untuk M05**.

## Status verifikasi

Seluruh modul dikompilasi ulang setelah dikonversi ke PlatformIO. **Pengujian di perangkat keras belum dilakukan pada konversi ini** — tidak ada Arduino Uno bershield LoRa yang tersambung saat penyusunan. Perilaku yang dijelaskan di tiap README berasal dari kode sumber asli beserta dokumentasinya, bukan dari pengamatan ulang. Angka pada tabel pengukuran memang disediakan kosong untuk diisi praktikan.

| Modul | Environment | Build | Flash (dari 32.256 B) |
|---|---|---|---|
| 01 | `sender` | ✅ | 18,3 % (5.890 B) |
| 01 | `receiver` | ✅ | 22,7 % (7.312 B) |
| 02 | `sender` | ✅ | 22,9 % (7.380 B) |
| 02 | `receiver` | ✅ | 24,5 % (7.916 B) |
| 03 | `devicea` | ✅ | 26,3 % (8.486 B) |
| 03 | `deviceb` | ✅ | 25,4 % (8.206 B) |
| 04 | `sender` | ✅ | 23,0 % (7.424 B) |
| 04 | `receiver` | ✅ | 26,9 % (8.686 B) |
| 05 | `master` | ✅ | 29,6 % (9.560 B) |
| 05 | `slave1` | ✅ | 26,3 % (8.492 B) |
| 05 | `slave2` | ✅ | 26,3 % (8.492 B) |

**Perubahan terhadap kode asli.** Isi program tidak diubah; yang berubah hanya cara membangunnya:

| Sebelum | Sesudah | Alasan |
|---|---|---|
| Berkas `.ino` per folder | `src/<peran>/main.cpp` + `platformio.ini` | Mengikuti alur PlatformIO seperti lab WSN-IOT-prak |
| `#define DEVICE_A` disunting manual (M03) | build flag `-DDEVICE_A` pada environment | Satu source untuk dua board; menghilangkan risiko lupa mengembalikan |
| `slave1.ino` dan `slave2.ino` terpisah (M05) | satu `slave/main.cpp` + `-DSLAVE_ID=n` | Kedua slave identik kecuali nomornya |
| Port ditulis `COM8`/`COM9` di komentar | `upload_port` di `platformio.ini` | Port terkumpul di satu tempat, tidak tersebar di komentar |

## Referensi

- [Dragino LoRa Shield — repositori resmi](https://github.com/dragino/Lora/tree/master/Lora%20Shield)
- [Skematik v1.2 (PDF)](skematik/Lora%20Shield%20v1.2.sch.pdf)
- [Library LoRa by sandeepmistry](https://github.com/sandeepmistry/arduino-LoRa)
- [Datasheet SX1276](https://www.semtech.com/products/wireless-rf/lora-connect/sx1276)
