// =====================================================================
//  Konfigurasi edisi buku
// =====================================================================
//
//  Ubah nilai `edisi_buku` di bawah ini, lalu kompilasi ulang:
//
//      typst compile main.typ
//
//  Nilai yang tersedia:
//
//    "dosen"     -> (default) sampul edisi pengajar (ilustrasi chip LoRa).
//    "mahasiswa" -> sampul edisi mahasiswa (ilustrasi topologi star LoRa).

#let edisi_buku = "dosen"

// ---------------------------------------------------------------------
//  Turunan otomatis dari edisi di atas (tidak perlu diubah)
// ---------------------------------------------------------------------

// Subjudul yang dicetak pada halaman sampul.
#let edisi-subtitle = if edisi_buku == "dosen" {
  "Arduino Uno & Raspberry Pi Version - Buku Pegangan untuk Pengajar"
} else {
  "Arduino Uno & Raspberry Pi Version - Buku Pegangan untuk Mahasiswa"
}
