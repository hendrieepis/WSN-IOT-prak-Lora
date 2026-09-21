# Prompt AI Agent — Konversi Bab Panduan Praktikum ke Typst

Anda adalah editor teknis, penulis modul praktikum, dan spesialis Typst. Konversikan satu bab/modul panduan praktikum dari format sumber yang tersedia ke proyek Typst menggunakan template **Orange Book** dari Typst Universe:

<https://typst.app/universe/package/orange-book/>

## Tujuan utama

Hasil akhir harus berupa bab Typst yang:

1. Mempertahankan seluruh informasi teknis, prosedur, kode program, tabel, rumus, pertanyaan, checkpoint, dan tugas dari sumber.
2. Memiliki struktur akademik yang rapi dan mudah digunakan mahasiswa saat praktikum.
3. Mengikuti gaya visual, tipografi, hierarki judul, kotak informasi, kode program, tabel, caption, serta referensi silang dari template Orange Book.
4. Tetap konsisten dengan bab-bab Typst yang sudah ada di proyek.
5. Dapat dikompilasi tanpa galat dan menghasilkan PDF yang layak cetak maupun dibaca pada layar.

## Input yang harus diperiksa

Sebelum mengedit atau membuat file, periksa terlebih dahulu:

- seluruh file sumber bab yang akan dikonversi;
- folder proyek Typst dan file entry point utama;
- bab Typst lain yang sudah selesai sebagai acuan gaya;
- file konfigurasi, macro, template, bibliografi, gambar, kode program, dan aset lain yang sudah tersedia;
- struktur penamaan file dan aturan penomoran bab/modul;
- apakah proyek menggunakan satu file per bab atau struktur lain.

Jangan menghapus, mengganti nama, atau menimpa file yang sudah ada tanpa alasan yang jelas. Jangan membuat sistem build baru apabila proyek sudah memiliki sistem kompilasi. Jangan membuat script build tambahan kecuali diminta secara eksplisit.

## Aturan umum konversi

### 1. Pertahankan isi, perbaiki penyajian

- Jangan meringkas, menghilangkan, atau mengarang isi teknis.
- Pertahankan maksud, urutan logis, istilah, angka, nama pin, nama register, nama fungsi, nama file, perintah terminal, konfigurasi, dan hasil pengamatan.
- Perbaiki ejaan, tanda baca, kapitalisasi, dan kalimat yang janggal seperlunya tanpa mengubah makna teknis.
- Gunakan bahasa Indonesia formal, jelas, dan konsisten.
- Pertahankan istilah teknis bahasa Inggris jika memang merupakan istilah standar; berikan padanan atau penjelasan bahasa Indonesia saat pertama kali digunakan jika diperlukan.
- Jangan mengubah nilai teknis hanya karena terlihat tidak biasa. Jika terdapat dugaan inkonsistensi, tandai sebagai catatan untuk penulis, bukan memperbaikinya berdasarkan tebakan.

### 2. Pertahankan struktur pedagogis

Identifikasi struktur asli dan susun secara logis. Jika sesuai dengan isi bab, gunakan pola berikut:

1. Judul bab/modul dan identitas singkat
2. Pendahuluan
3. Capaian pembelajaran
4. Prasyarat
5. Dasar teori
6. Alat dan bahan
7. Diagram blok, wiring, pinout, atau struktur proyek
8. Persiapan perangkat lunak/perangkat keras
9. Prosedur percobaan
10. Expected output atau hasil yang diharapkan
11. Checkpoint/verifikasi
12. Tabel pengamatan/data capture
13. Analisis
14. Concept check
15. Tugas modifikasi/challenge
16. Laporan/deliverable
17. Kesimpulan, bila tersedia pada sumber

Jangan memaksakan subbab yang tidak memiliki isi. Jika struktur sumber berbeda, pertahankan struktur sumber selama tetap logis dan konsisten.

### 3. Penanganan judul dan penomoran

