```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
                  LAB HANDBOOK


         KOMUNIKASI JARAK JAUH
              DENGAN LoRa


   Arduino Uno + Raspberry Pi  •  7 MODUL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Yang dikerjakan:** LoRa mentah (SX1276) · RSSI & SNR · interrupt · ACK · master-slave multi-node · driver register langsung · gateway Linux

## Tentang lab ini

Ini bukan kumpulan tutorial Arduino. Ini buku kerja laboratorium: setiap modul adalah satu **misi rekayasa** dengan target sukses terukur, prosedur eksperimen, dan data yang harus dikumpulkan sendiri.

Fokusnya **LoRa mentah** — modulasi radio tanpa lapisan jaringan di atasnya. Tidak ada join, tidak ada alamat, tidak ada koneksi, tidak ada penjadwalan. Semua yang biasanya disediakan protokol harus dibangun sendiri di lapisan aplikasi, satu per satu, dan setiap penambahan diukur akibatnya. Justru di situlah nilai seri ini: praktikan menyaksikan sendiri masalah yang selama ini disembunyikan protokol, sebelum memakai protokol yang menyembunyikannya.

Lima modul pertama dikerjakan di atas Arduino Uno bershield Dragino LoRa v1.2. Dua modul terakhir berpindah ke Raspberry Pi bershield Dragino LoRa GPS HAT v1.4 — bukan sekadar ganti papan, melainkan dua pertanyaan lanjutan: **M06** melepas library dan memegang register SX1276 langsung dari Python, sehingga isi `LoRa.begin()` terlihat baris per baris; **M07** memindahkan master jaringan M05 ke Raspberry Pi tanpa mengubah firmware slave sama sekali, membentuk topologi gateway yang lazim di dunia nyata. Chip radionya tetap sama di seluruh seri, dan kesamaan itulah yang membuat kedua sisi dapat dipasangkan silang.

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
                                                            │
                            ┌───────────────────────────────┘
                            ▼
                    M06 library dilepas ─► M07 penjadwal pindah ke gateway
                    (platform berganti)     (sisi node tidak berubah)
```

| Modul | Yang hilang di modul sebelumnya | Yang ditambahkan |
|---|---|---|
| 01 | — | Tautan radio, parameter, RSSI & SNR |
| 02 | Penerima sibuk menunggu, paket terlewat | Interrupt DIO0 + flag pattern |
| 03 | Data hanya mengalir satu arah | Percakapan bergantian + auto-retry |
| 04 | Nasib paket tidak pernah diketahui | ACK, timeout, statistik keberhasilan |
| 05 | Dua node tidak pernah berebut bicara | Pengalamatan aplikasi + penjadwalan |
| 06 | Isi `LoRa.begin()` tidak pernah terlihat | Register SX1276 langsung, Python di Linux, uji silang platform |
| 07 | Master mikrokontroler buntu di Serial Monitor | Gateway Linux menjadwalkan node Arduino tanpa mengubah firmware-nya |

**Kontrak data yang konsisten.** Beberapa keputusan sengaja dipertahankan lintas modul supaya datanya dapat dibandingkan:

| Kontrak | Diperkenalkan | Dipakai lagi di |
|---|---|---|
| Nomor urut di dalam payload untuk menghitung loss | M01 (`Hello LoRa #n`) | M03, M04 (`DATA:n`), M05 (`S1:DATA:n`) |
| Parameter radio baku SF7 / BW 125 kHz / CR 4/5 / 17 dBm | M01 | M02–M05 |
| Identitas pengirim di dalam payload | M03 (`DeviceA:`) | M05 (`S1:`, `S2:`) |
| Pencocokan permintaan dengan balasan | M04 (`DATA:n` ↔ `ACK:n`) | M05, M07 (`POLL:n` ↔ `S<n>:DATA:m`) |
| RSSI dan SNR dicatat berpasangan | M01 | seluruh modul |

