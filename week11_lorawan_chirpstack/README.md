```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              LoRa COMMUNICATION LAB
     MODUL 11 — LoRaWAN: Protokol Mengambil Alih

 Arduino Uno + Raspberry Pi 5 + ChirpStack · Advanced
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 1 · Pendahuluan

Modul 11 dirancang untuk satu pertemuan (1 × 50 menit) pada tingkat lanjut, dan membuka arc ketiga lab ini. Sepuluh modul sebelumnya membangun sendiri semua yang menyerupai jaringan: alamat node di M05, ACK di M04 dan M08B, retry di M09, penjadwalan di M10. Semuanya buatan tangan, semuanya di lapisan aplikasi, dan semuanya berhenti bekerja begitu ada node ketiga atau gateway kedua. Modul ini menyerahkan seluruh pekerjaan itu kepada **protokol** — LoRaWAN — lalu memakai sisa waktunya untuk satu pertanyaan: apa yang sebenarnya Anda dapatkan sebagai gantinya, dan apa yang Anda serahkan.

Yang didapat: join dengan kunci (OTAA), alamat perangkat yang diberikan server (DevAddr), enkripsi payload ujung-ke-ujung, penomoran frame anti-ulang (FCnt), dan dua jendela downlink terjadwal. Yang diserahkan: kendali atas kapan node boleh bicara, dan kemampuan membaca isi paket dari gateway — sebab **gateway LoRaWAN tidak memegang kunci aplikasi**. Pemisahan peran itulah inti modul ini, dan cara membuktikannya sederhana: `single_chan_pkt_fwd.py` mencetak DevAddr dan FCnt tiap paket, tetapi tidak pernah bisa mencetak `T=27.4,H=68`. Angka itu baru muncul di ChirpStack.

Prasyaratnya M06 — driver register SX1276 di Python — karena gateway modul ini adalah kelanjutan langsung dari `week06_rpi_lora_python/src/receiver.py`, dengan register yang sama dan hanya beberapa tambahan (sync word LoRaWAN, header eksplisit, IQ terbalik untuk downlink). Prasyarat keduanya M08–M10, karena gateway kanal tunggal di sini setengah-dupleks: saat mengirim downlink ia tuli, dan uplink yang datang tepat pada saat itu hilang — persis tabrakan yang diukur di M08, kini dari sisi yang lain.

**Peta modul LoRa**

| Modul | Fokus (yang ditumpuk di atas modul sebelumnya) |
|---|---|
| 06 | Library dilepas — register SX1276 dipegang langsung dari Python |
| 07 | Penjadwal pindah ke gateway Linux, firmware node tidak berubah |
| 08–10 | Akses kanal tanpa penjadwal: ALOHA, ACK, retry, lalu slot |
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
| FCnt | Penghitung frame. Server menolak frame dengan FCnt yang sudah lewat — inilah anti-replay yang di M09 harus dibuat sendiri lewat `SEQ`. |
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
| Nomor urut & anti-duplikat | `SEQ` (M09) | FCnt, diperiksa server |
| Kirim ulang | retry + random backoff (M09) | Retry LMIC + ADR (dimatikan di modul ini) |
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
week11_lorawan_chirpstack/
├── platformio.ini
├── upload_auto.py                  ← upload kedua node, port dideteksi sendiri
├── logserial.md                    ← cuplikan log aktual dari pengujian perangkat
├── src/node/
│   ├── main.cpp                    ← LMIC OTAA + dummy sensor (env node1, node2)
│   └── lorawan_keys.h              ← DevEUI/JoinEUI/AppKey per node
└── gateway/                        ← seluruhnya dijalankan DI RASPBERRY PI
    ├── setup_chirpstack.sh         ← pasang Docker + ChirpStack v4 (sekali jalan)
    ├── docker-compose.override.yml ← satu-satunya perubahan: region EU433
    ├── single_chan_pkt_fwd.py      ← gateway kanal tunggal (lanjutan M06)
    ├── uplink_listen.py            ← baca uplink kedua node lewat MQTT + CSV
    ├── provision_lab.py            ← (asisten) daftarkan ulang isi server lewat API
    └── requirements.txt
```

