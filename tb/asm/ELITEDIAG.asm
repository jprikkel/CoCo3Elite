; ELITEDIAG - self-contained CoCo 3 Elite hardware diagnostic.
;
; This program runs without BASIC or ROM calls after entry.  It displays one
; result per line in native 80-column text and publishes each result through
; the existing passive UART mailbox writes:
;
;   FF70  $44 while a test completes, $53 for the final summary
;   FF71  test number (1..22)
;   FF72  result (0 PASS, nonzero FAIL)
;   FF73  cumulative pass count
;   FF74  cumulative fail count
;
; Tests target the later 1987 GIME behavior used by CoCo 3 software.  External
; analog audio, the monitor, SD media, and the serial cable cannot be sensed by
; 6809 software; their tests verify the software-visible control/telemetry
; paths.  HDL and hardware capture validate the corresponding external path.

SCREEN          equ $2000
SCREEN_END      equ $27D0
PROMPT_ROW      equ $2780
EXEC_ADDRESS    equ $6000

        org EXEC_ADDRESS
entry   orcc #$50              ; keep IRQ/FIRQ handlers out of destructive tests
        lds #$7FFF
        sta $FFDE              ; internal ROM map, MMU disabled
        clr $FF90
        clr $FF91
        clr $FF92
        clr $FF93

        ; Clear the complete 80 x 25 screen before selecting native text.
        jsr clearscreen

        ; Native 80-column text, no attributes, screen at physical $72000.
        clr $FF9A
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

        ldd #SCREEN
        std lineptr
        clr testno
        clr passcount
        clr failcount

        ldx #title
        jsr plainline
        ldx #subtitle
        jsr plainline
        jsr blankline

        ldx #group_cpu
        jsr plainline
        ldx #msg_cpu
        ldu #test_cpu
        jsr runone
        ldx #msg_cpu_regs
        ldu #test_cpu_registers
        jsr runone
        ldx #msg_ram
        ldu #test_ram
        jsr runone
        ldx #msg_mmu_regs
        ldu #test_mmu_regs
        jsr runone
        ldx #msg_mmu_banks
        ldu #test_mmu_banks
        jsr runone
        ldx #msg_mmu_tasks
        ldu #test_mmu_tasks
        jsr runone

        ldx #group_rom
        jsr plainline
        ldx #msg_vectors
        ldu #test_vectors
        jsr runone
        ldx #msg_romprotect
        ldu #test_romprotect
        jsr runone
        ldx #msg_diskrom
        ldu #test_diskrom
        jsr runone
        ldx #msg_vecpage
        ldu #test_vector_page
        jsr runone
        ldx #msg_sam_overlay
        ldu #test_sam_overlay
        jsr runone

        ; Keep related groups together and exercise the same paging path used
        ; automatically when a future test would enter the bottom prompt row.
        jsr nextpage

        ldx #group_video
        jsr plainline
        ldx #msg_screen
        ldu #test_screen
        jsr runone
        ldx #msg_video_regs
        ldu #test_video_regs
        jsr runone
        ldx #msg_palette
        ldu #test_palette
        jsr runone
        ldx #msg_display_ctl
        ldu #test_display_controls
        jsr runone
        ldx #msg_timer
        ldu #test_timer
        jsr runone
        ldx #msg_timer_irq
        ldu #test_timer_irq
        jsr runone
        ldx #msg_borders
        ldu #test_border_events
        jsr runone

        ldx #group_io
        jsr plainline
        ldx #msg_pia
        ldu #test_pia_registers
        jsr runone
        ldx #msg_audio
        ldu #test_audio
        jsr runone
        ldx #msg_fdc
        ldu #test_fdc
        jsr runone
        ldx #msg_serial
        ldu #test_serial
        jsr runone

        ldx #summary
        jsr beginline
        lda passcount
        jsr decimal2
        ldx #passed
        jsr printz
        lda failcount
        jsr decimal2
        ldx #failed
        jsr printz
        jsr endline

        lda testno
        sta $FF71
        clr $FF72
        lda passcount
        sta $FF73
        lda failcount
        sta $FF74
        lda #$53              ; final serial summary, written last
        sta $FF70
halt    bra halt

; Run the routine in U, print its description and result, and publish a UART
; result record.  Every diagnostic routine returns A=0 for PASS.
runone  inc testno
        pshs x,u
        jsr ,u
        sta lastresult
        puls x,u
        jsr beginline
        lda lastresult
        bne runfail
        inc passcount
        ldx #passmsg
        bra runprint
