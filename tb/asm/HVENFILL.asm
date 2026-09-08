; 96 virtual rows x 256 bytes, displayed twice per row (192 lines).
; Uses only $60000-$65FFF, within BASIC's 32K graphics allocation.
; Caller reserves $6000 upward. No stack accesses while $4000 is remapped.
        org ORIGIN
entry   pshs cc,d,x,y,u
        orcc #$50
        ldu #$ffa2
        lda $ff91
        bita #1
        beq taskok
        leau 8,u
taskok  lda ,u
        sta oldpage
        ldy #$30
page    tfr y,d
        stb ,u
        ldx #$4000
        clra
stripe  tfr x,d
        andb #$f0
        stb shade
        lsrb
        lsrb
        lsrb
        lsrb
        orb shade
        tfr b,a
        ldb #16
pixel   sta ,x+
        decb
        bne pixel
        cmpx #$6000
        blo stripe
        leay 1,y
        cmpy #$33
        blo page
        lda oldpage
        sta ,u
        lda $ff98
        anda #$f8
        ora #2
        sta $ff98
        lda #$80
        sta $ff9f
        puls cc,d,x,y,u,pc
oldpage fcb 0
shade   fcb 0
