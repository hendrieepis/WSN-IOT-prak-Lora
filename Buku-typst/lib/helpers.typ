// ============================================================================
// Pembantu tata letak: gambar, tabel, listing kode, blok keluaran, dan
// checklist. Semua pembungkus memakai `figure` bawaan Typst agar penomoran,
// caption, daftar gambar/tabel, dan referensi silang dihasilkan otomatis.
// ============================================================================

/// Gambar dengan caption dan label wajib.
/// `w` adalah lebar relatif terhadap lebar teks.
#let gbr(berkas, caption, label-name, w: 80%) = [
  #figure(
    image("../assets/images/" + berkas, width: w),
    caption: caption,
  ) #label(label-name)
]

/// Tabel dengan caption dan label wajib. `isi` adalah hasil pemanggilan `table`.
#let tbl(isi, caption, label-name) = [
  #figure(isi, caption: caption) #label(label-name)
]

/// Gaya baris kepala tabel.
#let th(body) = text(weight: "bold", body)

/// Sel kosong untuk tabel pengamatan: tinggi baris dijaga agar tersedia ruang
/// tulis tangan saat lembar kerja dicetak.
#let isian = v(1.1em)

/// Listing kode dengan caption dan label wajib.
/// `bahasa` mengikuti nama bahasa yang dikenali Typst ("cpp", "ini", "bash").
/// `pecah` dibiarkan `false` supaya listing pendek tidak terbelah dua halaman;
/// setel `true` hanya untuk listing yang memang lebih panjang dari satu
/// halaman, agar isinya tidak menembus tepi bawah.
#let kode(isi, caption, label-name, bahasa: "cpp", pecah: false) = [
  #show figure: set block(breakable: pecah)
  #figure(
    block(
      width: 100%,
      breakable: pecah,
      inset: (x: 0.8em, y: 0.7em),
      fill: luma(247),
      stroke: (left: 2.5pt + luma(180), rest: none),
      {
        set align(left)
        set text(size: 0.78em)
        set par(justify: false, leading: 0.55em)
        raw(isi, lang: bahasa, block: true)
      },
    ),
    caption: caption,
  ) #label(label-name)
]

/// Listing kode yang isinya dibaca langsung dari salinan berkas sumber di
/// `assets/code/`. Seluruh listing kode buku ini memakai jalur ini, bukan
/// transkripsi manual, supaya isinya dijamin identik dengan berkas aslinya
/// pada repositori praktikum.
/// Bahasa ditebak dari ekstensi berkas bila tidak diberikan secara eksplisit.
#let kode-berkas(berkas, caption, label-name, bahasa: auto, pecah: false) = {
  let ext = berkas.split(".").last()
  let lang = if bahasa != auto {
    bahasa
  } else if ext == "ino" or ext == "cpp" or ext == "h" {
    "cpp"
  } else if ext == "ini" {
    "ini"
  } else if ext == "py" {
    "python"
  } else if ext == "sh" {
    "bash"
  } else {
    ext
  }
  kode(read("../assets/code/" + berkas), caption, label-name,
       bahasa: lang, pecah: pecah)
}

// ---------------------------------------------------------------------------
// Rujukan ke repositori kode praktikum
// ---------------------------------------------------------------------------

/// Alamat repositori kode sumber praktikum LoRa.
#let REPO = "https://github.com/hendrieepis/WSN-IOT-prak-Lora"

/// Tautan ke satu berkas di repositori, ditampilkan sebagai jalur relatifnya.
#let gh(jalur) = link(REPO + "/blob/main/" + jalur, raw(jalur))

/// Tautan ke satu folder di repositori.
#let gh-folder(jalur) = link(REPO + "/tree/main/" + jalur, raw(jalur + "/"))

/// Kotak rujukan kode sumber, dipasang di awal bagian "Kode Program" tiap bab.
/// Seluruh berkas modul dimuat lengkap di buku; kotak ini menunjuk salinan
/// daringnya agar kode dapat diunduh tanpa mengetik ulang.
#let sumber-kode(folder, berkas) = {
  let w = rgb("#334155")
  set par(first-line-indent: 0em, justify: false)
  block(
    width: 100%,
    breakable: false,
    spacing: 1.2em,
    inset: (left: 0.9em, right: 0.9em, top: 0.7em, bottom: 0.7em),
    fill: w.lighten(93%),
    stroke: (left: 3pt + w, rest: none),
    {
      text(weight: "bold", fill: w, size: 0.95em)[KODE SUMBER]
      linebreak()
      [Seluruh berkas di bawah dimuat lengkap pada bab ini. Salinan daringnya:
       #gh-folder(folder)]
      linebreak()
      set text(size: 0.92em)
      for b in berkas {
        block(spacing: 0.35em, [#sym.bullet #h(0.4em) #gh(folder + "/" + b)])
      }
    },
  )
}

/// Blok keluaran terminal / log Serial Monitor tanpa penomoran listing.
/// Seperti `kode`, blok ini dijaga tetap utuh kecuali `pecah` disetel `true`.
#let keluaran(isi, pecah: false) = block(
  width: 100%,
  breakable: pecah,
  inset: (x: 0.8em, y: 0.7em),
  fill: luma(247),
  stroke: (left: 2.5pt + luma(180), rest: none),
  {
    set align(left)
    set text(size: 0.78em)
    set par(justify: false, leading: 0.55em)
    raw(isi, block: true)
  },
)

/// Blok diagram ASCII (topologi, sekuens, struktur direktori).
/// Font DejaVu Sans Mono dipilih karena memuat karakter penggambar kotak dan
/// panah Unicode yang dipakai diagram pada berkas sumber.
#let diagram(isi, rapat: false) = block(
  width: 100%,
  breakable: false,
  inset: (x: 0.8em, y: 0.7em),
  fill: luma(250),
  stroke: 0.6pt + luma(200),
  radius: 3pt,
  {
    set align(left)
    set text(
      size: if rapat { 0.66em } else { 0.78em },
      font: ("DejaVu Sans Mono", "Consolas"),
    )
    set par(justify: false, leading: 0.5em)
    raw(isi, block: true)
  },
)

/// Diagram dengan caption dan label, untuk diagram yang dirujuk dari teks.
#let diagram-gbr(isi, caption, label-name, rapat: false) = [
  #figure(diagram(isi, rapat: rapat), caption: caption, kind: image) #label(label-name)
]

// ---------------------------------------------------------------------------
// Checklist
// ---------------------------------------------------------------------------
// Kotak centang digambar (bukan karakter Unicode U+2610) agar tampilannya
// tidak bergantung pada ketersediaan glyph pada font yang terpasang, dan agar
// ukurannya tetap sama saat dicetak.

#let _kotak = box(
  width: 0.78em,
  height: 0.78em,
  stroke: 0.7pt + luma(90),
  radius: 1pt,
  baseline: 0.06em,
)

/// Satu baris checklist.
#let cek(body) = [#_kotak #h(0.45em) #body]

/// Daftar checklist. Pemakaian: `#checklist(( [..], [..] ))`.
#let checklist(butir) = {
  set par(first-line-indent: 0em, justify: false)
  block(spacing: 1.1em, width: 100%, {
    for b in butir {
      block(spacing: 0.62em, cek(b))
    }
  })
}
