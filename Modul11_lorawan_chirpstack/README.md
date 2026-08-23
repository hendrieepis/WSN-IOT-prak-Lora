```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
     MODUL 11 — LoRaWAN: Protokol Mengambil Alih

 Arduino Uno + Raspberry Pi 5 + ChirpStack · Advanced
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 11 dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat lanjut, dan membuka arc ketiga lab ini. Sepuluh modul sebelumnya membangun sendiri semua yang menyerupai jaringan: alamat node di M05, ACK di M04 dan M08B, retry di M08C, penjadwalan di M10. Semuanya buatan tangan, semuanya di lapisan aplikasi, dan semuanya berhenti bekerja begitu ada node ketiga atau gateway kedua. Modul ini menyerahkan seluruh pekerjaan itu kepada **protokol** — LoRaWAN — lalu memakai sisa waktunya untuk satu pertanyaan: apa yang sebenarnya Anda dapatkan sebagai gantinya, dan apa yang Anda serahkan.

Yang didapat: join dengan kunci (OTAA), alamat perangkat yang diberikan server (DevAddr), enkripsi payload ujung-ke-ujung, penomoran frame anti-ulang (FCnt), dan dua jendela downlink terjadwal. Yang diserahkan: kendali atas kapan node boleh bicara, dan kemampuan membaca isi paket dari gateway — sebab **gateway LoRaWAN tidak memegang kunci aplikasi**. Pemisahan peran itulah inti modul ini, dan cara membuktikannya sederhana: `single_chan_pkt_fwd.py` mencetak DevAddr dan FCnt tiap paket, tetapi tidak pernah bisa mencetak `T=27.4,H=68`. Angka itu baru muncul di ChirpStack.

Prasyaratnya M06 — driver register SX1276 di Python — karena gateway modul ini adalah kelanjutan langsung dari `Modul06_rpi_lora_python/src/receiver.py`, dengan register yang sama dan hanya beberapa tambahan (sync word LoRaWAN, header eksplisit, IQ terbalik untuk downlink). Prasyarat keduanya M08–M10 (arc akses kanal), karena gateway kanal tunggal di sini setengah-dupleks: saat mengirim downlink ia tuli, dan uplink yang datang tepat pada saat itu hilang — persis tabrakan yang diukur di M08, kini dari sisi yang lain.

**Peta modul LoRa**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 06 | Library dilepas — register SX1276 dipegang langsung dari Python |
| 07 | Penjadwal pindah ke gateway Linux, firmware node tidak berubah |
| 08–08C | Akses kanal tanpa penjadwal: ALOHA telanjang, lalu ACK, lalu retry acak |
| 09 | Carrier sense — dengar dulu sebelum bicara (CSMA/CA) |
| 10 | Slot waktu bersama: Slotted ALOHA (Mode A) dan TDMA (Mode B) |
| **11 (ini)** | **Seluruh lapisan MAC buatan tangan diganti protokol: LoRaWAN + ChirpStack** |

**Kontrak data modul ini.** Payload sengaja dibuat **sesederhana mungkin dan tanpa encoding**: ASCII polos `T=<suhu>,H=<kelembapan>`, dikirim *unconfirmed* di FPort 1. Pengemasan biner yang hemat byte adalah bahan modul berikutnya; di sini fokusnya tetap pada alur **Register Device → OTAA Join → Uplink → data terlihat di ChirpStack**. Rentang dummy tiap node dibedakan supaya asal data langsung terbaca di layar tanpa mencocokkan DevEUI:

| Node | Lokasi | Temperature | Humidity | Contoh payload |
|---|---|---|---|---|
| Node 1 | Ruangan 1 | 25–30 °C | 60–75 % | `T=27.4,H=68` |
| Node 2 | Ruangan 2 | 28–35 °C | 40–65 % | `T=31.2,H=52` |

## 2 · Capaian Pembelajaran

Setelah menyelesaikan modul ini, praktikan mampu:

1. Membedakan peran **gateway**, **network server**, dan **application server** pada LoRaWAN, serta membuktikan dari log bahwa gateway meneruskan paket tanpa dapat membaca isinya.
2. Mendaftarkan perangkat OTAA di ChirpStack (DevEUI, JoinEUI, AppKey) dan menjelaskan mengapa DevEUI ditulis terbalik urutan bytenya di firmware sementara AppKey tidak.
3. Menjelaskan sekuens **OTAA join**: JoinRequest berisi DevNonce dan MIC, JoinAccept dibalas di jendela RX1 pada detik ke-5, lalu NwkSKey/AppSKey diturunkan di kedua sisi dan DevAddr dipakai untuk seluruh uplink berikutnya.
4. Menjelaskan keterbatasan **single channel gateway** (satu frekuensi, satu SF, setengah-dupleks) dan menerapkan penguncian kanal di sisi node agar tetap dapat join.
5. Membaca uplink kedua node di ChirpStack dan lewat integrasi MQTT, serta menafsirkan FCnt, RSSI, SNR, dan asal data berdasarkan rentang dummy tiap ruangan.

**Kriteria keberhasilan**

- ☐ Gateway muncul **online** di ChirpStack dan mencetak `[RX] ... JoinRequest DevEUI=...` saat node dinyalakan.
- ☐ Kedua node mencetak `[JOIN] BERHASIL` beserta DevAddr yang berbeda, dan status keduanya di ChirpStack berubah menjadi ter-aktivasi.
- ☐ Uplink kedua node terlihat berselang-seling di **Applications → praktikum-wsn → Devices → Events**, dengan payload `T=..,H=..` yang rentangnya sesuai ruangannya.
- ☐ FCnt tiap node naik satu per satu tanpa lompat besar selama pengamatan berlangsung.

## 3 · Dasar Teori (secukupnya)

| Istilah | Definisi kerja di lab ini |
|---|---|
| Gateway | Penerus paket. Menangkap apa pun yang mengudara pada kanalnya, membungkusnya dalam UDP, mengirimkannya ke network server. Tidak punya kunci aplikasi, tidak tahu isi paket, tidak memutuskan apa pun. |
| Network server (ChirpStack) | Otak jaringan. Memeriksa MIC, menghapus duplikat dari banyak gateway, mengelola FCnt, menjawab join, dan menjadwalkan downlink. |
| Application server | Tujuan akhir data. Pada ChirpStack v4 menyatu dengan network server, dan pintu keluarnya adalah integrasi MQTT yang dipakai `uplink_listen.py`. |
| OTAA | *Over-The-Air Activation*. Perangkat join memakai DevEUI + JoinEUI + AppKey; kunci sesi diturunkan saat join, tidak pernah dikirim di udara. |
| ABP | Alternatifnya: kunci sesi ditanam langsung, tanpa join. Lebih mudah, tetapi tidak dipakai modul ini justru karena join-lah yang mau diamati. |
| DevEUI / JoinEUI | Identitas 64-bit perangkat dan server join. Di firmware LMIC ditulis **LSB-first**; di layar ChirpStack tampil MSB-first. |
| AppKey | Rahasia 128-bit. Ditulis **MSB-first** di kedua sisi (tidak dibalik). Dari sinilah NwkSKey dan AppSKey diturunkan. |
| DevAddr | Alamat 32-bit yang **diberikan server** saat join. Bandingkan dengan `NODE_ID` M05–M10 yang ditentukan sendiri lewat build flag. |
| FCnt | Penghitung frame. Server menolak frame dengan FCnt yang sudah lewat — inilah anti-replay yang di M08C harus dibuat sendiri lewat `SEQ`. |
| FPort | Nomor port aplikasi (1–223). Memisahkan jenis pesan dalam satu perangkat, tanpa perlu menaruh penanda di dalam payload. |
| Class A | Kelas paling hemat daya: node bicara kapan saja (seperti ALOHA di M08), lalu membuka **dua** jendela RX pendek sesudahnya. Server hanya boleh menjawab di jendela itu. |
| RX1 / RX2 | Jendela pertama: 1 detik sesudah uplink (5 detik untuk JoinAccept), frekuensi dan SF sama dengan uplink. Jendela kedua: 2 detik sesudahnya, di frekuensi tetap (EU433: 434.665 MHz SF12). |
| Sync word 0x34 | Penanda jaringan publik LoRaWAN. Modul 01–10 memakai 0x12 (privat) — itu sebabnya paket M01–M10 dan paket LoRaWAN tidak saling terdengar walau frekuensinya sama. |
| Semtech UDP (GWMP) | Protokol antara gateway dan server: `PUSH_DATA` membawa uplink, `PULL_DATA` menjaga jalur balik tetap terbuka, `PULL_RESP` membawa downlink beserta `tmst` — waktu persis paket harus mengudara. |

**Apa yang sebelumnya dibuat tangan, dan siapa yang mengerjakannya sekarang**

| Kemampuan | Dibuat sendiri di | Disediakan LoRaWAN sebagai |
|---|---|---|
| Alamat node | `NODE=1` (M05, M08–M10) | DevAddr dari server + DevEUI global |
| Balasan terima | `ACK=<id>,SEQ=<n>` (M04, M08B) | Confirmed uplink (satu argumen di `LMIC_setTxData2`) |
| Nomor urut & anti-duplikat | `SEQ` (M08C) | FCnt, diperiksa server |
| Kirim ulang | retry + random backoff (M08C) | Retry LMIC + ADR (dimatikan di modul ini) |
| Giliran bicara | SYNC + slot (M10) | Duty cycle + jendela RX1/RX2 |
| Kerahasiaan | tidak ada — semua terbaca di udara | AES-128: AppSKey (payload) dan NwkSKey (MIC) |

**Gateway hanya melihat amplop.** Inilah yang membedakan gateway LoRaWAN dari gateway M07 yang membaca isi paket dengan bebas. Jalankan `single_chan_pkt_fwd.py` dan bandingkan dua barisnya: gateway mencetak `UnconfirmedDataUp DevAddr=01D9B47E FCnt=3 FPort=1 (payload terenkripsi)`, sementara `uplink_listen.py` — yang menerima data setelah melewati network server — mencetak `T=31.8,H=53`. Data yang sama, dua sudut pandang, dan yang membedakannya hanya kepemilikan kunci.

**Keterbatasan single channel gateway.** Gateway sungguhan memakai konsentrator SX1301/SX1302 yang mendengar 8 kanal × seluruh SF sekaligus. Modul ini memakai SX1276 — satu modem, satu frekuensi, satu SF pada satu waktu. Tiga akibat yang harus disadari, dan ketiganya terlihat di percobaan:

1. **Node wajib dikunci.** Rencana kanal EU433 punya tiga kanal wajib (433.175/433.375/433.575). Node yang menyebar uplink ke ketiganya akan kehilangan dua dari tiga paketnya. Karena itu `lockSingleChannel()` di firmware mematikan semua kanal kecuali satu.
2. **Setengah-dupleks.** Saat menembakkan downlink, gateway tidak mendengarkan. Uplink node lain yang datang tepat pada saat itu hilang tanpa jejak — versi LoRaWAN dari tabrakan M08.
3. **Downlink dijadwalkan dari user space.** Jendela RX1 hanya terbuka beberapa puluh milidetik. Python tidak sepresisi pencacah keras konsentrator, karena itu node memakai `LMIC_setClockError(MAX_CLOCK_ERROR * 20 / 100)` untuk melebarkan jendelanya.

**EU433 di atas rencana kanal EU868.** Perangkat keras lab ini 433 MHz, dan ChirpStack memang punya region `eu433` (aktif secara bawaan; yang perlu diubah hanya awalan topik MQTT gateway bridge — lihat `gateway/docker-compose.override.yml`). Di sisi node, MCCI LMIC tidak menyediakan `CFG_eu433`, jadi dipakai `CFG_eu868` lalu frekuensi kanalnya ditimpa ke 433.175 MHz. Ini sah karena EU433 dan EU868 memakai **tabel datarate yang sama persis** (DR0 = SF12 … DR5 = SF7 pada BW125), sehingga DR5 di node berarti DR5 yang sama di server. Yang berbeda hanya frekuensi, dan itulah satu-satunya yang ditimpa.

**Sekuens yang diamati (join lalu dua uplink)**

```
   Node                        (udara)                 Gateway Pi 5          ChirpStack
     |                                                      |                     |
  JoinRequest ---------------------------------------->  [RX] PUSH_DATA ------->  periksa MIC
  (DevEUI, DevNonce, MIC)                                   |                     dengan AppKey
     |                                                      |  <---- PULL_RESP ---|  JoinAccept
     |                                                      |       (tmst = +5 s) |
  buka RX1 (t+5 s)  <----------- JoinAccept ------------ [TX] IQ terbalik         |
     |                                                      |                     |
  turunkan NwkSKey & AppSKey, pakai DevAddr                 |                     |
     |                                                      |                     |
  "T=27.4,H=68" (terenkripsi) ------------------------>  [RX] PUSH_DATA ------->  dekripsi
  FCnt=0, FPort=1                                           |                     terbitkan ke MQTT
     |                                                      |                     |
  buka RX1 (t+1 s), kosong -> RX2 (t+2 s), kosong           |                     |
     |                                                      |                     |
  (30 detik kemudian, FCnt=1) ...                           |                     |
