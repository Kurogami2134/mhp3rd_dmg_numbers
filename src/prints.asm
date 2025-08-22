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
DURATION    equ     27
BASE_SIZE   equ     0x12
; bigger means less scaling, exponentially
SCALING_PWR equ     5

; ---------------- Parametrização do ruído e offsets fixos ----------------
; NOISE_STEPS = número máximo de steps (bin ∈ [0..NOISE_STEPS], total = NOISE_STEPS+1 opções)
; NOISE_STEP  = tamanho de cada step (px)
; NOISE_FIX_X / NOISE_FIX_Y = deslocamentos fixos aplicados após o ruído
;   - NOISE_FIX_X: **positivo move para a ESQUERDA**, negativo para a direita
;   - NOISE_FIX_Y: positivo desce, negativo sobe
NOISE_STEP    equ   3
NOISE_STEPS   equ   6
NOISE_FIX_X   equ   12         ; + => esquerda, − => direita
NOISE_FIX_Y   equ   -45        ; + => baixo,     − => cima

; ---------------- Parametrização da tela e do clamp ----------------
SCREEN_W      equ   480
SCREEN_H      equ   272
CLAMP_MARGIN  equ   25         ; margem interna (px) nas bordas
X_MIN         equ   CLAMP_MARGIN
Y_MIN         equ   CLAMP_MARGIN
X_MAX         equ   (SCREEN_W - CLAMP_MARGIN)
Y_MAX         equ   (SCREEN_H - CLAMP_MARGIN)

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

.word 0x2134

; ---------------- Bounce por TABELA (independente de DURATION) -------------
; BOUNCE_LEN = número de frames em que aplicamos deslocamento (age ∈ 1..BOUNCE_LEN)
; BOUNCE_TABLE[i] = deltaY aplicado (em pixels) no frame age=(i+1)
; Obs.: valores negativos sobem na tela (y menor)
BOUNCE_LEN    equ   11
;            age:   1,   2,   3,    4,    5,    6,    7,    8,   9,   10,  11
BOUNCE_TABLE:
    .hword      0,  -2,  -5,  -10,  -15,  -20,  -15,  -10,  -5,  -2,   0
.align 4                    ; <<< garante alinhamento de 4 bytes para instruções

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

    ; ---------- Ruído inicial parametrizado + mix por slot ----------
    srl         t9, t0, 3                  ; t9 = idx do slot (0..MAX_NUMBERS-1)

    ; ---- X: base + (bin*NOISE_STEP) - NOISE_FIX_X ----
    jal         rng
    nop
    li          t7, 7
    multu       t9, t7
    mflo        t7
    addiu       t7, t7, 3
    andi        t7, t7, 0x00FF
    xor         t1, s1, t7
    andi        t1, t1, 0x0F

    li          t6, NOISE_STEPS
    multu       t1, t6
    mflo        t2
    addiu       t2, t2, 15
    srl         t2, t2, 4                  ; bin 0..NOISE_STEPS

    li          t5, NOISE_STEP
    multu       t2, t5
    mflo        t1                         ; offset = bin*NOISE_STEP

    li          t4, NOISE_FIX_X
    addu        s1, a1, t1                 ; base + noise (direita)
    subu        s1, s1, t4                 ; − NOISE_FIX_X (positivo => esquerda)
    sh          s1, 0x0(s0)                ; x inicial

    ; ---- Y: base - (bin*NOISE_STEP) + NOISE_FIX_Y ----
    jal         rng
    nop
    li          t7, 11
    multu       t9, t7
    mflo        t7
    addiu       t7, t7, 5
    andi        t7, t7, 0x00FF
    xor         t1, s1, t7
    andi        t1, t1, 0x0F

    li          t6, NOISE_STEPS
    multu       t1, t6
    mflo        t2
    addiu       t2, t2, 15
    srl         t2, t2, 4                  ; bin 0..NOISE_STEPS

    li          t5, NOISE_STEP
    multu       t2, t5
    mflo        t1                         ; offset

    li          t4, NOISE_FIX_Y
    subu        s1, a2, t1                 ; base - noise (para cima)
    addu        s1, s1, t4                 ; + NOISE_FIX_Y
    sh          s1, 0x2(s0)                ; y inicial

    ; clamp depois do cálculo inicial
    jal         clamp_initial_pos
    nop
    
    sh          v0, 0x4(s0)                ; value
    li          s1, DURATION << 8          ; frames (hi) + cor (lo será ajustado)

    ; cor por thresholds (mantido como antes)
    slti        at, v0, 100
    beql        at, zero, @@other_colors
    addiu       s1, RED
    slti        at, v0, 10
    beql        at, zero, @@other_colors
    addiu       s1, YELLOW
