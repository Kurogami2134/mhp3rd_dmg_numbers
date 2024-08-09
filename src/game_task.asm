.createfile "../bin/game_a.bin", 0x09C1EC70

    nop

.close


.createfile "../bin/game_b.bin", 0x09C750FC

    j       add
    nop

.close
