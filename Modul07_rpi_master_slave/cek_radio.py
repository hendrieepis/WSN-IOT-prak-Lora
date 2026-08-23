"""Baca BALIK register SX1276 di master setelah loraBegin()+konfigurasi.
Yang dilaporkan adalah isi chip, bukan konstanta di source."""
import sys
sys.path.insert(0, 'src')
import master as M

assert M.loraBegin(M.FREQUENCY), "loraBegin GAGAL"
M.setSpreadingFactor(M.SPREADING_FACTOR)
M.setSignalBandwidth(M.BANDWIDTH)
M.setCodingRate4(M.CODING_RATE)
M.setTxPower(M.TX_POWER)

msb = M._read_reg(M.REG_FRF_MSB); mid = M._read_reg(M.REG_FRF_MID); lsb = M._read_reg(M.REG_FRF_LSB)
frf = (msb << 16) | (mid << 8) | lsb
freq = frf * 32e6 / (1 << 19)
print(f"REG_VERSION   : 0x{M._read_reg(M.REG_VERSION):02x}   (0x12 = SX1276/77/78/79)")
print(f"FRF register  : 0x{msb:02x} 0x{mid:02x} 0x{lsb:02x}  -> frf={frf}")
print(f"FREKUENSI     : {freq/1e6:.6f} MHz   (target 433.000000, selisih {freq-433e6:+.1f} Hz)")

mc1 = M._read_reg(M.REG_MODEM_CONFIG_1); mc2 = M._read_reg(M.REG_MODEM_CONFIG_2)
bw_tab = ["7.8","10.4","15.6","20.8","31.25","41.7","62.5","125","250","500"]
print(f"MODEM_CFG_1   : 0x{mc1:02x} -> BW={bw_tab[mc1>>4]} kHz | CR=4/{((mc1>>1)&0x07)+4} | header={'implicit' if mc1&1 else 'explicit'}")
print(f"MODEM_CFG_2   : 0x{mc2:02x} -> SF{mc2>>4} | CRC payload={'AKTIF' if mc2&0x04 else 'MATI'}")
print(f"PA_CONFIG     : 0x{M._read_reg(M.REG_PA_CONFIG):02x} -> PA_BOOST, power={(M._read_reg(M.REG_PA_CONFIG)&0x0F)+2} dBm")
M.loraEnd()
