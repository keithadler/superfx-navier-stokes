; game.s -- PAPER GRAB: title = Super FX Navier-Stokes blowup demo, PRESS START,
; then a side-scrolling beat-em-up: an AI billionaire punches mathematician nerds
; and steals their papers. Build: make DEMO=game

.p816
.smart
.include "ns.inc"                ; GSU_* symbols from gsuasm.py
.import __RAMCODE_LOAD__, __RAMCODE_RUN__, __RAMCODE_SIZE__

INIDISP  = $2100
OBSEL    = $2101
BGMODE   = $2105
MOSAIC   = $2106
BG1SC    = $2107
BG3SC    = $2109
BG12NBA  = $210B
BG34NBA  = $210C
BG1HOFS  = $210D
BG1VOFS  = $210E
BG3HOFS  = $2111
BG3VOFS  = $2112
VMAIN    = $2115
VMADD    = $2116
VMDATAL  = $2118
VMDATAH  = $2119
VMDATA   = $2118
CGADD    = $2121
CGDATA   = $2122
TM       = $212C
TS       = $212D
CGWSEL   = $2130
CGADSUB  = $2131
COLDATA  = $2132
SETINI   = $2133
NMITIMEN = $4200
WRIO     = $4201
MDMAEN   = $420B
HDMAEN   = $420C
MEMSEL   = $420D
HVBJOY   = $4212
DMAP0    = $4300
BBAD0    = $4301
A1T0L    = $4302
A1B0     = $4304
DAS0L    = $4305
OAMADD   = $2102
OAMDATA  = $2104
JOY1L    = $4218
BGCHR    = $5000                ; BG1 tiles for the level (BG12NBA = 5)
SPRCHR   = $4000                ; sprite tiles (OBSEL name base 2)

; sprite frames (OAM tile numbers, sheet layout from tools/sprites.py)
TILE_P_IDLE  = 0
TILE_P_WALK1 = 4
TILE_P_WALK2 = 8
TILE_P_PUNCH = 12
TILE_N_IDLE  = 64
TILE_N_WALK1 = 68
TILE_N_WALK2 = 72
TILE_N_PUNCH = 76
TILE_N_HIT   = 128
TILE_PAPER   = 136
TILE_STAR    = 138
ATTR_PLAYER  = $30              ; priority 3, palette 0
ATTR_NERD    = $32              ; palette 1
ATTR_ITEM    = $34              ; palette 2
HIDE_Y       = 224

MAX_ENEMIES  = 6
MAX_PAPERS   = 6
E_SIZE       = 16
E_ACT   = 0
E_X     = 1
E_Y     = 3
E_FACE  = 4
E_STATE = 5
E_TIMER = 6
E_HP    = 7
E_ANIM  = 8
E_COOL  = 9
P_SIZE  = 8
P_ACT   = 0
P_X     = 1
P_Y     = 3
FLOOR_TOP = 120
FLOOR_BOT = 188
PAPERS_TO_WIN = 12
PLAYER_HP = 10

GSU_R15  = $301E
SFR      = $3030
PBR      = $3034
CFGR     = $3037
SCBR     = $3038
CLSR     = $3039
SCMR     = $303A

SCMR_OFF = $09
SCMR_ON  = $19

TEXTMAP  = $0000
CUBEMAP  = $0400
FONTCHR  = $1000
CUBECHR  = $2000
CUBE_COL = 8
CUBE_ROW = 9

FXRAM    = $700000
FX_FB    = FXRAM + $0000
FX_SIN   = FXRAM + $2000
FX_ATAB  = FXRAM + $2200
FX_BTAB  = FXRAM + $2400
FX_GTAB  = FXRAM + $2600
FX_GPTAB = FXRAM + $2800
FX_OMTAB = FXRAM + $2A00
FX_AMP   = FXRAM + $2C00
FX_PARAM = FXRAM + $2D00        ; scale_r, scale_z, omf, frame, seed, spawn, pulse_cd, frames
FX_PART  = FXRAM + $3000
FX_PULSE = FXRAM + $3500

.segment "ZEROPAGE"
num:        .res 2
tmp:        .res 2
frame:      .res 2
text_attr:  .res 1
joy:        .res 2
joy_prev:   .res 2
joy_press:  .res 2
cam_x:      .res 2
rng:        .res 2
px:         .res 2
py:         .res 1
pface:      .res 1
pstate:     .res 1
ptimer:     .res 1
panim:      .res 1
phealth:        .res 1
pinv:       .res 1
papers:     .res 1
dx:         .res 2
dy:         .res 2
s_x:        .res 2
s_y:        .res 1
s_tile:     .res 1
s_attr:     .res 1
s_size:     .res 1
s_idx:      .res 1
spawn_t:    .res 1
ecount:     .res 1
star_t:     .res 1
star_x:     .res 2
star_y:     .res 1
blink:      .res 1
eptr:       .res 2

