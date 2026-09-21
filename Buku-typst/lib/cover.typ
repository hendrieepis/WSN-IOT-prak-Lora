// =====================================================================
//  lib/cover.typ - Halaman sampul depan.
//
//  Gaya sama dengan sampul buku WSN-IOT-prak: latar gelap penuh halaman
//  dengan pola titik halus (kesan papan PCB), judul besar di bagian atas,
//  ilustrasi CeTZ di tengah, deretan topik praktikum, dan identitas
//  penulis di dalam blok aksen bawah.
//
//  Ilustrasi tengah dibedakan per edisi (lihat config.typ):
//    "dosen"     -> chip radio LoRa dengan jalur PCB;
//    "mahasiswa" -> topologi star LoRa: gateway di tengah, node di
//                   sekelilingnya dengan riak jangkauan radio.
//
//  Catatan teknis: template orange-book menempelkan sampul ini lewat
//  `place(bottom, cover)`. Di dalam `place`, blok `height: 100%` tetap
//  mengisi halaman dengan benar, tetapi isi yang mengalir di dalamnya
//  terdorong ke dasar halaman. Karena itu seluruh elemen di sini
//  diposisikan eksplisit memakai `place` + `dx`/`dy`.
//
//  Dipakai dari main.typ:
//
//    #show: book.with(
//      title: "", subtitle: "", author: "",      // matikan blok bawaan
//      cover-background: rgb(0%, 0%, 0%, 0%),    // latar bawaan transparan
//      cover: cover-page(...),
//      ...
//    )
// =====================================================================

#import "@preview/cetz:0.4.2" as cetz
#import "../config.typ": edisi_buku, edisi-subtitle

// Palet khusus sampul (sengaja mandiri agar tidak bergantung lib lain).
#let _accent = rgb("#F36619")            // jingga, sama dengan warna-utama
#let _ink = rgb("#16161a")               // latar gelap
#let _chip = rgb("#26262d")              // badan chip
#let _rise = white.transparentize(20%)   // label kecil di blok aksen
#let _subtitle-fill = rgb("#cfcdc8")     // abu hangat untuk subjudul
#let _muted = rgb("#8a8a93")             // teks redup
#let _fonts = ("Noto Sans", "Segoe UI", "DejaVu Sans")
#let _mono = ("JetBrains Mono", "Consolas", "DejaVu Sans Mono")

// Geometri sampul.
#let _pad-x = 2.4cm                      // jarak kiri teks ke tepi halaman
#let _bar-top = 0.45cm                   // tinggi batang aksen atas
#let _bar-bottom = 4.3cm                 // tinggi blok aksen bawah
#let _text-top = 3.2cm                   // awal blok judul dari tepi atas
#let _foot-dy = -1.35cm                  // jarak blok penulis dari tepi bawah
#let _page-w = 21cm                      // lebar A4
#let _content-w = _page-w - 2 * _pad-x   // lebar area teks

// Nama penulis yang panjang (daftar beberapa nama) dicetak sedikit lebih kecil
// agar blok identitas tetap muat di dalam blok aksen bawah.
#let _name-size(author) = {
  let n = if type(author) == str { author.len() } else { 0 }
  if n > 46 { 14pt } else if n > 26 { 16pt } else { 18pt }
}

// Pola titik halus sebagai latar (kesan papan PCB).
#let _dots = tiling(size: (0.55cm, 0.55cm), place(
  dx: 0.275cm, dy: 0.275cm,
  circle(radius: 0.55pt, fill: white.transparentize(88%)),
))