runfail inc failcount
        ldx #failmsg
runprint jsr printz
        jsr endline
        lda testno
        sta $FF71
        lda lastresult
        sta $FF72
        lda passcount
        sta $FF73
        lda failcount
        sta $FF74
        lda #$44              ; per-test serial record, written last
        sta $FF70
        rts

plainline
        jsr beginline
        jsr endline
        rts
blankline
        jsr endline
        rts

; X points to a zero-terminated string.  All visible lines begin in column 10.
beginline
        pshs x
        ldx lineptr
        cmpx #PROMPT_ROW
        blo line_room
        jsr nextpage
line_room
        puls x
        ldy lineptr
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

; Reserve the bottom row for a deterministic page prompt.  Keyboard row 7 is
; ignored because it also carries the analog joystick comparator; rows 0..6
; cover the normal keyboard.  Requiring release/press/release prevents the key
; that launched the diagnostic from skipping the report page.
nextpage
        ldy #PROMPT_ROW
        ldb #10
pageindent
        lda #' '
        sta ,y+
        decb
        bne pageindent
        ldx #pageprompt
        jsr printz
        lda #$45              ; page-wait telemetry marker
        sta $FF70
        jsr keyboard_setup
wait_release
        clr $FF02
        lda $FF00
        ora #$80
        cmpa #$FF
        bne wait_release
wait_press
        clr $FF02
        lda $FF00
        ora #$80
        cmpa #$FF
        beq wait_press
wait_key_up
        clr $FF02
        lda $FF00
        ora #$80
        cmpa #$FF
        bne wait_key_up
        jsr clearscreen
        ldy #SCREEN
        ldb #10
contindent
        lda #' '
        sta ,y+
        decb
        bne contindent
        ldx #continued
        jsr printz
        ldd #SCREEN+160        ; title plus one blank line
        std lineptr
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

clearscreen
        ldx #SCREEN
        lda #' '
clear_screen_loop
        sta ,x+
        cmpx #SCREEN_END
        blo clear_screen_loop
        rts

endline ldd lineptr
        addd #80
        std lineptr
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

; --------------------------------------------------------------------------
; CPU and memory

test_cpu
        ldd #$1234
        addd #$4321
        cmpd #$5555
        lbne bad
        lda #25
        ldb #10
        mul
        cmpd #250
        lbne bad
        ldx #cpu_operand
        ldd 1,x
        cmpd #$3456
        lbne bad
        lda #$5A
        pshs a
        clra
        puls a
        cmpa #$5A
        lbne bad
        lda #$FF
        inca
        lbne bad
        clra
        rts

test_cpu_registers
        tfr dp,a
        sta saved_dp
        lda $7D00
        sta saved_direct
        clr work
        lda #$7D
        tfr a,dp
        lda #$A6
        sta <$00
        cmpa <$00
        bne cpu_regs_bad
        ldx #$1234
        ldy #$ABCD
        exg x,y
        cmpx #$ABCD
        bne cpu_regs_bad
        cmpy #$1234
        beq cpu_regs_restore
cpu_regs_bad
        inc work
cpu_regs_restore
        lda saved_direct
        sta <$00
        lda saved_dp
        tfr a,dp
        lda work
        rts

test_ram
        ldd $5000
        std savedram
        clr work
        ldd #$55AA
        std $5000
        cmpd $5000
        beq ram2
        inc work
ram2    ldd #$AA55
        std $5000
        cmpd $5000
        beq ramdone
        inc work
ramdone ldd savedram
        std $5000
        lda work
        rts

test_mmu_regs
        lda $FF91
        anda #1
        beq mmu_inactive1
        ldx #$FFA0
        bra mmu_base
mmu_inactive1
        ldx #$FFA8
mmu_base
        stx mmubase
        ldy #mmusave
        ldb #8
mmusave_loop
        lda ,x+
        sta ,y+
        decb
        bne mmusave_loop
        ldx mmubase
        ldb #8
        lda #$25
        sta pattern
mmuwrite
        lda pattern
        sta ,x+
        adda #7
        sta pattern
        decb
        bne mmuwrite
        clr work
        ldx mmubase
        ldb #8
        lda #$25
        sta pattern
