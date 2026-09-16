; GIMELPR - dynamic 1987 GIME LPR/infinite-row hardware probe.
;
; Sock Master's description of Boink says it changes FF98.LPR to 111 during
; the frame to control vertical row repetition.  This original test performs
; that operation on a synthetic 256x192 16-color image.  A colored horizontal
; band should stretch and move vertically while the other rows remain stable.
; It uses no BASIC/ROM calls after entry and never changes the display start
; during an active frame, isolating FF98 row advancement from page switching.
;
; FF70-FF77 mailbox:
;   42 frame start end hh ll 98 99
;   signature, frame, hold-start, hold-end, previous HBORD count, FF98, FF99

        org $7000
entry   orcc #$50
        lds #$7FFF

        clr $FF90              ; native mode, GIME IRQ/FIRQ master gates off
        clr $FF91
        clr $FF92
        lda #$18               ; expose HBORD and VBORD pending status
        sta $FF93
        clr $FF9B
        clr $FF9C
        clr $FF9F

        ; Sixteen distinct RGB palette entries.
        ldx #$FFB0
        ldb #$00
pal     tfr b,a
        anda #$3F
        sta ,x+
        addb #$05
        cmpx #$FFC0
        blo pal

        ; 192 rows x 128 bytes at logical $1000-$6FFF.  Every row has a
        ; distinct pair of color indexes so incorrect advancement is obvious.
        ldx #$1000
        clrb
fillrow
        tfr b,a
        anda #$0F
        lsla
        lsla
        lsla
        lsla
        pshs a
        tfr b,a
        inca
        anda #$0F
        ora ,s+
        ldu #128
fillbyte
        sta ,x+
        leau -1,u
        cmpu #0
        bne fillbyte
        incb
        cmpb #192
        blo fillrow

        lda #$80               ; graphics, normal one-line rows
        sta $FF98
        lda #$1A               ; 192 lines, 128 bytes, 256x16 colors
        sta $FF99
        lda #$01
        sta $FF9A              ; visible native border
        ldd #$E200             ; physical $71000 = logical $1000
        std $FF9D

        clr frame
        lda #48
        sta holdstart
        lda #72
        sta holdend
        lda #1
        sta direction
        clr hcount
        clr hcount+1
        jsr publish
        lda $FF93              ; acknowledge stale pending sources

poll    lda $FF93
        sta events
        bita #$10              ; HBORD
        beq novline
        ldd hcount
        addd #1
        std hcount
        lda hcount+1
        cmpa holdstart
        bne checkend
        lda #$87               ; freeze current graphics row
        sta $FF98
checkend
        lda hcount+1
        cmpa holdend
        bne novline
        lda #$80               ; resume one row per scanline
        sta $FF98
novline lda events
        bita #$08              ; VBORD
        beq poll

        jsr publish
        clr hcount
        clr hcount+1
        lda #$80
        sta $FF98              ; every frame begins in normal-row mode
        inc frame

        lda direction
        bmi movingup
        inc holdstart
        inc holdend
        lda holdend
        cmpa #150
        blo poll
        lda #$FF
        sta direction
        bra poll
movingup
        dec holdstart
        dec holdend
        lda holdstart
        cmpa #24
        bhi poll
        lda #1
        sta direction
        bra poll

publish
        lda frame
        sta $FF71
        lda holdstart
        sta $FF72
        lda holdend
        sta $FF73
        ldd hcount
        sta $FF74
        stb $FF75
        lda $FF98
        sta $FF76
        lda $FF99
        sta $FF77
        lda #$42
        sta $FF70
        rts

frame     rmb 1
holdstart rmb 1
holdend   rmb 1
direction rmb 1
hcount    rmb 2
events    rmb 1

        end entry