**Perintah deploy**

```bash
# 1. DI RASPBERRY PI — server, sekali saja
bash week11_lorawan_chirpstack/gateway/setup_chirpstack.sh
pip3 install -r week11_lorawan_chirpstack/gateway/requirements.txt
#   Raspberry Pi OS Bookworm ke atas menolak pip di luar venv; pakai apt:
#   sudo apt install python3-spidev python3-rpi-lgpio python3-paho-mqtt

# 2. DI RASPBERRY PI — gateway; catat Gateway EUI yang tercetak
python3 week11_lorawan_chirpstack/gateway/single_chan_pkt_fwd.py

# 3. DI PC — kedua node, SETELAH gateway berjalan
python3 week11_lorawan_chirpstack/upload_auto.py --monitor

# 4. DI RASPBERRY PI — pantau data yang sudah didekripsi server
python3 week11_lorawan_chirpstack/gateway/uplink_listen.py
```

**Pre-flight checklist**

- ☐ Antena terpasang pada ketiga radio (dua shield + satu HAT).
- ☐ SPI aktif di Raspberry Pi (`ls /dev/spidev0.0`), dan `rpi-lgpio` terpasang — **bukan** RPi.GPIO asli (Pi 5).
- ☐ `docker compose ps` di `~/chirpstack-docker` menunjukkan seluruh service `Up`.
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
| Status gateway di ChirpStack setelah ±30 detik | **online** — berasal dari pesan `stat` tiap 30 detik |
| Region pada device profile | **EU433**, LoRaWAN 1.0.3, Regional parameters A, OTAA |
| DevEUI Node 1 / Node 2 seperti tampil di ChirpStack | **`0011223344556601`** / **`0011223344556602`** |

> **CHECKPOINT** — Gateway harus berubah menjadi **online** di ChirpStack sebelum node dinyalakan. Statusnya berasal dari pesan `stat` yang dikirim gateway tiap 30 detik; kalau tetap offline, periksa `--server` menunjuk ke IP yang benar dan port 1700/UDP tidak diblokir.

### EXP-02 — OTAA Join, dan satu kesalahan yang sengaja dibuat

Nyalakan Node 1 saja lebih dahulu (buka Serial Monitor 115200), amati sampai `[JOIN] BERHASIL`, baru nyalakan Node 2.

**Expected output — node**

```
=== LoRaWAN NODE 1 - Ruangan 1 ===
Kanal   : 433.175 MHz SF7BW125 (kanal tunggal)
Interval: 30 detik
Menyusun JoinRequest OTAA ...
[JOIN] mengirim JoinRequest ...
[TX] radio: 433175 kHz DR5
[JOIN] BERHASIL
  DevAddr : 7FCCA
  NetID   : 0
[TX #1] FPort=1 "T=27.3,H=64" -> antre di LMIC
[TX] selesai (FCntUp=1)
```

**Expected output — gateway**

```
[RX]  23 B  RSSI= -66 dBm  SNR=  9.8 dB  tmst=2744282123
     JoinRequest DevEUI=0011223344556601 DevNonce=3234
[TX] downlink dijadwalkan: 17 B  433.175 MHz  SF7BW125  dalam 4784 ms
     JoinAccept (17 byte)
[TX] terkirim (meleset -0.3 ms dari jadwal)
```

Sesudah join berhasil, **buat kesalahannya dengan sengaja**: balik urutan byte `DEVEUI` di `lorawan_keys.h` (tulis MSB-first seperti tampilan ChirpStack), unggah ulang, dan amati apa yang terjadi di kedua sisi.

**Data capture**

