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
GAME        equ     0x656D6167

RED         equ     0x13
YELLOW      equ     0x12
WHITE       equ     0x00

MAX_NUMBERS equ     10
DURATION    equ     15
BASE_SIZE   equ     0x10
; bigger means less scaling, exponentially
SCALING_PWR equ     5

.macro liw,dest,value
    .if (value & 0xFFFF) > 0xFFFF/2
        lui			at, value / 0x10000 + 0x1
    .else
        lui			at, value / 0x10000
    .endif
	lw			dest, value & 0xFFFF(at)
.endmacro

.macro lib,dest,value
	lui			at, value / 0x10000
	lb			dest, value & 0xFFFF(at)
.endmacro

.createfile "../bin/prints.bin", LOAD_ADD

; GUARD_VALUE
.word 0x2134

last:
    .word       0
add:
    beq         v0, zero,  @skip_add
    nop
    addiu       sp, sp, -0x18
    sw          s0, 0x00(sp)
    sw          s1, 0x04(sp)
    sw          t0, 0x08(sp)
    sw          a0, 0x0C(sp)
    sw          a1, 0x10(sp)
    sw          a2, 0x14(sp)

    li          a1, player_area
    lb          a1, 0x0(a1)
    lb          a2, 0xD6(a0)
    bne         a1, a2, @ret
    nop

    liw         t0, last
    sll         t0, t0, 0x3
    li          s0, printdata
    addu        s0, s0, t0

    ; create print data
create_print:
    jal         get_coords
    nop
    jal         rng
    nop
    addu        s1, s1, a1
    sh          s1, 0x0(s0)  ; saves random value to x coordinate

    jal         rng
    nop
    addu        s1, s1, a2
    addiu       s1, s1, -0x10
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
    lw          a0, 0x0C(sp)
    lw          a1, 0x10(sp)
    lw          a2, 0x14(sp)
    addiu       sp, sp, 0x18
@skip_add:
    li          ra, ADD_RA
    j           ADD_RET
    nop

check_n_enable:
    li          s0, TASK
    li          at, GAME
    lw          s0, 0x0(s0)
    bne         s0, at, check_ret
    nop
    li          s0, CHECK
    lw          at, 0x0(s0)
    bnel        at, zero, @@n_skip
    sw          zero, 0x0(s0)
@@n_skip:
    li          s0, ADD_HOOK
    li          at, 0x0A000000 | (add/4)
    lw          a0, 0x0(s0)
    beq         a0, at, @@add_skip
    nop
    sw          at, 0x0(s0)
    sw          zero, 0x4(s0)
@@add_skip:
    j           check_ret
    nop

main:
    addiu       sp, sp, -0x8
    sw          s0, 0x0(sp)
    sw          ra, 0x4(sp)

    b           check_n_enable
    nop

check_ret:
    
    li          s0, MAX_NUMBERS

    li          at, printdata
    
@loop:
    ; skip if remaining frames == 0
    lb          a0, 0x7(at)
    beq         a0, zero, @loop_end
    nop
    
    addiu       a0, a0, -0x1
    sb          a0, 0x7(at)

    li          a0, PRINT_SETTINGS

    lh          a1, 0x0(at)
    sh          a1, Xcurs(a0)

    lh          a1, 0x2(at)
    addiu       a1, a1, -0x2
    sh          a1, 0x2(at)
    sh          a1, Ycurs(a0)

    lb          a1, 0x6(at)
    sb          a1, CHARCOLOR(a0)

    lh          a2, 0x4(at)
    srl         a2, a2, SCALING_PWR
    addiu       a2, a2, BASE_SIZE
    sll         a1, a2, 8
    or          a1, a1, a2
    sh          a1, CHARWIDTH(a0)
    
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
    lw          ra, 0x4(sp)

    li          a0, PRINT_SETTINGS
    li          a1, 0x0
    li          a2, 0x1
    j           MAIN_RET
    addiu       sp, sp, 0x8

seed:
    .word       149

get_coords: ; a0 monster data
    li      a1, ViewMatrix

    lv.q    r100, 0x00(a1)
    lv.q    r101, 0x10(a1)
    lv.q    r102, 0x20(a1)
    lv.q    r103, 0x30(a1)

    ; load monster coords
    lv.q  c500, 0x80(a0)
    vone.s  s503

    ; view matrix * monster coords
    vtfm4.q r600, m100, c500

    ; set projection matrix
    vzero.q  c500
    vzero.q  c510
    vzero.q  c520
    vzero.q  c530

    li	a0,	0x3f9b8c00
    mtv	a0, s500

    li	a0, 0x40093eff
    mtv	a0, s511

    li	a0, 0xbf800000
    mtv	a0, s522

    li	a0, 0xbf800000
    mtv	a0, s532

    li	a0, 0xc2700000
    mtv	a0, s523

    ; projection matrix * view matrix * monster coords
    vtfm4.q r601, M500, r600

    vdiv.s s602, s601, s631
    vdiv.s s612, s611, s631
    vdiv.s s622, s621, s631

    li	a0, 0x43f00000
    mtv	a0, s600

    li	a0, 0x43880000
    mtv	a0, s610

    li	a0, 0x3f000000
    mtv	a0, s620

    vadd.s s602, s602, s630
    vmul.s s602, s602, s620
    vmul.s s602, s602, s600 ;result x

    vsub.s s612, s630, s612
    vmul.s s612, s612, s620
    vmul.s s612, s612, s610 ;result y

    ; set crosshair vertices
    vf2iz.p     r602, r602, 0
    mfv         a1, s602
    mfv         a2, s612
    
    jr          ra
    nop

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
