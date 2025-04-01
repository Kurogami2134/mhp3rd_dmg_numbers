from ModIO import CwCheatIO

with CwCheatIO("bin/cheats.txt") as file:
    file.write("DMG NUMBERS 1/2")
    with open("bin/prints.bin", "rb") as prints:
        data = prints.read()
    file.seek(0x09F00400)
    file.write_once(data)

    file.write("DMG NUMBERS 2/2")
    file.seek(0x088E6D64)
    with open("bin/eboot.bin", "rb") as eboot:
        file.write(eboot.read())