```

## 4 · Topologi

```
        +---------------------+
        | Node 1              |
        | Arduino Uno+SX1276  |
        |                     |
        | Ruangan 1           |
        | 25-30 C / 60-75 %   |
        +----------+----------+
                   |
                   | LoRaWAN 433.175 MHz SF7
                   v
            Single Channel Gateway
              Raspberry Pi 5 + SX1276
              single_chan_pkt_fwd.py
                   |
                   | Semtech UDP :1700
                   v
            ChirpStack v4 (Docker, di Pi yang sama)
              network + application server
                   |
                   | MQTT :1883
                   v
            Web UI :8080  /  uplink_listen.py
                   ^
                   | LoRaWAN 433.175 MHz SF7
        +----------+----------+
        | Node 2              |
        | Arduino Uno+SX1276  |
        |                     |
        | Ruangan 2           |
        | 28-35 C / 40-65 %   |
        +---------------------+
```

| Perangkat | Environment / skrip | Peran |
|---|---|---|
| Node 1 | `node1` | Join OTAA, kirim dummy Ruangan 1 tiap 30 detik |
| Node 2 | `node2` | Join OTAA, kirim dummy Ruangan 2 tiap 30 detik |
| Raspberry Pi 5 | `gateway/single_chan_pkt_fwd.py` | Menangkap paket, meneruskan ke ChirpStack, menembakkan downlink |
| Raspberry Pi 5 | ChirpStack v4 (Docker) | Network + application server, web UI, broker MQTT |

Perhatikan bahwa **tidak ada environment `gateway`** di `platformio.ini` modul ini — gateway bukan lagi Arduino, seperti halnya master M07 yang juga sudah pindah ke Raspberry Pi.

## 5 · Alat yang Digunakan

| No | Peralatan | Spesifikasi | Jumlah |
|---|---|---|---|
| 1 | Arduino Uno | ATmega328P | 2 |
| 2 | Dragino LoRa Shield | v1.2, SX1276, 433 MHz | 2 |
| 3 | Raspberry Pi 5 | 4/8 GB, Raspberry Pi OS 64-bit | 1 |
| 4 | Dragino LoRa GPS HAT | v1.4, SX1276, 433 MHz | 1 |
| 5 | Antena SMA | **wajib terpasang sebelum diberi daya** | 3 |
| 6 | Kabel USB tipe B | kabel data | 2 |

**Pemetaan pin — node (Dragino LoRa Shield v1.2)**

| Pin Uno | Fungsi | Catatan |
|---|---|---|
| D10 | NSS / CS | sama seperti M01–M10 |
| D9 | RST | sama seperti M01–M10 |
| D2 | DIO0 | RxDone / TxDone |
| **D6** | **DIO1** | **BARU di modul ini.** RxTimeout — tanpa ini LMIC tidak pernah tahu kapan harus berhenti menunggu downlink. Sudah tersambung dari pabrik pada shield v1.2. |
| D11/D12/D13 | MOSI/MISO/SCK | SPI |

**Pemetaan pin — gateway (Dragino LoRa GPS HAT v1.4)**, sama seperti M06/M07:

| WiringPi | BCM | Fungsi |
|---|---|---|
| GPIO6 | 25 | LoRa_NSS |
| GPIO0 | 17 | RESET |
| GPIO7 | 4 | DIO0 |

**Struktur proyek**

```
Modul11_lorawan_chirpstack/
├── platformio.ini
├── upload_auto.py                  ← upload kedua node, port dideteksi sendiri
├── logserial.md                    ← cuplikan log aktual dari pengujian perangkat
├── src/node/
│   ├── main.cpp                    ← LMIC OTAA + dummy sensor (env node1, node2)
│   └── lorawan_keys.h              ← DevEUI/JoinEUI/AppKey per node
└── gateway/                        ← seluruhnya dijalankan DI RASPBERRY PI
    ├── setup_chirpstack.sh         ← pasang Docker + ChirpStack v4 (sekali jalan)
    ├── siapkan_gateway.sh          ← siapkan Pi satu kelompok (kanal + kunci + EUI)
    ├── lorawan-gateway.service     ← unit systemd, bila gateway ingin jalan otomatis
    ├── simpan_image_docker.sh      ← bungkus image ChirpStack untuk dipindah lewat flashdisk
    ├── docker-compose.override.yml ← satu-satunya perubahan: region EU433
    ├── single_chan_pkt_fwd.py      ← gateway kanal tunggal (lanjutan M06)
    ├── uplink_listen.py            ← baca uplink kedua node lewat MQTT + CSV
    ├── provision_lab.py            ← (asisten) daftarkan ulang isi server lewat API
    └── requirements.txt