// Edisi dosen: chip radio dengan jalur PCB dan gelombang radio (satuan CeTZ = cm).
// `label` berisi empat baris teks di badan chip: (besar, aksen, baris-1, baris-2).
#let _ilustrasi-chip(label) = cetz.canvas(length: 1cm, {
  import cetz.draw: *

  let (besar, aksen, baris-1, baris-2) = label
  let s = 2.6                // setengah lebar badan chip
  let n = 10                 // jumlah pin per sisi
  let jarak = 2 * s / (n + 1)
  let jejak(i) = _accent.transparentize(if calc.rem(i, 3) == 0 { 0% } else { 55% })

  // Jalur PCB: keluar lurus dari pin, lalu berbelok 45 derajat, berakhir di via.
  for i in range(n) {
    let t = -s + (i + 1) * jarak
    let panjang = 0.9 + calc.rem(i * 7, 5) * 0.35
    let belok = if t < 0 { -0.7 } else { 0.7 }
    let st = 0.9pt + jejak(i)
    // atas & bawah
    for arah in (1, -1) {
      let y0 = arah * (s + 0.35)
      let y1 = arah * (s + 0.35 + panjang)
      let ujung = (t + belok, y1 + arah * 0.7)
      line((t, y0), (t, y1), ujung, stroke: st)
      circle(ujung, radius: 0.1, fill: _ink, stroke: 0.9pt + jejak(i))
    }
    // kiri & kanan
    for arah in (1, -1) {
      let x0 = arah * (s + 0.35)
      let x1 = arah * (s + 0.35 + panjang)
      let ujung = (x1 + arah * 0.7, t + belok)
      line((x0, t), (x1, t), ujung, stroke: st)
      circle(ujung, radius: 0.1, fill: _ink, stroke: 0.9pt + jejak(i))
    }
  }

  // Kaki-kaki chip.
  for i in range(n) {
    let t = -s + (i + 1) * jarak
    rect((t - 0.07, s), (t + 0.07, s + 0.35), fill: rgb("#9a9aa3"), stroke: none)
    rect((t - 0.07, -s), (t + 0.07, -s - 0.35), fill: rgb("#9a9aa3"), stroke: none)
    rect((s, t - 0.07), (s + 0.35, t + 0.07), fill: rgb("#9a9aa3"), stroke: none)
    rect((-s, t - 0.07), (-s - 0.35, t + 0.07), fill: rgb("#9a9aa3"), stroke: none)
  }

  // Badan chip.
  rect((-s, -s), (s, s), radius: 0.18, fill: _chip, stroke: 1pt + rgb("#3a3a44"))
  rect((-s + 0.3, -s + 0.3), (s - 0.3, s - 0.3), radius: 0.1, fill: none, stroke: 0.5pt + white.transparentize(88%))
  circle((-s + 0.6, s - 0.6), radius: 0.16, fill: _ink, stroke: 0.6pt + white.transparentize(80%))

  // Gelombang radio di pojok kanan atas badan chip (penanda radio LoRa).
  let pusat = (s - 0.75, s - 0.75)
  circle(pusat, radius: 0.07, fill: _accent, stroke: none)
  for (k, r) in (0.28, 0.5, 0.72).enumerate() {
    arc(pusat, start: 0deg, stop: 90deg, radius: r, anchor: "origin",
      stroke: (paint: _accent.transparentize(k * 25%), thickness: 1.1pt, cap: "round"))
  }

  content((0, 0.75), text(font: _fonts, size: 30pt, weight: 800, fill: white, tracking: 1pt, besar))
  content((0, -0.2), text(font: _fonts, size: 13pt, weight: 600, fill: _accent, aksen))
  content((0, -1.2), text(font: _mono, size: 8pt, fill: _muted, baris-1))
  content((0, -1.65), text(font: _mono, size: 7pt, fill: _muted.transparentize(30%), baris-2))
})

// Edisi mahasiswa: topologi star LoRa (satuan CeTZ = cm). Gateway di tengah
// dengan antena, node di sekelilingnya pada jarak berselang-seling, dan riak
// jangkauan radio. `label` berisi (gateway-besar, gateway-aksen,
// gateway-kecil, label-node).
#let _ilustrasi-star(label) = cetz.canvas(length: 1cm, {
  import cetz.draw: *

  let (gw-besar, gw-aksen, gw-kecil, node) = label
  let n = 8                  // jumlah node
  let sudut(k) = 90deg + 22.5deg + k * 360deg / n
  let titik(r, a) = (r * calc.cos(a), r * calc.sin(a))
  let jari(k) = if calc.rem(k, 2) == 0 { 4.1 } else { 5.1 }

  // Riak jangkauan radio gateway.
  for (k, r) in (2.0, 2.9, 3.8).enumerate() {
    circle((0, 0), radius: r, stroke: (paint: _accent.transparentize(55% + k * 12%), thickness: 0.6pt, dash: "dashed"))
  }

  // Tautan node -> gateway (uplink radio).
  for k in range(n) {
    let st = if calc.rem(k, 2) == 0 {
      1.1pt + _accent
    } else {
      (paint: _accent.transparentize(45%), thickness: 0.9pt, dash: "densely-dashed")
    }
    line(titik(jari(k), sudut(k)), (0, 0), stroke: st)
  }

  // Node.
  for k in range(n) {
    let p = titik(jari(k), sudut(k))
    circle(p, radius: 0.6, fill: _chip, stroke: 1.2pt + _accent)
    content(p, text(font: _mono, size: 7pt, weight: 700, fill: white, node))
  }

  // Gateway di tengah, lengkap dengan antena.
  line((0, 1.1), (0, 1.85), stroke: 1.4pt + _accent)
  circle((0, 1.85), radius: 0.12, fill: _accent, stroke: none)
  rect((-1.7, -1.1), (1.7, 1.1), radius: 0.18, fill: _chip, stroke: 1.2pt + _accent)
  content((0, 0.35), text(font: _fonts, size: 15pt, weight: 800, fill: white, gw-besar))
  content((0, -0.2), text(font: _fonts, size: 9pt, weight: 600, fill: _accent, gw-aksen))
  content((0, -0.62), text(font: _mono, size: 6.5pt, fill: _muted, gw-kecil))
})

