// ============================================================================
// Buku Petunjuk Praktikum Komunikasi Jarak Jauh dengan LoRa
// Hasil konversi berkas README.md tiap modul pada repositori WSN-IOT-prak-Lora.
//
// Berkas ini hanya menangani konfigurasi global, halaman judul, daftar isi,
// dan pemanggilan setiap modul. Isi buku berada di folder `chapters/`.
// Kompilasi:  typst compile main.typ
// ============================================================================

#import "@preview/orange-book:0.7.1": book, chapter, appendices, update-heading-image

#let warna-utama = rgb("#F36619")

#show: book.with(
  title: "Petunjuk Praktikum Komunikasi Jarak Jauh dengan LoRa",
  subtitle: "LoRa mentah SX1276, ACK, master-slave, ALOHA, CSMA/CA, TDMA, dan LoRaWAN pada Arduino Uno dan Raspberry Pi",
  date: datetime(year: 2026, month: 9, day: 21),
  author: "Akhmad Hendriawan",
  main-color: warna-utama,
  lang: "id",
  // Sampul hanya menyediakan latar dan keterangan pelengkap. Judul, subjudul,
  // dan nama penulis digambar oleh template `orange-book` sendiri sebagai pita
  // di bagian tengah halaman, sehingga tidak boleh diulang di sini. Isi sampul
  // dijaga tetap berada di atas dan di bawah pita tersebut (kira-kira 11 cm
  // sampai 19 cm dari tepi atas).
  cover: block(width: 100%, height: 100%, fill: rgb("#FDF1E7"), {
    place(
      top + left,
      dx: 2.6cm,
      dy: 2.6cm,
      block(width: 15cm)[
        #set par(justify: false)
        #text(size: 1.1em, fill: warna-utama, weight: "bold", tracking: 0.18em)[
          LoRa COMMUNICATION LAB
        ]
        #v(0.7em)
        #block(width: 5.5cm, height: 5pt, fill: warna-utama)
        #v(0.9em)
        #text(size: 1.35em, fill: luma(55), weight: "medium")[
          Buku kerja laboratorium \
          komunikasi radio jarak jauh
        ]
        #v(1.1em)
        #text(size: 1.05em, fill: luma(80))[
          LoRa mentah · ACK · Master-Slave · ALOHA · CSMA/CA · TDMA · LoRaWAN
        ]
      ],
    )
    place(
      bottom + left,
      dx: 2.6cm,
      dy: -2.8cm,
      block(width: 15cm)[
        #set par(justify: false)
        #block(width: 5.5cm, height: 2pt, fill: warna-utama)
        #v(0.8em)
        #text(size: 1.05em, fill: luma(60))[
          Arduino Uno · Raspberry Pi · SX1276 · 14 modul · 1 semester
        ]
        #v(0.7em)
        #text(size: 1em, fill: luma(80))[
          Departemen Teknik Elektro \
          Politeknik Elektronika Negeri Surabaya
        ]
        #v(0.7em)
        #text(size: 1em, fill: luma(95))[Edisi September 2026]
      ],
    )
  }),
  list-of-figure-title: "Daftar Gambar",
  list-of-table-title: "Daftar Tabel",
  // Penomoran bab berjalan 1, 2, 3, … sedangkan label modul pada sumber tidak
  // berurutan (01, …, 07, 07B, 08, 08B, 08C, …). Supplement dibuat "Bab" agar
  // kedua penomoran itu tidak tertukar; kode modul ditulis pada judul bab dan
  // pada kotak identitas di awal tiap bab.
  supplement-chapter: "Bab",
  supplement-part: "Bagian",
  heading-style: 0,
  outline-depth: 3,
  first-line-indent: false,
  lowercase-references: false,
  copyright: [
    *Lisensi Dokumen*

    Copyright © 2026 oleh Akhmad Hendriawan.

    Dokumen ini disusun sebagai petunjuk praktikum mata kuliah Wireless Sensor
    Network dan Internet of Things, seri komunikasi LoRa. Seluruh isinya dapat
    digunakan dan disebarkan secara bebas untuk tujuan bukan komersial
    (nonprofit), dengan syarat tidak menghapus atau mengubah atribut penulis
    dan pernyataan copyright yang disertakan di dalamnya.

    Seluruh berkas kode sumber setiap modul dimuat lengkap di dalam buku ini,
    sehingga buku dapat dipakai tanpa akses jaringan. Salinan daringnya berada
    pada repositori praktikum
    #link("https://github.com/hendrieepis/WSN-IOT-prak-Lora")[`github.com/hendrieepis/WSN-IOT-prak-Lora`],
    di dalam folder `ModulNN_nama` yang disebut pada awal tiap modul.

    Departemen Teknik Elektro, Politeknik Elektronika Negeri Surabaya
  ],
)

