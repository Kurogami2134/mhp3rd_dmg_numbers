from ModIO import CwCheatIO
from struct import unpack

with open("bin/adds.bin", "rb") as file:
    MAIN_HOOK, LOAD_ADD = unpack("2i", file.read(8))

with CwCheatIO("bin/cheats.txt") as file:
    file.write("DMG NUMBERS 1/2")
    with open("bin/prints.bin", "rb") as prints:
        data = prints.read()
    file.seek(LOAD_ADD)
    file.write_once(data)

    file.write("DMG NUMBERS 2/2")
    file.seek(MAIN_HOOK)
    with open("bin/eboot.bin", "rb") as eboot:
        file.write(eboot.read())