.segment "BSS"
oam_lo:     .res 512
oam_hi:     .res 32
enemies:    .res MAX_ENEMIES * E_SIZE
papers_t:   .res MAX_PAPERS * P_SIZE

.segment "CODE"

.macro locate row, col
    rep #$20
    lda #TEXTMAP + (row) * 32 + (col)
    sta VMADD
    sep #$20
.endmacro

.macro puts str
    .local msg
    .pushseg
    .segment "RODATA"
msg: .byte str, 0
    .popseg
    ldx #msg
    jsr print_str
.endmacro

.macro copy_fx src, dst, len
    .local l
    ldx #0
l:  lda f:src, x
    sta f:dst, x
    inx
    cpx #len
    bne l
.endmacro

.macro dma_fb src, vram, len
    lda #$80
    sta VMAIN
    rep #$20
    lda #vram
    sta VMADD
    lda #.loword(src)
    sta A1T0L
    lda #len
    sta DAS0L
    sep #$20
    lda #$01
    sta DMAP0
    lda #$18
    sta BBAD0
    lda #.bankbyte(src)
    sta A1B0
    lda #$01
    sta MDMAEN
.endmacro

.macro setcol idx, bgr
    lda #idx
    sta CGADD
    lda #<(bgr)
    sta CGDATA
    lda #>(bgr)
    sta CGDATA
.endmacro

.a8
.i16

print_str:
@l: lda a:0, x
    beq @d
    sta VMDATAL
    lda text_attr
    sta VMDATAH
    inx
    bra @l
@d: rts

; X = offset into ns_text of a 30-char string; leaves X past it
print_30:
    ldy #30
@l: lda f:ns_text, x
    sta VMDATAL
    lda text_attr
    sta VMDATAH
    inx
    dey
    bne @l
    rts

print_hex8:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr @nib
    pla
@nib:
    rep #$20
    .a16
    and #$000F
    tay
    sep #$20
    .a8
    lda hexchars, y
    sta VMDATAL
    lda text_attr
    sta VMDATAH
    rts
hexchars: .byte "0123456789ABCDEF"

wait_vblank:
@a: lda HVBJOY
    bmi @a
@b: lda HVBJOY
    bpl @b
    rts

; Copy this frame's parameters (3 words + frame index) to the GSU.
frame_params:
    rep #$20
    .a16
    lda frame
    asl
    adc frame               ; *3
    asl                     ; *6 bytes
    tax
    lda f:ns_frames, x
    sta f:FX_PARAM
    lda f:ns_frames+2, x
    sta f:FX_PARAM+2
    lda f:ns_frames+4, x
    sta f:FX_PARAM+4
    lda frame
    sta f:FX_PARAM+6
    sep #$20
    .a8
    rts

reset:
    sei
    clc
    xce
    rep #$38
    .a16
    .i16
    ldx #$1FFF
    txs
    lda #$0000
    tcd
    sep #$20
    .a8
    phk
    plb

    lda #$80
    sta INIDISP
    stz OBSEL
    stz BGMODE
    stz MOSAIC
    stz BG1SC
    stz BG3SC
    stz BG12NBA
    stz BG34NBA
    stz BG1HOFS
    stz BG1HOFS
    stz BG1VOFS
    stz BG1VOFS
    stz BG3HOFS
    stz BG3HOFS
    stz BG3VOFS
    stz BG3VOFS
    stz TM
    stz TS
    lda #$30
    sta CGWSEL
    stz CGADSUB
    lda #$E0
    sta COLDATA
    stz SETINI
    stz NMITIMEN
    lda #$FF
    sta WRIO
    stz MDMAEN
    stz HDMAEN
    stz MEMSEL

    lda #$80
    sta CFGR
    lda #$01
    sta CLSR
    stz SCBR
    lda #SCMR_OFF
    sta SCMR
    lda #$01
    sta PBR                 ; GSU code lives in ROM bank 1

    ; ---- palette ----
    setcol 0,  (10 << 10) | (2 << 5) | 3        ; backdrop
    setcol 1,  (25 << 10) | (25 << 5) | 25      ; text
    setcol 2,  (14 << 10) | (9 << 5) | 9        ; axis / core circle
    setcol 3,  (28 << 10) | (31 << 5) | 15      ; core particles
    setcol 4,  (25 << 10) | (15 << 5) | 9       ; outer particles
    setcol 5,  (7 << 10) | (21 << 5) | 31       ; pulse family +
    setcol 6,  (27 << 10) | (11 << 5) | 30      ; pulse family -
    setcol 9,  (0 << 10) | (31 << 5) | 31       ; title (BG3 palette 2, colour 1)

    ; ---- font ----
    lda #$80
    sta VMAIN
    rep #$20
    .a16
    lda #FONTCHR
    sta VMADD
    ldx #0
