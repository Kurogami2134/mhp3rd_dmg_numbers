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
NOISE_STEP    equ   3          ; ex.: 6 px (0,6,12,18,24,30)
NOISE_STEPS   equ   6          ; max step = 5  => opções 0..5
NOISE_FIX_X   equ   12          ; + => esquerda, − => direita
NOISE_FIX_Y   equ   -45          ; + => baixo,     − => cima

; ---------------- Parametrização da tela e do clamp ----------------
SCREEN_W      equ   480
SCREEN_H      equ   272
CLAMP_MARGIN  equ   25          ; margem interna (px) nas bordas
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

    ; ---------- Ruído inicial parametrizado + mix por slot ----------
    ; idx = (offset/8)
    srl         t9, t0, 3                  ; t9 = idx do slot (0..MAX_NUMBERS-1)

    ; ---- X: base + (bin*NOISE_STEP) - NOISE_FIX_X  (bin 0..NOISE_STEPS) ----
    jal         rng
    nop
    ; mixX = (idx*7 + 3) & 0xFF
    li          t7, 7
    multu       t9, t7
    mflo        t7
    addiu       t7, t7, 3
    andi        t7, t7, 0x00FF
    xor         t1, s1, t7                 ; t1 = rng ^ mixX
    andi        t1, t1, 0x0F               ; t1 ∈ 0..15

    li          t6, NOISE_STEPS            ; maxStep
    multu       t1, t6                     ; t1 * maxStep
    mflo        t2
    addiu       t2, t2, 15                 ; +15 p/ arredondar ao dividir por 16
    srl         t2, t2, 4                  ; t2 = bin 0..NOISE_STEPS

    li          t5, NOISE_STEP
    multu       t2, t5
    mflo        t1                         ; t1 = offset = bin*NOISE_STEP

    li          t4, NOISE_FIX_X
    addu        s1, a1, t1                 ; base + noise (para a direita)
    subu        s1, s1, t4                 ; − NOISE_FIX_X (positivo => esquerda)
    sh          s1, 0x0(s0)                ; x inicial

    ; ---- Y: base - (bin*NOISE_STEP) + NOISE_FIX_Y  (sobe com noise) ----
    jal         rng
    nop
    ; mixY = (idx*11 + 5) & 0xFF
    li          t7, 11
    multu       t9, t7
    mflo        t7
    addiu       t7, t7, 5
    andi        t7, t7, 0x00FF
    xor         t1, s1, t7                 ; t1 = rng ^ mixY
    andi        t1, t1, 0x0F               ; 0..15

    li          t6, NOISE_STEPS
    multu       t1, t6
    mflo        t2
    addiu       t2, t2, 15
    srl         t2, t2, 4                  ; bin 0..NOISE_STEPS

    li          t5, NOISE_STEP
    multu       t2, t5
    mflo        t1                         ; offset

    li          t4, NOISE_FIX_Y
    subu        s1, a2, t1                 ; base - noise  (para cima)
    addu        s1, s1, t4                 ; + NOISE_FIX_Y (ajuste fino)
    sh          s1, 0x2(s0)                ; y inicial

    ; clamp de margem/tela visível após calcular x,y iniciais
    jal         clamp_initial_pos
    nop
    
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
    sb          a0, 0x7(at)          ; a0 = remaining_frames (já decrementado)

    ; --- Preparar ponteiro para PRINT_SETTINGS em t8 ---
    li          t8, PRINT_SETTINGS

    ; --- X: cursor ---
    lh          a1, 0x0(at)
    sh          a1, Xcurs(t8)

    ; --- Y: animação com bounce (11 frames) ---
    lh          t2, 0x2(at)          ; t2 = y_base (não persistimos alterações)
    li          t4, DURATION
    subu        t0, t4, a0           ; t0 = age = DURATION - remaining_frames
    move        t1, zero             ; t1 = deltaY default (0)

    ; age map (1..11):
    ; 1: 0
    ; 2: -2
    ; 3: -5
    ; 4: -10
    ; 5: -15
    ; 6: -20
    ; 7: -15
    ; 8: -10
    ; 9: -5
    ; 10: -2
    ; 11: 0

    li          t5, 2
    beq         t0, t5, @b_n2
    nop
    li          t5, 3
    beq         t0, t5, @b_n5
    nop
    li          t5, 4
    beq         t0, t5, @b_n10
    nop
    li          t5, 5
    beq         t0, t5, @b_n15
    nop
    li          t5, 6
    beq         t0, t5, @b_n20
    nop
    li          t5, 7
    beq         t0, t5, @b_n15
    nop
    li          t5, 8
    beq         t0, t5, @b_n10
    nop
    li          t5, 9
    beq         t0, t5, @b_n5
    nop
    li          t5, 10
    beq         t0, t5, @b_n2
    nop
    li          t5, 11
    beq         t0, t5, @b_0
    nop
    b           @b_done
    nop

