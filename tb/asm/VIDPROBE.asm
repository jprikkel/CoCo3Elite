; Controlled native-text probe. No BASIC/ROM calls while mapping is changed.
; LOADM at $6000 after CLEAR 200,&H5FFF. Original BASIC is restored before RTS.
; Interface: $6003 case (1..6), $6004 error bits, $6005 completion marker $FE.
; Error bits: 1 register mismatch, 2 pattern mismatch, 4 unsafe entry mapping.
; $7000-$7FFF backs up the selected 4K screen area. Stack is below $6FFF.
; WAIT_COUNT and WAIT_OUTER supplied by build_video_probe.ps1.
        org $6000
        jmp entry
caseid  fcb 1
result  fcb 0
stage   fcb 0
entry   pshs cc,a,b,dp,x,y,u
        orcc #$50
        sts oldstack
        clr result
        clr stage
        lda $FF90
        sta oldinit
        bita #$40
        beq mapok
        ldb $FF91
        andb #1
        lslb
        lslb
        lslb
        ldx #$FFA3
        lda b,x
        anda #$0F
        cmpa #$0B
        beq mapok
        lda #4
        sta result
        lbra earlyexit
mapok   lda caseid
        cmpa #1
        lblo badcase
        cmpa #6
        lbhi badcase
        deca
        ldb #6
        mul
        ldx #cases
        leax d,x
        ldy #config
        ldb #6
cfgcopy lda ,x+
        sta ,y+
        decb
        bne cfgcopy
        ldx #$FF98
        ldy #oldvideo
        ldb #8
svvid   lda ,x+
        sta ,y+
        decb
        bne svvid
        ldx #$FFB0
        ldy #oldpal
        ldb #16
svpal   lda ,x+
        sta ,y+
        decb
        bne svpal
        lda $FF02
        sta oldcols
        lds #$6FFF
        ; Disable MMU only from its known fixed-map page. Code/stack stay put.
        clr $FF90
        sta $FFDE
        ldx base
        ldy #$7000
        ldu #4096
backup  lda ,x+
        sta ,y+
        leau -1,u
        cmpu #0
        bne backup
        ldx base
        lda #25
        sta rows
rowloop ldb columns
        lda #'A'
cell    sta ,x+
        tst attrs
        beq plain
        pshs a
        lda #$0A
        sta ,x+
        puls a
plain   inca
        cmpa #'Z'+1
        blo nowrap
        lda #'A'
nowrap  decb
        bne cell
        dec rows
        bne rowloop
        ; Verify the whole generated pattern independently before display.
        ldx base
        lda #25
        sta rows
vrow    ldb columns
        lda #'A'
vcell   cmpa ,x+
        bne badpattern
        tst attrs
        beq vplain
        pshs a
        lda ,x+
        cmpa #$0A
        puls a
        bne badpattern
vplain  inca
        cmpa #'Z'+1
        blo vnowrap
        lda #'A'
vnowrap decb
        bne vcell
        dec rows
        bne vrow
        bra setup
badpattern lda result
        ora #2
        sta result
setup   lda #3
        sta $FF98
        lda resolution
        sta $FF99
        ldd base
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        adda #$E0
        std offset
        std $FF9D
        tst clean
        beq palette
        clr $FF9B
        clr $FF9C
        clr $FF9F
palette clr $FF9A
        ; Contrasting entries for both attributed and non-attributed paths.
        lda #$12
        sta $FFB0
        clr $FFB1
        clr $FFB2
        sta $FFB9
        clr $FFBC
        sta $FFBD
        lda $FF90
        bne badregs
        lda $FF98
        cmpa #3
        bne badregs
        lda $FF99
        cmpa resolution
        bne badregs
        ldd $FF9D
        cmpd offset
        beq display
badregs lda result
        ora #1
        sta result
display lda #1
        sta stage
        ; Direct matrix scan with bounded timeout; no POLCAT or ROM calls.
        clr released
        clr $FF02
        ldu #WAIT_OUTER
waitouter ldy #WAIT_COUNT
waitkey lda $FF00
        anda #$7F
        cmpa #$7F
        bne pressed
        lda #1
        sta released
        bra tick
pressed tst released
        bne restore
tick    leay -1,y
        bne waitkey
        leau -1,u
        cmpu #0
        bne waitouter
restore ldx #$7000
        ldy base
        ldu #4096
unbackup lda ,x+
        sta ,y+
        leau -1,u
        cmpu #0
        bne unbackup
        ldx #oldvideo
        ldy #$FF98
        ldb #8
rsvid   lda ,x+
        sta ,y+
        decb
        bne rsvid
        ldx #oldpal
        ldy #$FFB0
        ldb #16
rspal   lda ,x+
        sta ,y+
        decb
        bne rspal
        lda oldcols
        sta $FF02
        ; Disk BASIC executes from its RAM copy. Never call its ROM version.
        sta $FFDF
        lda oldinit
        sta $FF90
earlyexit lda #$FE
        sta stage
        lds oldstack
        puls cc,a,b,dp,x,y,u,pc
badcase lda #4
        sta result
        lbra earlyexit
cases   fcb 40,0,$02,$00,$24,0
        fcb 40,0,$02,$00,$24,1
        fcb 40,1,$02,$00,$25,1
        fcb 80,0,$02,$00,$34,1
        fcb 32,0,$02,$00,$20,1
        fcb 40,0,$12,$00,$24,1
config
columns rmb 1
attrs   rmb 1
base    rmb 2
resolution rmb 1
clean   rmb 1
offset  rmb 2
rows    rmb 1
released rmb 1
oldstack rmb 2
oldinit rmb 1
oldcols rmb 1
oldvideo rmb 8
oldpal  rmb 16
        end entry