/// Halaman sampul depan ukuran penuh.
///
/// - kicker: baris kecil huruf kapital di atas judul (maks. 1 baris).
/// - title: judul buku, dicetak besar. Bagian akhir judul yang cocok dengan
///   `highlight` dicetak dengan warna aksen.
/// - highlight: bagian judul yang diberi warna aksen, none untuk tanpa sorotan.
/// - subtitle: keterangan tambahan di bawah garis aksen.
/// - topics: daftar topik singkat yang ditampilkan sebagai label.
/// - chip: empat baris teks chip pada edisi dosen (besar, aksen, baris-1, baris-2).
/// - star: teks topologi star pada edisi mahasiswa
///   (gateway-besar, gateway-aksen, gateway-kecil, label-node).
/// - author: nama penulis (boleh berupa daftar nama).
/// - publisher: tahun/edisi di sudut kanan bawah, none untuk menyembunyikan.
#let cover-page(
  kicker: "LoRa Communication Lab · Buku Kerja Laboratorium",
  title: "Petunjuk Praktikum Komunikasi Jarak Jauh dengan LoRa",
  highlight: "LoRa",
  subtitle: edisi-subtitle,
  topics: ("LoRa P2P", "ACK", "Master-Slave", "ALOHA", "CSMA/CA", "TDMA", "LoRaWAN"),
  chip: ("LoRa", "SX1276", "Sub-GHz", "Chirp Spread Spectrum"),
  star: ("Gateway", "LoRa", "Raspberry Pi", "Node"),
  author: "Akhmad Hendriawan",
  publisher: "2026",
) = {
  set text(font: _fonts, fill: white, lang: "id")
  set par(justify: false, leading: 0.4em)

  let label-edisi = if edisi_buku == "dosen" { "Edisi Pengajar" } else { "Edisi Mahasiswa" }
  let ilustrasi = if edisi_buku == "dosen" { _ilustrasi-chip(chip) } else { _ilustrasi-star(star) }

  // Pisahkan judul menjadi bagian biasa dan bagian yang disorot.
  let judul = if highlight != none and title.ends-with(highlight) {
    let depan = title.slice(0, title.len() - highlight.len()).trim()
    stack(
      spacing: 0.35cm,
      text(size: 24pt, weight: 300, fill: white, depan),
      text(size: 44pt, weight: 800, fill: _accent, highlight),
    )
  } else {
    text(size: 34pt, weight: 800, title)
  }

  block(width: 100%, height: 100%, fill: _ink, {
    // Pola titik di area tengah.
    place(top + left, dy: _bar-top, rect(width: 100%, height: 29.7cm - _bar-top - _bar-bottom, fill: _dots))
    // Batang aksen atas dan blok aksen bawah.
    place(top + left, rect(width: 100%, height: _bar-top, fill: _accent))
    place(bottom + left, rect(width: 100%, height: _bar-bottom, fill: _accent))

    // Lencana edisi di kanan atas.
    place(top + right, dx: -_pad-x, dy: 1.3cm, box(
      inset: (x: 9pt, y: 5pt),
      radius: 20pt,
      stroke: 0.8pt + _accent,
      text(size: 8pt, weight: 600, tracking: 1.5pt, fill: _accent, upper(label-edisi)),
    ))

    // Blok judul.
    place(top + left, dx: _pad-x, dy: _text-top, block(width: _content-w, {
      text(size: 9.5pt, weight: 500, tracking: 2.2pt, fill: _muted, upper(kicker))
      v(0.9cm, weak: true)
      block(judul)
      v(0.7cm, weak: true)
      line(length: 3.5cm, stroke: 2.5pt + _accent)
      v(0.55cm, weak: true)
      text(size: 12pt, weight: 400, fill: _subtitle-fill, subtitle)
    }))

    // Ilustrasi di tengah halaman (chip untuk dosen, topologi star untuk mahasiswa).
    place(top + center, dy: 11.2cm, ilustrasi)

    // Deretan topik praktikum.
    if topics != none and topics.len() > 0 {
      place(bottom + left, dx: _pad-x, dy: -_bar-bottom - 1.0cm, block(width: _content-w, {
        set align(center)
        topics
          .map(t => box(
            inset: (x: 7pt, y: 4pt),
            radius: 3pt,
            fill: white.transparentize(92%),
            stroke: 0.5pt + white.transparentize(80%),
            text(font: _mono, size: 7.5pt, fill: _subtitle-fill, t),
          ))
          .join(h(5pt))
      }))
    }

    // Identitas penulis di dalam blok aksen bawah.
    //
    // Lebar blok dibatasi `_content-w` lalu disusun sebagai grid dua kolom
    // (label + nilai) supaya nama penulis yang panjang tidak menabrak
    // keterangan tahun di sebelah kanan.
    place(bottom + left, dx: _pad-x, dy: _foot-dy, block(width: _content-w, {
      let kecil(teks) = text(size: 8pt, weight: 600, tracking: 1.8pt, fill: _rise, upper(teks))
      let besar(teks) = text(size: _name-size(teks), weight: 700, fill: white, teks)

      if publisher == none {
        kecil("Penulis")
        v(0.25cm, weak: true)
        besar(author)
      } else {
        grid(
          columns: (1fr, auto),
          column-gutter: 1.2cm,
          row-gutter: 0.28cm,
          align: (left + bottom, right + bottom),
          kecil("Penulis"), kecil("Tahun"),
          besar(author), text(size: 26pt, weight: 800, fill: white, publisher),
        )
      }
    }))
  })
}
