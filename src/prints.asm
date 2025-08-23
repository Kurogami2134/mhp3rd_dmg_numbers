; -----------------------------------------------------------------------------
;  Monster Hunter Portable 3rd – Damage Numbers
;  This blob is placed at LOAD_ADD and provides:
;   - A hook ("add") that captures damage events and creates a per-hit print slot
;   - A tiny per-frame “engine” that animates numbers with a bounce, size and tail color sequence
;   - 2D screen projection of the monster position to place the initial number
;   - Clamp to keep the text inside the visible area (with margin)
;
;  Notes on design:
;   • We keep state in a ring of MAX_NUMBERS slots (each 8 bytes, see printdata).
;   • Initial position is the projected monster position + “coarse noise” (gridy).
;   • Noise uses a cheap 8-bit LCG + per-slot mixing to decorrelate simultaneous hits.
;   • Animation Y-offset uses a small bounce TABLE (data-driven, easy to tune).
;   • End-of-life visuals (last frames) use a small **color sequence** per base color
;     instead of blinking on/off: we step through a palette that includes 0xFF
;     for “invisible”. This preserves a single draw path and allows precise fades.
;   • We deliberately over-save a few regs to be robust inside a foreign callsite.
;   • All numbers/constants that we expect to tweak frequently are `equ`.
;
;  Tooling:
;   • When emitting .hword data (e.g., bounce table), we realign with `.align 4`
;     to keep MIPS instructions on word boundaries (fixes “opcode not aligned”).
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; printdata layout (8 bytes per slot):
;  offset 0x0: x (short)
;  offset 0x2: y (short)
;  offset 0x4: value (short)      – the damage value printed
;  offset 0x6: color (byte)       – low 8 bits of the halfword at 0x6
;             remaining_frames    – high 8 bits of the halfword at 0x6
; -----------------------------------------------------------------------------

Xcurs		equ		0x120   ; PRINT_SETTINGS->X cursor offset
Ycurs		equ		0x122   ; PRINT_SETTINGS->Y cursor offset
CHARWIDTH	equ		0x12C   ; PRINT_SETTINGS->char width/height (packed)
CHARHEIGHT	equ		0x12D   ; not directly used; width write covers both
CHARCOLOR	equ		0x12E   ; PRINT_SETTINGS->char color

GAME        equ     0x656D6167  ; ASCII "game" sentinel used to detect task init

; Ring-buffer of active numbers
MAX_NUMBERS equ     10          ; simultaneous numbers tracked
DURATION    equ     28          ; total life (frames) for each number instance
BASE_SIZE   equ     0x12        ; base glyph size (see downscale/log-ish logic)
SCALING_PWR equ     5           ; larger = more downscaling for small values

; Tail color sequencing (replaces old blink)
;  • For the last TAIL_FRAMES, we index a small palette per base color.
;  • Outside that window, we render using the base color itself.
TAIL_FRAMES equ     4

; ---------------- Coarse noise and fixed offsets (spawn jitter) --------------
; NOISE_STEPS = maximum discrete steps (bin ∈ [0..NOISE_STEPS])
; NOISE_STEP  = step size in pixels (offset = bin * NOISE_STEP)
; NOISE_FIX_X / NOISE_FIX_Y are small developer-friendly fixed offsets applied
; AFTER noise, BEFORE clamping.
;  • X semantics: positive moves LEFT (counteracts the default “noise-right” drift)
;  • Y semantics: positive moves DOWN (negative moves UP)
NOISE_STEP    equ   5           ; (pixels per step) e.g., step=3 → 0,3,6,…
NOISE_STEPS   equ   4           ; bins 0..6 → up to 18 px of jitter
NOISE_FIX_X   equ   12          ; + => shift left;  − => shift right
NOISE_FIX_Y   equ   -35         ; + => shift down; − => shift up

; ---------------- Screen and clamp parameters --------------------------------
; For stock PSP: 480x272. We clamp inside a margin to avoid half-clipped glyphs.
SCREEN_W      equ   480
SCREEN_H      equ   272
CLAMP_MARGIN  equ   25          ; inner margin on all sides
X_MIN         equ   CLAMP_MARGIN
Y_MIN         equ   CLAMP_MARGIN
X_MAX         equ   (SCREEN_W - CLAMP_MARGIN)
Y_MAX         equ   (SCREEN_H - CLAMP_MARGIN)

; -----------------------------------------------------------------------------
; Small helpers for loading immediates from absolute addresses (armips style)
; -----------------------------------------------------------------------------
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