mmuverify
        lda ,x+
        cmpa pattern
        beq mmu_next
        inc work
mmu_next
        lda pattern
        adda #7
        sta pattern
        decb
        bne mmuverify
        ldx mmubase
        ldy #mmusave
        ldb #8
mmurestore
        lda ,y+
        sta ,x+
        decb
        bne mmurestore
        lda work
        rts

test_mmu_banks
        lda $FFA2
        sta savemap2
        lda $FFA3
        sta savemap3
        clr $FF91
        lda #$3B              ; keep code and stack on physical page B
        sta $FFA3
        lda #$3C
        sta $FFA2
        lda #$40
        sta $FF90
        lda $4000
        sta savebankc
        lda #$A5
        sta $4000
        lda #$3D
        sta $FFA2
        lda $4000
        sta savebankd
        lda #$5A
        sta $4000
        clr work
        cmpa $4000
        beq bankc
        inc work
bankc   lda #$3C
        sta $FFA2
        lda $4000
        cmpa #$A5
        beq bankrestore
        inc work
bankrestore
        lda savebankc
        sta $4000
        lda #$3D
        sta $FFA2
        lda savebankd
        sta $4000
        clr $FF90
        lda savemap2
        sta $FFA2
        lda savemap3
        sta $FFA3
        lda work
        rts

test_mmu_tasks
        lda $FF90
        sta saveinit0
        lda $FF91
        sta saveinit1
        lda $FFA2
        sta savemap2
        lda $FFAA
        sta savemap2_task1
        lda $FFA3
        sta savemap3
        lda $FFAB
        sta savemap3_task1
        lda saveinit1
        anda #$FE
        sta $FF91
        lda #$3B
        sta $FFA3
        sta $FFAB
        lda #$3C
        sta $FFA2
        lda #$3D
        sta $FFAA
        lda saveinit0
        ora #$40
        sta $FF90
        lda $5001
        sta savebankc
        lda #$C3
        sta $5001
        lda $FF91
        ora #1
        sta $FF91
        lda $5001
        sta savebankd
        lda #$D4
        sta $5001
        clr work
        cmpa $5001
        beq task_check_zero
        inc work
task_check_zero
        lda $FF91
        anda #$FE
        sta $FF91
        lda $5001
        cmpa #$C3
        beq task_restore
        inc work
task_restore
        lda savebankc
        sta $5001
        lda $FF91
        ora #1
        sta $FF91
        lda savebankd
        sta $5001
        lda $FF91
        anda #$FE
        sta $FF91
        lda saveinit0
        anda #$BF              ; restore mappings with translation disabled
        sta $FF90
        lda savemap2
        sta $FFA2
        lda savemap2_task1
        sta $FFAA
        lda savemap3
        sta $FFA3
        lda savemap3_task1
        sta $FFAB
        lda saveinit1
        sta $FF91
        lda saveinit0
        sta $FF90
        lda work
        rts

; --------------------------------------------------------------------------
; ROM and vectors

test_vectors
        ldd $FFFE
        cmpd #$8C1B
        lbne bad
        ldx #$FFF2
        ldb #7
vector_loop
        lda ,x
        lbpl bad
        leax 2,x
        decb
        bne vector_loop
        clra
        rts

test_romprotect
        lda $FFFF
        sta savedbyte
        coma
        sta $FFFF
        lda $FFFF
        cmpa savedbyte
        lbne bad
        clra
        rts

test_diskrom
        ldx #$8000
        ldu #$2000
        clra
        clrb
romsum  addb ,x+
        adca #0
        leau -1,u
        cmpu #0
        bne romsum
        cmpd #$0CD9          ; Extended Color BASIC 2.0
        bne rombad
        ldx #$A000
        ldu #$2000
        clra
        clrb
romsum2 addb ,x+
        adca #0
        leau -1,u
        cmpu #0
        bne romsum2
        cmpd #$9684          ; Color BASIC 2.0
        bne rombad
        ldx #$C000
        ldu #$2000
        clra
        clrb
romsum3 addb ,x+
        adca #0
        leau -1,u
        cmpu #0
        bne romsum3
        cmpd #$E038          ; Disk Extended Color BASIC 1.1
        bne rombad
        ldx #$E000
        ldu #$1E00
        clra
        clrb
romsum4 addb ,x+
        adca #0
        leau -1,u
        cmpu #0
        bne romsum4
        cmpd #$77F4          ; selected Super Extended BASIC image
        bne rombad
        clra
        rts
