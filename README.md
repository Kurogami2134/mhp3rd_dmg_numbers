# Damage Numbers display for Monster Hunter Portable 3rd

Adds damage display to MHP3rd.

## Installation

### [mhp3reload](https://github.com/Kurogami2134/mhp3reload)

[Build](#building) or download `dmg_num.bin` from the latest release and refer to [mhp3reload](https://github.com/Kurogami2134/mhp3reload)'s readme for paths and file structures.

### CWCheat

[Build](#building) or download `CHEATS.txt` from the latest release and add the included code to you emulator/console's cheats file.

## Building

### Requirements

- [armips](https://github.com/Kingcom/armips)
- [ModIO](https://github.com/Kurogami2134/modio)

### Instructions

Assemble either `src/no_hd.asm` for the PSP version of the game, or `src/hd_ver.asm` for the HD version of the game using armips, and run the python script that suits your needs.

#### Assembling

##### PSP

    armips src/no_hd.asm

##### HD

    armips src/hd_ver.asm

#### Creating a mod

    py create_mod.py

#### Creating a cheat

    py create_cheats.py
