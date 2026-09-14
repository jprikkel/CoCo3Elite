; Temporary ROM-Pak used to receive a prevalidated DECB LOADM stream.
; The manager exposes status/data at $FF62/$FF63.  $FE00-$FEFF is reserved
; during loading for this program's stack and final cartridge-unmap trampoline.
BINSTAT equ $FF62
BINDATA equ $FF63
BINCTRL equ $FF64
TRAMP   equ $FE00
LENGTH  equ $FE80
TARGET  equ $FE82
BYTE    equ $FE84
SAVEDS  equ $FE86

        org $C000
; The ROM-Pak entry arrives after the system ROM has completed its cold-start
; setup, including creation of BASIC's normal stack.  Preserve that execution
; context while the streaming loop uses a private stack.
entry   sts SAVEDS
        orcc #$50
        lds #$FEFF
        sta $FFDF              ; all-RAM stores; external ROM-Pak remains visible

record jsr getbyte
        cmpa #$00
        beq datarecord
        cmpa #$FF
        beq execrecord
        bra failed

datarecord
        jsr getbyte
        sta LENGTH
        jsr getbyte
        sta LENGTH+1
        ldu LENGTH             ; U = big-endian record byte count
        jsr getbyte
        sta TARGET
        jsr getbyte
        sta TARGET+1
        ldx TARGET             ; X = big-endian logical destination
copybyte
        cmpu #0
        beq record
        jsr getbyte
        sta ,x+
        leau -1,u
        bra copybyte

execrecord
        jsr getbyte            ; consume validated zero trailer length
        jsr getbyte
        jsr getbyte
        sta TARGET
        jsr getbyte
        sta TARGET+1
        ldx TARGET             ; X = execution address
        leay trampoline,pcr
        ldu #TRAMP
        ldb #trampoline_end-trampoline
copytramp
        lda ,y+
        sta ,u+
        decb
        bne copytramp
        tfr x,d
        std TRAMP+15
        jmp TRAMP

; Return the next stream byte in A. The explicit acknowledge happens after
; the data read, so the FIFO head cannot change before the 6809 samples it.
; Empty is normal back-pressure; error is terminal and Ctrl-Alt-Delete remains
; available as the recovery path.
getbyte
        lda BINSTAT
        bita #$04
        bne failed
        bita #$01
        beq getbyte
        lda BINDATA
        sta BYTE
        lda #2
        sta BINCTRL
        lda BYTE
        rts

failed  bra failed

trampoline
        lda #1
        sta $FFDE              ; restore the normal ROM/RAM map used by LOADM
        sta BINCTRL            ; atomically disable the temporary ROM-Pak
        lds SAVEDS             ; match an EXEC issued from initialized BASIC
        andcc #$AF             ; BASIC enables IRQ and FIRQ before direct mode
        jmp $0000              ; execution address patched at TRAMP+15
trampoline_end
        end entry