; -----------------------------------------------------------------------------
; We start emitting the code/data blob for the cheat at LOAD_ADD.
; -----------------------------------------------------------------------------
.createfile "../bin/prints.bin", LOAD_ADD

; A tiny guard so the Python writer can assert correct placement (also used as
; “padding eater”: if we ever need a placeholder, it’s easy to track in the dump).
.word 0x2134

; -----------------------------------------------------------------------------
; Bounce animation (data-driven)
;  • Negative values move the number UP (because 2D Y grows downward on screen).
;  • Table indexed by “age” (1-based). If age > BOUNCE_LEN, deltaY = 0.
;  • Kept short and symmetric. Tweak here without changing code.
; -----------------------------------------------------------------------------
BOUNCE_LEN    equ   11
;            age:   1,   2,   3,    4,    5,    6,    7,    8,   9,   10,  11
BOUNCE_TABLE:
    .hword      0,  -2,  -5,  -10,  -15,  -20,  -15,  -10,  -5,  -2,   0
.align 4                      ; Keep subsequent MIPS instructions word-aligned

; -----------------------------------------------------------------------------
; `last` is the current ring index (0..MAX_NUMBERS-1), advanced after each add.
; We multiply by 8 (slot size) to get the byte offset into printdata.
; -----------------------------------------------------------------------------
last:
    .word       0

; =============================================================================
; add(a0=monster*, a1=?, a2=?, v0=damage)
; Hook entry called from the injected trampoline when a damage event occurred.
; Creates/initializes one print slot with position, value, color+duration.
; =============================================================================
add:
    beq         v0, zero,  @skip_add        ; ignore zero-damage events (rare)
    nop
    ; Save a minimal register set. We’re inside foreign code; be conservative.
    addiu       sp, sp, -0x18
    sw          s0, 0x00(sp)
    sw          s1, 0x04(sp)
    sw          t0, 0x08(sp)
    sw          a0, 0x0C(sp)
    sw          a1, 0x10(sp)
    sw          a2, 0x14(sp)

    ; Filter: only print damage for the local player’s current area/camp, to
    ; avoid UI spam from off-screen entities. This mirrors the original mod.
    li          a1, player_area
    lb          a1, 0x0(a1)
    lb          a2, 0xD6(a0)
    bne         a1, a2, @ret
    nop

    ; Compute slot pointer: s0 = &printdata[ last * 8 ]
    liw         t0, last
    sll         t0, t0, 0x3
    li          s0, printdata
    addu        s0, s0, t0

create_print:
    ; Get screen-space XY from the monster’s world/anim position
    jal         get_coords
    nop

    ; Keep the spawn inside the visible area, considering a safety margin.
    jal         clamp_initial_pos
    nop

    ; We use a small “coarse noise” to avoid perfect overlap of digits when
    ; multiple hits land at the same place. The noise is unidirectional by
    ; default (X to the right, Y upward), then we add developer-chosen FIX.
    ; To reduce collisions between simultaneously spawned slots, we mix the
    ; RNG output with a per-slot linear “hash” (very cheap, good enough).

    ; idx = slot index = (byteOffset / 8)
    srl         t9, t0, 3

    ; --- X noise: base + bin*NOISE_STEP, then shift by FIX to the *left* if >0
    jal         rng                            ; s1 = 0..15 (from high nibble)
    nop
    ; mixX = (idx*7 + 3) & 0xFF  → inexpensive “salt” per slot
    li          t7, 7
    multu       t9, t7
    mflo        t7
    addiu       t7, t7, 3
    andi        t7, t7, 0x00FF
    xor         t1, s1, t7
    andi        t1, t1, 0x0F                 ; 0..15

    ; Map 4-bit RNG to discrete bin 0..NOISE_STEPS with round-like behavior.
    ; We do: bin = ((rng * NOISE_STEPS) + 15) >> 4  [divide by 16 with bias]
    li          t6, NOISE_STEPS
    multu       t1, t6
    mflo        t2
    addiu       t2, t2, 15
    srl         t2, t2, 4                    ; t2=bin 0..NOISE_STEPS

    li          t5, NOISE_STEP
    multu       t2, t5
    mflo        t1                            ; t1 = offset = bin*step

    li          t4, NOISE_FIX_X
    addu        s1, a1, t1                    ; default drift to the right
    subu        s1, s1, t4                    ; positive FIX pulls left
    sh          s1, 0x0(s0)                   ; x initial

    ; --- Y noise: base - bin*NOISE_STEP  (i.e., push UP) + Y FIX
    jal         rng
    nop
    ; mixY = (idx*11 + 5) & 0xFF
    li          t7, 11
    multu       t9, t7
    mflo        t7
    addiu       t7, t7, 5
    andi        t7, t7, 0x00FF
    xor         t1, s1, t7
    andi        t1, t1, 0x0F                  ; 0..15

    li          t6, NOISE_STEPS
    multu       t1, t6
    mflo        t2
    addiu       t2, t2, 15
    srl         t2, t2, 4                     ; bin 0..NOISE_STEPS

    li          t5, NOISE_STEP
    multu       t2, t5
    mflo        t1                            ; offset

    li          t4, NOISE_FIX_Y
    subu        s1, a2, t1                    ; UP by noise
    addu        s1, s1, t4                    ; + FIX (down if positive)
    sh          s1, 0x2(s0)                   ; y initial

    ; Store the value and (frames<<8)|color into the slot.
    sh          v0, 0x4(s0)                   ; value
    li          s1, DURATION << 8             ; frames in high 8 bits

    ; Color thresholds (family) and **base color** = first item in list
    ;   v0 >= 100 → RED palette[0]
    ;   v0 < 10   → YELLOW palette[0]
    ;   else → WHITE palette[0]
    slti        at, v0, 100
    beql        at, zero, @@use_red
    nop
    slti        at, v0, 10
    beql        at, zero, @@use_yellow
    nop
