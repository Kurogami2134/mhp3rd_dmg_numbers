from ModIO import CwCheatIO

with CwCheatIO("bin/cheats.txt") as file:
    file.write("DMG NUMBERS 1/2")
    with open("bin/prints.bin", "rb") as prints:
        data = prints.read()
    file.file.write(f'_L 0xE1{hex(len(data)//4+1).replace("0x", ""):0>2}0000 0x000004FF\n')
    file.seek(0x88004FF)
    file.write(b'\x01')
    file.write(data)

    file.write("DMG NUMBERS 2/2")
    file.seek(0x088E6D64)
    with open("bin/eboot.bin", "rb") as eboot:
        file.write(eboot.read())
    file.file.write('_L 0xE002002e 0x0147C22C\n')
    file.seek(0x09C1EC70)
    with open("bin/game_a.bin", "rb") as game:
        file.write(game.read())
    file.seek(0x09C750FC)
    with open("bin/game_b.bin", "rb") as game:
        file.write(game.read())
