        org $8000
        orcc #$50
        lds #$5fff
        lda #$3a
        sta $ffa2
        lda #$3b
        sta $ffa3
        lda #$40
        sta $ff90
        lda #$80
        sta $ff98
        jsr $6000
        lda #$fe
        sta $ff70
done    bra done