@font:
    lda font, x
    sta VMDATA
    inx
    inx
    cpx #font_end - font
    bne @font

    lda #TEXTMAP
    sta VMADD
    lda #$0000
    ldx #1024
@clr:
    sta VMDATA
    dex
    bne @clr

    lda #CUBECHR + 256 * 16
    sta VMADD
    lda #$0000
    ldx #16
@clr3:
    sta VMDATA
    dex
    bne @clr3
    sep #$20
    .a8

    ldx #0
@rc: lda __RAMCODE_LOAD__, x
    sta __RAMCODE_RUN__, x
    inx
    cpx #__RAMCODE_SIZE__
    bne @rc

    ; ---- sprite + level graphics into VRAM ----
    lda #$80
    sta VMAIN
    rep #$20
    .a16
    lda #SPRCHR
    sta VMADD
    ldx #0
@spr:
    lda f:sprite_tiles, x
    sta VMDATA
    inx
    inx
    cpx #sprite_tiles_end - sprite_tiles
    bne @spr
    lda #BGCHR
    sta VMADD
    ldx #0
@bgt:
    lda f:bg_tiles, x
    sta VMDATA
    inx
    inx
    cpx #16 * 32
    bne @bgt
    sep #$20
    .a8
    ; palettes: BG palette 1 (CGRAM 16), sprite palettes 0-2 (CGRAM 128..175)
    lda #16
    sta CGADD
    ldx #0
@bgp:
    lda f:bg_pal, x
    sta CGDATA
    inx
    cpx #32
    bne @bgp
    lda #128
    sta CGADD
    ldx #0
@spp:
    lda f:sprite_pals, x
    sta CGDATA
    inx
    cpx #96
    bne @spp
    lda #$62                ; OBJ 16x16 / 32x32, name base $4000
    sta OBSEL
    lda #$01
    sta NMITIMEN            ; auto-joypad read, no NMI

    ; ---- tables and state into cartridge RAM ----
    copy_fx ns_sin,    FX_SIN,   512
    copy_fx ns_atab,   FX_ATAB,  512
    copy_fx ns_btab,   FX_BTAB,  512
    copy_fx ns_gtab,   FX_GTAB,  512
    copy_fx ns_gptab,  FX_GPTAB, 512
    copy_fx ns_omtab,  FX_OMTAB, 512
    copy_fx ns_amptab, FX_AMP,   128
    copy_fx ns_particles, FX_PART, NS_NPART * 6
    ldx #0
    lda #0
@zp: sta f:FX_PARAM, x
    inx
    cpx #$40
    bne @zp
    ldx #0
    lda #$FF                ; pulse slots inactive (age = $FFFF)
@zq: sta f:FX_PULSE, x
    inx
    cpx #48
    bne @zq
    rep #$20
    .a16
    lda #$1234
    sta f:FX_PARAM+8        ; seed
    lda #1
    sta f:FX_PARAM+12       ; pulse countdown
    stz frame
    sep #$20
    .a8

    ; ---- static text ----
    lda #$28                ; priority, palette 2
    sta text_attr
    locate 1, 0
    puts "NAVIER-STOKES FINITE-TIME BLOWUP"
    lda #$20
    sta text_attr
    locate 2, 1
    puts "OPENAI 2026  SUPER FX 2 RENDER"
    locate 3, 1
    puts "SELF-SIMILAR CORE, LOG TIME"
    locate 26, 0
    puts "CYAN=CORE BLUE=OUTER RING=PULSE"

title_setup:
    lda #$80
    sta INIDISP
    lda #$05
    sta TM                  ; BG1 + BG3, no sprites on the title
    lda #(CUBEMAP >> 10) << 2
    sta BG1SC               ; 32x32 framebuffer map
    lda #CUBECHR >> 12
    sta BG12NBA
    stz BG1HOFS
    stz BG1HOFS
    jsr fb_tilemap
    jsr clear_text
    lda #$28
    sta text_attr
    locate 1, 0
    puts "NAVIER-STOKES FINITE-TIME BLOWUP"
    lda #$20
    sta text_attr
    locate 2, 1
    puts "OPENAI 2026  SUPER FX 2 RENDER"
    locate 3, 1
    puts "SELF-SIMILAR CORE, LOG TIME"
    locate 26, 0
    puts "CYAN=CORE BLUE=OUTER RING=PULSE"
    rep #$20
    .a16
    stz frame
    sep #$20
    .a8

    jsr frame_params
    jsl gsu_run
    dma_fb FX_FB,        CUBECHR,        4096
    dma_fb FX_FB + 4096, CUBECHR + 2048, 4096

    lda #$09
    sta BGMODE
    lda #(TEXTMAP >> 10) << 2
    sta BG3SC
    lda #FONTCHR >> 12
    sta BG34NBA
    lda #$0F
    sta INIDISP

