# M05 — Multinode LoRa: Satu Kanal, Banyak Node

## Pendahuluan

Pada modul sebelumnya, komunikasi LoRa dilakukan antara dua perangkat. Pada modul ini, sistem dikembangkan menjadi **satu Master dan beberapa Slave** yang berbagi **satu kanal radio**.

Tantangan utama pada sistem multinode bukan hanya mengirim data, tetapi mengatur:

- siapa yang boleh mengirim,
- kapan node boleh mengirim,
- node mana yang harus menjawab,
- dan bagaimana menghindari beberapa node mengirim secara bersamaan.

Pada praktikum ini digunakan pendekatan **Master-driven polling**. Master mengatur giliran komunikasi, sedangkan setiap Slave hanya menjawab ketika dipanggil.

---

## Tujuan Praktikum

Setelah menyelesaikan praktikum ini, mahasiswa mampu:

1. Memahami konsep komunikasi LoRa multinode pada satu kanal radio.
2. Membedakan **kanal radio** dan **identitas node**.
3. Mengimplementasikan pengalamatan sederhana menggunakan `SLAVE_ID`.
4. Mengimplementasikan komunikasi polling antara Master dan beberapa Slave.
5. Menjelaskan mengapa hanya satu node yang boleh mengirim pada satu waktu.
6. Mengamati mekanisme respons, ignore, dan timeout pada sistem multinode.

---

# 1. Dasar Teori

## 1.1 Shared Radio Channel

Pada praktikum ini, semua node menggunakan konfigurasi radio yang sama.

Contoh:

```text
Frequency       = 433 MHz
Bandwidth       = 125 kHz
SpreadingFactor = SF7
Coding Rate     = 4/5
```

Dengan demikian, Master dan seluruh Slave berada pada **kanal komunikasi yang sama**.

```text
MASTER   ─┐
SLAVE 1  ─┤
SLAVE 2  ─┼── Shared LoRa Channel
SLAVE 3  ─┤
SLAVE N  ─┘
```

Frekuensi bukan identitas node.

Misalnya:

```text
433 MHz ≠ Slave 1
```

Semua node dapat menggunakan frekuensi yang sama. Identitas setiap node dibedakan menggunakan **Node ID**.

---

## 1.2 Node ID

Setiap Slave memiliki identitas unik.

```text
Slave 1 → SLAVE_ID = 1
Slave 2 → SLAVE_ID = 2
Slave 3 → SLAVE_ID = 3
```

ID ini digunakan pada level aplikasi untuk menentukan node tujuan.

Contoh:

```text
POLL:1
```

berarti:

> Master memanggil Slave dengan ID 1.

Sedangkan:

```text
POLL:2
```

berarti:

> Master memanggil Slave dengan ID 2.

---

## 1.3 Polling

Polling adalah mekanisme ketika Master secara aktif memanggil node satu per satu.

Urutan sederhananya:

```text
Master → POLL:1
Slave 1 → Response

Master → POLL:2
Slave 2 → Response

Master → POLL:3
Slave 3 → Response
```

Master tidak memanggil semua Slave sekaligus.

Master menunggu hasil dari Slave yang sedang dipanggil sebelum melanjutkan ke Slave berikutnya.

---

## 1.4 Mengapa Perlu Scheduling?

Semua node menggunakan media radio yang sama.

Jika semua Slave bebas mengirim kapan saja:

```text
Slave 1 ───►
Slave 2 ───►  RADIO CHANNEL
Slave 3 ───►
```

beberapa transmisi dapat terjadi bersamaan dan komunikasi menjadi sulit dikendalikan.

Karena itu, Master mengatur giliran komunikasi.

```text
Master
  │
  ├── Poll Slave 1
  │       └── Response / Timeout
  │
  ├── Poll Slave 2
  │       └── Response / Timeout
  │
  ├── Poll Slave 3
  │       └── Response / Timeout
  │
  └── Ulangi
```

---

# 2. Topologi Sistem

