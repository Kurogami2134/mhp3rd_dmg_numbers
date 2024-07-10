import struct

with open("bin/mods.bin", "wb") as file:
    file.write(struct.pack("H", 2))
    
    with open("bin/prints.bin", "rb") as prints:
        data = prints.read()
    
    file.write(struct.pack("2I", 0x8800500, len(data)))
    file.write(data)

    with open("bin/eboot.bin", "rb") as eboot:
        data = eboot.read()
    
    file.write(struct.pack("2I", 0x88E6D64, len(data)))
    file.write(data)
