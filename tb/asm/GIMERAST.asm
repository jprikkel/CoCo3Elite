; GIMERAST - hardware-visible 1987 GIME raster probe.
;
; The program is deliberately self-contained: it does not call BASIC or ROM
; routines after entry.  It cycles through four two-second phases while the
; passive FPGA UART monitor reports the FF70-FF77 mailbox:
;
;   FF70  $47 signature
;   FF71  phase (0 normal, 1 infinite LPR, 2 raster LPR, 3 horizontal offset)
;   FF72  frame within phase
;   FF73  HBORD count high byte for the preceding frame
;   FF74  HBORD count low byte
;   FF75  FF98 readback
;   FF76  FF99 readback
;   FF77  FF9F readback
;
; Target behavior is the 1987 GIME described by Sock Master's reference.
; FF93 is polled with its master FIRQ gate disabled, so the test measures the
; documented HBORD/VBORD pending sources without running an interrupt handler.

        org $6000
entry   orcc #$50
        lds #$7FFF

        ; Fixed native map.  Screen RAM is logical $2000-$5E7F and this code
        ; remains above it at $6000.
        clr $FF90
        clr $FF91
        clr $FF92
        lda #$18              ; HBORD + VBORD status in FIRQ register
        sta $FF93
        clr $FF9B
        clr $FF9C
        clr $FF9F

        ; Four-color palette: black, blue, red/orange, white.
        clr $FFB0
        lda #$09
        sta $FFB1
        lda #$24
        sta $FFB2
        lda #$3F
        sta $FFB3

        ; Fill 200 rows of 80 bytes. Adjacent rows invert a 0,1,2,3 pixel
        ; sequence, producing a checkerboard in normal LPR mode and straight
        ; vertical bars when infinite LPR repeats one memory row.
        ldx #$2000
        lda #$1B
        sta pattern
        lda #200
        sta rows
fillrow ldu #80
        lda pattern
fillbyte
        sta ,x+
        leau -1,u
        cmpu #0
        bne fillbyte
        eora #$FF
        sta pattern
        dec rows
        bne fillrow

        lda #$80              ; graphics, one scanline per memory row
        sta $FF98
        lda #$35              ; 200 lines, 80 bytes/row, four colors
        sta $FF99
        clr $FF9A
        lda #$E4              ; physical $72000: $E000 + ($2000 / 8)
        sta $FF9D
        clr $FF9E

        clr phase
        clr frame
        clr hcount
        clr hcount+1
        lda #$47
        sta $FF70
        jsr applyphase
        jsr publish
        lda $FF93             ; discard stale pending state

poll    lda $FF93             ; read reports and acknowledges pending events
        sta events
        bita #$10
        beq novline
        ldd hcount
        addd #1
        std hcount
        jsr rasterstep
novline lda events
        bita #$08
        beq poll

        ; Publish the completed frame before clearing its counter.
        jsr publish
        clr hcount
        clr hcount+1
        inc frame
        lda frame
        cmpa #120             ; roughly two seconds at 60 Hz
        blo samephase
        clr frame
        inc phase
        lda phase
        cmpa #4
        blo phaseok
        clr phase
phaseok jsr applyphase
samephase
        lda phase
        cmpa #3
        bne poll
        lda frame             ; smooth two-byte horizontal movement
        anda #$3F
        sta $FF9F
        bra poll

; Phase 2 changes LPR at known HBORD counts. The UART W= field records the
; exact renderer line on which the most recent write occurred.
rasterstep
        lda phase
        cmpa #2
        bne rasterdone
        lda hcount+1
        cmpa #32
        beq setinfinite
        cmpa #96
        beq setnormal
        cmpa #160
        beq setinfinite
        cmpa #224
        beq setnormal
rasterdone
        rts
setinfinite
        lda #$87
        sta $FF98
        rts
setnormal
        lda #$80
        sta $FF98
        rts

applyphase
        clr $FF9F
        lda phase
        sta $FF9A             ; border identifies phase 0..3
        cmpa #1
        beq phaseinf
        lda #$80
        sta $FF98
        rts
phaseinf
        lda #$87
        sta $FF98
        rts

publish
        lda #$47
        sta $FF70
        lda phase
        sta $FF71
        lda frame
        sta $FF72
        ldd hcount
        sta $FF73
        stb $FF74
        lda $FF98
        sta $FF75
        lda $FF99
        sta $FF76
        lda $FF9F
        sta $FF77
        rts

phase   rmb 1
frame   rmb 1
hcount  rmb 2
events  rmb 1
rows    rmb 1
pattern rmb 1

        end entry