Konsekuensinya: **angka pengukuran modul awal dipakai lagi di modul akhir.** Loss terhadap jarak dari M01 menjadi pembanding tingkat keberhasilan ACK di M04; waktu pulang-pergi M03 menjadi dasar penentuan batas waktu di M04 dan M05.

Kontrak yang sama itu pula yang membuat dua modul terakhir dapat disambungkan silang ke modul awal. Payload M06 identik dengan M01 (`Hello LoRa #n`, SF7/BW 125 kHz), sehingga **sender Raspberry Pi dapat diuji langsung terhadap receiver Arduino M01** dan sebaliknya — percobaan inti M06. Firmware slave M07 pun identik dengan slave M05 kecuali satu baris pesan pembuka, dan kesamaan itu diperiksa dengan `diff` sebagai bagian dari laporan, bukan sekadar dinyatakan.

## Mission roster

| Modul | Folder | MISSION | Arah data | Mekanisme RX | Level |
|---|---|---|---|---|---|
| 01 | `week01_lora_uart` | Establish the Link | satu arah | polling | Basic |
| 02 | `week02_lora_led_notif` | Stop Waiting for Packets | satu arah | interrupt + flag | Basic |
| 03 | `week03_lora_p2p` | Take Turns Talking | dua arah | polling | Intermediate |
| 04 | `week04_lora_ack` | Know If It Arrived | dua arah | interrupt + timeout | Intermediate |
| 05 | `week05_lora_master_slave` | Schedule the Airwaves | bintang, 3 node | polling terjadwal | Advanced |
| 06 | `week06_rpi_lora_python` | Drop the Library | satu arah | polling register | Intermediate |
| 07 | `week07_rpi_master_slave` | Move the Scheduler to Linux | bintang, 3 node | polling terjadwal | Advanced |

Modul 01–05 memakai Arduino Uno + Dragino LoRa Shield v1.2. Modul 06 memakai dua Raspberry Pi + LoRa GPS HAT v1.4. Modul 07 mencampur keduanya: Raspberry Pi sebagai master, dua Arduino Uno sebagai slave.

## Perangkat keras

Dua papan Dragino dipakai di seri ini. Keduanya membawa chip radio yang **sama**, SX1276; yang berbeda hanya papan pembawa dan pin mana yang tersambung ke mana. Perbedaan itu tidak terasa sama sekali di udara — itulah yang dibuktikan M06 dan M07.

### Arduino Uno + Dragino LoRa Shield v1.2 — Modul 01–05, dan sisi slave M07

![bab988112f70e658f0ee6025f1f4670d322eb797](./assets/bab988112f70e658f0ee6025f1f4670d322eb797.jpeg)

| Parameter | Nilai |
|---|---|
| Board | Arduino Uno (ATmega328P), flash 32 KB, RAM 2 KB |
| Shield | Dragino LoRa Shield v1.2 |
| Chip radio | Semtech SX1276 |
| Frekuensi | **433 MHz** — shield yang dipakai lab ini; varian 868 / 915 / 920 MHz juga beredar |
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

### Raspberry Pi + Dragino LoRa GPS HAT v1.4 — Modul 06, dan sisi master M07

![Dragino LoRa GPS HAT terpasang di Raspberry Pi](./assets/lora-gps-hat-terpasang.webp)

| Parameter | Nilai |
|---|---|
| Board | Raspberry Pi 2 / 3 / 4 — **diuji pada Pi 4** oleh penyusun kode aslinya |
| HAT | Dragino LoRa GPS HAT v1.4 |
| Chip radio | Semtech SX1276 — sama persis dengan shield Arduino |
| GPS | modul onboard, UART 9600 bps, NMEA 0183 — **tidak dipakai** di seri ini |
| Antarmuka | SPI0 perangkat keras + 3 jalur GPIO (NSS, RESET, DIO0) |
| Antena | konektor SMA eksternal — **wajib terpasang**, sama seperti shield |

**Pemetaan pin HAT**

