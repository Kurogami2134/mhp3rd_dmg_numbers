import struct

with open("bin/dmg_num.bin", "wb") as file:
    with open("bin/prints.bin", "rb") as prints:
        data = prints.read()
    
    file.write(struct.pack("2I", 0x9F00000, len(data)))
    file.write(data)

    with open("bin/eboot.bin", "rb") as eboot:
        data = eboot.read()
    
    file.write(struct.pack("2I", 0x88E6D64, len(data)))
    file.write(data)

    file.write(b'\xFF\xFF\xFF\xFF\x00\x00\x00\x00')