@@use_white:
    li          t3, white_palette
    lbu         t1, 0(t3)                      ; t1 = white_palette[0]
    or          s1, s1, t1
    b           @@color_done
    nop
@@use_yellow:
    li          t3, yellow_palette
    lbu         t1, 0(t3)                      ; t1 = yellow_palette[0]
    or          s1, s1, t1
    b           @@color_done
    nop
@@use_red:
    li          t3, red_palette
    lbu         t1, 0(t3)                      ; t1 = red_palette[0]
    or          s1, s1, t1
@@color_done:
    sh          s1, 0x6(s0)                    ; pack frames+color
    ; Advance ring index: last = (last + 1) % MAX_NUMBERS
    srl         t0, t0, 0x3                    ; restore idx from byte offset
    addiu       s1, t0, 0x1
    li          s0, MAX_NUMBERS
    blt         s1, s0, @ret
    nop
    li          s1, 0
@ret:
    li          s0, last
    sw          s1, 0x0(s0)

    ; Epilogue
    lw          s0, 0x0(sp)
    lw          s1, 0x4(sp)
    lw          t0, 0x8(sp)
    lw          a0, 0x0C(sp)
    lw          a1, 0x10(sp)
    lw          a2, 0x14(sp)
    addiu       sp, sp, 0x18
@skip_add:
    ; Return to the original code (addresses wired by the outer patcher)
    li          ra, ADD_RA
    j           ADD_RET
    nop

; =============================================================================
; check_n_enable
;  • Runs every frame from main(). Ensures we only patch the ADD_HOOK once the
;    game “task” reports a ready state; also clears a simple CHECK flag.
; =============================================================================
check_n_enable:
    li          s0, TASK
    li          at, GAME
    lw          s0, 0x0(s0)
    bne         s0, at, check_ret            ; wait until TASK == "game"
    nop
    li          s0, CHECK
    lw          at, 0x0(s0)
    bnel        at, zero, @@n_skip
    sw          zero, 0x0(s0)                ; clear one-shot CHECK
@@n_skip:
    li          s0, ADD_HOOK
    li          at, 0x0A000000 | (add/4)     ; J-type opcode to our 'add'
    lw          a0, 0x0(s0)
    beq         a0, at, @@add_skip
    nop
    sw          at, 0x0(s0)                  ; patch hook
    sw          zero, 0x4(s0)                ; NOP delay slot (safety)
@@add_skip:
    j           check_ret
    nop

; =============================================================================
; main – tiny scheduler tick called from the EBOOT hook.
;  • Calls check_n_enable, then iterates all slots and draws/animates them.
; =============================================================================
main:
    addiu       sp, sp, -0x8
    sw          s0, 0x0(sp)
    sw          ra, 0x4(sp)
    b           check_n_enable
    nop

; =============================================================================
; check_ret – iterate through slots and render
;  • Decrements remaining_frames, applies bounce (via table), computes size,
;    and applies the **tail color sequence** in the last TAIL_FRAMES frames.
;    We no longer skip draws to blink: we swap the palette entry per-frame and
;    let 0xFF act as “invisible”.
; =============================================================================
check_ret:
    li          s0, MAX_NUMBERS
    li          at, printdata