| Parameter | Node 1 | Node 2 |
|---|---|---|
| Percobaan join yang berhasil | **ke-1** | **ke-1** |
| Waktu dari `mengirim JoinRequest` sampai `BERHASIL` | **9,2 detik** | **12,6 detik** |
| DevAddr yang diberikan server | **`00ACC8E9`** | **`0013E3DD`** |
| RSSI / SNR JoinRequest di gateway | **−65 dBm / 9,8 dB** | **−61 dBm / 9,5 dB** |
| Jeda JoinAccept yang dijadwalkan server (ms) | **4784** | **4786** |
| Ketelitian penembakan JoinAccept | **−0,3 ms** | **−0,2 ms** |
| Dengan DevEUI terbalik: apakah gateway tetap menerima paket? | *(belum diuji — kerjakan sendiri)* | |
| Dengan DevEUI terbalik: apakah ChirpStack mencatat join? | *(belum diuji — kerjakan sendiri)* | |

Sebagian besar dari 9–12 detik itu **bukan** waktu udara: LMIC menunda JoinRequest pertama beberapa detik secara acak (supaya sekumpulan node yang menyala bersamaan tidak serentak bicara), lalu JoinAccept baru boleh dikirim 5 detik sesudah uplink. Waktu udara paketnya sendiri hanya puluhan milidetik.

**Buka abstraksinya** — di `src/node/main.cpp`, `lockSingleChannel()` dipanggil **tiga kali**, dan salah satunya ada di dalam `case EV_JOINING`. Hapus yang di `EV_JOINING` saja, unggah ulang, lalu baca baris `[TX] radio: ... kHz`. Jelaskan angka yang muncul, dan telusuri di sumber LMIC mengapa penguncian kanal yang dilakukan di `setup()` bisa hilang begitu saja. (Petunjuk: `LMICeulike_initJoinLoop()` memanggil `LMICbandplan_initDefaultChannels()`.)

> **CHECKPOINT** — DevAddr kedua node harus **berbeda**, dan keduanya diberikan server, bukan ditentukan firmware. Bila salah satu node tidak pernah join sementara yang lain lancar, periksa AppKey-nya di ChirpStack sebelum menyalahkan radio.

### EXP-03 — Uplink dua node: mengenali asal data tanpa melihat DevEUI

Biarkan kedua node berjalan minimal 5 menit. Buka **Applications → Devices → Events** di ChirpStack untuk kedua perangkat, dan jalankan `uplink_listen.py` di Raspberry Pi.

**Expected output — uplink_listen.py**

```
waktu     device      FCnt  payload          suhu    RH    RSSI    SNR
------------------------------------------------------------------------
16:20:13  node2-ruangan-2     0  T=31.8,H=53     31.8C   53%    -65 dBm   9.5 dB
16:20:41  node1-ruangan-1     0  T=27.3,H=64     27.3C   64%    -66 dBm   9.8 dB
```

**Data capture** (isi dari CSV `uplink_listen.py` atau tabel Events)

| Parameter | Node 1 | Node 2 |
|---|---|---|
| Jumlah uplink diterima selama ~5 menit | **10** | **9** |
| Rentang suhu yang terlihat | **25,2–29,9 °C** (spesifikasi 25–30) | **28,3–33,6 °C** (spesifikasi 28–35) |
| Rentang kelembapan yang terlihat | **60–74 %** (spesifikasi 60–75) | **40–62 %** (spesifikasi 40–65) |
| FCnt awal → akhir | **0 → 10** | **0 → 9** |
| Ada FCnt yang terlewat? Berapa? | **tidak ada** | **tidak ada** |
| RSSI rata-rata / SNR rata-rata | **−64,3 dBm / 9,8 dB** | **−61,6 dBm / 9,9 dB** |

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
| Ketelitian jadwal downlink (`meleset ... ms`), terbaik / terburuk | **−0,2 ms / −0,3 ms** dari 4 downlink |
| Jumlah uplink node yang tidak sampai ke gateway | **0 dari 19** — ketika node dinyalakan bergantian |
| Bila kedua node dinyalakan **bersamaan** | **1 JoinRequest hilang**, node itu baru join 69 detik kemudian |

**Buka abstraksinya** — di `gateway/single_chan_pkt_fwd.py`, fungsi `start_rx()` mengembalikan **frekuensi dan SF**, bukan hanya mode radio. Hapus dua baris `_set_frequency`/`_set_spreading_factor` di sana, jalankan sampai ada satu downlink RX2, lalu jelaskan mengapa sesudah itu gateway tidak pernah menerima apa pun lagi — dan mengapa tidak ada satu pun pesan galat yang muncul.

