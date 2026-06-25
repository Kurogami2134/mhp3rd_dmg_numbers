.psp

.relativeinclude on

MAIN_HOOK       equ 0x088E881C
MAIN_RET        equ 0x088EE410
printf          equ 0x088EC51C
player_area     equ 0x08B2B139
ViewMatrix      equ 0x09F4F120
LOAD_ADD        equ 0x0AFF0000

CHECK           equ 0x0A025608
ADD_HOOK        equ 0x0A07BA7C

ADD_RA          equ 0x0A07BA84
ADD_RET         equ 0x0A09BD60
TASK            equ 0x0A05E620

PRINT_SETTINGS  equ 0x09EE2350

.include        "prints.asm"
.include        "eboot.asm"

.createfile "../bin/adds.bin", 0x0
.word MAIN_HOOK
.word LOAD_ADD
.close

.createfile "../bin/dmg_num.bin", 0
.ascii "0.01"

.word 1
.word @main_block_end - @main_block
.ascii "DMGN"
@main_block:
.import "../bin/prints.bin"
@main_block_end:

.word 2
.word MAIN_HOOK
.halfword main - LOAD_ADD
.byte 0xC
.byte 0

.word -1

.asciiz "Damage Numbers Display - Kurogami2134"
.close