@loop:
    ; Skip inactive slots
    lb          a0, 0x7(at)                  ; remaining_frames (low byte after dec)
    beq         a0, zero, @loop_end
    nop

    ; Decrement remaining_frames (lifetime countdown)
    addiu       a0, a0, -0x1
    sb          a0, 0x7(at)

    ; Set up PRINT_SETTINGS pointer in t8 (used like a small UI struct)
    li          t8, PRINT_SETTINGS

    ; X cursor: from slot
    lh          a1, 0x0(at)
    sh          a1, Xcurs(t8)

    ; Y cursor: base + bounce(age)
    lh          t2, 0x2(at)                  ; base Y (kept constant per instance)
    li          t4, DURATION
    subu        t0, t4, a0                   ; age = DURATION - remaining_frames

    ; age in [1..BOUNCE_LEN] → use table; otherwise 0
    li          t7, BOUNCE_LEN
    slt         t6, t7, t0                   ; t6=1 if age > BOUNCE_LEN
    bne         t6, zero, @bounce_zero
    nop
    addiu       t6, t0, -1                   ; index = age-1 (0-based)
    sll         t6, t6, 1                    ; *2 (halfword addressing)
    li          t7, BOUNCE_TABLE
    addu        t7, t7, t6
    lh          t1, 0x0(t7)                  ; deltaY from table
    b           @bounce_done
    nop
@bounce_zero:
    move        t1, zero
@bounce_done:
    addu        t3, t2, t1
    sh          t3, Ycurs(t8)

    ; Size: width/height packed. The pipeline is:
    ;   sz = BASE_SIZE + (value >> SCALING_PWR)
    ; This behaves like a “soft-log” growth (cheaper than float pow).
    lh          a2, 0x4(at)                  ; value
    srl         a2, a2, SCALING_PWR
    addiu       a2, a2, BASE_SIZE
    sll         a1, a2, 8
    or          a1, a1, a2
    sh          a1, CHARWIDTH(t8)            ; writes width&height at once

    ; ------------------------------------------------------------------
    ; Tail Color Sequence (last TAIL_FRAMES frames)
    ;  • base_color = *(at + 0x6)
    ;  • if (remaining_frames > TAIL_FRAMES) → use base_color
    ;  • else idx = (TAIL_FRAMES - remaining_frames) ∈ [0..TAIL_FRAMES-1],
    ;    pick from palette for WHITE/YELLOW/RED; fallback = base_color
    ;  Palettes:
    ;    WHITE  : 00, FF, 09, FF, 2A
    ;    YELLOW : 12, FF, 0B, FF, 2C
    ;    RED    : 13, FF, 37, FF, 08
    ; ------------------------------------------------------------------
    lb          t9, 0x6(at)             ; t9 = base_color
    li          t6, TAIL_FRAMES
    slt         t5, t6, a0              ; t5=1 if remaining_frames > TAIL_FRAMES
    bne         t5, zero, @color_normal
    nop

    ; inside tail window → idx = TAIL_FRAMES - remaining_frames
    li          t0, TAIL_FRAMES
    subu        t0, t0, a0              ; t0 = 0..TAIL_FRAMES  (se a0==0 → 5)
    bne         a0, zero, @idx_ok
    nop
    li          t0, TAIL_FRAMES-1       ; clamp para o último item (4)
@idx_ok:
    ; dispatch for **first item** of each pallet (constant agnostic)
    li          t3, white_palette
    lbu         t1, 0(t3)              ; white head
    beq         t9, t1, @pal_white
    nop
    li          t3, yellow_palette
    lbu         t1, 0(t3)              ; yellow head
    beq         t9, t1, @pal_yellow
    nop
    li          t3, red_palette
    lbu         t1, 0(t3)              ; red head
    beq         t9, t1, @pal_red
    nop
    ; fallback: keep base color
    move        t1, t9
    b           @color_apply
    nop
@pal_white:
    li          t3, white_palette
    addu        t3, t3, t0
    lbu         t1, 0x0(t3)
    b           @color_apply
    nop

@pal_yellow:
    li          t3, yellow_palette
    addu        t3, t3, t0
    lbu         t1, 0x0(t3)
    b           @color_apply
    nop

@pal_red:
    li          t3, red_palette
    addu        t3, t3, t0
    lbu         t1, 0x0(t3)
    b           @color_apply
    nop

@color_normal:
    move        t1, t9

@color_apply:
    sb          t1, CHARCOLOR(t8)

@draw:
    ; printf("%d", value) at the prepared position / style in PRINT_SETTINGS
    move        a0, t8
    li          a1, fmt
    lh          a2, 0x4(at)
    jal         printf
    nop