main_loop:
    jsr wait_vblank
    dma_fb FX_FB, CUBECHR, 4096
    ; readout lines for this frame: ns_text + frame*60
    rep #$20
    .a16
    lda frame
    asl
    asl
    asl
    asl
    asl
    asl                     ; *64
    sec
    sbc frame
    sbc frame
    sbc frame
    sbc frame               ; *60
    tax
    sep #$20
    .a8
    phx
    locate 5, 1
    plx
    jsr print_30
    phx
    locate 6, 1
    plx
    jsr print_30
    lda frame
    and #$10
    bne t_blink_on
    locate 23, 10
    puts "           "
    bra t_blink_done
t_blink_on:
    lda #$28
    sta text_attr
    locate 23, 10
    puts "PRESS START"
    lda #$20
    sta text_attr
t_blink_done:
    jsr read_joy
    lda joy_press+1
    and #$10                ; Start
    beq t_nostart
    jmp game_setup
t_nostart:

    jsr wait_vblank
    dma_fb FX_FB + 4096, CUBECHR + 2048, 4096

    rep #$20
    .a16
    inc frame
    lda frame
    cmp #NS_FRAMES
    bne @ok
    stz frame
@ok:
    sep #$20
    .a8
    jsr frame_params
    jsl gsu_run
    jmp main_loop

; ============================================================================
; helpers shared by title and game
; ============================================================================

; BG1 32x32 map for the Super FX framebuffer (column-major tiles, 256 = blank)
fb_tilemap:
    rep #$20
    .a16
    lda #CUBEMAP
    sta VMADD
    lda #256
    ldx #1024
@clr2:
    sta VMDATA
    dex
    bne @clr2
    ldy #0
@row:
    tya
    asl
    asl
    asl
    asl
    asl
    clc
    adc #CUBEMAP + CUBE_ROW * 32 + CUBE_COL
    sta VMADD
    tya
    ldx #16
@col:
    sta VMDATA
    clc
    adc #16
    dex
    bne @col
    iny
    cpy #16
    bne @row
    sep #$20
    .a8
    rts

clear_text:
    rep #$20
    .a16
    lda #TEXTMAP
    sta VMADD
    lda #$0000
    ldx #1024
@c: sta VMDATA
    dex
    bne @c
    sep #$20
    .a8
    rts

; joypad: joy = current, joy_press = newly pressed (call right after wait_vblank)
read_joy:
@j: lda HVBJOY
    and #$01
    bne @j
    rep #$20
    .a16
    lda joy
    sta joy_prev
    lda JOY1L
    sta joy
    eor joy_prev
    and joy
    sta joy_press
    sep #$20
    .a8
    rts

; rng: 16-bit LCG, result in A (low byte)
random:
    rep #$20
    .a16
    lda rng
    asl
    asl
    clc
    adc rng
    adc #$3619
    sta rng
    sep #$20
    .a8
    lda rng+1
    rts

; ============================================================================
; game setup
; ============================================================================
game_setup:
    lda #$80
    sta INIDISP
    lda #$15
    sta TM                  ; OBJ + BG1 + BG3
    lda #((CUBEMAP >> 10) << 2) | 1
    sta BG1SC               ; 64x32 map
    lda #BGCHR >> 12
    sta BG12NBA
    ; level map -> VRAM
    rep #$20
    .a16
    lda #CUBEMAP
    sta VMADD
    ldx #0
@map:
    lda f:bg_map, x
    sta VMDATA
    inx
    inx
    cpx #64 * 32 * 2
    bne @map
    stz cam_x
    lda #120
    sta px
    stz frame
    sep #$20
    .a8
    jsr clear_text
    lda #$28
    sta text_attr
    locate 27, 0
    puts "PAPER GRAB  B/Y=PUNCH  GET 12 PAPERS"
    lda #$20
    sta text_attr
    ; player
    lda #150
    sta py
    stz pface
    stz pstate
    stz ptimer
    stz panim
    lda #PLAYER_HP
    sta phealth
    stz pinv
    stz papers
    stz star_t
    lda #40
    sta spawn_t
    stz ecount
    ; enemies + papers off
    ldx #0
@ce: stz enemies, x
    inx
    cpx #MAX_ENEMIES * E_SIZE
    bne @ce
    ldx #0
@cp: stz papers_t, x
    inx
    cpx #MAX_PAPERS * P_SIZE
    bne @cp
    jsr hud
    jsr build_oam
    jsr wait_vblank
    jsr oam_dma
    lda #$0F
    sta INIDISP

