; GIMEINIT - capture the untouched EXEC entry environment.
;
; Run this identical DECB binary both with LOADM/EXEC from a mounted DSK and
; directly from the SD management menu.  It records the entry state in the
; passive FF70-FF77 UART mailbox before changing the stack, interrupt masks,
; GIME registers, or BASIC workspace:
;
;   FF70  $49 ("I" signature, written last)
;   FF71  entry S high
;   FF72  entry S low
;   FF73  entry DP
;   FF74  entry CC
;   FF75  FF90 INIT0
;   FF76  FF91 INIT1
;   FF77  BASIC warm-start flag at $0071

        org $6000
entry   sts $FF71
        tfr dp,a
        sta $FF73
        tfr cc,a
        sta $FF74
        lda $FF90
        sta $FF75
        lda $FF91
        sta $FF76
        lda $0071
        sta $FF77
        lda #$49
        sta $FF70              ; publish only after all fields are complete
        orcc #$50
halt    bra halt

        end entry