```

**Perintah deploy**

```bash
# 1. DI RASPBERRY PI — server, sekali saja (belum pernah pakai Docker?
#    baca Lampiran A di akhir README ini lebih dulu — cukup lima perintah)
bash Modul11_lorawan_chirpstack/gateway/setup_chirpstack.sh
pip3 install -r Modul11_lorawan_chirpstack/gateway/requirements.txt
#   Raspberry Pi OS Bookworm ke atas menolak pip di luar venv; pakai apt:
#   sudo apt install python3-spidev python3-rpi-lgpio python3-paho-mqtt

# 2. DI RASPBERRY PI — gateway; catat Gateway EUI yang tercetak
python3 Modul11_lorawan_chirpstack/gateway/single_chan_pkt_fwd.py

# 3. DI PC — kedua node, SETELAH gateway berjalan
python3 Modul11_lorawan_chirpstack/upload_auto.py --monitor

# 4. DI RASPBERRY PI — pantau data yang sudah didekripsi server
python3 Modul11_lorawan_chirpstack/gateway/uplink_listen.py
```

Bila **beberapa kelompok bekerja bersamaan** di satu ruangan, langkah 1–2 diganti
satu perintah `siapkan_gateway.sh --kelompok <n>` dan hanya satu Pi yang perlu
menjalankan ChirpStack — lihat **Lampiran B**.

**Pre-flight checklist**

- ☐ Antena terpasang pada ketiga radio (dua shield + satu HAT).
- ☐ SPI aktif di Raspberry Pi (`ls /dev/spidev0.0`), dan `rpi-lgpio` terpasang — **bukan** RPi.GPIO asli (Pi 5).
- ☐ `docker compose ps` di `~/chirpstack-docker` menunjukkan seluruh service `Up` (cara membacanya: **Lampiran A**).
- ☐ Web UI ChirpStack terbuka di `http://<ip-pi>:8080` (admin / admin).
- ☐ Gateway EUI hasil `single_chan_pkt_fwd.py` sudah didaftarkan dan berstatus online.
- ☐ DevEUI dan AppKey di ChirpStack **sama persis** dengan `src/node/lorawan_keys.h` (ingat urutan byte DevEUI).
- ☐ Gateway dijalankan **lebih dahulu**, baru node dinyalakan.

## 6 · Percobaan

### EXP-01 — Register Device: menyiapkan jaringan sebelum ada satu pun paket

Jalankan server, lalu daftarkan tiga hal lewat web UI: gateway, device profile, dan kedua device. Urutan ini tidak boleh dibalik — device tidak bisa dibuat tanpa profile, dan uplink tidak akan diterima dari gateway yang tidak dikenal.

1. **Gateway** — Gateways → Add gateway. Isi *Gateway EUI* dengan nilai yang dicetak `single_chan_pkt_fwd.py` saat dijalankan.
2. **Device profile** — Device profiles → Add. Region **EU433**, MAC version **LoRaWAN 1.0.3**, Regional parameters **A**, aktifkan **Device supports OTAA**.
3. **Application** → Add, lalu **Add device** dua kali dengan DevEUI dari `lorawan_keys.h`, dan isi *Application key* dengan AppKey masing-masing node.

**Expected output — gateway (sebelum node dinyalakan)**

```
=== SINGLE CHANNEL LoRaWAN GATEWAY ===
Init SX1276 ... OK
Gateway EUI : 2CCF67FFFE53AC11
Server      : 127.0.0.1:1700 (Semtech UDP)
Kanal       : 433.175 MHz  SF7BW125  CR4/5
Sync word   : 0x34 (LoRaWAN publik)
```

**Data capture**

| Parameter | Hasil |
|---|---|
| Gateway EUI yang dipakai | **`2CCF67FFFE53AC11`** (diturunkan dari MAC `eth0` Pi) |
| Status gateway di ChirpStack setelah ±30 detik | **online** — `lastSeenAt` terisi dan maju tiap 30 detik, berasal dari pesan `stat` (bukan dari uplink; lihat catatan di A.6) |
| Region pada device profile | **EU433**, LoRaWAN 1.0.3, Regional parameters A, OTAA |
| DevEUI Node 1 / Node 2 seperti tampil di ChirpStack | **`0011223344556601`** / **`0011223344556602`** |

> **CHECKPOINT** — Gateway harus berubah menjadi **online** di ChirpStack sebelum node dinyalakan. Statusnya berasal dari pesan `stat` yang dikirim gateway tiap 30 detik; kalau tetap offline, periksa `--server` menunjuk ke IP yang benar dan port 1700/UDP tidak diblokir.

### EXP-02 — OTAA Join, dan satu kesalahan yang sengaja dibuat

Nyalakan Node 1 saja lebih dahulu (buka Serial Monitor 115200), amati sampai `[JOIN] BERHASIL`, baru nyalakan Node 2.

**Expected output — node**

```
=== LoRaWAN NODE 1 - Ruangan 1 (Kelompok 1) ===
Kanal   : 433.175 MHz SF7BW125 (kanal tunggal)
Interval: 30 detik
Menyusun JoinRequest OTAA ...
[JOIN] mengirim JoinRequest ...
[TX] radio: 433175 kHz DR5
[JOIN] BERHASIL
  DevAddr : 1EBD973
  NetID   : 0
[TX #1] FPort=1 "T=25.0,H=66" -> antre di LMIC
[TX] selesai (FCntUp=1)
```

`DevAddr` berbeda di tiap sesi — server memberi yang baru setiap kali perangkat join.

**Expected output — gateway**

```
17:18:43.397  [RX]  23 B  RSSI= -66 dBm  SNR=  9.8 dB  tmst=1631694015
              JoinRequest DevEUI=0011223344556601 DevNonce=23600
17:18:43.611  [TX] downlink dijadwalkan: 17 B  433.175 MHz  SF7BW125  dalam 4786 ms
              JoinAccept (17 byte)
17:18:48.443  [TX] terkirim (meleset -0.2 ms dari jadwal)
```

Sesudah join berhasil, **buat kesalahannya dengan sengaja**: balik urutan byte `DEVEUI` di `lorawan_keys.h` (tulis MSB-first seperti tampilan ChirpStack), unggah ulang, dan amati apa yang terjadi di kedua sisi.

**Data capture**

| Parameter | Node 1 | Node 2 |
|---|---|---|
| Percobaan join yang berhasil | **ke-1** | **ke-1** |
| Waktu dari `mengirim JoinRequest` sampai `BERHASIL` | **8,2 detik** | **6,5 detik** |
| DevAddr yang diberikan server | **`01EBD973`** | **`01DC98E3`** |
| RSSI / SNR JoinRequest di gateway | **−66 dBm / 9,8 dB** | **−64 dBm / 9,8 dB** |
| Jeda JoinAccept yang dijadwalkan server (ms) | **4786** | **4786** |
| Ketelitian penembakan JoinAccept | **−0,2 ms** | **−0,4 ms** |
| Dengan DevEUI terbalik: apakah gateway tetap menerima paket? | *(belum diuji — kerjakan sendiri)* | |
| Dengan DevEUI terbalik: apakah ChirpStack mencatat join? | *(belum diuji — kerjakan sendiri)* | |

Sebagian besar dari 6–8 detik itu **bukan** waktu udara: LMIC menunda JoinRequest pertama beberapa detik secara acak (supaya sekumpulan node yang menyala bersamaan tidak serentak bicara), lalu JoinAccept baru boleh dikirim 5 detik sesudah uplink. Waktu udara paketnya sendiri hanya puluhan milidetik.

**Buka abstraksinya** — di `src/node/main.cpp`, `lockSingleChannel()` dipanggil **tiga kali**, dan salah satunya ada di dalam `case EV_JOINING`. Hapus yang di `EV_JOINING` saja, unggah ulang, lalu baca baris `[TX] radio: ... kHz`. Jelaskan angka yang muncul, dan telusuri di sumber LMIC mengapa penguncian kanal yang dilakukan di `setup()` bisa hilang begitu saja. (Petunjuk: `LMICeulike_initJoinLoop()` memanggil `LMICbandplan_initDefaultChannels()`.)

> **CHECKPOINT** — DevAddr kedua node harus **berbeda**, dan keduanya diberikan server, bukan ditentukan firmware. Bila salah satu node tidak pernah join sementara yang lain lancar, periksa AppKey-nya di ChirpStack sebelum menyalahkan radio.

### EXP-03 — Uplink dua node: mengenali asal data tanpa melihat DevEUI

Biarkan kedua node berjalan minimal 5 menit. Buka **Applications → Devices → Events** di ChirpStack untuk kedua perangkat, dan jalankan `uplink_listen.py` di Raspberry Pi.

**Expected output — uplink_listen.py**