; ============================================================================
; game loop
; ============================================================================
game_loop:
    jsr wait_vblank
    jsr oam_dma
    lda cam_x
    sta BG1HOFS
    lda cam_x+1
    sta BG1HOFS
    jsr hud
    jsr read_joy
    inc frame
    jsr update_player
    jsr update_enemies
    jsr update_papers
    jsr spawner
    jsr build_oam
    lda phealth
    beq g_lose
    lda papers
    cmp #PAPERS_TO_WIN
    bcs g_win
    jmp game_loop
g_lose:
    lda #$28
    sta text_attr
    locate 12, 11
    puts "GAME OVER"
    locate 13, 5
    puts "THE NERDS KEPT THEIR PAPERS"
    bra g_hold
g_win:
    lda #$28
    sta text_attr
    locate 12, 5
    puts "TRAINING RUN COMPLETE!"
    locate 13, 4
    puts "12 PAPERS INGESTED. NO CREDIT."
g_hold:
    ldy #200
g_hold_l: jsr wait_vblank
    jsr oam_dma
    dey
    bne g_hold_l
    jmp title_setup

; ---- HUD line (row 0): PAPERS nn/12   HP ########## ----
hud:
    locate 0, 1
    puts "PAPERS "
    lda papers
    jsr print_dec8
    puts "/12  HP "
    ldx #0
@bar:
    txa
    cmp phealth
    bcs @dark
    lda #'#'
    bra @w
@dark:
    lda #'.'
@w: sta VMDATAL
    lda text_attr
    sta VMDATAH
    inx
    cpx #PLAYER_HP
    bne @bar
    rts

; A = 0..99 -> two digits
print_dec8:
    ldx #0
@t: cmp #10
    bcc @d
    sbc #10
    inx
    bra @t
@d: pha
    txa
    clc
    adc #'0'
    sta VMDATAL
    lda text_attr
    sta VMDATAH
    pla
    clc
    adc #'0'
    sta VMDATAL
    lda text_attr
    sta VMDATAH
    rts

oam_dma:
    stz OAMADD
    stz OAMADD+1
    rep #$20
    .a16
    lda #oam_lo
    sta A1T0L
    lda #544
    sta DAS0L
    sep #$20
    .a8
    stz DMAP0               ; 1 register, A->B, increment
    lda #$04
    sta BBAD0
    lda #$7E
    sta A1B0
    lda #$01
    sta MDMAEN
    rts

; ---- player ----
update_player:
    lda pinv
    beq @noinv
    dec pinv
@noinv:
    lda pstate
    beq @free
    dec ptimer
    bne @busy
    stz pstate
    bra @free
@busy:
    cmp #1
    bne @done
    lda ptimer
    cmp #8
    bne @done
    jsr player_hit_check
@done:
    rts
@free:
    ; punch?
    lda joy_press+1
    and #$C0                ; B or Y
    beq @move
    lda #1
    sta pstate
    lda #14
    sta ptimer
    rts
@move:
    lda joy+1
    and #$01                ; right
    beq @notright
    stz pface
    rep #$20
    .a16
    inc px
    inc px
    sep #$20
    .a8
    inc panim
@notright:
    lda joy+1
    and #$02                ; left
    beq @notleft
    lda #1
    sta pface
    rep #$20
    .a16
    dec px
    dec px
    lda px
    cmp cam_x
    bcs @lok
    lda cam_x
    sta px
@lok:
    sep #$20
    .a8
    inc panim
@notleft:
    lda joy+1
    and #$08                ; up
    beq @notup
    lda py
    cmp #FLOOR_TOP
    beq @notup
    dec py
    inc panim
@notup:
    lda joy+1
    and #$04                ; down
    beq @notdown
    lda py
    cmp #FLOOR_BOT
    beq @notdown
    inc py
    inc panim
@notdown:
    ; camera follows
    rep #$20
    .a16
    lda px
    sec
    sbc cam_x
    cmp #112
    bcc @cam
    lda px
    sec
    sbc #112
    sta cam_x
@cam:
    sep #$20
    .a8
    rts

; player punch connects? (facing-aware box in front of the player)
player_hit_check:
    ldx #0
@e: lda enemies + E_ACT, x
    beq @next
    lda enemies + E_STATE, x
    cmp #2
    beq @next               ; already reeling
    jsr enemy_delta         ; dx = ex - px, dy = ey - py
    lda pface
    bne @left
    rep #$20
    .a16
    lda dx
    cmp #12
    bcc @nx
    cmp #52
    bcs @nx
    bra @yok
@left:
    rep #$20
    .a16
    lda dx
    cmp #$FFFF - 44 + 1     ; dx >= -44
    bcc @nx
    cmp #$FFFF - 4 + 1      ; dx <= -4  (unsigned: -44..-4 map high)
    bcs @nx
