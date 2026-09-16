; Test-only ROM-Pak that reads the first 63 bytes of track 18, sector 1
; through the production WD1773/FDC path, validates the expected DECB record
; header, copies its payload to $6000, and executes it.

        org $C000
entry   orcc #$50
        lds #$7F00

        lda #$01
        sta $FF40             ; drive 0 selected
        lda #18
        sta $FF49             ; ToolShed's first allocated granule ($22)
        lda #$01
        sta $FF4A             ; sector 1
        lda #$80
        sta $FF48             ; read one sector

waitdrq lda $FF48
        bita #$02
        beq waitdrq

        ldx #$7000
        ldb #63               ; complete GIMEREF.BIN stream
readbyte
waitnext
        lda $FF48
        bita #$02
        beq waitnext
        lda $FF4B
        sta ,x+
        decb
        bne readbyte

        lda $7000
        bne failed            ; data-record marker
        ldd $7001
        cmpd #$0035           ; GIMEREF payload length
        bne failed
        ldd $7003
        cmpd #$6000           ; GIMEREF load address
        bne failed

        ldx #$7005
        ldy #$6000
        ldb #$35
copy    lda ,x+
        sta ,y+
        decb
        bne copy
        jmp $6000

failed  lda #$E1
        sta $FF70             ; distinct malformed-DSK sentinel
        bra failed

        end entry
