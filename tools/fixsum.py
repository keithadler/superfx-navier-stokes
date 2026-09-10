#!/usr/bin/env python3
"""Write the SNES internal-header checksum/complement into a LoROM image."""
import sys
path = sys.argv[1]
data = bytearray(open(path, 'rb').read())
hdr = 0x7FC0  # LoROM header lives at $00:FFC0 = file offset $7FC0
data[hdr + 0x1C:hdr + 0x20] = b'\xFF\xFF\x00\x00'  # neutral values, sum to $1FE
s = sum(data) & 0xFFFF
comp = s ^ 0xFFFF
data[hdr + 0x1C:hdr + 0x1E] = comp.to_bytes(2, 'little')
data[hdr + 0x1E:hdr + 0x20] = s.to_bytes(2, 'little')
open(path, 'wb').write(data)
print(f"{path}: {len(data)} bytes, checksum ${s:04X}, title {bytes(data[hdr:hdr+21]).decode('ascii').strip()!r}")