```text
                    ┌─────────────────┐
                    │     MASTER      │
                    │                 │
                    │ Arduino / Pi    │
                    │       +         │
                    │      LoRa       │
                    └────────┬────────┘
                             │
                     Shared Radio Channel
                       433 MHz / SF7
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
          ▼                  ▼                  ▼
     ┌──────────┐       ┌──────────┐       ┌──────────┐
     │ SLAVE 1  │       │ SLAVE 2  │       │ SLAVE 3  │
     │  Uno     │       │  Uno     │       │  Uno     │
     │ + LoRa   │       │ + LoRa   │       │ + LoRa   │
     └──────────┘       └──────────┘       └──────────┘
```

---

# 3. 🧠 Cara Membayangkan Jaringan Ini

## Seperti RS485 Multidrop, tetapi kabel bus diganti oleh udara

Untuk memahami jaringan ini, bayangkan sistem RS485 multidrop.

Pada RS485, semua perangkat terhubung pada satu kabel bus.

```text
                 MASTER
                    │
════════════════════╪════════════════════
                  RS485 BUS
════════════════════╪════════════════════
                    │
             ┌──────┼──────┐
             │      │      │
             ▼      ▼      ▼
           Slave1 Slave2 Slave3
```

Ketika Master mengirim pesan:

```text
POLL:2
```

semua perangkat pada bus dapat menerima atau mendengarkan pesan tersebut.

Namun:

```text
Slave 1 → Bukan untuk saya → Diam
Slave 2 → Untuk saya       → Menjawab
Slave 3 → Bukan untuk saya → Diam
```

Pada praktikum LoRa, konsepnya sama.

Perbedaannya:

```text
RS485 → Media bersama berupa kabel
LoRa  → Media bersama berupa kanal radio
```

Sehingga:

```text
                 MASTER
                    │
                    │ POLL:2
                    ▼

            )))))  RADIO  (((((

              /       |       \
             /        |        \
            ▼         ▼         ▼
         Slave1    Slave2    Slave3

          Ignore    Answer    Ignore
```

## Prinsip utama

> **Semua node mendengarkan. Hanya node yang dipanggil yang berbicara.**

---

# 4. Contoh Cara Kerja

Misalkan terdapat tiga Slave:

```text
Slave 1 → ID = 1
Slave 2 → ID = 2
Slave 3 → ID = 3
```

Master mengirim:

```text
POLL:1
```

Semua Slave berada pada kanal yang sama dan mendengarkan paket tersebut.

### Slave 1

```text
Pesan diterima : POLL:1
ID saya        : 1

Cocok → Menjawab
```

Slave 1 mengirim:

```text
S1:DATA:123
```

### Slave 2

```text
Pesan diterima : POLL:1
ID saya        : 2

Tidak cocok → Ignore
```

### Slave 3

```text
Pesan diterima : POLL:1
ID saya        : 3

Tidak cocok → Ignore
```

Setelah selesai, Master melanjutkan:

```text
POLL:2
```

Maka hanya Slave 2 yang menjawab.

Kemudian:

```text
POLL:3
```

Maka hanya Slave 3 yang menjawab.

---

# 5. Urutan Komunikasi

```text
MASTER                S1              S2              S3
   │                   │               │               │
   │──── POLL:1 ───────►               │               │
   │                   │               │               │
   │◄── S1:DATA:10 ────│               │               │
   │                   │               │               │
   │──────── POLL:2 ───────────────────►               │
   │                   │               │               │
   │◄────────────────── S2:DATA:20 ───│               │
   │                   │               │               │
   │──────────────────────────────────── POLL:3 ──────►│
   │                   │               │               │
   │◄──────────────────────────────────── S3:DATA:30 ─│
   │                   │               │               │
   └──────────────────── Next Cycle ──────────────────┘
```

---

# 6. Dua Konsep yang Harus Dibedakan

| Konsep | Fungsi |
|---|---|
| **433 MHz** | Kanal radio bersama |
| **SF / BW / CR** | Parameter komunikasi radio |
| **SLAVE_ID** | Identitas logis setiap node |
| `POLL:1` | Panggilan untuk Slave 1 |
| `POLL:2` | Panggilan untuk Slave 2 |
| `S1:DATA:123` | Respons dari Slave 1 |

Ingat:

```text
Frekuensi ≠ alamat node
```