@yok:
    lda dy
    clc
    adc #14
    cmp #29
    bcs @nx
    sep #$20
    .a8
    ; hit!
    lda #2
    sta enemies + E_STATE, x
    lda #16
    sta enemies + E_TIMER, x
    dec enemies + E_HP, x
    lda pface
    eor #1
    sta enemies + E_FACE, x ; knocked away from the player
    ; star effect
    lda #8
    sta star_t
    rep #$20
    .a16
    lda enemies + E_X, x
    clc
    adc #8
    sta star_x
    sep #$20
    .a8
    lda enemies + E_Y, x
    clc
    adc #6
    sta star_y
    bra @next
@nx:
    sep #$20
    .a8
@next:
    rep #$20
    txa
    clc
    adc #E_SIZE
    tax
    sep #$20
    cpx #MAX_ENEMIES * E_SIZE
    bne @e
    rts

; dx = enemy x - px, dy = enemy y - py (16-bit signed), X = enemy offset
enemy_delta:
    rep #$20
    .a16
    lda py
    and #$00FF
    sta num
    lda enemies + E_X, x
    sec
    sbc px
    sta dx
    lda enemies + E_Y, x
    and #$00FF
    sec
    sbc num
    sta dy
    sep #$20
    .a8
    rts

; ---- enemies ----
update_enemies:
    stz ecount
    ldx #0
@e: lda enemies + E_ACT, x
    bne :+
    brl @next
:
    inc ecount
    lda enemies + E_COOL, x
    beq @cool0
    dec enemies + E_COOL, x
@cool0:
    lda enemies + E_STATE, x
    bne :+
    brl @walk
:
    cmp #1
    beq @punching
    ; reeling: knockback, then either die or recover
    lda enemies + E_FACE, x
    bne @kb_left
    rep #$20
    .a16
    lda enemies + E_X, x
    clc
    adc #3
    sta enemies + E_X, x
    sep #$20
    .a8
    bra @kb_done
@kb_left:
    rep #$20
    .a16
    lda enemies + E_X, x
    sec
    sbc #3
    sta enemies + E_X, x
    sep #$20
    .a8
@kb_done:
    dec enemies + E_TIMER, x
    beq :+
    brl @next
:
    lda enemies + E_HP, x
    beq @die
    stz enemies + E_STATE, x
    lda #30
    sta enemies + E_COOL, x
    brl @next
@die:
    stz enemies + E_ACT, x
    jsr drop_paper
    brl @next
@punching:
    dec enemies + E_TIMER, x
    beq @punch_end
    lda enemies + E_TIMER, x
    cmp #10
    beq :+
    brl @next
:
    ; does it land?
    jsr enemy_delta
    rep #$20
    .a16
    lda dx
    clc
    adc #40
    cmp #81                 ; |dx| <= 40
    bcs @miss
    lda dy
    clc
    adc #12
    cmp #25
    bcs @miss
    sep #$20
    .a8
    lda pinv
    beq :+
    brl @next
:
    lda phealth
    bne :+
    brl @next
:
    dec phealth
    lda #60
    sta pinv
    lda #2
    sta pstate
    lda #10
    sta ptimer
    brl @next
@miss:
    sep #$20
    .a8
    brl @next
@punch_end:
    stz enemies + E_STATE, x
    jsr random
    and #$3F
    clc
    adc #80
    sta enemies + E_COOL, x
    brl @next
@walk:
    jsr enemy_delta
    ; face the player
    lda dx+1
    bmi @face_r             ; enemy left of player -> faces right
    lda #1
    sta enemies + E_FACE, x
    bra @faced
@face_r:
    stz enemies + E_FACE, x
@faced:
    ; horizontal: keep (28 + slot*6) px from the player, on the facing side
    txa
    lsr
    lsr
    lsr
    lsr                     ; slot 0..5
    asl
    sta num
    asl
    adc num
    adc #28
    sta num                 ; standoff
    stz num+1
    rep #$20
    .a16
    lda dx
    bmi @onleft
    cmp num
    bcc @xok
    dec enemies + E_X, x
    bra @xok
@onleft:
    eor #$FFFF
    inc                     ; -dx
    cmp num
    bcc @xok
    inc enemies + E_X, x
@xok:
    sep #$20
    .a8
    inc enemies + E_ANIM, x
    ; vertical: close in on the player's lane
    lda dy+1
    bmi @up
    lda dy
    beq @vok
    dec enemies + E_Y, x
    bra @vok
@up:
    inc enemies + E_Y, x
@vok:
    ; attack when close and cooled down
    lda enemies + E_COOL, x
    beq :+
    brl @next
:
    rep #$20
    .a16
    lda dx
    clc
    adc #36
    cmp #73
    bcs @far
    lda dy
    clc
    adc #8
    cmp #17
    bcs @far
    sep #$20
    .a8
    lda #1
    sta enemies + E_STATE, x
    lda #22
    sta enemies + E_TIMER, x
    brl @next
