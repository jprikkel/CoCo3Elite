; ELITEMEM - cartridge-resident destructive 128 KiB CoCo 3 memory test.
;
; The code executes from the external $C000-$DFFF ROM-Pak window, allowing
; every implemented RAM page to be overwritten.  Choose a suite at the menu:
;   Q = quick data/address/pattern tests
;   L = long March C- transitions
;   A = all tests
;
; Once a suite starts, the test engine uses no stack or RAM variables.  Its
; mode and failure bits live in the 6809 DP register while all sixteen 8 KiB
; physical pages are mapped through logical $4000-$5FFF.  Tests target the
; 128 KiB 1987 CoCo 3 memory organization.  All tested RAM is erased.

SCREEN      equ $2000
SCREEN_END  equ $27D0
LINEPTR     equ $7E00
TESTNO      equ $7E02
PASSCOUNT   equ $7E03
FAILCOUNT   equ $7E04
FAILMASK    equ $7E05
SUITEMODE   equ $7E06
TESTMASK    equ $7E07

MODE_QUICK  equ $40
MODE_LONG   equ $80
MODE_ALL    equ $C0

        org $C000
entry   orcc #$50
        lds #$7FFF
        clr $FF90
        clr $FF91
        clr $FF92
        clr $FF93
        jsr video80
        jsr clearscreen
        ldd #SCREEN
        std LINEPTR
        ldx #title
        jsr plainline
        ldx #warning
        jsr plainline
        jsr blankline
        ldx #quickoption
        jsr plainline
        ldx #longoption
        jsr plainline
        ldx #alloption
        jsr plainline
        jsr keyboard_setup
        lda #$4D              ; menu ready marker
        sta $FF70

release lda #$00             ; select every keyboard column
        sta $FF02
        lda $FF00
        cmpa #$FF
        bne release
select  lda #$FD             ; column 1: A=row 0, Q=row 2
        sta $FF02
        lda $FF00
        bita #$01
        beq choose_all
        bita #$04
        beq choose_quick
        lda #$EF             ; column 4: L=row 1
        sta $FF02
        lda $FF00
        bita #$02
        bne select
choose_long
        lda #MODE_LONG
        tfr a,dp
        bra begin_test
choose_all
        lda #MODE_ALL
        tfr a,dp
        bra begin_test
choose_quick
        lda #MODE_QUICK
        tfr a,dp

; No JSR, PSH or PUL is permitted between begin_test and test_complete.
; The stack is RAM and every physical page is deliberately overwritten.
begin_test
        tfr dp,a
        sta $FF71
        lda #$50              ; suite started marker is written last
        sta $FF70
        ldx #$FFB0            ; keep the display black while screen RAM is tested
        ldb #16
black_palette
        clr ,x+
        decb
        bne black_palette
        lda #$40              ; MMU enabled, task 0
        sta $FF90
        clr $FF91
        tfr dp,a
        bita #MODE_QUICK
        lbeq march_start

; Quick 1: walking-one and walking-zero data bus patterns.
        lda #$30
        sta $FFA2
        ldb #1
data_bits
        stb $4002
        cmpb $4002
        beq data_zero
        tfr dp,a
        ora #$01
        tfr a,dp
data_zero
        tfr b,a
        coma
        sta $4002
        cmpa $4002
        beq data_next
        tfr dp,a
        ora #$01
        tfr a,dp
data_next
        aslb
        bne data_bits
        lda #1
        sta $FF71
        tfr dp,a
        anda #$01
        sta $FF72
        lda #$51
        sta $FF70

; Quick 2: unique sentinel in every physical 8 KiB page catches page aliases.
        clrb
page_write
        tfr b,a
        ora #$30
        sta $FFA2
        tfr b,a
        eora #$5A
        sta $4000
        incb
        cmpb #16
        blo page_write
        clrb
page_check
        tfr b,a
        ora #$30
        sta $FFA2
        tfr b,a
        eora #$5A
        cmpa $4000
        beq page_next
        tfr dp,a
        ora #$02
        tfr a,dp
page_next
        incb
        cmpb #16
        blo page_check
        lda #2
        sta $FF71
        tfr dp,a
        anda #$02
        sta $FF72
        lda #$51
        sta $FF70

; Quick 3: fill and verify $00, $FF, $AA and $55 across all 128 KiB.
        lds #patterns
pattern_next
        ldy ,s++
        cmpy #$1234
        beq address_start
        ldu #0
pattern_page
        tfr u,d
        orb #$30
        stb $FFA2
        ldx #$4000
pattern_fill
        sty ,x++
        cmpx #$6000
        blo pattern_fill
        leau 1,u
        cmpu #16
        blo pattern_page
        ldu #0
pattern_verify_page
        tfr u,d
        orb #$30
        stb $FFA2
        ldx #$4000