rombad  lda #1
        rts

test_vector_page
        lda $FFA3
        sta savemap3
        lda $FFA7
        sta savemap7
        lda #$3B
        sta $FFA3
        lda #$3E
        sta $FFA7
        lda #$40             ; MMU page 7 at $FE00
        sta $FF90
        lda $FE00
        sta savevecmap
        lda #$48             ; fixed page $3F at $FE00
        sta $FF90
        lda $FE00
        sta savevecfix
        lda #$A5
        sta $FE00
        cmpa $FE00
        bne vecbad
        lda #$40
        sta $FF90
        lda #$5A
        sta $FE00
        cmpa $FE00
        bne vecbad
        lda #$48
        sta $FF90
        lda $FE00
        cmpa #$A5
        bne vecbad
        clr work
        bra vecrestore
vecbad  lda #1
        sta work
vecrestore
        lda savevecfix
        sta $FE00
        lda #$40
        sta $FF90
        lda savevecmap
        sta $FE00
        clr $FF90
        lda savemap3
        sta $FFA3
        lda savemap7
        sta $FFA7
        lda work
        rts

test_sam_overlay
        sta $FFDE              ; begin with internal ROM selected
        lda $C000
        sta saved_rom_byte
        sta $FFDF              ; expose all RAM beneath the ROM window
        lda $C000
        sta saved_overlay_byte
        eora #$A5
        sta overlay_pattern
        sta $C000
        clr work
        cmpa $C000
        bne sam_overlay_bad
        sta $FFDE
        lda $C000
        cmpa saved_rom_byte
        beq sam_overlay_restore
sam_overlay_bad
        inc work
sam_overlay_restore
        sta $FFDF
        lda saved_overlay_byte
        sta $C000
        sta $FFDE
        lda work
        rts

; --------------------------------------------------------------------------
; Native video and 1987 GIME

test_screen
        lda $27CF
        sta savedbyte
        lda #$A5
        sta $27CF
        cmpa $27CF
        bne screenbad
        clr work
        bra screenrestore
screenbad
        lda #1
        sta work
screenrestore
        lda savedbyte
        sta $27CF
        lda work
        rts

test_video_regs
        lda $FF98
        cmpa #$03
        lbne bad
        lda $FF99
        cmpa #$34
        lbne bad
        ldd $FF9D
        cmpd #$E400
        lbne bad
        clra
        rts

test_palette
        ldx #$FFB0
        ldy #palettesave
        ldb #16
palsave lda ,x+
        sta ,y+
        decb
        bne palsave
        ldx #$FFB0
        ldb #16
        lda #3
        sta pattern
palwrite
        lda pattern
        ora #$C0             ; upper bits must be discarded
        sta ,x+
        lda pattern
        adda #5
        anda #$3F
        sta pattern
        decb
        bne palwrite
        clr work
        ldx #$FFB0
        ldb #16
        lda #3
        sta pattern
palcheck
        lda ,x+
        cmpa pattern
        beq palnext
        inc work
palnext lda pattern
        adda #5
        anda #$3F
        sta pattern
        decb
        bne palcheck
        ldx #$FFB0
        ldy #palettesave
        ldb #16
palrestore
        lda ,y+
        sta ,x+
        decb
        bne palrestore
        lda work
        rts

test_display_controls
        lda $FF9A
        sta saveborder
        lda #$15
        sta $FF9A
        lda #$0F
        sta $FF9C
        lda #$85
        sta $FF9F
        clr work
        lda $FF9A
        cmpa #$15
        bne displaybad
        lda $FF9C
        cmpa #$0F
        bne displaybad
        lda $FF9F
        cmpa #$85
        beq displayrestore
displaybad
        inc work
displayrestore
        clr $FF9C
        clr $FF9F
        lda saveborder
        sta $FF9A
        lda work
        rts

test_timer
        lda #$20              ; fast timer source, master FIRQ remains off
        sta $FF91
        lda #$20
        sta $FF93
        lda $FF93             ; acknowledge stale events
        lda #1
        sta $FF95
        clr $FF94             ; 1987 value 1 expires on its second tick
        ldx #$4000
timerwait
        lda $FF93
        bita #$20
        bne timergot
        leax -1,x
        cmpx #0
        bne timerwait
        lda #1
        sta work
        bra timerstop