```
waktu     device      FCnt  payload          suhu    RH    RSSI    SNR
------------------------------------------------------------------------
17:18:48  node1-ruangan-1     0  T=25.0,H=66     25.0C   66%    -67 dBm  10.0 dB
17:19:32  node2-ruangan-2     0  T=32.1,H=47     32.1C   47%    -64 dBm  11.8 dB
17:20:00  node1-ruangan-1     3  T=26.0,H=61     26.0C   61%    -67 dBm   9.8 dB
17:20:11  node2-ruangan-2     2  T=33.7,H=44     33.7C   44%    -63 dBm   9.8 dB
```

**Data capture** (isi dari CSV `uplink_listen.py` atau tabel Events)

| Parameter | Node 1 | Node 2 |
|---|---|---|
| Uplink dikirim (dihitung dari `[TX #n]` di serial) | **10** | **9** |
| Uplink yang sampai ke ChirpStack | **9** | **9** |
| Rentang suhu yang terlihat | **25,0–28,5 °C** (spesifikasi 25–30) | **31,1–34,4 °C** (spesifikasi 28–35) |
| Rentang kelembapan yang terlihat | **60–71 %** (spesifikasi 60–75) | **40–65 %** (spesifikasi 40–65) |
| FCnt awal → akhir | **0 → 10** | **0 → 9** |
| Ada FCnt yang terlewat? Berapa? | **ya — FCnt 2** (satu uplink hilang) | **tidak ada** |
| RSSI rata-rata / SNR rata-rata | **−66,1 dBm / 9,7 dB** | **−62,8 dBm / 10,0 dB** |

Satu frame per node **tidak** dihitung di tabel ini: uplink 15 byte tanpa FPort yang muncul beberapa detik sesudah join. Itu jawaban otomatis LMIC atas perintah MAC dari server, bukan data aplikasi — lihat `logserial.md`.

> **CHECKPOINT** — Tanpa melihat kolom nama perangkat, Anda harus bisa menebak node asal tiap baris hanya dari angkanya. Bila suhu Node 2 pernah terbaca di bawah 28 °C, berarti Anda membaca baris Node 1.

### EXP-04 — Kanal tunggal: harga yang dibayar

Amati apa yang hilang karena gateway hanya punya satu modem. Dua pengamatan, keduanya ada di log yang sudah Anda kumpulkan:

1. **Setengah-dupleks.** Cari di log gateway momen `[TX] terkirim` dan periksa apakah ada uplink node lain yang jatuh dalam jendela ±100 ms di sekitarnya. Bandingkan dengan `[TX] selesai (FCntUp=...)` di kedua node — uplink yang tidak pernah muncul di sisi gateway adalah uplink yang hilang.
2. **RX2 sebagai cadangan.** Bila server terlambat mengirim jawabannya, gateway mencetak `[TX] TERLAMBAT - jadwal sudah lewat` lalu ChirpStack mencoba lagi lewat RX2 (434.665 MHz SF12). Cari kejadian ini di log Anda.

**Data capture**

| Parameter | Hasil |
|---|---|
| Jumlah `[TX] TERLAMBAT` selama sesi | **0** (pada sesi lain, saat uplink pertama sesudah join, pernah terjadi 1×) |
| Jumlah downlink yang akhirnya lewat RX2 | **0** (pada sesi tersebut: 1, di 434.665 MHz SF12 — dan berhasil diterima node) |
| Ketelitian jadwal downlink (`meleset ... ms`), terbaik / terburuk | **−0,2 ms / −0,4 ms** dari 4 downlink |
| Jumlah uplink node yang tidak sampai ke gateway | **1 dari 19** — Node 1 `FCnt=2`, saat gateway sedang menangani JoinRequest Node 2 |
| Bila kedua node dinyalakan **bersamaan** | **1 JoinRequest hilang**, node itu baru join 69 detik kemudian |

Kejadian `FCnt` yang melompat itu justru bahan analisis paling berharga di modul ini: cocokkan cap waktu `[TX #n]` di serial node dengan log gateway pada detik yang sama, dan Anda akan menemukan gateway sedang sibuk dengan node lain. `logserial.md` memuat kedua log yang sudah disejajarkan.

**Buka abstraksinya** — di `gateway/single_chan_pkt_fwd.py`, fungsi `start_rx()` mengembalikan **frekuensi dan SF**, bukan hanya mode radio. Hapus dua baris `_set_frequency`/`_set_spreading_factor` di sana, jalankan sampai ada satu downlink RX2, lalu jelaskan mengapa sesudah itu gateway tidak pernah menerima apa pun lagi — dan mengapa tidak ada satu pun pesan galat yang muncul.

### Verifikasi hardware

**Diuji di perangkat pada 2026-08-22** — 2× Arduino Uno asli + Dragino LoRa Shield v1.2 (`/dev/ttyACM1`, `/dev/ttyACM2`), Raspberry Pi 5 (Debian 13) + Dragino LoRa GPS HAT v1.4 sebagai gateway, ChirpStack v4 di Docker pada Pi yang sama, region EU433. Build kedua environment sukses (RAM 69,8 %, Flash 75,0 % dari ATmega328P). EXP-02, EXP-03, dan EXP-04 dijalankan dengan kode yang persis seperti di repositori ini, dan datanya nyata — kedua node **join OTAA pada percobaan pertama**, **18 dari 19 uplink** sampai ke aplikasi selama jendela rekam 5,5 menit (yang satu hilang beserta penyebabnya terdokumentasi di `logserial.md`), dan seluruh downlink meleset kurang dari setengah milidetik dari jadwal server. Skema pembagian kelompok (Lampiran B) diuji terpisah dengan menjalankan kelompok 2 di 433.375 MHz.

Yang **belum** dijalankan pada sesi ini dan memang menjadi pekerjaan praktikan: EXP-01 lewat web UI (di sesi ini pendaftaran dilakukan dengan `gateway/provision_lab.py` supaya cepat direproduksi), percobaan DevEUI sengaja dibalik di EXP-02, kedua kotak **Buka abstraksinya**, dan seluruh Challenge.

## 7 · Pengukuran

**A. Join OTAA**

| Node | Percobaan join ke- | Waktu join (detik) | DevAddr | RSSI JoinRequest | Jeda JoinAccept (ms) |
|---|---|---|---|---|---|
| Node 1 | 1 | 8,2 | `01EBD973` | −66 dBm | 4786 |
| Node 2 | 1 | 6,5 | `01DC98E3` | −64 dBm | 4786 |

**B. Uplink 5 menit**

| Node | Uplink dikirim (dari serial) | Uplink diterima gateway | Uplink muncul di ChirpStack | Loss (%) | RSSI rata-rata | SNR rata-rata |
|---|---|---|---|---|---|---|
| Node 1 | 10 | 9 | 9 | 10 | −66,1 dBm | 9,7 dB |
| Node 2 | 9 | 9 | 9 | 0 | −62,8 dBm | 10,0 dB |

**C. Rentang data dummy (bukti asal data)**

| Node | Suhu min | Suhu maks | RH min | RH maks | Sesuai spesifikasi ruangan? |
|---|---|---|---|---|---|
| Node 1 (25–30 °C, 60–75 %) | 25,0 | 28,5 | 60 | 71 | ya |
| Node 2 (28–35 °C, 40–65 %) | 31,1 | 34,4 | 40 | 65 | ya |

## 8 · Analisis

1. Dari tabel B, hitung loss tiap node. Bandingkan dengan loss M08 (Pure ALOHA) pada kepadatan kirim yang sebanding. Apakah LoRaWAN menghapus tabrakan, atau hanya memindahkan penanganannya? Dukung jawaban dengan data.
2. Gateway mencetak `DevAddr` dan `FCnt` untuk tiap uplink, tetapi tidak pernah mencetak suhu. Jelaskan secara teknis kunci mana yang dipegang siapa, dan mengapa pemisahan ini masuk akal untuk jaringan dengan ribuan gateway milik pihak lain.
3. Dari tabel A, bandingkan jeda JoinAccept (±5 detik) dengan jeda downlink data (±1 detik). Mengapa spesifikasi LoRaWAN memberi waktu jauh lebih panjang khusus untuk JoinAccept?
4. Modul ini mematikan ADR (`LMIC_setAdrMode(0)`). Jelaskan apa yang akan dilakukan server bila ADR aktif dan SNR uplink Anda tinggi, lalu jelaskan mengapa hal itu justru mematikan komunikasi pada gateway kanal tunggal.
5. Bandingkan `FCnt` LoRaWAN dengan `SEQ` yang dibuat sendiri di M08C. Sebutkan dua hal yang dilakukan FCnt tetapi tidak dilakukan `SEQ`, dan jelaskan akibatnya bila keduanya tidak ada.

## 9 · Concept Check