@loop_end:
    addiu       at, at, 8                    ; next slot
    addiu       s0, s0, -0x1
    bne         s0, zero, @loop
    nop

end:
    ; Return to original main
    lw          s0, 0x0(sp)
    lw          ra, 0x4(sp)
    li          a0, PRINT_SETTINGS
    li          a1, 0x0
    li          a2, 0x1
    j           MAIN_RET
    addiu       sp, sp, 0x8

; -----------------------------------------------------------------------------
; RNG: very small 8-bit LCG-like step
;   seed = (seed*17 + 0x16) & 0xFF
;   return s1 = seed >> 4  (upper nibble in 0..15)
; This keeps it cheap and good enough for “visual jitter”. We also mix per-slot.
; -----------------------------------------------------------------------------
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

; -----------------------------------------------------------------------------
; get_coords(a0 = monsterData)
;  • Loads current view matrix (game-provided), reads monster world coords,
;    multiplies by view and then by a hand-built projection matrix (constants).
;  • Converts to screen pixels: X∈[0,480), Y∈[0,272); then returns (a1=X, a2=Y).
;  • All with VFPU instructions for speed.
; -----------------------------------------------------------------------------
get_coords:
    li      a1, ViewMatrix

    ; m100..m103 ← view matrix rows
    lv.q    r100, 0x00(a1)
    lv.q    r101, 0x10(a1)
    lv.q    r102, 0x20(a1)
    lv.q    r103, 0x30(a1)

    ; c500 ← monster position (vec4), s503=1
    lv.q    c500, 0x80(a0)
    vone.s  s503

    ; view * monster
    vtfm4.q r600, m100, c500

    ; Build a projection matrix (M500) directly in VFPU registers.
    ; Values tuned for PSP’s typical perspective and screen mapping.
    vzero.q  c500
    vzero.q  c510
    vzero.q  c520
    vzero.q  c530

    li	a0,	0x3f9b8c00          ; ≈1.213  (proj scale terms)
    mtv	a0, s500

    li	a0, 0x40093eff          ; ≈2.146
    mtv	a0, s511

    li	a0, 0xbf800000          ; -1.0
    mtv	a0, s522

    li	a0, 0xbf800000          ; -1.0
    mtv	a0, s532

    li	a0, 0xc2700000          ; -60.0
    mtv	a0, s523

    ; proj * view * pos
    vtfm4.q r601, M500, r600

    ; perspective divide
    vdiv.s s602, s601, s631
    vdiv.s s612, s611, s631
    vdiv.s s622, s621, s631

    ; map NDC [-1..1] to pixels (0..W/H)
    li	a0, 0x43f00000          ; 480.0f
    mtv	a0, s600
    li	a0, 0x43880000          ; 272.0f
    mtv	a0, s610
    li	a0, 0x3f000000          ; 0.5f
    mtv	a0, s620

    vadd.s s602, s602, s630     ; (x+1)
    vmul.s s602, s602, s620     ; *0.5
    vmul.s s602, s602, s600     ; *480 → pixel X

    vsub.s s612, s630, s612     ; (1 - y)
    vmul.s s612, s612, s620     ; *0.5
    vmul.s s612, s612, s610     ; *272 → pixel Y

    ; Convert to integers and return in a1/a2
    vf2iz.p     r602, r602, 0
    mfv         a1, s602
    mfv         a2, s612
    jr          ra
    nop

; -----------------------------------------------------------------------------
; clamp_initial_pos
;  • Ensures x∈[X_MIN..X_MAX], y∈[Y_MIN..Y_MAX] for the current slot (s0).
;  • Should be called RIGHT AFTER we finish computing initial spawn x/y
;    (noise + FIX), so that later animation doesn’t fight the clamp.
; -----------------------------------------------------------------------------
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

; -----------------------------------------------------------------------------
; Tail palettes (3 items per base color; TAIL_FRAMES must match list length)
; -----------------------------------------------------------------------------
white_palette:
    .byte   0x00, 0x2A, 0x09, 0x0A

yellow_palette:
    .byte   0x12, 0x3A, 0x2C, 0x0C

red_palette:
    .byte   0x13, 0x20, 0x0D, 0xC2

; -----------------------------------------------------------------------------
; printf format (kept separate to make it trivial to try "%03d", "%4d", etc.)
; -----------------------------------------------------------------------------
fmt:
    .asciiz     "%d"
    .align      4

; -----------------------------------------------------------------------------
; printdata – slot array starts here. Runtime writes (add/check_ret) will
; address this as a byte buffer, each slot is 8 bytes as described on top.
; -----------------------------------------------------------------------------
printdata:

.close
