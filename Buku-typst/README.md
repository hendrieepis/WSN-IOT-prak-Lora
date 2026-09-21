# Buku Typst — Petunjuk Praktikum Komunikasi Jarak Jauh dengan LoRa

Sumber Typst buku petunjuk praktikum, hasil konversi berkas `README.md` tiap modul pada repositori `WSN-IOT-prak-Lora`. Template tampilan memakai [orange-book](https://typst.app/universe/package/orange-book/) versi `0.7.1`, sama dengan buku praktikum WSN & IoT agar kedua buku terbaca sebagai satu keluarga.

Seluruh berkas kode sumber tiap modul **dimuat lengkap** di dalam buku, sehingga buku dapat dipakai tanpa akses jaringan. Setiap bagian "Kode Program" juga memuat kotak **KODE SUMBER** berisi tautan ke salinan daringnya di <https://github.com/hendrieepis/WSN-IOT-prak-Lora>.

## Kompilasi

```bash
typst compile main.typ          # menghasilkan main.pdf
typst watch main.typ            # kompilasi ulang otomatis saat berkas berubah
```

Paket `orange-book` diambil otomatis dari Typst Universe pada kompilasi pertama. Buku ini diuji dengan Typst 0.14.2; hasilnya 376 halaman.

## Struktur

| Berkas / folder | Isi |
|---|---|
| `main.typ` | konfigurasi global, sampul, daftar isi, dan `include` tiap bab |
| `chapters/` | satu berkas Typst untuk setiap bab |
| `lib/callouts.typ` | kotak informasi: `catatan`, `tip`, `penting`, `peringatan`, `checkpoint`, `buka-abstraksi`, `todo`, `pengantar`, `tujuan-prak`, `identitas-modul` |
| `lib/helpers.typ` | pembungkus gambar, tabel, listing kode, blok keluaran, diagram ASCII, dan checklist |
| `assets/images/` | gambar dari `../assets/` dan `../Modul07_rpi_master_slave/assets/` |
| `assets/code/` | salinan **seluruh** berkas sumber tiap modul (81 berkas); dibaca `kode-berkas(...)` saat kompilasi |

## Peta bab dan sumbernya

| Bab | Berkas Typst | Sumber |
|---|---|---|
| Pendahuluan | `chapters/00-prakata.typ` | `../README.md` |
| Bab 1 — Modul 01 | `chapters/modul-01-lora-uart.typ` | `../Modul01_lora_uart/` |
| Bab 2 — Modul 02 | `chapters/modul-02-lora-led-notif.typ` | `../Modul02_lora_led_notif/` |
| Bab 3 — Modul 03 | `chapters/modul-03-lora-p2p.typ` | `../Modul03_lora_p2p/` |
| Bab 4 — Modul 04 | `chapters/modul-04-lora-ack.typ` | `../Modul04_lora_ack/` |
| Bab 5 — Modul 05 | `chapters/modul-05-lora-master-slave.typ` | `../Modul05_lora_master_slave/` |
| Bab 6 — Modul 06 | `chapters/modul-06-rpi-lora-python.typ` | `../Modul06_rpi_lora_python/` |
| Bab 7 — Modul 07 | `chapters/modul-07-rpi-master-slave.typ` | `../Modul07_rpi_master_slave/` |
| Bab 8 — Modul 07B | `chapters/modul-07b-rpi-master-slave-crc.typ` | `../Modul07b_rpi_master_slave_crc/` |
| Bab 9 — Modul 08 | `chapters/modul-08-lora-aloha-tanpa-ack.typ` | `../Modul08_lora_aloha_tanpa_ack/` |
| Bab 10 — Modul 08B | `chapters/modul-08b-lora-aloha-ack.typ` | `../Modul08b_lora_aloha_ack/` |
| Bab 11 — Modul 08C | `chapters/modul-08c-lora-aloha-retry.typ` | `../Modul08c_lora_aloha_retry/` |
| Bab 12 — Modul 09 | `chapters/modul-09-lora-csma-ca.typ` | `../Modul09_lora_csma_ca/` |
| Bab 13 — Modul 10 | `chapters/modul-10-lora-slotted-aloha-tdma.typ` | `../Modul10_lora_slotted_aloha_tdma/` |
| Bab 14 — Modul 11 | `chapters/modul-11-lorawan-chirpstack.typ` | `../Modul11_lorawan_chirpstack/` (termasuk Lampiran A–D) |
| Lampiran A | `chapters/lampiran-a-perkakas.typ` | `../tools/` |

Penomoran bab berjalan 1–14 sedangkan kode modul pada sumber tidak berurutan (01…07, 07B, 08, 08B, 08C, 09, 10, 11). Supplement bab dibuat `"Bab"` agar kedua penomoran itu tidak tertukar; kode modul ditulis pada judul bab dan pada kotak identitas di awal tiap bab.

## Memperbarui kode sumber

Berkas di `assets/code/` adalah salinan. Bila kode di folder modul berubah, salin ulang sebelum mengompilasi:

```bash
cd "$(dirname "$0")/.."
for d in Modul*/; do
  find "$d" -type f \( -name "*.cpp" -o -name "*.h" -o -name "*.py" -o -name "*.ini" \
       -o -name "*.txt" -o -name "*.sh" -o -name "*.yml" -o -name "*.service" \) \
       -not -path "*/.pio/*" | while read f; do
    mkdir -p "Buku-typst/assets/code/$(dirname "$f")"
    cp "$f" "Buku-typst/assets/code/$f"
  done
done
cp tools/deteksi_port.py Buku-typst/assets/code/tools/
```

## Catatan penyuntingan

Dua hal yang mudah membuat isi bab hilang tanpa pesan galat, keduanya pernah terjadi saat konversi ini:

- **`/*` di dalam teks** membuka komentar blok Typst dan menelan seluruh isi berkas sesudahnya tanpa galat kompilasi. Tulis `CSMA/#[*CD*]` atau sisipkan spasi (`147 / 154 / *152 ms*`), jangan `CSMA/*CD*`.
- **Jumlah halaman yang turun mendadak** setelah menyunting adalah tanda pertama masalah semacam itu. Periksa dengan membandingkan daftar judul `^== ` di `chapters/*.typ` terhadap teks hasil `pdftotext main.pdf`.

## TODO yang menunggu konfirmasi penulis

Dua penanda `TODO` sengaja ditinggalkan di dalam buku, keduanya mengenai penomoran pada berkas sumber, bukan isi teknisnya:

- **Bab 12 (Modul 09), bagian Analisis** — pada `Modul09_lora_csma_ca/README.md` butir bernomor 6 ditulis sebelum butir bernomor 5. Urutan isinya dipertahankan apa adanya, penomorannya dibuat otomatis.
- **Bab 13 (Modul 10), bagian Challenge** — pada `Modul10_lora_slotted_aloha_tdma/README.md` CH-5 ditulis sebelum CH-4. Urutan penyajiannya dipertahankan agar cocok dengan sumber.