1. Mengapa DevEUI ditulis terbalik urutan bytenya di firmware sementara AppKey tidak? Apa gejalanya bila keduanya tertukar?
2. Apa beda peran gateway di modul ini dengan peran gateway di M07? Sebutkan satu hal yang bisa dilakukan gateway M07 tetapi tidak boleh dilakukan gateway LoRaWAN.
3. Node ini Class A. Apa yang terjadi bila server ingin mengirim perintah ke node tepat setelah node selesai membuka jendela RX-nya?
4. Sync word LoRaWAN 0x34, sedangkan M01–M10 memakai 0x12. Apa yang terjadi bila node M08 dan node M11 dinyalakan bersamaan di frekuensi yang sama?
5. OTAA menurunkan kunci sesi saat join; ABP menanamnya langsung. Sebutkan satu keunggulan OTAA yang tidak dimiliki ABP, dan satu situasi nyata yang membuat orang tetap memilih ABP.

## 10 · Challenge (tugas modifikasi)

- **CH-1 — Confirmed uplink.** Ubah argumen terakhir `LMIC_setTxData2()` menjadi `1`, unggah ulang satu node saja, lalu bandingkan log kedua node: berapa downlink tambahan yang muncul di gateway, dan apa yang terjadi pada tingkat keberhasilan node yang satunya?
- **CH-2 — Payload biner.** Ganti payload ASCII `T=27.4,H=68` (11 byte) dengan 3 byte biner: suhu ×10 sebagai int16, kelembapan sebagai uint8. Tulis decoder-nya di device profile ChirpStack, lalu hitung penghematan waktu udara memakai kalkulator airtime LoRa.
- **CH-3 — Downlink.** Kirim downlink dari ChirpStack (Devices → Queue) berisi satu byte, dan tampilkan isinya di Serial Monitor node. Ukur berapa lama pesan itu menunggu sebelum benar-benar mengudara, dan jelaskan mengapa.
- **CH-4 — Node ketiga tanpa menyentuh gateway.** Tambahkan `node3` dengan rentang dummy Ruangan 3 sendiri. Catat apa saja yang perlu diubah di gateway (jawabannya: tidak ada) dan bandingkan dengan usaha menambah node ketiga di M10.

## 11 · Laporan

**Deliverable**

1. Misi dan capaian pembelajaran
2. Dasar teori ringkas — peran gateway/network server/application server, OTAA, Class A, keterbatasan kanal tunggal
3. Konfigurasi — Gateway EUI, region, device profile, DevEUI/AppKey kedua node, parameter radio
4. Hasil eksperimen — log gateway, log serial kedua node, dan tangkapan layar ChirpStack (EXP-01…04 beserta checkpoint)
5. Data pengukuran — tabel A, B, C pada bagian Pengukuran
6. Analisis dan concept check
7. Challenge — minimal CH-1
8. Kesimpulan yang disusun sendiri: bandingkan seluruh lapisan buatan tangan M04–M10 dengan yang disediakan LoRaWAN, dan tentukan untuk skenario seperti apa membangun sendiri masih lebih tepat


---

## Lampiran A · Docker seperlunya (untuk yang belum pernah memakainya)

Modul ini satu-satunya di lab yang memakai Docker, dan Anda **tidak** perlu mempelajarinya sebagai bahan kuliah. Lampiran ini hanya berisi yang benar-benar dipakai: lima perintah, cara membaca keluarannya, dan apa yang harus dilakukan kalau ada yang tidak beres.

### A.1 Kenapa harus ada Docker

ChirpStack bukan satu program. Supaya berjalan, ia memerlukan lima hal sekaligus:

| Komponen | Tugasnya di modul ini |
|---|---|
| `chirpstack` | network + application server: memeriksa MIC, mengelola join, FCnt, downlink |
| `chirpstack-gateway-bridge` | menerima UDP dari `single_chan_pkt_fwd.py` di port 1700 |
| `postgres` | menyimpan gateway, device, DevEUI/AppKey, dan sesi OTAA |
| `redis` | menyimpan keadaan sementara tiap perangkat |
| `mosquitto` | broker MQTT: pintu keluar data ke `uplink_listen.py` |

Memasang kelimanya satu per satu berarti mengurus lima versi, lima berkas konfigurasi, dan lima cara menyalakan — dan sebagian besar waktu praktikum akan habis di situ, bukan di LoRaWAN-nya.

Analogi yang mungkin lebih dekat: Docker itu seperti memakai **modul jadi** (modul relay, modul step-down) alih-alih merakitnya sendiri dari komponen. Kotaknya sudah berisi semua yang diperlukan dengan nilai yang sudah benar; Anda tinggal memberi daya dan menyambungkan pin yang tepat.

| Istilah Docker | Padanan yang mungkin lebih akrab |
|---|---|
| **image** | modul yang masih di dalam kemasan — belum menyala, isinya tetap |
| **container** | modul yang sedang menyala di atas meja |
| **volume** | EEPROM di dalam modul: isinya **tidak hilang** saat modul dimatikan |
| **docker-compose.yml** | skema rangkaian: modul apa saja, port mana disambung ke mana |
| `docker compose up -d` | menyalakan seluruh rangkaian sekaligus |

### A.2 Lima perintah yang dipakai

Semuanya dijalankan **dari dalam folder `~/chirpstack-docker`** — perintah `docker compose` membaca `docker-compose.yml` di folder tempat ia dipanggil, jadi kalau dijalankan dari folder lain akan berkata tidak menemukan apa-apa.

```bash
cd ~/chirpstack-docker
```

| Perintah | Artinya | Kapan dipakai |
|---|---|---|
| `docker compose ps` | apa saja yang sedang menyala | pertama kali dicek saat ada yang aneh |
| `docker compose up -d` | nyalakan semuanya (`-d` = jalan di latar belakang) | awal praktikum; aman diulang berkali-kali |
| `docker compose stop` | matikan sementara — **data tetap aman** | selesai praktikum |
| `docker compose logs -f chirpstack` | lihat "serial monitor" milik satu service | saat join gagal dan penyebabnya belum jelas |
| `docker compose restart` | matikan lalu nyalakan lagi | setelah mengubah berkas konfigurasi |

`Ctrl-C` pada `logs -f` hanya menutup tampilannya, **tidak** mematikan server.

Satu perintah lagi yang sebaiknya diketahui justru supaya tidak salah ketik:

```bash
docker compose down -v      # HAPUS container BESERTA datanya
```

`-v` itulah yang membuang volume — seluruh gateway, device, dan sesi OTAA yang sudah didaftarkan ikut hilang, dan EXP-01 harus diulang dari nol. Tanpa `-v`, `down` hanya membongkar container dan data tetap utuh.

### A.3 Membaca `docker compose ps`

```
SERVICE                                  STATUS          PORTS
chirpstack                               Up 43 minutes   0.0.0.0:8080->8080/tcp
chirpstack-gateway-bridge                Up 43 minutes   0.0.0.0:1700->1700/udp
chirpstack-gateway-bridge-basicstation   Up 43 minutes   0.0.0.0:3001->3001/tcp
chirpstack-rest-api                      Up 43 minutes   0.0.0.0:8090->8090/tcp
mosquitto                                Up 43 minutes   0.0.0.0:1883->1883/tcp
postgres                                 Up 43 minutes   5432/tcp
redis                                    Up 43 minutes   6379/tcp
```

Yang perlu dilihat hanya kolom **STATUS**: semuanya harus `Up`. `Exited` berarti mati; `Restarting` berarti gagal menyala berulang-ulang — dan penyebabnya selalu ada di `docker compose logs <nama service>`.

Kolom PORTS menjelaskan siapa memakai pintu yang mana:

| Port | Dipakai oleh | Terlihat di |
|---|---|---|
| 8080 | web UI ChirpStack | browser Anda |
| 1700/udp | `single_chan_pkt_fwd.py` | opsi `--server` pada skrip gateway |
| 1883 | `uplink_listen.py` | opsi `--host` |
| 8090 | `provision_lab.py` (REST API) | opsi `--api` |
| 3001 | protokol BasicStation | **tidak dipakai** modul ini, biarkan saja |

`postgres` dan `redis` tidak punya `0.0.0.0:` di depan portnya: keduanya hanya bisa dihubungi container lain, tidak dari jaringan. Itu memang disengaja.

### A.4 Perlu `sudo` atau tidak

`setup_chirpstack.sh` memasukkan pengguna `pi` ke grup `docker`, tetapi keanggotaan grup baru berlaku **setelah login ulang**. Jadi:

- Baru selesai memasang, masih di sesi SSH yang sama → muncul `permission denied ... /var/run/docker.sock`. Pakai `sudo docker compose ...`, atau keluar lalu SSH lagi.
- Sesi SSH baru → `docker compose ...` tanpa `sudo` sudah bisa. Di Pi lab ini sudah diuji dan memang bisa.

### A.5 Sesudah Raspberry Pi dimatikan atau reboot

