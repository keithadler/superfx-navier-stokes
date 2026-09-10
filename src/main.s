; main.s -- SNES side of the Super FX dev cart.
; Probes the hardware, prints the cartridge/display specs on BG3, and runs the
; GSU program (src/cube.gsu) each cycle, DMAing its framebuffer to BG1.
; Build: make   (ca65 --cpu 65816, ld65 -C lorom.cfg, tools/fixsum.py)

.p816
.smart
.include "cube.inc"       ; GSU_* symbols from gsuasm.py
.import __RAMCODE_LOAD__, __RAMCODE_RUN__, __RAMCODE_SIZE__

; ---- PPU / CPU registers ----
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
STAT77   = $213E
STAT78   = $213F
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

; ---- Super FX registers (bank $00-$3F) ----
GSU_R15  = $301E
SFR      = $3030
PBR      = $3034
CFGR     = $3037
SCBR     = $3038
CLSR     = $3039
SCMR     = $303A
VCR      = $303B

SCMR_OFF = $09                  ; 16 colors, 128 lines, ROM/RAM to the SNES
SCMR_ON  = $19                  ; same, ROM+RAM handed to the GSU

; ---- VRAM map (word addresses) ----
TEXTMAP  = $0000                ; BG3 tilemap 32x32
CUBEMAP  = $0400                ; BG1 tilemap 32x32
FONTCHR  = $1000                ; 128 2bpp tiles
CUBECHR  = $2000                ; 8 KB framebuffer as 256 4bpp tiles

CUBE_COL = 8                    ; where the 16x16-tile framebuffer sits on screen
CUBE_ROW = 11

; ---- cartridge RAM (bank $70) ----
FXRAM    = $700000
FX_FB    = FXRAM + $0000
FX_SIN   = FXRAM + $2000
FX_RECIP = FXRAM + $2200
FX_VERTS = FXRAM + $2300
FX_EDGES = FXRAM + $2330
FX_ANG_A = FXRAM + $2380
FX_ANG_B = FXRAM + $2382
FX_FRAMES= FXRAM + $2384

BACKDROP = (10 << 10) | (2 << 5) | 3    ; BGR555
TEXTCOL  = (26 << 10) | (26 << 5) | 26
TITLECOL = (0 << 10) | (31 << 5) | 31
CUBECOL  = (24 << 10) | (31 << 5) | 8

.segment "ZEROPAGE"
num:        .res 2
tmp:        .res 2
ptr:        .res 3
text_attr:  .res 1
ram_banks:  .res 1
decl_banks: .res 1
ang_a:      .res 1
ang_b:      .res 1

; ============================================================================
.segment "CODE"

; ---- helpers ---------------------------------------------------------------

; Set the text cursor (BG3 tilemap address).
.macro locate row, col
    rep #$20
    lda #TEXTMAP + (row) * 32 + (col)
    sta VMADD
    sep #$20
.endmacro

; Print a string literal at the cursor.
.macro puts str
    .local msg
    .pushseg
    .segment "RODATA"
msg: .byte str, 0
    .popseg
    ldx #msg
    jsr print_str
.endmacro

; Copy len bytes from ROM (bank 0) to cartridge RAM.
.macro copy_fx src, dst, len
    .local l
    ldx #0
l:  lda a:src, x
    sta f:dst, x
    inx
    cpx #len
    bne l
.endmacro

; DMA bytes from cartridge RAM to VRAM.
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

.a8
.i16

; X = zero-terminated string
print_str:
@l: lda a:0, x
    beq @d
    sta VMDATAL
    lda text_attr
    sta VMDATAH
    inx
    bra @l
@d: rts

; Print `num` in decimal, leading zeros suppressed.
print_dec:
    stz tmp                     ; 0 = still suppressing zeros
    ldy #0
@digit:
    lda #'0'
    sta tmp+1
@sub:
    rep #$20
    lda num
    cmp pow10, y
    bcc @under
    sbc pow10, y
    sta num
    sep #$20
    inc tmp+1
    bra @sub
@under:
    sep #$20
    lda tmp+1
    cmp #'0'
    bne @print
    lda tmp
    bne @print
    cpy #8
    bne @skip                   ; drop a leading zero unless it is the last digit
@print:
    lda tmp+1
    sta VMDATAL
    lda text_attr
    sta VMDATAH
    lda #1
    sta tmp
@skip:
    iny
    iny
    cpy #10
    bne @digit
    rts
pow10: .word 10000, 1000, 100, 10, 1

; Print A as two hex digits.
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
    and #$000F
    tay
    sep #$20
    lda hexchars, y
    sta VMDATAL
    lda text_attr
    sta VMDATAH
    rts
hexchars: .byte "0123456789ABCDEF"