### Verifikasi hardware

**Diuji di perangkat pada 2026-08-22** — 2× Arduino Uno asli + Dragino LoRa Shield v1.2 (`/dev/ttyACM1`, `/dev/ttyACM2`), Raspberry Pi 5 (Debian 13) + Dragino LoRa GPS HAT v1.4 sebagai gateway, ChirpStack v4 di Docker pada Pi yang sama, region EU433. Build kedua environment sukses (RAM 69,8 %, Flash 75,0 % dari ATmega328P). EXP-02, EXP-03, dan EXP-04 dijalankan dan datanya nyata — kedua node **join OTAA pada percobaan pertama**, 19 uplink berturut-turut sampai ke aplikasi tanpa satu pun hilang selama ~5,5 menit, dan seluruh downlink meleset kurang dari 1 ms dari jadwal server. Rinciannya di `logserial.md`.

Yang **belum** dijalankan pada sesi ini dan memang menjadi pekerjaan praktikan: EXP-01 lewat web UI (di sesi ini pendaftaran dilakukan dengan `gateway/provision_lab.py` supaya cepat direproduksi), percobaan DevEUI sengaja dibalik di EXP-02, kedua kotak **Buka abstraksinya**, dan seluruh Challenge.

## 7 · Pengukuran

**A. Join OTAA**

| Node | Percobaan join ke- | Waktu join (detik) | DevAddr | RSSI JoinRequest | Jeda JoinAccept (ms) |
|---|---|---|---|---|---|
| Node 1 | 1 | 9,2 | `00ACC8E9` | −65 dBm | 4784 |
| Node 2 | 1 | 12,6 | `0013E3DD` | −61 dBm | 4786 |

**B. Uplink 5 menit**

| Node | Uplink dikirim (dari serial) | Uplink diterima gateway | Uplink muncul di ChirpStack | Loss (%) | RSSI rata-rata | SNR rata-rata |
|---|---|---|---|---|---|---|
| Node 1 | 10 | 10 | 10 | 0 | −64,3 dBm | 9,8 dB |
| Node 2 | 9 | 9 | 9 | 0 | −61,6 dBm | 9,9 dB |

**C. Rentang data dummy (bukti asal data)**

| Node | Suhu min | Suhu maks | RH min | RH maks | Sesuai spesifikasi ruangan? |
|---|---|---|---|---|---|
| Node 1 (25–30 °C, 60–75 %) | 25,2 | 29,9 | 60 | 74 | ya |
| Node 2 (28–35 °C, 40–65 %) | 28,3 | 33,6 | 40 | 62 | ya |

## 8 · Analisis

1. Dari tabel B, hitung loss tiap node. Bandingkan dengan loss M08 (Pure ALOHA) pada kepadatan kirim yang sebanding. Apakah LoRaWAN menghapus tabrakan, atau hanya memindahkan penanganannya? Dukung jawaban dengan data.
2. Gateway mencetak `DevAddr` dan `FCnt` untuk tiap uplink, tetapi tidak pernah mencetak suhu. Jelaskan secara teknis kunci mana yang dipegang siapa, dan mengapa pemisahan ini masuk akal untuk jaringan dengan ribuan gateway milik pihak lain.
3. Dari tabel A, bandingkan jeda JoinAccept (±5 detik) dengan jeda downlink data (±1 detik). Mengapa spesifikasi LoRaWAN memberi waktu jauh lebih panjang khusus untuk JoinAccept?
4. Modul ini mematikan ADR (`LMIC_setAdrMode(0)`). Jelaskan apa yang akan dilakukan server bila ADR aktif dan SNR uplink Anda tinggi, lalu jelaskan mengapa hal itu justru mematikan komunikasi pada gateway kanal tunggal.
5. Bandingkan `FCnt` LoRaWAN dengan `SEQ` yang dibuat sendiri di M09. Sebutkan dua hal yang dilakukan FCnt tetapi tidak dilakukan `SEQ`, dan jelaskan akibatnya bila keduanya tidak ada.

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
