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

MAX_NUMBERS equ     10
x           equ     100
y           equ     100

.macro liw,dest,value
	lui			at, value / 0x10000
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
    addiu       sp, sp, -0x8
    sw          s0, 0x0(sp)
    sw          s1, 0x4(sp)
    liw         at, last
    sll         at, at, 0x3
    li          s0, printdata
    addu        s0, s0, at

    ; create print data
    li          s1, x
    sh          s1, 0x0(s0)
    li          s1, y
    sh          s1, 0x2(s0)
    sh          v0, 0x4(s0)
    li          s1, 0x1e12
    sh          s1, 0x6(s0)

    srl         at, at, 0x3
    addiu       s1, at, 0x1
    li          s0, MAX_NUMBERS
    blt         s1, s0, @ret
    nop
    li          s1, 0
@ret:
    li          s0, last
    sw          s1, 0x0(s0)
    lw          s0, 0x0(sp)
    lw          s1, 0x4(sp)

    li          ra, 0x9C75104
    j           0x09C953E0
    addiu       sp, sp, 0x8


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
fmt:
    .asciiz     "%d"
    .align      4
printdata:

.close
