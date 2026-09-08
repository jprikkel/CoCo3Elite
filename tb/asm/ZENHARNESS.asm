        org $8000
        orcc #$50
        lds #$5fff
        lda #$38
        sta $ffa0
        lda #$39
        sta $ffa1
        lda #$3a
        sta $ffa2
        lda #$3b
        sta $ffa3
; Enter as Disk BASIC can: standard fixed map with the MMU disabled.  ZENFILL
; must initialize and enable the active task map before using high page aliases.
        jmp $6000