pattern_verify
        cmpy ,x++
        beq pattern_verify_next
        tfr dp,a
        ora #$04
        tfr a,dp
pattern_verify_next
        cmpx #$6000
        blo pattern_verify
        leau 1,u
        cmpu #16
        blo pattern_verify_page
        bra pattern_next

; Quick 4: each RAM word stores its logical address, detecting address aliases.
address_start
        ldu #0
address_write_page
        tfr u,d
        orb #$30
        stb $FFA2
        ldx #$4000
address_write
        stx ,x
        leax 2,x
        cmpx #$6000
        blo address_write
        leau 1,u
        cmpu #16
        blo address_write_page
        ldu #0
address_check_page
        tfr u,d
        orb #$30
        stb $FFA2
        ldx #$4000
address_check
        cmpx ,x
        beq address_next
        tfr dp,a
        ora #$08
        tfr a,dp
address_next
        leax 2,x
        cmpx #$6000
        blo address_check
        leau 1,u
        cmpu #16
        blo address_check_page
        lda #3
        sta $FF71
        tfr dp,a
        anda #$04
        sta $FF72
        lda #$51
        sta $FF70
        lda #4
        sta $FF71
        tfr dp,a
        anda #$08
        sta $FF72
        lda #$51
        sta $FF70
        tfr dp,a
        bita #MODE_LONG
        lbeq test_complete

; Long 1: March C- ascending 0->1 and 1->0 transitions.
march_start
        lda #$40
        sta $FF90
        ldu #0
march_init_page
        tfr u,d
        orb #$30
        stb $FFA2
        ldx #$4000
        clra
        clrb
march_init
        std ,x++
        cmpx #$6000
        blo march_init
        leau 1,u
        cmpu #16
        blo march_init_page
        lda #$54              ; March initialization completed
        sta $FF70
        ldu #0
march_up_page
        tfr u,d
        orb #$30
        stb $FFA2
        ldx #$4000
march_up_one
        ldd ,x
        cmpd #$0000
        beq march_up_write_one
        std $FF76             ; first observed value for failure telemetry
        tfr dp,a
        bita #$10
        bne march_up_marked
        tfr u,d
        stb $FF73             ; first failing physical page
        stx $FF74             ; first failing logical address
        lda #$52
        sta $FF70
march_up_marked
        tfr dp,a
        ora #$10
        tfr a,dp
march_up_write_one
        ldd #$FFFF
        std ,x++
        cmpx #$6000
        blo march_up_one
        leau 1,u
        cmpu #16
        blo march_up_page
        ldu #0
march_up_zero_page
        tfr u,d
        orb #$30
        stb $FFA2
        ldx #$4000
march_up_zero
        ldd ,x
        cmpd #$FFFF
        beq march_up_write_zero
        std $FF76
        tfr dp,a
        bita #$10
        bne march_up_zero_marked
        tfr u,d
        stb $FF73
        stx $FF74
        lda #$52
        sta $FF70
march_up_zero_marked
        tfr dp,a
        ora #$10
        tfr a,dp
march_up_write_zero
        clra
        clrb
        std ,x++
        cmpx #$6000
        blo march_up_zero
        leau 1,u
        cmpu #16
        blo march_up_zero_page
        lda #5
        sta $FF71
        tfr dp,a
        anda #$10
        sta $FF72
        lda #$51
        sta $FF70

; Long 2: descending 0->1 and 1->0 transitions catch coupling faults.
        ldu #15
march_down_page
        tfr u,d
        orb #$30
        stb $FFA2
        ldx #$5FFE
march_down_one
        ldd ,x
        cmpd #$0000
        beq march_down_write_one
        std $FF76
        tfr dp,a
        bita #$20
        bne march_down_marked
        tfr u,d
        stb $FF73
        stx $FF74
        lda #$52
        sta $FF70
march_down_marked
        tfr dp,a
        ora #$20
        tfr a,dp
march_down_write_one
        ldd #$FFFF
        std ,x
        leax -2,x
        cmpx #$3FFF
        bhi march_down_one
        leau -1,u
        cmpu #$FFFF
        bne march_down_page
        ldu #15
march_down_zero_page
        tfr u,d
        orb #$30
        stb $FFA2
        ldx #$5FFE
march_down_zero
        ldd ,x
        cmpd #$FFFF
        beq march_down_write_zero
        std $FF76
        tfr dp,a
        bita #$20
        bne march_down_zero_marked
        tfr u,d
        stb $FF73
        stx $FF74
        lda #$52
        sta $FF70
march_down_zero_marked
        tfr dp,a
        ora #$20
        tfr a,dp
march_down_write_zero
        clra
        clrb
        std ,x
        leax -2,x
        cmpx #$3FFF
        bhi march_down_zero
        leau -1,u
        cmpu #$FFFF
        bne march_down_zero_page
        lda #6
        sta $FF71
        tfr dp,a
        anda #$20
        sta $FF72
        lda #$51
        sta $FF70

