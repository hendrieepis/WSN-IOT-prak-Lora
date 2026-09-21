// ============================================================================
// Lampiran A — Perkakas lintas modul
// Sumber: tools/deteksi_port.py pada akar repositori WSN-IOT-prak-Lora,
//         beserta keterangan pemakaiannya pada README utama.
// ============================================================================

#import "@preview/orange-book:0.7.1": chapter
#import "../lib/callouts.typ": penting, peringatan, tip, catatan
#import "../lib/helpers.typ": tbl, th, kode-berkas, sumber-kode, gh, gh-folder, keluaran, diagram, REPO

#chapter("Lampiran A — Perkakas Lintas Modul", l: "bab:lampiran-a")

Seluruh perkakas yang dipakai pada lebih dari satu modul berada di folder
`tools/` pada akar repositori praktikum. Perkakas yang hanya dipakai satu modul
--- `monitor_serial.py`, `lora_monitor.py`, `upload_auto.py`, `cek_radio.py`
--- dimuat lengkap pada bagian "Kode Program" bab modul yang bersangkutan,
sebab isinya memang berbeda-beda mengikuti format log tiap modul.

== Mengenali Port Sebelum Mengunggah

Lab ini memakai Arduino Uno asli maupun klon secara bercampur. Firmware
keduanya identik; yang berbeda hanya chip jembatan USB-ke-serial, dan itu hanya
mengubah nama port di sistem operasi (lihat @tbl:p-jembatan-usb pada bab
Pendahuluan). Skrip `tools/deteksi_port.py` membaca VID dan PID tiap port
serial lalu melaporkan jenis board-nya, sehingga `upload_port` di
`platformio.ini` dapat diisi dengan pasti, bukan ditebak.

#keluaran("python3 tools/deteksi_port.py          # daftar port + jenis board
python3 tools/deteksi_port.py --ini    # potongan platformio.ini siap tempel")

Tanpa argumen, skrip mencetak daftar port beserta jenis jembatannya.

#keluaran("Port             VID:PID      Jenis          Jembatan USB
--------------------------------------------------------------
/dev/ttyACM0     2341:0043    Uno asli       ATmega16U2 (Arduino LLC)
/dev/ttyACM1     2341:0043    Uno asli       ATmega16U2 (Arduino LLC)
/dev/ttyUSB0     1a86:7523    klon           CH340/CH341")

Dengan `--ini`, keluarannya berupa potongan `platformio.ini` yang tinggal
disalin ke berkas modul yang sedang dikerjakan.

#penting[
  Jalankan skrip ini *sebelum* mengunggah pada setiap modul yang memakai lebih
  dari satu board. Port di tiap `platformio.ini` yang disertakan repositori
  masih memakai nilai contoh untuk tiga Uno asli, dan nilai itu hampir pasti
  berbeda di komputer lain.
]

#peringatan[
  Skrip serial yang menyetel jalur DTR/RTS *sebelum* `open()` ditolak oleh CDC
  ATmega16U2 pada Uno asli dengan `[Errno 110] Connection timed out`, sementara
  pada klon CH340 hal itu lolos. Seluruh `monitor_serial.py` pada seri ini
  sudah tidak menyentuh jalur tersebut. Bila menulis skrip serial sendiri, buka
  port apa adanya --- jangan mengatur DTR/RTS sebelum membukanya.
]

== Kode Program

#sumber-kode("tools", ("deteksi_port.py",))

#kode-berkas("tools/deteksi_port.py",
  [`tools/deteksi_port.py` --- kenali jenis board pada tiap port serial],
  "lst:la-deteksi-port",
  pecah: true,
)

== Peta Perkakas Tiap Modul

#tbl(
  table(
    columns: (auto, 1.4fr, 1.4fr),
    align: (center + horizon, left, left),
    inset: (x: 0.55em, y: 0.45em),
    stroke: 0.5pt + luma(170),
    table.header(th[Modul], th[Perkakas pemantau], th[Perkakas lain]),
    [01--04], [`monitor_serial.py`], [`upload_auto.py`],
    [05], [`monitor_serial.py`, `lora_monitor.py`], [`upload_auto.py`],
    [06], [--- (keluaran langsung ke terminal Pi)], [---],
    [07, 07B], [`lora_monitor.py`], [`cek_radio.py`, `upload_auto.py`],
    [08, 08B, 08C], [`lora_monitor.py`], [`upload_auto.py`],
    [09, 10], [`lora_monitor.py`], [`upload_auto.py`],
    [11], [`gateway/uplink_listen.py`], [`gateway/provision_lab.py`, `upload_auto.py`],
    [semua], [---], [`tools/deteksi_port.py`],
  ),
  [Perkakas yang tersedia pada tiap modul],
  "tbl:la-perkakas",
)

Perkakas yang memerlukan pustaka tambahan hanya dua: `lora_monitor.py`
(memerlukan `pyserial` dan `rich`) serta `gateway/uplink_listen.py`
(memerlukan `paho-mqtt`). Sisanya berjalan dengan Python 3 standar, kecuali
`monitor_serial.py` yang memerlukan `pyserial`.

== Salinan Daring

Seluruh berkas yang dimuat di buku ini tersedia pada repositori praktikum
#link(REPO)[`github.com/hendrieepis/WSN-IOT-prak-Lora`]. Folder perkakas
lintas modul: #gh-folder("tools"). Aset pendukung yang tidak dimuat di buku ---
skematik shield dan HAT, user manual Dragino, serta berkas `logserial.md` tiap
modul --- juga berada di repositori yang sama.
