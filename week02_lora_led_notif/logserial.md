# Log Serial — Modul 02 (Penerimaan Non-Blocking & Indikator LED)

Hasil aktual dari perangkat. Baud 9600, frekuensi **433 MHz**, SF7 / BW 125 kHz / CR 4/5 / 17 dBm. Jarak antar-board ±30 cm.

## Board & Port

| Peran | Environment | Port | Board |
|---|---|---|---|
| Sender | `sender` | `/dev/ttyUSB0` | Uno klon, bridge CH340 (`1a86:7523`) |
| Receiver | `receiver` | `/dev/ttyACM1` | Uno asli (`2341:0043`) |

Board Uno asli di `/dev/ttyACM0` tidak dipakai: shield-nya gagal `LoRa.begin()`. Diagnosisnya tercatat pada `../week01_lora_uart/logserial.md`.

Kedua aliran serial direkam bersamaan memakai `monitor_serial.py`, sehingga stempel waktunya berasal dari satu sumbu yang sama dan hitungan paket hilang berasal dari selisih nomor urut.

## EXP-01 — Penerimaan Tanpa Polling

```
[   1.813] RX      | === LoRa RECEIVER (Dragino) ===
[   1.813] RX      | Init LoRa ... OK
[   1.813] RX      | Freq: 433.00 MHz | BW: 125.00 kHz | SF7
[   1.813] RX      | Menunggu paket (non-blocking)...
[   1.822] TX      | === LoRa SENDER (Dragino) ===
[   1.822] TX      | Init LoRa ... OK
[   2.013] RX      | ================================
[   2.013] RX      | [RX] Pesan : Hello #0
[   2.013] RX      | [RX] RSSI  : -38 dBm
[   2.013] RX      | [RX] SNR   : 9.50 dB
[   2.013] RX      | ================================
[   2.022] TX      | Freq: 433.00 MHz | BW: 125.00 kHz | SF7 | Power: 17 dBm
[   2.022] TX      | Mulai kirim tiap 2 detik...
[   2.022] TX      | [TX] Kirim: "Hello #0" ... OK
```

| Parameter | Hasil |
|---|---|
| Apakah `parsePacket()` ada di `loop()` penerima? | **tidak** — hanya `if (rxFlag)` |
| Paket dikirim / diterima (20 s) | 9 / 9 (loss 0 %) |
| RSSI: min / maks / rata-rata | −38 / −38 / **−38,0 dBm** |
| SNR: min / maks / rata-rata | 9,00 / 9,50 / **9,28 dB** |
| Flash sender / receiver | 22,9 % (7.380 B) / 24,5 % (7.916 B) |

Penerima mencetak paket pertama **0,2 detik** setelah init, tanpa satu pun panggilan `parsePacket()` — pemberitahuan datang dari DIO0 lewat interrupt.

## EXP-02 — LED Sebagai Instrumen

**Belum diverifikasi.** Pengamatan LED bersifat visual dan tidak muncul pada aliran serial, sehingga tidak dapat direkam oleh perangkat lunak. Yang dapat dipastikan dari kode: `LED_PIN` disetel ke `LED_BUILTIN`, yaitu **D13**, pin yang sama dengan SCK jalur SPI menuju SX1276. Perbandingan D13 dengan LED eksternal di D3 perlu diamati langsung dengan mata sesuai prosedur pada README.

## EXP-03 — Bukti Non-Blocking

Percobaan inti modul ini. Pekerjaan tiruan `delay(n)` disisipkan pada awal `loop()` penerima, lalu jumlah paket hilang diukur selama 40 detik untuk tiap nilai.

**Pengirim tidak diubah sama sekali** — pengirim Modul 02 yang sama dipakai untuk kedua firmware penerima, sehingga satu-satunya variabel adalah mekanisme penerimaannya.

| `delay()` di `loop()` | M02 interrupt — hilang | M01 polling — hilang |
|---|---|---|
| 0 ms | 0 / 19 (**0 %**) | 0 / 19 (**0 %**) |
| 500 ms | 0 / 19 (**0 %**) | 13 / 19 (**68,4 %**) |
| 1500 ms | 0 / 19 (**0 %**) | 18 / 19 (**94,7 %**) |
| 3000 ms | 8 / 19 (**42,1 %**) | 19 / 19 (**100 %**) |

Data mentahnya:

```
EXP-03 — penerima INTERRUPT (M02):
  delay=0      dikirim 19 (0..18)  diterima 19 (0..18)  hilang 0 (0.0 %)
  delay=500    dikirim 19 (0..18)  diterima 19 (0..18)  hilang 0 (0.0 %)
  delay=1500   dikirim 19 (0..18)  diterima 19 (0..18)  hilang 0 (0.0 %)
  delay=3000   dikirim 19 (0..18)  diterima 11 (1..17)  hilang 8 (42.1 %)

EXP-03 — penerima POLLING (M01):
  delay=0      dikirim 19 (0..18)  diterima 19 (0..18)  hilang 0 (0.0 %)
  delay=500    dikirim 19 (0..18)  diterima  6 (11..16) hilang 13 (68.4 %)
  delay=1500   dikirim 19 (0..18)  diterima  1 (11..11) hilang 18 (94.7 %)
  delay=3000   dikirim 19 (0..18)  diterima  0          hilang 19 (100.0 %)
```

### Bacaan hasil

**Pada beban ringan keduanya setara.** Tanpa pekerjaan tiruan, kedua mekanisme menerima seluruh paket. Perbedaannya tidak akan terlihat bila diuji hanya pada kondisi ideal — inilah alasan percobaan ini memerlukan beban buatan.

**Polling runtuh sejak beban terkecil.** Dengan `delay(500)` saja, penerima polling sudah kehilangan 68 % paket, padahal pengirim hanya mengirim tiap 2 detik. Penyebabnya: `parsePacket()` hanya membaca paket yang **sedang** tersedia saat dipanggil. Selama `loop()` tertahan, paket yang tiba tidak diambil dari FIFO, dan paket berikutnya menimpanya.

**Interrupt bertahan sampai batas yang dapat dihitung.** Penerima interrupt tetap sempurna sampai `delay(1500)`, lalu runtuh pada `delay(3000)`. Batas itu bukan kebetulan: pengirim mengirim tiap **2000 ms**, sehingga selama penahanan 1500 ms masih ada sela untuk memproses paket dan memanggil `LoRa.receive()` kembali. Pada penahanan 3000 ms, paket baru sudah tiba sebelum penerima sempat mengambil paket sebelumnya dan mempersenjatai ulang radio — dan SX1276 hanya menyimpan satu paket pada satu waktu.

Kesimpulan yang dapat diuji ulang: interrupt memindahkan pemberitahuan ke perangkat keras, tetapi **tidak** membuat penerima kebal. Batas ketahanannya kira-kira sepanjang interval kirim, bukan tak berhingga.

## Catatan pengambilan log

- Seluruh penyisipan `delay()` pada EXP-03 dikembalikan ke kondisi semula setelah pengujian, dan firmware Modul 02 diunggah ulang untuk memastikan board kembali ke keadaan baku.
- Nilai `Paket dikirim` dihitung dari nomor urut yang benar-benar terlihat pada aliran serial pengirim, bukan diperkirakan dari lama pengujian.
- Baris `[TX] Kirim: ... OK` pada pengirim dicetak setelah `LoRa.endPacket()` kembali, tanpa memeriksa status radio — bukan bukti paket diterima siapa pun.
- Tabel pengukuran jarak pada README belum terisi: percobaan ini dijalankan di satu meja pada jarak tetap ±30 cm.