; Wait for the start of the next vertical blank.
wait_vblank:
@a: lda HVBJOY
    bmi @a
@b: lda HVBJOY
    bpl @b
    rts

; Read/write test of the cartridge RAM banks the header declares.
; decl_banks = declared 64 KB banks, ram_banks = banks that pass (first and last byte).
probe_ram:
    lda #1
    sta decl_banks          ; declared banks = 1 << (log2(KB) - 6)
    lda $FFBD               ; expansion RAM size = log2(KB)
    sec
    sbc #6
    beq @shd
    sta tmp+1
@sh: asl decl_banks
    dec tmp+1
    bne @sh
@shd:
    stz ptr
    stz ptr+1
    lda #$70
    sta ptr+2
    stz ram_banks
@bank:
    ldy #$0000
    lda ptr+2
    sta [ptr], y
    ldy #$FFFF
    eor #$FF
    sta [ptr], y
    ldy #$0000
    lda [ptr], y
    cmp ptr+2
    bne @next
    ldy #$FFFF
    lda [ptr], y
    eor #$FF
    cmp ptr+2
    bne @next
    inc ram_banks
@next:
    inc ptr+2
    lda ptr+2
    sec
    sbc #$70
    cmp decl_banks
    bne @bank
    rts

; ---- reset -----------------------------------------------------------------

reset:
    sei
    clc
    xce                     ; native mode
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
    sta INIDISP             ; forced blank
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

    ; ---- Super FX: quiet, 21 MHz, framebuffer at RAM $0000 ----
    lda #$80
    sta CFGR                ; mask the GSU IRQ
    lda #$01
    sta CLSR                ; 21.4 MHz
    stz SCBR
    lda #SCMR_OFF
    sta SCMR
    lda #$01
    sta PBR                 ; GSU code lives in ROM bank 1

    ; ---- palette ----
    stz CGADD
    lda #<BACKDROP
    sta CGDATA
    lda #>BACKDROP
    sta CGDATA
    lda #<TEXTCOL
    sta CGDATA
    lda #>TEXTCOL
    sta CGDATA
    lda #5
    sta CGADD
    lda #<TITLECOL
    sta CGDATA
    lda #>TITLECOL
    sta CGDATA
    lda #15
    sta CGADD
    lda #<CUBECOL
    sta CGDATA
    lda #>CUBECOL
    sta CGDATA

    ; ---- font -> VRAM ----
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

    ; ---- clear the text tilemap ----
    lda #TEXTMAP
    sta VMADD
    lda #$0000
    ldx #1024
@clr:
    sta VMDATA
    dex
    bne @clr

    ; ---- cube tilemap: framebuffer tiles are column-major ----
    lda #TEXTMAP + 1024     ; = CUBEMAP: fill with the blank tile 256
    sta VMADD
    lda #256
    ldx #1024
@clr2:
    sta VMDATA
    dex
    bne @clr2
    lda #CUBECHR + 256 * 16 ; tile 256 (just past the framebuffer) = blank
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
    asl                     ; row * 32
    clc
    adc #CUBEMAP + CUBE_ROW * 32 + CUBE_COL
    sta VMADD
    tya                     ; tile = col * 16 + row
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

    ; ---- WRAM routine that drives the GSU ----
    ldx #0
@rc: lda __RAMCODE_LOAD__, x
    sta __RAMCODE_RUN__, x
    inx
    cpx #__RAMCODE_SIZE__
    bne @rc

    ; ---- probe and fill cartridge RAM ----
    jsr probe_ram
    copy_fx sin_tab,   FX_SIN,   512
    copy_fx recip_tab, FX_RECIP, 256
    copy_fx cube_verts, FX_VERTS, 48
    copy_fx cube_edges, FX_EDGES, 24
    ldx #0
    lda #0
@zv: sta f:FX_ANG_A, x
    inx
    cpx #$80
    bne @zv
    stz ang_a
    stz ang_b

    ; ---- spec screen (columns 2..29) ----
    lda #$24                ; priority, palette 1 (title colour)
    sta text_attr
    locate 1, 6
    puts "SUPER FX 2 DEV CART"
    lda #$20
    sta text_attr

    locate 3, 2
    puts "CPU   65816 2.68MHZ SLOWROM"

    locate 4, 2
    puts "GSU   GSU-2 21.4MHZ VCR "
    lda VCR
    jsr print_hex8

    locate 5, 2
    puts "ROM   "
    lda $FFD7               ; header ROM size = log2(KB)
    rep #$20
    .a16
    and #$00FF
    tax
    lda #1
@sh: cpx #0
    beq @shd
    asl
    dex
    bra @sh
