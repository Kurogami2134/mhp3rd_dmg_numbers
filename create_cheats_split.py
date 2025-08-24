from ModIO import CwCheatIO
from struct import unpack

with open("bin/adds.bin", "rb") as f:
    MAIN_HOOK, LOAD_ADD = unpack("2i", f.read(8))

with open("bin/prints.bin", "rb") as f:
    prints_blob = f.read()
with open("bin/eboot.bin", "rb") as f:
    eboot_blob = f.read()

MAX_LINES = 230
BYTES_PER_PART = MAX_LINES * 4

# Split prints.bin into contiguous chunks
parts = []
offset = 0
# Write cheats.txt
with CwCheatIO("cheats.txt") as cw:
    total = len(prints_blob) // BYTES_PER_PART + 1
    cw.seek(LOAD_ADD)
    for i in range(total):
        cw.write(f"DMG NUMBERS [PART {i+1}/{total}]")
        cw.write_once(prints_blob[i*BYTES_PER_PART:(i+1)*BYTES_PER_PART])

    cw.write("DMG NUMBERS [HOOKS]")
    cw.seek(MAIN_HOOK)
    cw.write(eboot_blob)

