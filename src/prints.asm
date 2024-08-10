; printdata {
;   x: short,
;   y: short,
;   value: short,
;   color: byte,
;   remaining_frames: byte
; }

Xcurs		equ		0x120
Ycurs		equ		0x122
CHARWIDTH	equ		0x12C
CHARHEIGHT	equ		0x12D
CHARCOLOR	equ		0x12E
printf      equ     0x088EAA64

RED         equ     0x13
YELLOW      equ     0x12
WHITE       equ     0x00

MAX_NUMBERS equ     10
x           equ     100
y           equ     100
DURATION    equ     30

.macro liw,dest,value
    .if (value & 0xFFFF) > 0xFFFF/2
        lui			at, value / 0x10000 + 0x1
    .else
        lui			at, value / 0x10000
    .endif
	lw			dest, value & 0xFFFF(at)
.endmacro

.createfile "../bin/prints.bin", 0x8800500

last:
    .word       0
add:
    bne         v0, zero,  @fn
    nop
    li          ra, 0x9C75104
    j           0x09C953E0
    nop
@fn:
    addiu       sp, sp, -0xC
    sw          s0, 0x0(sp)
    sw          s1, 0x4(sp)
    sw          t0, 0x8(sp)

    liw         t0, last
    sll         t0, t0, 0x3
    li          s0, printdata
    addu        s0, s0, t0

    ; create print data
    jal         rng
    nop
    addiu       s1, s1, x
    sh          s1, 0x0(s0)  ; saves random value to x coordinate

    jal         rng
    nop
    addiu       s1, s1, y
    sh          s1, 0x2(s0)  ; saves random value to y coordinate
    
    sh          v0, 0x4(s0)  ; value
    li          s1, DURATION << 8   ; set frames to duration
    
    ; set the color depending on damage
    slti        at, v0, 100
    beql        at, zero, @@other_colors
    addiu       s1, RED
    
    slti        at, v0, 10
    beql        at, zero, @@other_colors
    addiu       s1, YELLOW
@@white:
    addiu       s1, WHITE
@@other_colors:

    sh          s1, 0x6(s0)  ; frames and color

    srl         t0, t0, 0x3
    addiu       s1, t0, 0x1
    li          s0, MAX_NUMBERS
    blt         s1, s0, @ret
    nop
    li          s1, 0
@ret:
    li          s0, last
    sw          s1, 0x0(s0)
    lw          s0, 0x0(sp)
    lw          s1, 0x4(sp)
    lw          t0, 0x8(sp)

    li          ra, 0x9C75104
    j           0x09C953E0
    addiu       sp, sp, 0xC


main:
    addiu       sp, sp, -0x4
    sw          s0, 0x0(sp)
    
    li          s0, MAX_NUMBERS

    li          at, printdata
    
@loop:
    ; skip if remaining frames == 0
    lb          a0, 0x7(at)
    beq         a0, zero, @loop_end
    nop
    
    addiu       a0, a0, -0x1
    sb          a0, 0x7(at)

    li          a0, 0x09ADB910

    lh          a1, 0x0(at)
    sh          a1, Xcurs(a0)

    lh          a1, 0x2(at)
    addiu       a1, a1, -0x2
    sh          a1, 0x2(at)
    sh          a1, Ycurs(a0)

    lb          a1, 0x6(at)
    sb          a1, CHARCOLOR(a0)
    
    li          a1, fmt
    lh          a2, 0x4(at)
    jal         printf
    nop
@loop_end:
    addiu       at, at, 8
    addiu       s0, s0, -0x1
    bne         s0, zero, @loop
    nop
end:
    lw          s0, 0x0(sp)
    addiu       sp, sp, 0x4

    li          a0, 0x09ADB910
    li          a1, 0x0
    li          a2, 0x1
    li          ra, 0x088E6D6C
    j           0x088EBAB8
    nop

seed:
    .word       149

rng:
    liw         at, seed
    sll         s1, at, 0x4
    addu        s1, s1, at
    addiu       s1, 0x16
    andi        s1, s1, 0xFF
    li          at, seed
    sw          s1, 0x0(at)

    srl         s1, s1, 0x4

    jr          ra
    nop

fmt:
    .asciiz     "%d"
    .align      4
printdata:

.close