@far:
    sep #$20
    .a8
@next:
    rep #$20
    txa
    clc
    adc #E_SIZE
    tax
    sep #$20
    cpx #MAX_ENEMIES * E_SIZE
    beq @out
    jmp @e
@out:
    rts

; enemy X drops a paper at its feet
drop_paper:
    ldy #0
@p: lda papers_t + P_ACT, y
    beq @free
    rep #$20
    tya
    clc
    adc #P_SIZE
    tay
    sep #$20
    cpy #MAX_PAPERS * P_SIZE
    bne @p
    rts
@free:
    lda #1
    sta papers_t + P_ACT, y
    rep #$20
    .a16
    lda enemies + E_X, x
    clc
    adc #8
    sta papers_t + P_X, y
    sep #$20
    .a8
    lda enemies + E_Y, x
    clc
    adc #16
    sta papers_t + P_Y, y
    rts

; ---- papers: pick up on overlap ----
update_papers:
    ldy #0
@p: lda papers_t + P_ACT, y
    beq @next
    rep #$20
    .a16
    lda papers_t + P_X, y
    sec
    sbc px
    clc
    adc #12                 ; paper centre vs player centre (px+16 .. )
    cmp #36
    bcs @nx
    sep #$20
    .a8
    lda papers_t + P_Y, y
    sec
    sbc py
    clc
    adc #4
    cmp #34
    bcs @next
    lda #0
    sta papers_t + P_ACT, y
    inc papers
    bra @next
@nx:
    sep #$20
    .a8
@next:
    rep #$20
    tya
    clc
    adc #P_SIZE
    tay
    sep #$20
    cpy #MAX_PAPERS * P_SIZE
    bne @p
    rts

; ---- spawner: a new nerd every ~75 frames while fewer than 4 are about ----
spawner:
    dec spawn_t
    bne @done
    lda #110
    sta spawn_t
    lda ecount
    cmp #3
    bcs @done
    ldx #0
@s: lda enemies + E_ACT, x
    beq @slot
    rep #$20
    txa
    clc
    adc #E_SIZE
    tax
    sep #$20
    cpx #MAX_ENEMIES * E_SIZE
    bne @s
@done:
    rts
@slot:
    lda #1
    sta enemies + E_ACT, x
    stz enemies + E_STATE, x
    lda #2
    sta enemies + E_HP, x
    lda #40
    sta enemies + E_COOL, x
    jsr random
    and #$3F
    clc
    adc #FLOOR_TOP + 4
    sta enemies + E_Y, x
    jsr random
    and #$01
    beq @from_right
    ; from the left edge (only if the camera has moved)
    rep #$20
    .a16
    lda cam_x
    beq @right16
    sec
    sbc #40
    sta enemies + E_X, x
    sep #$20
    .a8
    rts
@from_right:
    rep #$20
    .a16
@right16:
    lda cam_x
    clc
    adc #272
    sta enemies + E_X, x
    sep #$20
    .a8
    rts

; ---- OAM ----
; s_idx, s_x (16-bit screen x), s_y, s_tile, s_attr, s_size -> oam buffers
oam_set:
    rep #$20
    .a16
    lda s_idx
    and #$00FF
    asl
    asl
    tax
    sep #$20
    .a8
    lda s_x
    sta oam_lo, x
    lda s_y
    sta oam_lo+1, x
    lda s_tile
    sta oam_lo+2, x
    lda s_attr
    sta oam_lo+3, x
    ; high table bits: byte idx>>2, field (idx&3)*2 = size<<1 | x9
    rep #$20
    .a16
    lda s_idx
    and #$00FF
    lsr
    lsr
    tay
    sep #$20
    .a8
    lda s_idx
    and #$03
    asl
    sta tmp                 ; shift count
    lda s_size
    asl
    ora s_x+1
    and #$03
    sta tmp+1
@shl:
    lda tmp
    beq @sh0
    dec tmp
    asl tmp+1
    bra @shl
@sh0:
    lda tmp+1
    ora oam_hi, y
    sta oam_hi, y
    rts

; place sprite s_idx at world (X reg = 16-bit world x in A) -- helper computes screen x
; input: s_x = world x, others set. Hides when off screen.
oam_world:
    rep #$20
    .a16
    lda s_x
    sec
    sbc cam_x
    sta s_x
    cmp #256
    bcc @on
    cmp #$FFFF - 31         ; >= -32 ?
    bcs @on
    sep #$20
    .a8
    lda #HIDE_Y
    sta s_y
    stz s_x+1
    jmp oam_set
@on:
    sep #$20
    .a8
    jmp oam_set

