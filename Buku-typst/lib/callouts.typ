// ============================================================================
// Komponen callout untuk Buku Petunjuk Praktikum Komunikasi LoRa
// ----------------------------------------------------------------------------
// Paket `orange-book` hanya menyediakan lingkungan bergaya teorema (thmbox)
// yang kurang tepat untuk buku petunjuk praktikum. Berkas ini mendefinisikan
// callout yang konsisten dengan gaya visual template: garis tebal di sisi
// kiri, latar bertingkat terang, dan label tebal berwarna.
//
// Gaya diselaraskan dengan buku "Petunjuk Praktikum Wireless Sensor Network
// & Internet of Things" agar kedua buku praktikum pada mata kuliah ini terbaca
// sebagai satu keluarga.
// ============================================================================

#import "../config.typ": edisi_buku

#let _callout(judul, warna, isi) = {
  set par(first-line-indent: 0em, justify: true)
  block(
    width: 100%,
    breakable: false,
    spacing: 1.2em,
    inset: (left: 0.9em, right: 0.9em, top: 0.7em, bottom: 0.7em),
    fill: warna.lighten(90%),
    stroke: (left: 3pt + warna, rest: none),
    {
      text(weight: "bold", fill: warna.darken(10%), size: 0.95em, judul)
      linebreak()
      isi
    },
  )
}

/// IMPORTANT — hal yang wajib diperhatikan sebelum melanjutkan.
#let penting(body) = _callout("PENTING", rgb("#C2410C"), body)

/// WARNING — tindakan berisiko: board salah flash, program tidak berjalan,
/// perangkat masuk mode yang tidak dikehendaki.
#let peringatan(body) = _callout("PERINGATAN", rgb("#B91C1C"), body)

/// TIP — cara praktis mempercepat konfigurasi atau diagnosis masalah.
#let tip(body) = _callout("TIP", rgb("#047857"), body)

/// NOTE — informasi pendukung yang berguna tetapi bukan langkah wajib.
#let catatan(body) = _callout("CATATAN", rgb("#1D4ED8"), body)

/// TODO — penanda bagian yang masih memerlukan keputusan/verifikasi dosen.
/// Hanya dicetak pada edisi dosen (lihat config.typ).
#let todo(body) = if edisi_buku == "dosen" {
  _callout("TODO", rgb("#7C3AED"), body)
}

/// CHECKPOINT — syarat verifikasi yang harus dipenuhi sebelum melanjutkan ke
/// tahap percobaan berikutnya. Dibuat berbeda dari callout lain (kotak penuh
/// bergaris tebal) karena fungsinya adalah gerbang, bukan keterangan.
#let checkpoint(body) = {
  let w = rgb("#0F766E")
  set par(first-line-indent: 0em, justify: true)
  block(
    width: 100%,
    breakable: false,
    spacing: 1.3em,
    stroke: 1pt + w,
    radius: 4pt,
    inset: 0pt,
  )[
    #block(
      width: 100%,
      fill: w,
      inset: (x: 0.85em, y: 0.45em),
      radius: (top: 3pt),
    )[#text(fill: white, weight: "bold", size: 0.95em)[CHECKPOINT]]
    #block(inset: 0.9em, width: 100%)[
      #set par(first-line-indent: 0em, justify: true)
      #body
    ]
  ]
}

/// Kotak "Buka abstraksinya" — ciri khas buku ini: satu tugas pembongkaran
/// abstraksi per modul.
#let buka-abstraksi(body) = {
  let w = rgb("#7C2D12")
  set par(first-line-indent: 0em, justify: true)
  block(
    width: 100%,
    breakable: false,
    spacing: 1.3em,
    stroke: (left: 3pt + w, rest: 0.6pt + w.lighten(55%)),
    fill: w.lighten(94%),
    inset: (left: 0.9em, right: 0.9em, top: 0.7em, bottom: 0.7em),
  )[
    #text(weight: "bold", fill: w, size: 0.95em)[BUKA ABSTRAKSINYA]
    #linebreak()
    #body
  ]
}

/// Capaian praktikum bertingkat: ikuti, modifikasi, dan tantangan.
#let tujuan-prak(level, judul, isi, tampilkan-judul: true) = {
  let w = if level == 1 { rgb("#15803D") }
          else if level == 2 { rgb("#1B6CA8") }
          else { rgb("#B45309") }
  let nama = if level == 1 { none }
             else if level == 2 { "Level 2 — Modifikasi" }
             else { "Level 3 — Tantangan" }
  block(
    width: 100%,
    breakable: false,
    stroke: 0.8pt + w.lighten(35%),
    radius: 4pt,
    inset: 0pt,
    spacing: 1.3em,
  )[
    #if tampilkan-judul {
      block(
        width: 100%,
        fill: w,
        inset: (x: 0.85em, y: 0.5em),
        radius: (top: 4pt),
      )[
        #if nama == none {
          text(fill: white, weight: "bold", judul)
        } else {
          text(fill: white, weight: "bold", nama)
          h(0.4em)
          text(fill: white.darken(8%))[· #judul]
        }
      ]
    }
    #block(inset: 0.9em, width: 100%)[
      #set par(first-line-indent: 0em, justify: true)
      #isi
    ]
  ]
}

/// Pengantar singkat yang ditempatkan sebelum tujuan praktikum sebuah modul.
#let pengantar(judul, isi) = {
  let w = rgb("#B45309")
  block(
    width: 100%,
    breakable: false,
    stroke: 0.8pt + w.lighten(35%),
    radius: 4pt,
    inset: 0pt,
    spacing: 1.3em,
  )[
    #block(
      width: 100%,
      fill: w,
      inset: (x: 0.85em, y: 0.5em),
      radius: (top: 4pt),
    )[
      #text(fill: white, weight: "bold")[PENGANTAR MODUL] #h(0.4em)
      #text(fill: white.darken(8%))[· #judul]
    ]
    #block(inset: 0.9em, width: 100%)[
      #set par(first-line-indent: 0em, justify: true)
      #quote(block: true)[#isi]
    ]
  ]
}

/// Identitas modul: papan nama ringkas di awal setiap bab, menggantikan blok
/// ASCII banner pada berkas sumber Markdown.
#let identitas-modul(kode, judul, baris) = {
  let w = rgb("#C2410C")
  block(
    width: 100%,
    breakable: false,
    stroke: (left: 4pt + w, rest: 0.8pt + w.lighten(55%)),
    fill: w.lighten(95%),
    inset: (x: 1em, y: 0.85em),
    spacing: 1.4em,
  )[
    #set par(first-line-indent: 0em, justify: false)
    #text(size: 0.85em, weight: "bold", fill: w, tracking: 0.08em)[
      LoRa COMMUNICATION LAB · #upper(kode)
    ]
    #v(0.35em, weak: true)
    #text(size: 1.25em, weight: "bold")[#judul]
    #v(0.45em, weak: true)
    #text(size: 0.9em, fill: luma(80))[#baris]
  ]
}
