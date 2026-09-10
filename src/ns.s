; ns.s -- SNES side: Navier-Stokes finite-time blowup on the Super FX 2.
; 256x192 16-colour framebuffer, double buffered in cart RAM, copied to VRAM in
; five VBlank chunks (12 fps, the Star Fox approach). Build: make DEMO=ns

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

GSU_R15  = $301E
SFR      = $3030
PBR      = $3034
CFGR     = $3037
SCBR     = $3038
CLSR     = $3039
SCMR     = $303A

SCMR_OFF = $29                  ; 16 colours, 192 lines, ROM/RAM to the SNES
SCMR_ON  = $39                  ; same, ROM+RAM to the GSU

TEXTMAP  = $0000
FBMAP    = $0400
FONTCHR  = $1000
FBCHR    = $2000                ; 768 tiles = $3000 words -> $2000..$4FFF
BLANK    = 768                  ; tile past the framebuffer, zeroed

FXRAM    = $700000
FX_FB0   = FXRAM + $0000
FX_FB1   = FXRAM + $6000
FX_SIN   = FXRAM + $C000
FX_ATAB  = FXRAM + $C200
FX_BTAB  = FXRAM + $C400
FX_GTAB  = FXRAM + $C600
FX_GPTAB = FXRAM + $C800
FX_OMTAB = FXRAM + $CA00
FX_AMP   = FXRAM + $CC00
FX_RECIP2= FXRAM + $CD00
FX_RECIP8= FXRAM + $CF00
FX_SHADE = FXRAM + $D100
FX_TUBE  = FXRAM + $D200
FX_PARAM = FXRAM + $D300        ; scale_r, scale_z, omf, frame, seed, spawn, pulse_cd, frames, cam, spin, fbase
FX_PART  = FXRAM + $D400
FX_PULSE = FXRAM + $DA00

CHUNKS   = 5                    ; 24 KB frame in five VBlank transfers (~4.9 KB each)

.segment "ZEROPAGE"
num:        .res 2
tmp:        .res 2
frame:      .res 2
text_attr:  .res 1
draw_buf:   .res 1              ; 0 or 1: buffer the GSU draws next
cam:        .res 2

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

; DMA `len` bytes from cart RAM (24-bit address in A:X? no: src = constant) to VRAM word `vram`
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

; X = offset into ns_text (bank 2) of a 30-char string; leaves X past it
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

wait_vblank:
@a: lda HVBJOY
    bmi @a
@b: lda HVBJOY
    bpl @b
    rts

; Frame parameters for the GSU: scale_r, scale_z, omf, frame, cam, fbase; SCBR.
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
    lda cam
    clc
    adc #96                 ; orbit: 1/683 turn per frame
    sta cam
    sta f:FX_PARAM+16
    sep #$20
    .a8
    lda draw_buf
    beq @b0
    rep #$20
    .a16
    lda #$6000
    sta f:FX_PARAM+20
    sep #$20
    .a8
    lda #$18                ; SCBR = $6000 / 1024
    sta SCBR
    rts
@b0:
    rep #$20
    .a16
    lda #0
    sta f:FX_PARAM+20
    sep #$20
    .a8
    stz SCBR
    rts

; DMA chunk Y (0..4) of the display buffer (the one the GSU is not drawing)
chunk_off:  .word 0, 4928, 9856, 14784, 19712
chunk_len:  .word 4928, 4928, 4928, 4928, 4864
dma_chunk:
    lda #$80
    sta VMAIN
    rep #$20
    .a16
    tya
    asl
    tax
    lda chunk_off, x
    sta num
    lsr
    clc
    adc #FBCHR
    sta VMADD               ; VRAM word address
    lda chunk_len, x
    sta DAS0L
    sep #$20
    .a8
    lda num
    sta A1T0L
    lda draw_buf
    bne @d0                 ; drawing buffer 1 -> display buffer 0
    lda num+1
    clc
    adc #$60                ; drawing buffer 0 -> display buffer 1 ($6000)
    bra @d1
@d0:
    lda num+1
@d1:
    sta A1T0L+1
    lda #$01
    sta DMAP0
    lda #$18
    sta BBAD0
    lda #$70
    sta A1B0
    lda #$01
    sta MDMAEN
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

    ; ---- palette: BG1 palette 0 ----
    setcol 0,  (9 << 10) | (2 << 5) | 3         ; backdrop
    setcol 1,  (26 << 10) | (26 << 5) | 26      ; text
    setcol 2,  (12 << 10) | (8 << 5) | 3        ; tube shades 2..9 (dark -> bright teal)
    setcol 3,  (15 << 10) | (11 << 5) | 4
    setcol 4,  (18 << 10) | (14 << 5) | 5
    setcol 5,  (21 << 10) | (18 << 5) | 6
    setcol 6,  (24 << 10) | (22 << 5) | 8
    setcol 7,  (27 << 10) | (26 << 5) | 11
    setcol 8,  (29 << 10) | (29 << 5) | 15
    setcol 9,  (31 << 10) | (31 << 5) | 21
    setcol 10, (5 << 10) | (20 << 5) | 31       ; pulse family +
    setcol 11, (28 << 10) | (10 << 5) | 31      ; pulse family -
    setcol 12, (18 << 10) | (12 << 5) | 12      ; axis / core circle
    setcol 13, (31 << 10) | (31 << 5) | 31      ; core particles
    setcol 14, (28 << 10) | (16 << 5) | 8       ; outer particles
    setcol 15, (10 << 10) | (30 << 5) | 31      ; streamlines

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

    ; BG1 map: 32 columns x 24 rows of framebuffer tiles (column-major), rest blank
    lda #FBMAP
    sta VMADD
    lda #BLANK
    ldx #1024