@shd:
    sta num
    sep #$20
    .a8
    jsr print_dec
    puts "K LOROM  "
    lda $FFD7
    sec
    sbc #5
    rep #$20
    .a16
    and #$00FF
    tax
    lda #1
@sh2:
    cpx #0
    beq @shd2
    asl
    dex
    bra @sh2
@shd2:
    sta num
    sep #$20
    .a8
    jsr print_dec
    puts " BANKS"

    locate 6, 2
    puts "RAM   "
    rep #$20
    .a16
    lda decl_banks          ; set by probe_ram
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    asl
    sta num
    sep #$20
    .a8
    jsr print_dec
    puts "K CART  128K WRAM"

    locate 7, 2
    puts "TEST  CART RAM 70-"
    lda #$6F
    clc
    adc decl_banks
    jsr print_hex8
    lda ram_banks
    cmp decl_banks
    beq ram_ok
    puts " FAIL"
    bra ram_done
ram_ok:
    puts " OK"
ram_done:

    locate 8, 2
    puts "VIDEO 256X224 "
    lda STAT78
    and #$10
    beq vid_ntsc
    puts "PAL 50HZ"
    bra vid_done
vid_ntsc:
    puts "NTSC 60HZ"
vid_done:

    locate 9, 2
    puts "PPU   1:V"
    lda STAT77
    and #$0F
    jsr print_hex8
    puts " 2:V"
    lda STAT78
    and #$0F
    jsr print_hex8
    puts "  BG MODE 1"

    locate 10, 2
    puts "GSU   FRAME "

    ; ---- first frame before the screen comes on ----
.ifndef NOGSU
    jsl gsu_run
.endif
    dma_fb FX_FB,         CUBECHR,         4096
    dma_fb FX_FB + 4096,  CUBECHR + 2048,  4096

    lda #$09
    sta BGMODE              ; mode 1, BG3 on top
    lda #(CUBEMAP >> 10) << 2
    sta BG1SC
    lda #(TEXTMAP >> 10) << 2
    sta BG3SC
    lda #CUBECHR >> 12
    sta BG12NBA
    lda #FONTCHR >> 12
    sta BG34NBA
    lda #$05
    sta TM                  ; BG1 + BG3
    lda #$0F
    sta INIDISP

; ---- main loop: 2 frames per cycle (8 KB framebuffer = two VBlank DMAs) ----
main_loop:
    jsr wait_vblank
    dma_fb FX_FB, CUBECHR, 4096
    locate 10, 14
    rep #$20
    .a16
    lda f:FX_FRAMES
    sta num
    sep #$20
    .a8
    jsr print_dec

    jsr wait_vblank
    dma_fb FX_FB + 4096, CUBECHR + 2048, 4096

    lda ang_a
    clc
    adc #2
    sta ang_a
    sta f:FX_ANG_A
    lda ang_b
    inc
    sta ang_b
    sta f:FX_ANG_B
.ifndef NOGSU
    jsl gsu_run
.endif
    jmp main_loop

stub:
    rti

; ---- runs from WRAM while the GSU owns ROM and RAM ----
.segment "RAMCODE"
gsu_run:
    lda #SCMR_ON
    sta SCMR
    ldx #GSU_main
    stx GSU_R15             ; writing R15's high byte starts the GSU
@w: lda SFR
    and #$20                ; G flag
    bne @w
    lda #SCMR_OFF
    sta SCMR
    rtl

; ---- data ----
.segment "RODATA"
font:
    .include "font.inc"
font_end:
    .include "tables.inc"

.segment "GSUCODE"
    .incbin "cube.bin"

; ---- extended internal header at $00:FFB0 ----
.segment "HEADER"
    .byte "00"                      ; maker code
    .byte "SNES"                    ; game code
    .res 7, $00
    .byte $07                       ; expansion RAM: 128 KB
    .byte $00                       ; special version
    .byte $00                       ; cartridge sub-type
    .byte "SUPER FX 2 DEV CART  "   ; 21-char title
    .byte $20                       ; LoROM, SlowROM
    .byte $1A                       ; GSU-2 + RAM + battery
    .byte $0B                       ; 2048 KB
    .byte $07                       ; RAM 128 KB
    .byte $01                       ; USA (NTSC)
    .byte $33                       ; extended header present
    .byte $00                       ; version
    .word $FFFF                     ; checksum complement (fixsum.py)
    .word $0000                     ; checksum

.segment "VECTORS"
    .word $0000, $0000
    .word stub, stub, stub, stub    ; native COP, BRK, ABORT, NMI
    .word $0000
    .word stub                      ; native IRQ
    .word $0000, $0000
    .word stub                      ; emulation COP
    .word $0000
    .word stub, stub                ; emulation ABORT, NMI
    .word reset                     ; RESET
    .word stub                      ; emulation IRQ/BRK