@b_n2:   addiu   t1, zero, -2    ; -2
         b       @b_done
         nop
@b_n5:   addiu   t1, zero, -5    ; -5
         b       @b_done
         nop
@b_n10:  addiu   t1, zero, -10   ; -10
         b       @b_done
         nop
@b_n15:  addiu   t1, zero, -15   ; -15
         b       @b_done
         nop
@b_n20:  addiu   t1, zero, -20   ; -20
         b       @b_done
         nop
@b_0:    move    t1, zero        ; 0
@b_done:
    addu        t3, t2, t1
    sh          t3, Ycurs(t8)

    ; --- Cor ---
    lb          a1, 0x6(at)
    sb          a1, CHARCOLOR(t8)

    ; --- Tamanho (width/height) ---
    lh          a2, 0x4(at)
    srl         a2, a2, SCALING_PWR
    addiu       a2, a2, BASE_SIZE
    sll         a1, a2, 8
    or          a1, a1, a2
    sh          a1, CHARWIDTH(t8)
    
    ; --- Pisca nos últimos 5 frames (a0 <= 4 após o dec) ---
    slti        t6, a0, 6            ; t6=1 se últimos 5 frames
    beq         t6, zero, @draw
    nop
    andi        t6, a0, 1            ; alterna desenhar (1) e não desenhar (0)
    beq         t6, zero, @loop_end  ; se par, pula o draw
    nop

@draw:
    move        a0, t8               ; a0 = PRINT_SETTINGS
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
;  - Usa s0 como ponteiro para o slot corrente (já configurado em create_print)
;  - Garante x,y dentro da tela com margem interna parametrizável:
;      x ∈ [X_MIN, X_MAX], y ∈ [Y_MIN, Y_MAX]  (p/ 480x272 e margem 10: [10..470], [10..262])
; ---------------------------------------------------------------------------
clamp_initial_pos:
    addiu       sp, sp, -0x10
    sw          ra, 0x00(sp)
    sw          t1, 0x04(sp)
    sw          t2, 0x08(sp)
    sw          t3, 0x0C(sp)

    ; ---- Clamp X ----
    lh          t1, 0x0(s0)          ; t1 = x
    li          t2, X_MIN            ; minX
    slt         t3, t1, t2           ; t3 = (x < minX)
    beq         t3, zero, @@x_ge_min
    nop
    sh          t2, 0x0(s0)          ; x = minX
    b           @@y_part
    nop
@@x_ge_min:
    li          t2, X_MAX            ; maxX
    slt         t3, t2, t1           ; t3 = (maxX < x) => x > maxX
    beq         t3, zero, @@y_part
    nop
    sh          t2, 0x0(s0)          ; x = maxX

    ; ---- Clamp Y ----
@@y_part:
    lh          t1, 0x2(s0)          ; t1 = y
    li          t2, Y_MIN            ; minY
    slt         t3, t1, t2           ; t3 = (y < minY)
    beq         t3, zero, @@y_ge_min
    nop
    sh          t2, 0x2(s0)          ; y = minY
    b           @@ret
    nop
@@y_ge_min:
    li          t2, Y_MAX            ; maxY
    slt         t3, t2, t1           ; t3 = (maxY < y) => y > maxY
    beq         t3, zero, @@ret
    nop
    sh          t2, 0x2(s0)          ; y = maxY

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