| Yang terjadi | Keterangan |
|---|---|
| ChirpStack **hidup sendiri** | layanan Docker berstatus `enabled`, dan ketujuh container memakai kebijakan `restart: unless-stopped` |
| Data **tetap utuh** | gateway, device, DevEUI/AppKey, dan sesi OTAA tersimpan di volume; kedua node **tidak perlu join ulang** |
| `single_chan_pkt_fwd.py` **tidak** hidup sendiri | skrip gateway dijalankan dari terminal, jadi harus dijalankan lagi setiap kali Pi dinyalakan |

Satu pengecualian yang sering membingungkan: bila container pernah dihentikan **manual** dengan `docker compose stop`, ia tidak akan ikut hidup pada boot berikutnya — itu memang arti kata *unless-stopped*. Nyalakan lagi dengan `docker compose up -d`.

Diukur di Pi lab ini: sesudah `docker compose down` lalu `docker compose up -d`, web UI sudah menjawab **2 detik** kemudian, dan kedua device masih terdaftar lengkap — bukti bahwa membongkar container tidak menyentuh data.

**Diuji dengan reboot sungguhan** pada 2026-08-23. Dari perintah `reboot` sampai layanan kembali: SSH menjawab pada detik ke-**40**, web UI ChirpStack pada detik ke-**48**, dan ketujuh container berstatus `Up` tanpa satu pun perintah diketik. Seluruh data selamat — kedua aplikasi masih ada, dan sesi OTAA kedua node utuh (`fCntUp` 307 dan 306 melanjutkan hitungan sebelum reboot), sehingga node tidak perlu join ulang.

### A.6 Kalau ada yang tidak beres

| Gejala | Sebab yang paling sering | Tindakan |
|---|---|---|
| Web UI tidak terbuka dari laptop | Pi dan laptop beda jaringan, atau alamat IP-nya berubah | `hostname -I` di Pi, lalu buka `http://<ip>:8080` |
| `permission denied ... docker.sock` | belum login ulang sesudah pemasangan | keluar dan SSH lagi, atau pakai `sudo` |
| Satu service `Restarting` terus | konfigurasi salah atau port bentrok | `docker compose logs <service>` — bacanya dari bawah |
| `port is already allocated` | ada program lain memakai port yang sama | matikan program itu, atau ubah nomor port di `docker-compose.override.yml` |
| Gateway tetap **offline** di UI padahal skrip gateway jalan | hampir selalu bukan Docker: `--server` salah alamat, atau Gateway EUI yang didaftarkan berbeda | cocokkan EUI yang dicetak skrip dengan yang ada di UI |
| Uplink sampai ke gateway tapi tidak muncul di UI | region gateway bridge bukan `eu433` | pastikan `docker-compose.override.yml` ada di `~/chirpstack-docker`, lalu `docker compose up -d` |
| Gateway tetap **offline** di UI padahal uplink jelas masuk | pesan `stat` ditolak gateway bridge, biasanya karena format waktunya salah | `docker compose logs chirpstack-gateway-bridge \| grep "could not handle"` — lihat catatan di bawah tabel |

> **Kenapa "offline" bisa berdampingan dengan data yang masuk.** Status online sebuah gateway di ChirpStack tidak ditentukan oleh uplink yang diteruskannya, melainkan oleh pesan **`stat`** yang dikirim gateway tiap 30 detik. Keduanya berjalan di jalur yang terpisah, jadi sangat mungkin data mengalir sempurna sementara gateway tampak mati. Modul ini pernah mengalaminya persis: `stat` memakai cap waktu ISO 8601 seperti pada `rxpk`, padahal gateway bridge mengurainya dengan pola lama `2006-01-02 15:04:05 MST` — seluruh `stat` ditolak diam-diam selama berjam-jam. Sudah diperbaiki di `single_chan_pkt_fwd.py` (fungsi `stat_time_now()`), dan inilah alasan fungsi itu ada terpisah dari `iso_now()`.

Kalau benar-benar buntu, membangun ulang dari nol memakan waktu kurang dari satu menit — tetapi **seluruh pendaftaran EXP-01 hilang** dan harus diulang:

```bash
cd ~/chirpstack-docker
docker compose down -v
docker compose up -d
```

### A.7 Tiga hal yang sebaiknya tidak dilakukan

1. **Jangan** menjalankan `docker system prune -a --volumes`. Perintah itu menghapus semua volume yang tidak terpakai — termasuk basis data ChirpStack bila container sedang mati.
2. **Jangan** mengedit `docker-compose.yml` bawaan repo ChirpStack. Semua penyesuaian lab ini ada di `docker-compose.override.yml`, dan Docker Compose otomatis menggabungkan keduanya — sehingga repo resminya tetap bersih dan bisa diperbarui.
3. **Jangan** menghapus folder `~/chirpstack-docker` selagi container menyala. Hentikan dulu dengan `docker compose down`, baru hapus.

Sebagai gambaran ruang: seluruh image modul ini berukuran sekitar 640 MB dan volume datanya puluhan MB — jauh di bawah kapasitas kartu memori Raspberry Pi lab ini.


---

## Lampiran B · Menjalankan lab untuk beberapa kelompok sekaligus

Tiga kelompok, tiga Raspberry Pi, satu ruangan. Yang perlu diputuskan ada dua: siapa yang menjalankan server, dan bagaimana ketiga kelompok tidak saling mengganggu di udara.

### B.1 Satu server untuk sekelas — bukan satu server per kelompok

Network server adalah **infrastruktur bersama**; itu memang bentuk LoRaWAN di dunia nyata. Satu gateway melayani banyak perangkat, dan satu server melayani banyak gateway. Lab ini sebaiknya mengikuti bentuk yang sama:

```
Kelompok 1: Pi + HAT ──┐
Kelompok 2: Pi + HAT ──┼── UDP :1700 ──► satu Pi berisi ChirpStack (Docker)
Kelompok 3: Pi + HAT ──┘
```

| | Server bersama (dianjurkan) | Server sendiri tiap kelompok |
|---|---|---|
| Docker | hanya di **satu** Pi | di ketiga Pi |
| Yang dipasang di Pi kelompok | dua paket apt saja | Docker + 637 MB image |
| Kesiapan | menit | bergantung unduhan, dikali tiga |
| Pemisahan data antar-kelompok | lewat Application masing-masing | terpisah total |
| Mirip praktik nyata | ya | tidak |

Pi mana yang menjadi server bebas — boleh salah satu Pi kelompok, boleh Pi dosen. Yang penting alamat IP-nya tetap dan diketahui semua kelompok.

### B.2 Yang membedakan tiap kelompok

Bila ketiga kelompok memakai frekuensi **dan** kunci yang sama, akan terjadi hal yang jauh lebih membingungkan daripada sekadar tabrakan:

> Gateway kelompok B ikut mendengar JoinRequest node kelompok A. Karena AppKey-nya sama persis, MIC-nya sah di mata server, dan server pun mengirim JoinAccept. Node kelompok A bisa berakhir join ke jaringan kelompok B — datanya muncul di dashboard yang salah, tanpa satu pun pesan galat di sisi mana pun.

Karena itu nomor kelompok menggeser tiga hal sekaligus, dan semuanya dihitung dari **satu** angka:

| Kelompok | Kanal (EU433) | DevEUI Node 1 / Node 2 | AppKey (awalan) | Application di ChirpStack |
|---|---|---|---|---|
| 1 | 433.175 MHz | `0011223344556601` / `…6602` | `00…f1` / `00…f2` | `praktikum-wsn` |
| 2 | 433.375 MHz | `0011223344557701` / `…7702` | `01…f1` / `01…f2` | `praktikum-wsn-k2` |
| 3 | 433.575 MHz | `0011223344558801` / `…8802` | `02…f1` / `02…f2` | `praktikum-wsn-k3` |

Ketiga frekuensi itu bukan pilihan bebas: **itulah tiga kanal wajib rencana EU433**, yang sudah dikenal ChirpStack tanpa perlu konfigurasi tambahan. Kelompok 1 memakai nilai yang sama persis dengan seluruh contoh di modul ini, jadi tabel dan log di README tetap berlaku apa adanya.

### B.3 Langkah tiap kelompok

**1 · Di Raspberry Pi kelompok** — satu perintah, mengurus dependensi, SPI, dan menghitung Gateway EUI:

```bash
bash Modul11_lorawan_chirpstack/gateway/siapkan_gateway.sh \
     --kelompok 2 --server 192.168.1.45
```

Tambahkan `--dengan-server` pada Pi yang sekaligus menjalankan ChirpStack. Keluarannya berisi Gateway EUI, perintah menjalankan gateway, serta DevEUI dan AppKey yang harus didaftarkan — salin apa adanya:

