; Exercise the CPU bus, rather than forcing peripheral read strobes.
        org $8000
        orcc #$50
        lda #4
        sta $ff03
        tst $ff02
        lda #1
        sta $ff70
        ldx #40
delay   leax -1,x
        bne delay
wait    tst $ff03
        bpl wait
        tst $ff03
        bpl fail
        tst $ff02
        tst $ff03
        bmi fail
        lda #2
        sta $ff70
        ldx #40
delay2  leax -1,x
        bne delay2
        lda $ff93
        bita #8
        beq fail
        lda $ff93
        bita #8
        bne fail
        lda #$fe
        sta $ff70
done    bra done
fail    lda #$ee
        sta $ff70
        bra done