| LoRa GPS HAT | WiringPi | BCM GPIO | Padanan di shield Arduino |
|---|---|---|---|
| LoRa_NSS | GPIO6 | **25** | D10 |
| RESET | GPIO0 | **17** | D9 |
| DIO0 | GPIO7 | **4** | D2 |
| SCK / MOSI / MISO | GPIO14/12/13 | **11 / 10 / 9** | D13 / D11 / D12 |
| GPS_RX / GPS_TX / 1PPS | GPIO15/16/1 | 14 / 15 / 18 | — |

Kolom **WiringPi** adalah penomoran yang dipakai dokumentasi resmi Dragino; kolom **BCM** adalah yang dipakai seluruh kode Python di seri ini (`GPIO.setmode(GPIO.BCM)`). Keduanya menunjuk pin fisik yang sama, dan tertukarnya keduanya adalah penyebab kegagalan yang paling sering terjadi.

**NSS bukan CE0.** HAT memakai GPIO 25 biasa sebagai chip select, bukan jalur CE0 bawaan SPI. Akibatnya kode Python membuka SPI pada `(0, 0)` tetapi menggerakkan NSS sendiri di sekitar tiap transaksi — persis seperti driver Arduino menggerakkan D10.

**Raspberry Pi 5** memakai chip GPIO baru (RP1) yang tidak didukung `RPi.GPIO`. Pasang `rpi-lgpio` sebagai gantinya; nama modulnya sama, sehingga tidak ada baris kode yang perlu diubah. Jangan memasang keduanya sekaligus.

Skematik HAT dan user manual resminya ada di [`skematik/`](skematik/) dan [`dokumen/`](dokumen/).

## Library

| Library | Versi | Fungsi |
|---|---|---|
| **LoRa** (sandeepmistry) | 0.8.x | Driver SX1276: init, TX blocking, RX polling/interrupt, RSSI, SNR |
| **SPI** | bawaan framework | Komunikasi SPI ke SX1276 |

PlatformIO mengunduh keduanya otomatis lewat `lib_deps`; tidak ada pemasangan manual.

> **Mengapa bukan RadioLib?** RadioLib terkompilasi menjadi lebih dari 33 KB pada Arduino Uno — melampaui flash 32 KB yang tersedia. Library sandeepmistry hanya memakai 18–30 % flash pada seluruh modul seri ini, sebagaimana terlihat pada tabel verifikasi di bawah.

**Sisi Raspberry Pi (M06 dan master M07)** tidak memakai library LoRa sama sekali:

| Paket | Fungsi |
|---|---|
| `spidev` | Akses `/dev/spidev0.0` — satu-satunya jalan bicara ke SX1276 |
| `RPi.GPIO` | Kendali jalur NSS dan RESET, pembacaan DIO0 |
| `rpi-lgpio` | Pengganti `RPi.GPIO` khusus Raspberry Pi 5 — nama modul sama, kode tidak berubah |

Driver SX1276-nya ditulis di dalam berkas program itu sendiri, langsung di atas register. Nama fungsinya sengaja dibuat menyerupai API sandeepmistry (`beginPacket`, `endPacket`, `parsePacket`, `packetRssi`) agar kedua platform dapat dibandingkan baris per baris — dan agar terlihat bahwa library Arduino tidak melakukan apa pun yang ajaib, hanya menulis register yang sama. Pemasangannya lewat `requirements.txt` di masing-masing folder modul.

## Board bercampur: Uno asli dan klon

Catatan ini berlaku untuk seluruh Arduino di lab: Modul 01–05 dan sisi slave Modul 07. Lab ini memakai Arduino Uno asli maupun klon secara bercampur. **Firmware kedua jenis board identik** — tidak ada satu baris pun yang perlu diubah, dan tidak ada environment terpisah. Hal itu sudah diverifikasi di perangkat, bukan sekadar diasumsikan:

| Yang diperiksa | Hasil |
|---|---|
| Mikrokontroler | `Device signature = 0x1e950f (m328p)` — sama pada kedua jenis |
| Protokol unggah | `arduino` pada kedua jenis |
| Berkas `.hex` untuk `upload_port` berbeda | **md5 identik** — port bukan masukan kompilasi |
| Modul 01 dengan peran ditukar antar-jenis | berjalan normal di kedua arah, RSSI −54,0 vs −53,8 dBm |
| Modul 05 dengan master asli + satu slave klon | 53 siklus, keberhasilan 100 % di kedua slave |

Yang berbeda hanya **chip jembatan USB-ke-serial** di atas board, dan itu hanya mengubah nama port di sistem operasi:

| Jenis board | Jembatan USB | Nama port di Linux |
|---|---|---|
| Uno asli | ATmega16U2 (`2341:0043`) | `/dev/ttyACM*` |
| Klon | CH340 (`1a86:7523`), CH343 (`1a86:55d3`), FTDI, CP2102 | `/dev/ttyUSB*` |

Di Windows keduanya sama-sama muncul sebagai `COMx`, sehingga perbedaan ini tidak terasa sama sekali.

**Kenali port sebelum mengunggah:**

```bash
python3 tools/deteksi_port.py          # daftar port + jenis board
python3 tools/deteksi_port.py --ini    # potongan platformio.ini siap tempel
```

```
Port             VID:PID      Jenis          Jembatan USB
--------------------------------------------------------------
/dev/ttyACM0     2341:0043    Uno asli       ATmega16U2 (Arduino LLC)
/dev/ttyACM1     2341:0043    Uno asli       ATmega16U2 (Arduino LLC)
/dev/ttyUSB0     1a86:7523    klon           CH340/CH341
```

**Satu hal yang benar-benar berbeda perilakunya**, dan hanya di sisi perkakas: skrip Python yang menyetel jalur DTR/RTS **sebelum** `open()` ditolak oleh CDC ATmega16U2 pada Uno asli dengan `[Errno 110] Connection timed out`, sementara pada klon CH340 hal itu lolos. Seluruh `monitor_serial.py` pada seri ini sudah tidak menyentuh jalur tersebut. Bila menulis skrip serial sendiri, buka port apa adanya — jangan mengatur DTR/RTS sebelum membukanya.

## Menjalankan

**Modul 01–05 dan sisi slave Modul 07 — Arduino, lewat PlatformIO:**

```bash
pio device list                                      # catat port tiap board
pio run -d week01_lora_uart -e receiver -t upload    # penerima dahulu
pio run -d week01_lora_uart -e sender   -t upload -t monitor
```

**Modul 06 dan sisi master Modul 07 — Raspberry Pi, langsung dengan Python:**

```bash
sudo raspi-config                                    # Interface Options > SPI > Yes, lalu reboot
ls /dev/spi*                                         # harus muncul spidev0.0

pip3 install -r week06_rpi_lora_python/requirements.txt
python3 week06_rpi_lora_python/src/receiver.py       # penerima dahulu
python3 week06_rpi_lora_python/src/sender.py         # di Pi kedua
```

Tidak ada yang dikompilasi di sisi Raspberry Pi, sehingga tidak ada `platformio.ini` untuknya. `week07_rpi_master_slave/platformio.ini` hanya memuat kedua environment slave; masternya dijalankan sebagai `python3 src/master.py`.

Port di tiap `platformio.ini` masih memakai nilai contoh untuk tiga Uno asli. Jalankan `tools/deteksi_port.py` lebih dahulu (lihat bagian sebelumnya), lalu sesuaikan `upload_port`/`monitor_port` sesuai board yang benar-benar terpasang.

**Urutan unggah** penting di sebagian besar modul: pihak yang **menunggu** diunggah lebih dahulu, pihak yang **memulai** belakangan. Tiap README menyebutkan urutannya.

**Baud Serial Monitor**: 9600 untuk M01–M04, **115200 untuk M05 dan slave M07**. Modul 06 tidak memakai Serial Monitor sama sekali — keluarannya langsung ke terminal Raspberry Pi.

## Status verifikasi

