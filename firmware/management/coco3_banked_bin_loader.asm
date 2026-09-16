; Generic loader for a C3B1 banked CoCo 3 BIN payload. The payload carries
; logical-address records plus physical MMU placement descriptors. Firmware
; validates the container and CRC before this loader is launched.
BINSTAT equ $FF62
BINDATA equ $FF63
BINCTRL equ $FF64

OLDADD equ $8000
LFFA1  equ $8002
BYTE   equ $8003
STK    equ $8108
TRAMP  equ $8200

        org $C000
entry   orcc #$50
        lds #STK
        lda #$ff
        sta $FFDF              ; expose RAM while the ROM-Pak remains mapped
        ldd #$4c20             ; MMU enabled, all RAM, slow 6809 timing
        std $FF90
        clr $FF92
        clr $FF93
        clr $0071              ; discard any BASIC warm-start context
        clr $0072
        clr $0073
        clr $FEED
        clra
        clrb
        std OLDADD

record jsr getbyte             ; every banked record begins with zero
        tstb
        lbne failed
        jsr getword
        pshs d                 ; length includes a placement descriptor when
        tfr d,u                ; the logical address is discontinuous
        jsr getword
        leau d,u
        subd OLDADD
        tfr cc,b
        stu OLDADD
        ldy ,s++
        tfr b,cc
        beq copybyte

        jsr getword            ; discontinuous record: physical placement
        cmpd #0
        beq execute
        pshs a
        lsra
        sta $FFA1
        sta LFFA1
        puls a
        jsr getblock
        leay -2,y              ; descriptor bytes count toward record length
        beq record

copybyte
        jsr getbyte
        stb ,x+
        leay -1,y
        beq record
        cmpx #$4000
        blo copybyte
        ldb LFFA1
        incb
        stb LFFA1
        stb $FFA1
        ldx #$2000
        bra copybyte

execute
        jsr getword            ; final descriptor selects the logical entry
        pshs a
        lsra
        sta $FFA1
        puls a
        jsr getblock
        leay trampoline,pcr
        ldu #TRAMP
        ldb #trampoline_end-trampoline
copytramp
        lda ,y+
        sta ,u+
        decb
        bne copytramp
        stx TRAMP+6
        jmp TRAMP

; Convert a placement descriptor in D to the $2000-$3fff logical MMU window.
getblock
        anda #1
        lslb
        rola
        lslb
        rola
        lslb
        rola
        lslb
        rola
        ldx #$2000
        leax d,x
        rts

getword
        jsr getbyte
        tfr b,a
        jsr getbyte
        rts

getbyte
        ldb BINSTAT
        bitb #$04
        bne failed
        bitb #$01
        beq getbyte
        ldb BINDATA
        stb BYTE
        ldb #2
        stb BINCTRL
        ldb BYTE
        rts

failed  bra failed

; Finish from RAM while firmware atomically removes the temporary ROM-Pak.
trampoline
        lda #1
        sta BINCTRL
        jmp $0000              ; patched to the logical entry at TRAMP+6
trampoline_end
        end entry