Yang benar:

```text
SEMUA NODE
    │
    ▼
BERBAGI SATU KANAL RADIO
    │
    ▼
DIBEDAKAN DENGAN NODE ID
    │
    ▼
MASTER MENGATUR GILIRAN KOMUNIKASI
```

---

# 7. Kontrak Komunikasi

Pada praktikum ini digunakan format pesan sederhana.

## Master ke Slave

```text
POLL:<ID>
```

Contoh:

```text
POLL:1
POLL:2
POLL:3
```

## Slave ke Master

```text
S<ID>:DATA:<VALUE>
```

Contoh:

```text
S1:DATA:10
S2:DATA:20
S3:DATA:30
```

Kontrak komunikasi ini harus dipahami oleh Master dan Slave.

Platform perangkat dapat berbeda, tetapi format komunikasinya tetap.

Contoh:

```text
Arduino Master
      │
      └── LoRa ── Arduino Slave

Raspberry Pi Master
      │
      └── LoRa ── Arduino Slave
```

Selama keduanya menggunakan kontrak:

```text
POLL:<ID>
S<ID>:DATA:<VALUE>
```

komunikasi dapat tetap menggunakan prinsip yang sama.

---

# 8. Percobaan

## Langkah 1 — Siapkan Node

Siapkan minimal:

```text
1 Master
2 Slave
```

Konfigurasikan:

```text
Slave 1 → SLAVE_ID = 1
Slave 2 → SLAVE_ID = 2
```

Pastikan seluruh node menggunakan parameter LoRa yang sama.

---

## Langkah 2 — Jalankan Master dan Slave

Nyalakan seluruh node.

Perhatikan Serial Monitor masing-masing Slave.

---

## Langkah 3 — Amati POLL:1

Master mengirim:

```text
POLL:1
```

Amati:

```text
Slave 1 → menerima dan menjawab
Slave 2 → menerima tetapi ignore
```

Catat hasil pengamatan.

---

## Langkah 4 — Amati POLL:2

Master mengirim:

```text
POLL:2
```

Amati:

```text
Slave 1 → ignore
Slave 2 → menerima dan menjawab
```

---

## Langkah 5 — Uji Timeout

Matikan salah satu Slave.

Misalnya Slave 2.

Master tetap menjalankan polling:

```text
POLL:1 → Response
POLL:2 → Timeout
```

Setelah timeout, Master harus melanjutkan proses ke node berikutnya.

---

# 9. Pertanyaan Analisis

1. Mengapa semua Slave menggunakan parameter radio yang sama?
2. Apakah `433 MHz` merupakan alamat Slave? Jelaskan.
3. Ketika Master mengirim `POLL:1`, apakah Slave 2 dapat menerima paket tersebut?
4. Mengapa Slave 2 tidak memberikan respons?
5. Apa yang dapat terjadi jika semua Slave mengirim data secara bebas pada waktu yang sama?
6. Apa fungsi `SLAVE_ID` pada sistem ini?
7. Jelaskan mengapa pendekatan ini dapat dianalogikan dengan RS485 multidrop.
8. Apa yang terjadi jika dua Slave memiliki `SLAVE_ID` yang sama?
9. Mengapa Master perlu menunggu respons atau timeout sebelum memanggil Slave berikutnya?
10. Bagaimana cara menambahkan Slave 3 ke sistem?

---

# 10. Kesimpulan

Arsitektur komunikasi pada praktikum ini menggunakan prinsip:

```text
ONE MASTER
     │
     ▼
MANY SLAVES
     │
     ▼
ONE SHARED RADIO CHANNEL
```

Master mengatur giliran komunikasi dengan mengirimkan pesan:

```text
POLL:<ID>
```

Semua Slave mendengarkan kanal yang sama, tetapi hanya Slave dengan ID yang sesuai yang memberikan respons.

Prinsip utama sistem adalah:

> **Semua node mendengarkan. Hanya node yang dipanggil yang berbicara.**

Dengan pendekatan ini, satu kanal radio dapat digunakan oleh beberapa node secara teratur, dengan Master sebagai pengatur lalu lintas komunikasi.