@clr2:
    sta VMDATA
    dex
    bne @clr2
    lda #FBCHR + BLANK * 16
    sta VMADD
    lda #$0000
    ldx #16
@clr3:
    sta VMDATA
    dex
    bne @clr3
    ldy #0                  ; row
@row:
    tya
    asl
    asl
    asl
    asl
    asl
    clc
    adc #FBMAP
    sta VMADD
    tya                     ; tile = col * 24 + row
    ldx #32
@col:
    sta VMDATA
    clc
    adc #24
    dex
    bne @col
    iny
    cpy #24
    bne @row
    sep #$20
    .a8

    ldx #0
@rc: lda __RAMCODE_LOAD__, x
    sta __RAMCODE_RUN__, x
    inx
    cpx #__RAMCODE_SIZE__
    bne @rc

    ; ---- tables and state into cartridge RAM ----
    copy_fx ns_sin,    FX_SIN,   512
    copy_fx ns_atab,   FX_ATAB,  512
    copy_fx ns_btab,   FX_BTAB,  512
    copy_fx ns_gtab,   FX_GTAB,  512
    copy_fx ns_gptab,  FX_GPTAB, 512
    copy_fx ns_omtab,  FX_OMTAB, 512
    copy_fx ns_amptab, FX_AMP,   64
    copy_fx ns_recip2, FX_RECIP2, 512
    copy_fx ns_recip8, FX_RECIP8, 512
    copy_fx ns_shade,  FX_SHADE, 256
    copy_fx ns_tube,   FX_TUBE,  56
    copy_fx ns_particles, FX_PART, NS_NPART * 6
    ldx #0
    lda #0
@zp: sta f:FX_PARAM, x
    inx
    cpx #$40
    bne @zp
    ldx #0
    lda #0
@zq: sta f:FX_PULSE, x
    inx
    cpx #48
    bne @zq
    lda #32                 ; age 32 = inactive slot (the GSU compares signed)
    sta f:FX_PULSE + 10
    sta f:FX_PULSE + 22
    sta f:FX_PULSE + 34
    sta f:FX_PULSE + 46
    rep #$20
    .a16
    lda #$1234
    sta f:FX_PARAM+8        ; seed
    lda #1
    sta f:FX_PARAM+12       ; pulse countdown
    stz frame
    stz cam
    sep #$20
    .a8
    stz draw_buf

    ; ---- static text (rows 24-27, below the picture) ----
    lda #$28
    sta text_attr
    locate 24, 0
    puts "NAVIER-STOKES BLOWUP OPENAI 2026"
    lda #$20
    sta text_attr
    locate 27, 0
    puts "SWIRL ISOSURFACE  RINGS=PULSES"

    ; first frame into buffer 0, then show it
    jsr frame_params
    jsl gsu_run
    lda #1
    sta draw_buf
    ldy #0
@first:
    phy
    jsr dma_chunk
    ply
    iny
    cpy #CHUNKS
    bne @first
    jsr frame_params        ; GSU will draw buffer 1 next

    lda #$09
    sta BGMODE
    lda #(FBMAP >> 10) << 2
    sta BG1SC
    lda #(TEXTMAP >> 10) << 2
    sta BG3SC
    lda #FBCHR >> 12
    sta BG12NBA
    lda #FONTCHR >> 12
    sta BG34NBA
    lda #$05
    sta TM
    lda #$0F
    sta INIDISP

; ---- main loop: one GSU frame per four VBlanks ----
main_loop:
    ; VBlank 0: chunk 0, then the readouts, then the GSU draws the other buffer
    jsr wait_vblank
    ldy #0
    jsr dma_chunk
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
    locate 25, 1
    plx
    jsr print_30
    phx
    jsl gsu_run
    plx

    ; VBlank 1: chunk 1 + readout line 2
    jsr wait_vblank
    phx
    ldy #1
    jsr dma_chunk
    plx
    phx
    locate 26, 1
    plx
    jsr print_30

    ldy #2
@rest:
    phy
    jsr wait_vblank
    ply
    phy
    jsr dma_chunk
    ply
    iny
    cpy #CHUNKS
    bne @rest

    ; swap: the buffer just drawn becomes the display buffer
    lda draw_buf
    eor #1
    sta draw_buf
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
    jmp main_loop

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

.segment "GSUCODE"
    .incbin "ns.bin"

.segment "HEADER"
    .byte "00"
    .byte "SNES"
    .res 7, $00
    .byte $07
    .byte $00
    .byte $00
    .byte "NAVIER STOKES BLOWUP "
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
