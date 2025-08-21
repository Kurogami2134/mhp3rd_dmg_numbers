import struct

with open("bin/adds.bin", "rb") as file:
    MAIN_HOOK, LOAD_ADD = struct.unpack("2i", file.read(8))


with open("bin/dmg_num.bin", "wb") as file:
    with open("bin/prints.bin", "rb") as prints:
        data = prints.read()
    
    file.write(struct.pack("2I", LOAD_ADD, len(data)))
    file.write(data)

    with open("bin/eboot.bin", "rb") as eboot:
        data = eboot.read()
    
    file.write(struct.pack("2I", MAIN_HOOK, len(data)))
    file.write(data)

    file.write(b'\xFF\xFF\xFF\xFF\x00\x00\x00\x00')