Seluruh modul Arduino dikompilasi ulang setelah dikonversi ke PlatformIO. **Pengujian di perangkat keras belum dilakukan pada konversi ini** — tidak ada Arduino Uno bershield LoRa maupun Raspberry Pi bershield LoRa GPS HAT yang tersambung saat penyusunan. Perilaku yang dijelaskan di tiap README berasal dari kode sumber asli beserta dokumentasinya, bukan dari pengamatan ulang. Angka pada tabel pengukuran memang disediakan kosong untuk diisi praktikan.

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
| 07 | `slave1` | ✅ | 26,4 % (8.522 B) |
| 07 | `slave2` | ✅ | 26,4 % (8.522 B) |

Modul 06 dan master Modul 07 tidak muncul pada tabel di atas karena tidak ada yang dikompilasi: keduanya Python yang dijalankan langsung. Yang diperiksa pada keduanya hanya kesahihan sintaksis (`python3 -m py_compile`), sebab `spidev` dan `RPi.GPIO` hanya dapat dipasang di Raspberry Pi. Kode aslinya berasal dari repositori Dragino LoRa GPS HAT yang menyatakan telah diuji berjalan pada Raspberry Pi 4.

**Perubahan terhadap kode asli.** Yang berubah hampir seluruhnya cara membangun dan menamai berkas, bukan isi programnya; satu-satunya perubahan perilaku adalah baris terakhir tabel:

| Sebelum | Sesudah | Alasan |
|---|---|---|
| Berkas `.ino` per folder | `src/<peran>/main.cpp` + `platformio.ini` | Mengikuti alur PlatformIO seperti lab WSN-IOT-prak |
| `#define DEVICE_A` disunting manual (M03) | build flag `-DDEVICE_A` pada environment | Satu source untuk dua board; menghilangkan risiko lupa mengembalikan |
| `slave1.ino` dan `slave2.ino` terpisah (M05) | satu `slave/main.cpp` + `-DSLAVE_ID=n` | Kedua slave identik kecuali nomornya |
| Port ditulis `COM8`/`COM9` di komentar | `upload_port` di `platformio.ini` | Port terkumpul di satu tempat, tidak tersebar di komentar |
| `01a-sender.py` / `01b-receiver.py` (M06) | `src/sender.py` / `src/receiver.py` | Tata letak `src/` seragam dengan seluruh modul lain |
| Nama modul disebut di docstring sebagai contoh lepas | Docstring menunjuk modul lab yang dicerminkannya | Tiap berkas Python menyebut padanan Arduino-nya secara langsung |
| Pesan pembuka slave M07 tertulis mati `POLL:1` | Menyebut `SLAVE_ID` yang sesungguhnya | Slave 2 tidak lagi mencetak `Menunggu POLL:1` — cacat kecil yang masih ada di M05 |

## Referensi

**Arduino — shield (M01–M05, slave M07)**

- [Dragino LoRa Shield — repositori resmi](https://github.com/dragino/Lora/tree/master/Lora%20Shield)
- [Skematik Shield v1.2 (PDF)](skematik/Lora%20Shield%20v1.2.sch.pdf)
- [Library LoRa by sandeepmistry](https://github.com/sandeepmistry/arduino-LoRa)

**Raspberry Pi — HAT (M06, master M07)**

- [Wiki Dragino — Lora/GPS HAT](https://wiki1.dragino.com/index.php?title=Lora/GPS_HAT)
- [Dragino LoRa GPS HAT v1.4 — repositori resmi](https://github.com/dragino/Lora/tree/master/Lora_GPS%20HAT/v1.4)
- [Skematik LoRa GPS HAT v1.4 (PDF)](skematik/Lora%20GPS%20HAT%20for%20RPi%20v1.4.pdf)
- [User Manual LoRa GPS HAT v1.0 (PDF)](dokumen/LoRa_GPS_HAT_UserManual_v1.0.pdf)

**Umum**

- [Datasheet SX1276](https://www.semtech.com/products/wireless-rf/lora-connect/sx1276)