timergot
        clr work
timerstop
        clr $FF95
        clr $FF94
        clr $FF91
        lda work
        rts

test_timer_irq
        lda $FF90
        sta saveinit0
        lda $FF91
        sta saveinit1
        ora #$20              ; fast timer source
        sta $FF91
        lda saveinit0
        ora #$20              ; master IRQ enable while CPU IRQ stays masked
        sta $FF90
        lda #$20
        sta $FF92
        lda $FF92             ; acknowledge stale IRQ status
        lda #1
        sta $FF95
        clr $FF94
        ldx #$4000
timer_irq_wait
        lda $FF92
        bita #$20
        bne timer_irq_seen
        leax -1,x
        cmpx #0
        bne timer_irq_wait
        lda #1
        sta work
        bra timer_irq_restore
timer_irq_seen
        lda #$FF              ; prevent a fast periodic event from reasserting
        sta $FF95
        lda #$0F
        sta $FF94
        ldx #8                ; allow the registered bus/status pipeline to retire
timer_irq_clear_wait
        lda $FF92
        bita #$20
        beq timer_irq_clear
        leax -1,x
        cmpx #0
        bne timer_irq_clear_wait
        lda #2
        sta work
        bra timer_irq_restore
timer_irq_clear
        clr work
timer_irq_restore
        clr $FF92
        clr $FF95
        clr $FF94
        lda saveinit1
        sta $FF91
        lda saveinit0
        sta $FF90
        lda work
        rts

test_border_events
        lda #$18
        sta $FF93
        lda $FF93
        clr eventseen
        ldx #$FFFF
eventwait
        lda $FF93
        anda #$18
        ora eventseen
        sta eventseen
        cmpa #$18
        beq eventgot
        leax -1,x
        cmpx #0
        bne eventwait
        lda #1
        rts
eventgot
        clra
        rts

; --------------------------------------------------------------------------
; Audio, storage and serial-visible control paths

test_pia_registers
        lda $FF21
        sta savep1cra
        lda $FF23
        sta savep1crb
        anda #$FB
        sta $FF23
        lda $FF22
        sta savep1ddrb
        lda savep1cra
        anda #$FB
        sta $FF21
        lda $FF20
        sta savep1ddra
        lda #$A5
        sta $FF20
        lda #$5A
        sta $FF22
        clr work
        lda $FF20
        cmpa #$A5
        bne pia_register_bad
        lda $FF22
        cmpa #$5A
        beq pia_register_restore
pia_register_bad
        inc work
pia_register_restore
        lda savep1ddra
        sta $FF20
        lda savep1ddrb
        sta $FF22
        lda savep1cra
        sta $FF21
        lda savep1crb
        sta $FF23
        lda work
        rts

test_audio
        lda $FF21
        sta savep1cra
        lda $FF23
        sta savep1crb
        lda $FF01
        sta savep0cra
        lda $FF03
        sta savep0crb
        anda #$F7
        sta $FF03
        lda savep0cra
        anda #$F7
        sta $FF01             ; joystick selector 00 routes DAC writes
        lda savep1cra
        anda #$FB
        sta $FF21
        lda $FF20
        sta savep1ddra
        lda #$FF
        sta $FF20
        lda savep1cra
        ora #$04
        sta $FF21
        lda savep1crb
        ora #$08
        sta $FF23
        lda #$A8
        sta $FF20
        cmpa $FF20
        bne audiobad
        clr work
        bra audiorestore
audiobad
        lda #1
        sta work
audiorestore
        lda #$80              ; leave the held six-bit DAC at midpoint
        sta $FF20
        lda savep1cra
        anda #$FB
        sta $FF21
        lda savep1ddra
        sta $FF20
        lda savep1cra
        sta $FF21
        lda savep1crb
        sta $FF23
        lda savep0cra
        sta $FF01
        lda savep0crb
        sta $FF03
        lda work
        rts

test_fdc
        clr $FF48              ; non-destructive RESTORE also aborts stale I/O
        lda $FF40
        sta savefdc0
        lda $FF49
        sta savefdc1
        lda $FF4A
        sta savefdc2
        lda $FF4B
        sta savefdc3
        clr work
        lda #$05
        sta $FF40
        cmpa $FF40
        bne fdcbad
        lda #$12
        sta $FF49
        cmpa $FF49
        bne fdcbad
        lda #$07
        sta $FF4A
        cmpa $FF4A
        bne fdcbad
        lda #$A5
        sta $FF4B
        cmpa $FF4B
        beq fdcrestore