```
 Gateway EUI : 2CCF67FFFE53AC11
 Kanal       : 433375000 Hz  SF7BW125
 Jalankan gateway:
   python3 single_chan_pkt_fwd.py --server 192.168.1.45 --freq 433375000
   DevEUI Node 1 : 0011223344557701
   AppKey Node 1 : 01112233445566778899aabbccddeef1
```

**2 · Di sisi node** — ubah **satu** baris di `platformio.ini`, lalu unggah ulang kedua node:

```ini
    -D KELOMPOK=2
```

Baris itu menentukan kanal sekaligus DevEUI dan AppKey; tidak ada berkas lain yang perlu disentuh. Periksa hasilnya di baris pembuka Serial Monitor:

```
=== LoRaWAN NODE 1 - Ruangan 1 (Kelompok 2) ===
Kanal   : 433.375 MHz SF7BW125 (kanal tunggal)
```

**3 · Di ChirpStack** — tiap kelompok mendaftarkan gateway dan kedua node-nya sendiri lewat web UI (ini inti EXP-01, jangan dilewati). Asisten yang ingin menyiapkan atau memulihkan seluruh kelas dengan cepat bisa memakai:

```bash
python3 gateway/provision_lab.py --token <API-KEY> \
        --gateway-id <EUI-KELOMPOK> --kelompok 2
```

### B.4 Hal-hal yang perlu diantisipasi

- **Jarak antar-meja.** Tiga kanal itu hanya berjarak 200 kHz, sedangkan bandwidth tiap sinyal 125 kHz dan node memancar 17 dBm. Dua papan yang berjarak beberapa sentimeter tetap dapat saling menulikan penerimaan meski beda kanal. Letakkan tiap kelompok di meja yang berbeda.
- **Lebih dari tiga kelompok.** EU433 hanya menyediakan tiga kanal wajib. Kelompok keempat boleh berbagi kanal dengan kelompok 1 **asalkan DevEUI dan AppKey-nya berbeda** — konsekuensinya hanya tabrakan yang lebih sering, bukan data yang tertukar. Skrip sengaja menolak `--kelompok 4` supaya keputusan itu diambil sadar, bukan tidak sengaja.
- **Satu Pi, satu radio.** Satu Raspberry Pi tidak bisa menjadi gateway dua kelompok sekaligus: SX1276 hanya punya satu modem, jadi satu frekuensi pada satu waktu.
- **Gateway EUI berbeda sendirinya.** EUI diturunkan dari MAC tiap Pi, jadi ketiga kelompok otomatis punya EUI berbeda tanpa diatur — tetapi berarti tiap kelompok wajib mendaftarkan EUI Pi-nya sendiri, bukan menyalin punya kelompok lain.

### B.5 Kalau tetap ingin meng-clone kartu SD

Cara ini masuk akal hanya bila internet lab tidak dapat diandalkan. Jangan memakai `dd` mentah: kartu 128 GB akan disalin seluruhnya termasuk ruang kosong. Pakai **rpi-clone** (berbasis rsync, hanya data terpakai) atau `dd` + **PiShrink**.

Sesudah itu, **tiap hasil clone wajib dibereskan** — kalau tidak, ketiga Pi akan bentrok di jaringan:

```bash
sudo hostnamectl set-hostname pi-gw2                   # 1. nama host jangan kembar
sudo rm /etc/ssh/ssh_host_*                            # 2. kunci host SSH jangan kembar
sudo dpkg-reconfigure openssh-server
sudo rm -f /etc/machine-id /var/lib/dbus/machine-id    # 3. machine-id kembar membuat
sudo systemd-machine-id-setup                          #    DHCP memberi IP yang sama
```

Keempat: basis data ChirpStack ikut tersalin, jadi isinya masih Gateway EUI Pi induk. Jalankan `siapkan_gateway.sh --kelompok <n> --token …` di tiap clone untuk mendaftarkan EUI Pi tersebut.

Alternatif yang jauh lebih ringan bila masalahnya memang internet ada di B.6.

### B.6 Memindahkan image lewat flashdisk, tanpa mengunduh ulang

Bila beberapa Pi masing-masing perlu menjalankan ChirpStack sendiri sementara internet lab lemah, yang berat bukan pemasangan Docker-nya melainkan **unduhan image**-nya. Image itu bisa dibungkus sekali di Pi yang sudah jalan, lalu dipindahkan:

```bash
# di Pi yang ChirpStack-nya sudah berjalan
bash gateway/simpan_image_docker.sh --keluar /media/pi/FLASHDISK/chirpstack.tar.gz

# di Pi tujuan, sesudah Docker terpasang
bash gateway/simpan_image_docker.sh --muat /media/pi/FLASHDISK/chirpstack.tar.gz
cd ~/chirpstack-docker && docker compose up -d
```

Daftar image tidak diketik manual, melainkan dibaca dari `docker-compose.yml` (`docker compose config --images`), sehingga tidak mungkin ketinggalan bila ChirpStack suatu saat menambah komponen. Kompresinya memakai `pigz` bila tersedia — Raspberry Pi 5 punya empat inti, dan `gzip` biasa hanya memakai satu.

Diukur di Pi lab ini: **6 image, 637 MB di dalam Docker → 165 MB** setelah dibungkus, **6,5 detik** untuk menyimpan dan **10,7 detik** untuk memuat kembali.

Dua hal yang **tidak** diselesaikan cara ini:

1. **Docker engine-nya sendiri tetap harus terpasang** di Pi tujuan. Yang dihemat hanya unduhan image. Bila Pi tujuan benar-benar tanpa internet sama sekali, siapkan paket `.deb`-nya lebih dahulu (`apt-get install --download-only`) dari mesin yang terhubung.
2. **Data tidak ikut terbawa.** Arsip ini berisi image, bukan volume — Pi tujuan akan menyala dengan basis data kosong, tanpa gateway dan tanpa device. Pendaftarannya diulang lewat web UI (EXP-01) atau `provision_lab.py`.

### B.7 Yang sudah diuji

Pemindahan image B.6 diuji di perangkat pada 2026-08-22, kedua arahnya: `docker save` menghasilkan arsip 165 MB dalam 6,5 detik, dan `--muat` mengembalikan keenam image (`Loaded image: chirpstack/chirpstack:4` dan seterusnya) dalam 10,7 detik.

Skema kelompok ini diuji di perangkat pada 2026-08-22 dengan menjalankan kelompok 2 secara penuh: gateway dipindah ke 433.375 MHz, node di-flash dengan `-D KELOMPOK=2`, dan hasilnya node mengirim di 433.375 MHz (`[TX] radio: 433375 kHz DR5`), join OTAA dengan DevEUI `0011223344557702`, mendapat DevAddr `00D1C237`, lalu uplink-nya masuk ke Application **`praktikum-wsn-k2`** yang terpisah dari `praktikum-wsn` milik kelompok 1. Join berhasil pada percobaan kedua; percobaan pertamanya tidak diterima node meski JoinAccept sudah ditembakkan tepat waktu — kejadian yang sama sesekali muncul juga pada kelompok 1 dan memang sifat gateway kanal tunggal, bukan akibat pembagian kelompok.


---

## Lampiran C · Menjalankan gateway otomatis lewat systemd

`single_chan_pkt_fwd.py` yang dijalankan dari terminal akan mati begitu SSH ditutup atau Pi dimatikan. Untuk praktikum itu justru tepat — baris `[RX]`/`[TX]` yang mengalir di layar adalah bahan EXP-02 sampai EXP-04. Tetapi untuk **demo yang ditinggal jalan** atau lab yang Pi-nya sering dimatikan, gateway sebaiknya hidup sendiri seperti ChirpStack.

### C.1 Memasang

```bash
bash Modul11_lorawan_chirpstack/gateway/siapkan_gateway.sh \
     --kelompok 1 --server 127.0.0.1 --service
```

Yang terpasang ada dua berkas, dan pemisahannya disengaja:

| Berkas | Isi | Kapan disentuh |
|---|---|---|
| `/etc/systemd/system/lorawan-gateway.service` | cara menjalankan: pengguna, folder kerja, perintah | hampir tidak pernah |
| `/etc/default/lorawan-gateway` | `SERVER`, `FREQ`, `OPSI` | tiap ganti kanal atau alamat server |

Jadi kelompok yang pindah kanal cukup mengubah satu baris:

```bash
sudo nano /etc/default/lorawan-gateway     # FREQ=433375000
sudo systemctl restart lorawan-gateway
```

### C.2 Perintah harian

| Perintah | Artinya |
|---|---|
| `systemctl status lorawan-gateway` | hidup atau tidak, plus beberapa baris terakhir |
| `journalctl -fu lorawan-gateway` | **pengganti terminal** — `[RX]`/`[TX]` mengalir seperti biasa |
| `sudo systemctl stop lorawan-gateway` | matikan, misalnya sebelum menjalankan manual |
| `sudo systemctl start lorawan-gateway` | nyalakan lagi |
| `sudo systemctl disable --now lorawan-gateway` | matikan sekaligus cabut dari daftar boot |

