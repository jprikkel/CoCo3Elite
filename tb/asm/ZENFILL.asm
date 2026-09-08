; Zenix-derived 320x225x16/HVEN integration pattern.
; The game displays $6B100 ($D620 in the GIME start registers), uses a
; 256-byte virtual row, and writes that RAM through MMU pages $35-$3C.
; On a 128K CoCo 3 those high page numbers alias by their low four bits.
;
; The standard CoCo 3 map places a BASIC-loaded $6000 helper and its stack
; inside that framebuffer. Relocate this image to physical page $04 before
; filling it, then remain there until reset.
        org ORIGIN
entry   orcc #$50

; Select the active task's page-zero and page-three MMU registers.
        ldu #$ffa0
        ldy #$ffa3
        lda $ff91
        bita #1
        beq taskok
        leau 8,u
        leay 8,y
taskok
        stu page0reg
        sty page3reg

; Disk BASIC normally leaves the MMU disabled.  In that state writes to the
; task registers succeed but do not affect CPU addressing, so establish the
; standard $38-$3F map for the active task before enabling it.  If the MMU is
; already active, retain the caller's map until the pages below are changed.
        lda $ff90
        bita #$40
        bne mmuok
        ldx page0reg
        lda #$38
        ldb #8
mapstd  sta ,x+
        inca
        decb
        bne mapstd
        lda $ff90
        ora #$40
        sta $ff90
mmuok

; Make physical page $04 visible at $0000 and copy this complete image there.
; It appears at the same logical addresses after page three is remapped.
        lda #$34
        sta ,u
        ldx #entry
        ldy #0
copy    lda ,x+
        sta ,y+
        cmpx #imageend
        blo copy

; The next opcode is fetched from the relocated copy at physical $08000.
        lda #$34
        ldy page3reg
        sta ,y
        ldu page0reg
        lds #$7fff             ; private stack in safe physical page $04

        lda #$35
        sta page
nextpg lda page
        sta ,u                 ; high page mapped at logical $0000
        ldx #0
        cmpa #$35
        bne fill
        ldx #$1100             ; physical $0B100, display start

; Each 16-byte horizontal band has one color. XORing the mapped page into
; the color also makes every 32-row MMU boundary visible on screen.
fill    tfr x,d
        lsrb
        lsrb
        lsrb
        lsrb
        eorb page
        andb #$0f
        stb shade
        tfr b,a
        lsla
        lsla
        lsla
        lsla
        adda shade
        tfr a,b
        std ,x++
        std ,x++
        std ,x++
        std ,x++
        std ,x++
        std ,x++
        std ,x++
        std ,x++
        lda page
        cmpa #$3c
        beq lastpg
        cmpx #$2000
        blo fill
        bra filled
lastpg  cmpx #$1200            ; physical $191FF, final visible row
        blo fill
filled  inc page
        lda page
        cmpa #$3d
        blo nextpg

        lda #$80               ; native graphics
        sta $ff98
        lda #$7e               ; Zenix: 225 lines, 320 pixels, 16 colors
        sta $ff99
        clr $ff9a
        clr $ff9b
        clr $ff9c
        ldd #$d620             ; Zenix display start: byte address $6B100
        std $ff9d

        ldx #colors
        ldu #$ffb0
        ldb #16
setpal  lda ,x+
        sta ,u+
        decb
        bne setpal

        lda #24
        sta offset
scroll  ora #$80               ; HVEN plus current word offset
        sta $ff9f
        ldx #0
delay   leax -1,x
        bne delay
        lda offset
        inca
        anda #$7f
        sta offset
        bra scroll

page    fcb 0
shade   fcb 0
offset  fcb 0
page0reg fdb 0
page3reg fdb 0
colors  fcb 0,9,18,27,36,45,54,63
        fcb 7,14,21,28,35,42,49,56
imageend