fdcbad  inc work
fdcrestore
        lda savefdc0
        sta $FF40
        lda savefdc1
        sta $FF49
        lda savefdc2
        sta $FF4A
        lda savefdc3
        sta $FF4B
        lda work
        rts

test_serial
        lda #$A5
        sta $FF75
        lda #$5A
        sta $FF76
        lda #$87
        sta $FF77
        clra                    ; HDL/UART capture validates the emitted bytes
        rts

bad     lda #1
        rts

; Text is deliberately mixed case to exercise both native character sets.
title       fcc "CoCo 3 Elite automated diagnostics"
            fcb 0
subtitle    fcc "1987 GIME target - one result per test"
            fcb 0
continued   fcc "CoCo 3 Elite diagnostics - continued"
            fcb 0
pageprompt  fcc "Press any key for the next page"
            fcb 0
group_cpu   fcc "CPU and memory"
            fcb 0
msg_cpu     fcc "CPU arithmetic, indexed and stack .......... "
            fcb 0
msg_cpu_regs fcc "Direct page and register exchange .......... "
            fcb 0
msg_ram     fcc "Base RAM pattern storage ................... "
            fcb 0
msg_mmu_regs fcc "Inactive MMU task registers ................ "
            fcb 0
msg_mmu_banks fcc "MMU bank mapping and isolation ............. "
            fcb 0
msg_mmu_tasks fcc "MMU task zero and task one switching ....... "
            fcb 0
group_rom   fcc "System ROM and vectors"
            fcb 0
msg_vectors fcc "Reset and hardware vectors ................. "
            fcb 0
msg_romprotect fcc "System ROM write protection ................ "
            fcb 0
msg_diskrom fcc "System and Disk BASIC ROM images ........... "
            fcb 0
msg_vecpage fcc "GIME fixed and mapped vector pages ......... "
            fcb 0
msg_sam_overlay fcc "SAM ROM and all-RAM overlay ................ "
            fcb 0
group_video fcc "Video and GIME"
            fcb 0
msg_screen  fcc "80-column display memory ................... "
            fcb 0
msg_video_regs fcc "Native text mode and display start ......... "
            fcb 0
msg_palette fcc "Palette RAM and six-bit masking ............ "
            fcb 0
msg_display_ctl fcc "Border, scroll and HVEN registers .......... "
            fcb 0
msg_timer   fcc "1987 GIME timer expiry and status .......... "
            fcb 0
msg_timer_irq fcc "GIME IRQ timer and read-to-clear status .... "
            fcb 0
msg_borders fcc "Horizontal and vertical border events ...... "
            fcb 0
group_io    fcc "Audio, storage and serial"
            fcb 0
msg_pia     fcc "PIA data-direction register readback ....... "
            fcb 0
msg_audio   fcc "PIA audio DAC control latch ................ "
            fcb 0
msg_fdc     fcc "FDC control and data registers ............. "
            fcb 0
msg_serial  fcc "Serial telemetry pattern emitted ........... "
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
cpu_operand fcb $12,$34,$56

lineptr     fdb SCREEN
testno      fcb 0
passcount   fcb 0
failcount   fcb 0
lastresult  fcb 0
work        fcb 0
pattern     fcb 0
eventseen   fcb 0
savedram    fdb 0
savedbyte   fcb 0
mmubase     fdb 0
mmusave     rmb 8
palettesave rmb 16
savemap2    fcb 0
savemap3    fcb 0
savemap7    fcb 0
savebankc   fcb 0
savebankd   fcb 0
savemap2_task1 fcb 0
savemap3_task1 fcb 0
saveinit0   fcb 0
saveinit1   fcb 0
saved_dp    fcb 0
saved_direct fcb 0
saved_rom_byte fcb 0
saved_overlay_byte fcb 0
overlay_pattern fcb 0
savevecmap  fcb 0
savevecfix  fcb 0
saveborder  fcb 0
savep1cra   fcb 0
savep1crb   fcb 0
savep0cra   fcb 0
savep0crb   fcb 0
savep1ddra  fcb 0
savep1ddrb  fcb 0
savefdc0    fcb 0
savefdc1    fcb 0
savefdc2    fcb 0
savefdc3    fcb 0

        end entry