> **Folder repo pindah atau berganti nama?** Berkas unit menyimpan lokasi skrip sebagai `WorkingDirectory`, jadi layanan akan gagal menyala dengan `status=200/CHDIR`. Perbaikannya satu perintah: jalankan ulang `siapkan_gateway.sh --kelompok <n> --service` dari lokasi yang baru — berkas unitnya ditulis ulang dengan path yang benar.

> **Jangan menjalankan skrip manual selagi layanan hidup.** Keduanya akan berebut `/dev/spidev0.0` dan register SX1276 yang sama, dan gejalanya bukan pesan galat melainkan paket yang hilang serta downlink yang kacau. Hentikan layanannya dulu.

### C.3 Perilaku yang sudah diatur

- **Ikut hidup saat boot** (`WantedBy=multi-user.target`, `enable` dijalankan oleh skrip).
- **Bangun sendiri bila jatuh** — `Restart=on-failure` dengan jeda 10 detik, berguna bila HAT belum siap saat boot. Batasnya 10 percobaan per 5 menit, supaya kegagalan permanen (HAT lepas, SPI mati) tidak menjadi loop tanpa henti; sesudah itu layanan berhenti dan alasannya terbaca di `journalctl`.
- **Berhenti dengan bersih.** systemd mengirim SIGTERM, dan skrip menanganinya sama seperti Ctrl-C: radio dikembalikan ke mode sleep, SPI ditutup, GPIO dilepas. Di journal terlihat sebagai `Dihentikan.` lalu `Radio dimatikan.`

### C.4 Yang sudah diuji

Diuji di perangkat pada 2026-08-22: layanan terpasang, berstatus `enabled` + `active`, dan uplink kedua node muncul di `journalctl` persis seperti saat dijalankan manual. `systemctl restart` pulih sendiri tanpa satu pun traceback, dan `systemctl stop` menghasilkan penutupan bersih (`Dihentikan.` → `Radio dimatikan.` → `Deactivated successfully`). Reboot sungguhan diuji pada 2026-08-23: layanan tegak sendiri **12 detik** sesudah kernel selesai boot, radio terinisialisasi (`Init SX1276 ... OK`), dan gateway kembali tercatat aktif di ChirpStack — tanpa satu pun perintah diketik. Rincian waktunya di A.5.


---

## Lampiran D · Menyiapkan Raspberry Pi 5 lain dari nol

Resep lengkap dari Pi yang baru selesai di-*flash* sampai ChirpStack berjalan. Ada dua jalur: **D.2** bila Pi punya internet yang layak, **D.3** bila tidak — memakai arsip image yang sudah dibungkus (`docker save`) sehingga tidak ada unduhan ratusan MB dari Docker Hub.

### D.1 Yang perlu ada lebih dulu

- Raspberry Pi OS **64-bit** (lab ini diuji di Debian 13 / Pi OS berbasis trixie), SSH aktif.
- Dragino LoRa GPS HAT terpasang dan SPI menyala. `siapkan_gateway.sh` akan menyalakan SPI sendiri bila belum, tetapi butuh satu kali reboot sesudahnya.
- Repositori lab ini ada di Pi tersebut:
  ```bash
  git clone <url-repo> ~/Documents/WSN-IOT-prak-Lora
  cd ~/Documents/WSN-IOT-prak-Lora
  ```
  Bila Pi tidak terhubung internet sama sekali, salin foldernya lewat flashdisk.

### D.2 Jalur cepat — Pi punya internet

```bash
bash Modul11_lorawan_chirpstack/gateway/setup_chirpstack.sh
```

Satu perintah itu memasang Docker (lewat skrip resmi `get.docker.com`), mengambil `chirpstack-docker`, memasang penyesuaian EU433, lalu menyalakan seluruh service. Sesudah selesai, lanjut ke **D.4**.

Satu hal yang sering membingungkan sesudah pemasangan pertama: perintah `docker` masih menolak dengan `permission denied ... docker.sock`. Penyebabnya keanggotaan grup `docker` baru berlaku pada sesi login berikutnya — keluar dari SSH lalu masuk lagi, atau sementara pakai `sudo`.

### D.3 Jalur tanpa unduhan besar — image dari arsip

Docker engine-nya tetap perlu dipasang sekali (langkah 1); yang dihemat adalah unduhan **image** yang jauh lebih besar.

**1 · Pasang Docker.** Bila Pi punya internet sebentar saja, ini cukup:

```bash
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sudo sh /tmp/get-docker.sh
sudo usermod -aG docker "$USER"      # keluar-masuk SSH sekali sesudah ini
```

Bila benar-benar tanpa internet, siapkan paketnya lebih dulu dari mesin yang terhubung (`sudo apt-get install --download-only docker.io`), salin berkas `.deb`-nya, lalu `sudo dpkg -i *.deb`.

**2 · Ambil arsip image.** Berkasnya (165 MB, berisi keenam image) ada di pCloud:

```
https://e.pcloud.link/publink/show?code=XZ2LUy7Zku2jHxEVvXmYmoQPqWw1GVbQaI7k
```

Lewat browser cukup klik unduh. Dari terminal Pi, tautan unduhan langsungnya harus diminta dulu ke API pCloud — tautan itu **kedaluwarsa dalam beberapa jam**, jadi jangan disimpan, mintalah baru setiap kali:

```bash
CODE=XZ2LUy7Zku2jHxEVvXmYmoQPqWw1GVbQaI7k
URL=$(curl -s "https://eapi.pcloud.com/getpublinkdownload?code=$CODE" \
      | python3 -c 'import sys,json; d=json.load(sys.stdin); print("https://"+d["hosts"][0]+d["path"])')
wget -O chirpstack-images.tar.gz "$URL"
```

`eapi.pcloud.com` dipakai karena tautannya beralamat `e.pcloud.link` (server Eropa); untuk tautan `u.pcloud.link` gantilah menjadi `api.pcloud.com`.

Periksa hasil unduhan sebelum dipakai:

```bash
sha256sum chirpstack-images.tar.gz
# aa10fae4a3688d7552e667128e74e2d8063af26fa003c15e5cac07ee633821a4
```

Alternatifnya tanpa internet sama sekali: salin berkas yang sama lewat flashdisk dari Pi yang sudah jalan — lihat **B.6**.

**3 · Muat image ke Docker:**

```bash
bash Modul11_lorawan_chirpstack/gateway/simpan_image_docker.sh --muat chirpstack-images.tar.gz
```

**4 · Siapkan folder ChirpStack.** `setup_chirpstack.sh` biasanya meng-*clone* `chirpstack-docker` dari GitHub. Bila Pi tidak punya internet, salin saja foldernya (hanya ±850 KB, berisi berkas konfigurasi) dari Pi yang sudah jalan ke `~/chirpstack-docker`. Skripnya memeriksa keberadaan folder itu dan melewati proses clone bila sudah ada:

```bash
bash Modul11_lorawan_chirpstack/gateway/setup_chirpstack.sh
```

Image yang diperlukan sudah ada di Docker lokal, jadi `docker compose up -d` tidak akan menariknya lagi dari internet.

### D.4 Menjadikan Pi itu gateway kelompok

```bash
bash Modul11_lorawan_chirpstack/gateway/siapkan_gateway.sh --kelompok 2 --server 192.168.1.45
```

Ganti `--server` dengan alamat Pi yang menjalankan ChirpStack — boleh Pi ini sendiri (`127.0.0.1`) bila D.2/D.3 dijalankan di sini juga. Tambahkan `--service` bila gateway ingin hidup otomatis tiap Pi menyala (**Lampiran C**). Keluarannya memuat Gateway EUI serta DevEUI/AppKey kelompok tersebut, yang tinggal didaftarkan di ChirpStack (EXP-01).

Sesudah itu Pi baru ini setara dengan Pi lab: web UI di `http://<ip>:8080` (bila menjalankan server sendiri), gateway mendengarkan di kanal kelompoknya, dan node tinggal di-*upload* dengan `-D KELOMPOK=<n>` yang cocok.

### D.5 Yang sudah diuji

Pemasangan Docker lewat `get.docker.com` dijalankan di perangkat pada 2026-08-22 di Raspberry Pi 5 dengan Debian 13 (hasil: Docker 29.7.2, Compose v5.5.0), diikuti `setup_chirpstack.sh` sampai ChirpStack melayani web UI. Pembungkusan dan pemuatan ulang image diuji dua arah (**B.6**). Tautan pCloud di D.3 diuji pada 2026-08-23: API-nya menghasilkan tautan unduhan yang sah, berkasnya berukuran 172.701.363 byte, dan potongan awal yang diunduh identik dengan arsip asli.

Yang **belum** diuji: menjalankan seluruh rangkaian D.3 di Raspberry Pi kedua yang benar-benar bersih — lab ini baru punya satu Pi.
