from ModIO import CwCheatIO

with CwCheatIO("bin/cheats.txt") as file:
    file.write("DMG NUMBERS 1/2")
    with open("bin/prints.bin", "rb") as prints:
        data = prints.read()
    file.file.write(f'_L 0xE1{int(len(data)/4+1)}0000 0x000004FF\n')
    file.seek(0x88004FF)
    file.write(b'\x01')
    file.write(data)

    file.write("DMG NUMBERS 2/2")
    file.seek(0x088E6D64)
    with open("bin/eboot.bin", "rb") as eboot:
        file.write(eboot.read())
    file.file.write('_L 0xD147C22C 0x0000002e\n')
    file.seek(0x09C7C22C)
    with open("bin/game.bin", "rb") as game:
        file.write(game.read())
