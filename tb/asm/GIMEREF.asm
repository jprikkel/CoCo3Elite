; Shared launch-path probe for the GIME reference regressions.
; The same DECB binary is executed through Disk BASIC LOADM/EXEC and through
; the management BIN FIFO.  The test benches verify the resulting register
; state, proving that both launch paths reach identical program behavior.

        org $6000
entry   orcc #$50

        lda #$87              ; native graphics, infinite lines per row
        sta $FF98
        lda #$7E              ; 225 lines, 160 bytes/row, 16 colors
        sta $FF99
        lda #$2A
        sta $FF9A             ; border color
        lda #$0B
        sta $FF9C             ; vertical fine scroll
        lda #$12
        sta $FF9D
        lda #$34
        sta $FF9E             ; display start = $1234 * 8
        lda #$85
        sta $FF9F             ; HVEN, horizontal offset 5 words

        lda #$01
        sta $FF95             ; timer low byte does not restart
        clra
        sta $FF94             ; timer high nibble write restarts

        lda #$A5
        sta $FF70             ; simulation completion sentinel
hang    bra hang

        end entry