// --- Gaya tambahan khusus buku ini -------------------------------------------
// Kode sumber memakai font monospaced yang lebih rapat agar listing panjang
// tetap muat di dalam margin, dan memuat karakter penggambar kotak Unicode
// yang dipakai diagram topologi.
#show raw: set text(font: ("DejaVu Sans Mono", "Consolas", "Courier New"))

// Nama fungsi dan konstanta yang panjang (mis.
// `LoRa.setSpreadingFactor(SPREADING_FACTOR)`) tidak memiliki titik henti
// baris, sehingga dapat menembus tepi kolom tabel. Aturan berikut menyisipkan
// peluang ganti baris (spasi selebar nol) sesudah garis bawah dan kurung buka
// pada kode sebaris, tanpa mengubah teks yang tercetak.
#show raw.where(block: false): it => {
  show "_": "_" + sym.zws
  show "(": "(" + sym.zws
  it
}

// Listing kode pada buku ini banyak yang lebih panjang dari satu halaman,
// sehingga figure harus boleh terpotong antar halaman.
#show figure: set block(breakable: true)

// `orange-book` mereset penomoran gambar dan tabel pada setiap bab, tetapi
// tidak mereset penomoran listing kode. Aturan berikut melengkapinya agar
// nomor listing juga dimulai ulang dari 1 pada tiap modul.
#show heading.where(level: 1): it => {
  counter(figure.where(kind: raw)).update(0)
  it
}

// Paragraf tidak memakai indentasi baris pertama, sehingga jarak antar
// paragraf perlu sedikit dilonggarkan.
#set par(spacing: 0.9em)

// Teks di dalam sel tabel tidak dijustifikasi: kolom sempit yang
// dijustifikasi menghasilkan jarak antar kata yang melebar dan sulit dibaca.
#show table: set par(justify: false)

// Jarak antar item daftar dirapatkan supaya langkah percobaan tetap padu.
#set enum(spacing: 0.9em, indent: 0.4em, body-indent: 0.5em)
#set list(spacing: 0.9em, indent: 0.4em, body-indent: 0.5em)

// --- Prakata ------------------------------------------------------------------
#include "chapters/00-prakata.typ"

// --- Modul --------------------------------------------------------------------
#include "chapters/modul-01-lora-uart.typ"
#include "chapters/modul-02-lora-led-notif.typ"
#include "chapters/modul-03-lora-p2p.typ"
#include "chapters/modul-04-lora-ack.typ"
#include "chapters/modul-05-lora-master-slave.typ"
#include "chapters/modul-06-rpi-lora-python.typ"
#include "chapters/modul-07-rpi-master-slave.typ"
#include "chapters/modul-07b-rpi-master-slave-crc.typ"
#include "chapters/modul-08-lora-aloha-tanpa-ack.typ"
#include "chapters/modul-08b-lora-aloha-ack.typ"
#include "chapters/modul-08c-lora-aloha-retry.typ"
#include "chapters/modul-09-lora-csma-ca.typ"
#include "chapters/modul-10-lora-slotted-aloha-tdma.typ"
#include "chapters/modul-11-lorawan-chirpstack.typ"

// --- Bagian pelengkap ---------------------------------------------------------
#show: appendices.with("Bagian Pelengkap")

#include "chapters/lampiran-a-perkakas.typ"