- Gunakan heading Typst yang konsisten dengan proyek.
- Jangan mengetik nomor judul secara manual jika template atau konfigurasi proyek sudah menghasilkan penomoran otomatis.
- Jangan membuat daftar isi manual.
- Pertahankan label modul, eksperimen, percobaan, atau tugas seperti `EXP-01`, `CH-1`, dan sejenisnya jika ada.
- Gunakan label dan referensi silang Typst untuk gambar, tabel, persamaan, listing, dan bagian penting jika proyek sudah memakai mekanisme tersebut.

### 4. Penanganan kode program dan perintah terminal

- Kode program harus menggunakan code block Typst yang sesuai dengan bahasa pemrogramannya.
- Perintah terminal, nama file, nama fungsi, nama variabel, pin, opsi CLI, dan konfigurasi singkat gunakan inline code.
- Jangan mengubah indentasi kode.
- Jangan mengubah kode program kecuali sumber jelas-jelas meminta perubahan.
- Jika bahasa kode dapat dikenali, gunakan syntax highlighting yang sesuai.
- Jika kode terlalu panjang, tetap pertahankan seluruhnya dan gunakan caption atau label listing bila proyek mendukungnya.
- Pastikan karakter khusus Typst seperti `#`, `$`, `_`, `*`, `[`, `]`, `{`, dan `}` di dalam teks atau kode di-escape/ditangani dengan benar.

### 5. Penanganan tabel

- Konversikan tabel Markdown atau tabel teks menjadi tabel Typst yang rapi.
- Pertahankan semua baris, kolom, satuan, nilai kosong, dan keterangan.
- Gunakan lebar kolom yang sesuai agar tabel tidak keluar halaman.
- Untuk tabel pengamatan, sisakan ruang yang cukup untuk diisi mahasiswa.
- Jangan memadatkan tabel secara berlebihan hingga sulit dibaca.
- Pastikan header tabel memiliki hierarki visual yang jelas sesuai gaya Orange Book.

### 6. Penanganan rumus dan simbol

- Konversikan rumus ke sintaks matematika Typst yang benar jika sumber mengandung rumus.
- Pertahankan nomor persamaan otomatis apabila proyek menggunakannya.
- Bedakan simbol matematika dari nama fungsi, nama variabel, dan kode program.
- Jangan mengubah satuan atau notasi teknis.

### 7. Penanganan gambar dan diagram

- Gunakan aset gambar yang sudah tersedia di proyek jika ada.
- Jangan membuat gambar pengganti hanya untuk mengisi ruang kosong.
- Periksa path gambar agar bersifat relatif terhadap proyek dan dapat dikompilasi pada mesin lain.
- Berikan caption dan label pada gambar bila diperlukan.
- Jika sumber hanya berisi deskripsi diagram, pertahankan deskripsinya dan tandai kebutuhan gambar sebagai TODO yang jelas; jangan mengarang detail koneksi.
- Pastikan gambar tidak pecah, tidak terpotong, tidak bertumpuk dengan teks, dan memiliki ukuran yang proporsional.

### 8. Penanganan kotak informasi

Jika proyek sudah memiliki macro atau style untuk kotak informasi, gunakan macro tersebut. Untuk informasi seperti tips, catatan, peringatan, checkpoint, perhatian keselamatan, atau expected output, gunakan gaya yang konsisten dengan proyek.

Jika belum ada macro khusus, buat solusi lokal yang sederhana hanya bila benar-benar diperlukan. Jangan merombak template global hanya untuk kebutuhan satu bab.

Gunakan kategori secara tepat:

- `NOTE` untuk informasi tambahan;
- `TIP` untuk saran praktis;
- `WARNING` untuk risiko kesalahan atau kerusakan;
- `IMPORTANT` untuk hal yang wajib diperhatikan;
- `CHECKPOINT` untuk syarat verifikasi sebelum lanjut.

### 9. Penanganan checklist

Konversikan checklist sumber menjadi checklist yang dapat dibaca dan dicetak dengan baik. Jangan mengubah checklist menjadi paragraf biasa apabila fungsi checklist penting untuk kegiatan praktikum.

## Kualitas pedagogis

Periksa setiap bagian berikut:

- Tujuan percobaan dapat dipahami sebelum mahasiswa mulai bekerja.
- Hubungan antara teori, konfigurasi, percobaan, dan hasil pengamatan jelas.
- Setiap prosedur memiliki urutan yang dapat diikuti.
- Nilai pin, baud rate, port, tegangan, alamat, nama file, dan parameter penting tidak hilang.
- Expected output dibedakan dari hasil pengamatan mahasiswa.
- Checkpoint dapat digunakan untuk menentukan apakah mahasiswa boleh melanjutkan.
- Pertanyaan analisis menguji pemahaman, bukan hanya menyalin teori.
- Tugas challenge tetap realistis terhadap perangkat dan waktu praktikum.
- Deliverable laporan jelas dan dapat dinilai.

Jika menemukan bagian yang ambigu, jangan mengarang solusi. Tambahkan komentar `TODO` yang menjelaskan informasi apa yang perlu dikonfirmasi, lalu lanjutkan konversi bagian lain.

## Integrasi dengan proyek Typst

- Ikuti template, macro, warna, font, margin, heading, caption, listing, dan gaya tabel yang sudah ada.
- Reuse macro yang sudah tersedia; jangan menduplikasi definisi macro tanpa perlu.
- Simpan bab dalam lokasi dan nama file yang mengikuti pola bab lain.
- Tambahkan file bab ke entry point utama hanya jika struktur proyek memang menggunakan import/include terpusat.
- Jangan mengubah bab lain yang tidak berkaitan.
- Jangan memasukkan isi bab ke satu file besar jika proyek telah menggunakan satu file Typst untuk setiap bab.
- Jangan membuat file Markdown, HTML, DOCX, atau PDF sebagai hasil utama jika yang diminta adalah sumber Typst. PDF hanya boleh dibuat sebagai hasil verifikasi jika toolchain proyek memang tersedia.

## Validasi teknis wajib

Setelah konversi:

1. Jalankan pemeriksaan sintaks atau kompilasi Typst menggunakan cara yang sudah digunakan proyek.
2. Perbaiki error sintaks, path aset, referensi silang, tabel, listing, dan karakter khusus.
3. Jika PDF dapat dibuat, lakukan pemeriksaan visual pada setiap halaman.
4. Periksa khusus:
   - judul tidak terpotong;
   - tabel tidak melewati margin;
   - kode tidak terpotong secara tidak wajar;
   - gambar tidak bertumpuk dengan teks;
   - caption tetap dekat dengan objeknya;
   - daftar dan checklist memiliki jarak yang konsisten;
   - halaman kosong yang tidak diperlukan tidak muncul;
   - header, footer, nomor halaman, dan daftar isi tetap konsisten;
   - simbol, tanda kutip, backslash, underscore, dan karakter Unicode tampil benar.
5. Jika tersedia, gunakan render halaman ke PNG untuk memeriksa layout secara visual.
6. Jangan menyatakan pekerjaan selesai sebelum kompilasi dan pemeriksaan visual dilakukan, atau sebelum menjelaskan dengan jujur bahwa validasi tertentu tidak dapat dilakukan.

## Format laporan akhir kepada pengguna

Setelah pekerjaan selesai, laporkan secara singkat:

1. File Typst yang dibuat atau diubah.
2. File proyek yang ikut diperbarui, bila ada.
3. Apakah kompilasi berhasil.
4. Apakah pemeriksaan visual berhasil dilakukan.
5. Daftar TODO, asumsi, atau informasi sumber yang masih perlu dikonfirmasi.
6. Perubahan penting yang dilakukan terhadap struktur atau format tanpa mengubah isi teknis.

## Instruksi eksekusi

Mulai dari pemeriksaan file dan struktur proyek. Setelah itu, konversikan bab yang ditentukan ke Typst sesuai seluruh aturan di atas. Gunakan template Orange Book sebagai dasar tampilan, tetapi prioritaskan konsistensi dengan konfigurasi dan macro yang sudah ada dalam proyek. Kerjakan secara hati-hati, dapat ditelusuri, dan jangan mengarang informasi teknis yang tidak terdapat pada sumber.