test_complete
        clr $FF90
        lds #$7FFF
        tfr dp,a
        sta FAILMASK
        anda #$C0
        sta SUITEMODE
        jsr video80
        jsr clearscreen
        ldd #SCREEN
        std LINEPTR
        clr TESTNO
        clr PASSCOUNT
        clr FAILCOUNT
        ldx #result_title
        jsr plainline
        ldx #memory_group
        jsr plainline
        lda SUITEMODE
        bita #MODE_QUICK
        beq report_long
        lda #$01
        ldx #msg_data
        jsr report
        lda #$02
        ldx #msg_pages
        jsr report
        lda #$04
        ldx #msg_patterns
        jsr report
        lda #$08
        ldx #msg_address
        jsr report
report_long
        lda SUITEMODE
        bita #MODE_LONG
        beq report_summary
        lda #$10
        ldx #msg_march_up
        jsr report
        lda #$20
        ldx #msg_march_down
        jsr report
report_summary
        jsr blankline
        ldx #summary
        jsr beginline
        lda PASSCOUNT
        jsr decimal2
        ldx #passed
        jsr printz
        lda FAILCOUNT
        jsr decimal2
        ldx #failed
        jsr printz
        jsr endline
        lda #$A5
        sta $FF75
        lda #$5A
        sta $FF76
        lda #$87
        sta $FF77
        lda TESTNO
        sta $FF71
        clr $FF72
        lda PASSCOUNT
        sta $FF73
        lda FAILCOUNT
        sta $FF74
        lda #$53
        sta $FF70
halt    bra halt

report sta TESTMASK
        inc TESTNO
        jsr beginline
        lda FAILMASK
        bita TESTMASK
        bne report_fail
        inc PASSCOUNT
        ldx #passmsg
        bra report_text
report_fail
        inc FAILCOUNT
        ldx #failmsg
report_text
        jsr printz
        jsr endline
        lda TESTNO
        sta $FF71
        lda FAILMASK
        anda TESTMASK
        sta $FF72
        lda PASSCOUNT
        sta $FF73
        lda FAILCOUNT
        sta $FF74
        lda #$44
        sta $FF70
        rts

video80 clr $FF9A
        clr $FF9B
        clr $FF9C
        clr $FF9F
        clr $FFB0
        lda #$3F
        sta $FFB1
        lda #$03
        sta $FF98
        lda #$34
        sta $FF99
        ldd #$E400
        std $FF9D
        rts

clearscreen
        ldx #SCREEN
        lda #' '
clear   sta ,x+
        cmpx #SCREEN_END
        blo clear
        rts

keyboard_setup
        clr $FF01
        clr $FF00
        clr $FF03
        lda #$FF
        sta $FF02
        lda #$04
        sta $FF01
        sta $FF03
        rts

plainline
        jsr beginline
        jsr endline
        rts
blankline
        jsr endline
        rts
beginline
        ldy LINEPTR
        ldb #10
indent  lda #' '
        sta ,y+
        decb
        bne indent
printz  lda ,x+
        beq printed
        sta ,y+
        bra printz
printed rts
endline ldd LINEPTR
        addd #80
        std LINEPTR
        rts
decimal2
        clrb
dec10   cmpa #10
        blo digits
        suba #10
        incb
        bra dec10
digits  pshs a
        tfr b,a
        adda #'0'
        sta ,y+
        puls a
        adda #'0'
        sta ,y+
        rts

patterns    fdb $0000,$FFFF,$AAAA,$5555,$1234
title       fcc "CoCo 3 Elite memory diagnostics"
            fcb 0
warning     fcc "Warning: selected test erases all 128K RAM"
            fcb 0
quickoption fcc "Q  Quick data, page, pattern and address tests"
            fcb 0
longoption  fcc "L  Long March C- transition tests"
            fcb 0
alloption   fcc "A  All quick and long memory tests"
            fcb 0
result_title fcc "CoCo 3 Elite memory diagnostic results"
            fcb 0
memory_group fcc "Full 128K memory"
            fcb 0
msg_data    fcc "Walking-one and walking-zero data bus ...... "
            fcb 0
msg_pages   fcc "Sixteen independent physical RAM pages .... "
            fcb 0
msg_patterns fcc "Full RAM 00, FF, AA and 55 patterns ........ "
            fcb 0
msg_address fcc "Word address uniqueness across every page . "
            fcb 0
msg_march_up fcc "March C- ascending transitions ............. "
            fcb 0
msg_march_down fcc "March C- descending transitions ............ "
            fcb 0
summary     fcc "Summary: "
            fcb 0
passed      fcc " passed, "
            fcb 0
failed      fcc " failed"
            fcb 0
passmsg     fcc "PASS"
            fcb 0
failmsg     fcc "FAIL"
            fcb 0

        end entry