build_oam:
    ; hide everything
    ldx #0
    lda #HIDE_Y
@h: sta oam_lo+1, x
    inx
    inx
    inx
    inx
    cpx #512
    bne @h
    ldx #0
@hh: stz oam_hi, x
    inx
    cpx #32
    bne @hh
    ; --- player (sprite 0) ---
    lda pinv
    and #$02
    bne @skip_player        ; flicker while invulnerable
    stz s_idx
    lda #1
    sta s_size
    rep #$20
    .a16
    lda px
    sta s_x
    sep #$20
    .a8
    lda py
    sta s_y
    lda pface
    beq @pf
    lda #ATTR_PLAYER | $40
    bra @pf2
@pf:lda #ATTR_PLAYER
@pf2:
    sta s_attr
    lda pstate
    cmp #1
    beq @ppunch
    lda joy+1
    and #$0F
    beq @pidle
    lda panim
    and #$08
    beq @pw1
    lda #TILE_P_WALK2
    bra @pt
@pw1:
    lda #TILE_P_WALK1
    bra @pt
@pidle:
    lda #TILE_P_IDLE
    bra @pt
@ppunch:
    lda #TILE_P_PUNCH
@pt:sta s_tile
    jsr oam_world
@skip_player:
    ; --- enemies (sprites 1..6) ---
    ldx #0
    lda #1
    sta s_idx
@e: lda enemies + E_ACT, x
    beq @enext
    lda #1
    sta s_size
    rep #$20
    .a16
    lda enemies + E_X, x
    sta s_x
    sep #$20
    .a8
    lda enemies + E_Y, x
    sta s_y
    lda enemies + E_FACE, x
    beq @ef
    lda #ATTR_NERD | $40
    bra @ef2
@ef:lda #ATTR_NERD
@ef2:
    sta s_attr
    lda enemies + E_STATE, x
    beq @ewalk
    cmp #1
    beq @epunch
    lda #TILE_N_HIT
    bra @et
@epunch:
    lda #TILE_N_PUNCH
    bra @et
@ewalk:
    lda enemies + E_ANIM, x
    and #$08
    beq @ew1
    lda #TILE_N_WALK2
    bra @et
@ew1:
    lda #TILE_N_WALK1
@et:sta s_tile
    phx
    jsr oam_world
    plx
@enext:
    inc s_idx
    rep #$20
    txa
    clc
    adc #E_SIZE
    tax
    sep #$20
    cpx #MAX_ENEMIES * E_SIZE
    bne @e
    ; --- papers (sprites 7..12) ---
    ldx #0
    lda #7
    sta s_idx
@p: lda papers_t + P_ACT, x
    beq @pnext
    stz s_size
    rep #$20
    .a16
    lda papers_t + P_X, x
    sta s_x
    sep #$20
    .a8
    lda papers_t + P_Y, x
    sta s_y
    lda #ATTR_ITEM
    sta s_attr
    lda #TILE_PAPER
    sta s_tile
    phx
    jsr oam_world
    plx
@pnext:
    inc s_idx
    rep #$20
    txa
    clc
    adc #P_SIZE
    tax
    sep #$20
    cpx #MAX_PAPERS * P_SIZE
    bne @p
    ; --- hit star (sprite 13) ---
    lda star_t
    beq @nostar
    dec star_t
    lda #13
    sta s_idx
    stz s_size
    rep #$20
    .a16
    lda star_x
    sta s_x
    sep #$20
    .a8
    lda star_y
    sta s_y
    lda #ATTR_ITEM
    sta s_attr
    lda #TILE_STAR
    sta s_tile
    jsr oam_world
@nostar:
    rts

stub:
    rti

.segment "RAMCODE"
gsu_run:
    lda #SCMR_ON
    sta SCMR
    ldx #GSU_main
    stx GSU_R15
@w: lda SFR
    and #$20
    bne @w
    lda #SCMR_OFF
    sta SCMR
    rtl

.segment "RODATA"
font:
    .include "font.inc"
font_end:

.segment "DATA2"
    .include "ns_tables.inc"

.segment "DATA3"
    .include "sprites.inc"
    .include "bg.inc"

.segment "GSUCODE"
    .incbin "ns.bin"

.segment "HEADER"
    .byte "00"
    .byte "SNES"
    .res 7, $00
    .byte $07
    .byte $00
    .byte $00
    .byte "PAPER GRAB           "
    .byte $20
    .byte $1A
    .byte $0B
    .byte $07
    .byte $01
    .byte $33
    .byte $00
    .word $FFFF
    .word $0000

.segment "VECTORS"
    .word $0000, $0000
    .word stub, stub, stub, stub
    .word $0000
    .word stub
    .word $0000, $0000
    .word stub
    .word $0000
    .word stub, stub
    .word reset
    .word stub