@@white:
    addiu       s1, WHITE
@@other_colors:
    sh          s1, 0x6(s0)                ; frames e color

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
    sb          a0, 0x7(at)          ; a0 = remaining_frames (já decrementado)

    li          t8, PRINT_SETTINGS    ; ponteiro settings

    ; X cursor
    lh          a1, 0x0(at)
    sh          a1, Xcurs(t8)

    ; Y com bounce por tabela
    lh          t2, 0x2(at)          ; y_base
    li          t4, DURATION
    subu        t0, t4, a0           ; age = DURATION - remaining
    
    li          t7, BOUNCE_LEN
    slt         t6, t7, t0           ; age > BOUNCE_LEN ?
    bne         t6, zero, @bounce_zero
    nop
    addiu       t6, t0, -1           ; index = age-1
    sll         t6, t6, 1            ; *2 (hword)
    li          t7, BOUNCE_TABLE
    addu        t7, t7, t6
    lh          t1, 0x0(t7)
    b           @bounce_done
    nop
@bounce_zero:
    move        t1, zero
@bounce_done:
    addu        t3, t2, t1
    sh          t3, Ycurs(t8)

    ; Cor
    lb          a1, 0x6(at)
    sb          a1, CHARCOLOR(t8)

    ; Tamanho
    lh          a2, 0x4(at)
    srl         a2, a2, SCALING_PWR
    addiu       a2, a2, BASE_SIZE
    sll         a1, a2, 8
    or          a1, a1, a2
    sh          a1, CHARWIDTH(t8)
    
    ; Blink (mantido)
    slti        t6, a0, 6
    beq         t6, zero, @draw
    nop
    andi        t6, a0, 1
    beq         t6, zero, @loop_end
    nop

@draw:
    move        a0, t8
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

; ---------------------------------------------------------------------------
; clamp_initial_pos
; ---------------------------------------------------------------------------
clamp_initial_pos:
    addiu       sp, sp, -0x10
    sw          ra, 0x00(sp)
    sw          t1, 0x04(sp)
    sw          t2, 0x08(sp)
    sw          t3, 0x0C(sp)

    ; ---- Clamp X ----
    lh          t1, 0x0(s0)
    li          t2, X_MIN
    slt         t3, t1, t2
    beq         t3, zero, @@x_ge_min
    nop
    sh          t2, 0x0(s0)
    b           @@y_part
    nop
@@x_ge_min:
    li          t2, X_MAX
    slt         t3, t2, t1
    beq         t3, zero, @@y_part
    nop
    sh          t2, 0x0(s0)

    ; ---- Clamp Y ----
@@y_part:
    lh          t1, 0x2(s0)
    li          t2, Y_MIN
    slt         t3, t1, t2
    beq         t3, zero, @@y_ge_min
    nop
    sh          t2, 0x2(s0)
    b           @@ret
    nop
@@y_ge_min:
    li          t2, Y_MAX
    slt         t3, t2, t1
    beq         t3, zero, @@ret
    nop
    sh          t2, 0x2(s0)

@@ret:
    lw          t3, 0x0C(sp)
    lw          t2, 0x08(sp)
    lw          t1, 0x04(sp)
    lw          ra, 0x00(sp)
    addiu       sp, sp, 0x10
    jr          ra
    nop

fmt:
    .asciiz     "%d"
    .align      4
printdata:

.close
