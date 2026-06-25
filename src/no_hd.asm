.psp

.relativeinclude on

MAIN_HOOK       equ 0x088E6D64
MAIN_RET        equ 0x088EBAB8
printf          equ 0x088EAA64
player_area     equ 0x08B24979
ViewMatrix      equ 0x09B486B0
LOAD_ADD        equ 0x08801B60

CHECK           equ 0x09C1EC70
ADD_HOOK        equ 0x09C750FC

ADD_RA          equ 0x09C75104
ADD_RET         equ 0x09C953E0
TASK            equ 0x09C57CA0

PRINT_SETTINGS  equ 0x09ADB910

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
