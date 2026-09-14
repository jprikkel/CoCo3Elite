#include "settings_ui.h"

#define REG32(a) (*(volatile uint32_t *)(a))
#define OSD_ADDRESS REG32(0x8000024cu)
#define OSD_DATA REG32(0x80000250u)
#define OSD_CONTROL REG32(0x80000254u)
#define POWER_CONTROL REG32(0x80000278u) /* bit0 soft power, bit1 hard reset, bit2 reboot */
#define MENU_KEY_STATE REG32(0x80000258u)
#define KEY_UP 2u
#define KEY_DOWN 4u
#define KEY_ENTER 8u
#define KEY_ESCAPE 16u
#define COLS 64u
#define ROWS 30u
#define CATEGORIES 8u
#define OPTIONS 45u

static const char *category[CATEGORIES] = {"Audio","Video","Joystick","Cassette","Floppy","Cartridge","Serial","Ethernet"};
static const char *option[OPTIONS] = {
 "Volume","Disk sounds","Tape playthru","Future audio chips",
 "Resolution","Scaling","Color artifacting","Status overlays","CRT filter",
 "Keyboard emulation","Swap joystick keys","Cycle joystick","Hardware source","Autofire","Autofire rate","Atari hardware","Classic analog",
 "Motor","Input source","Monitor/playthru","Relay polarity","Auto rewind",
 "Drive 0 source","Drive 1 source","Drive 2 source","Write protect","Disk sounds","Double density","Fast motor",
 "Cartridge image","Auto-launch","Cold reset on insert","ROM wait states",
 "Port mode","Baud rate","RX/TX routing","RTS/CTS","Invert signals",
 "Enable","DHCP","MAC address","IP address","Gateway","Network service"};
static const uint8_t first[CATEGORIES] = {0,4,9,16,21,29,33,38};
static const uint8_t last[CATEGORIES] = {3,8,15,20,28,32,37,44};
static uint8_t values[OPTIONS], staged[OPTIONS], cat, selected;

static void text(uint8_t row, uint8_t col, const char *s) { OSD_ADDRESS=(uint32_t)row*COLS+col; while(*s && col++<COLS) OSD_DATA=(uint8_t)*s++; }
static void clear(void) { OSD_ADDRESS=0; for(uint16_t i=0;i<COLS*ROWS;i++) OSD_DATA=' '; }
static void border(void) {
    OSD_ADDRESS=0; for(uint8_t x=0;x<COLS;x++) OSD_DATA=(x==0||x==COLS-1)?'+':'-';
    for(uint8_t y=1;y<ROWS-1;y++){OSD_ADDRESS=(uint32_t)y*COLS;OSD_DATA='|';OSD_ADDRESS=(uint32_t)y*COLS+COLS-1;OSD_DATA='|';}
    OSD_ADDRESS=(uint32_t)(ROWS-1)*COLS; for(uint8_t x=0;x<COLS;x++) OSD_DATA=(x==0||x==COLS-1)?'+':'-';
}
static void number(uint8_t row,uint8_t col,uint8_t n) { OSD_ADDRESS=(uint32_t)row*COLS+col; OSD_DATA=(uint8_t)('0'+n/10); OSD_DATA=(uint8_t)('0'+n%10); }
static void value_text(uint8_t row,uint8_t index) {
    uint8_t v=staged[index]; text(row,32,v==0?"OFF":v==1?"ON":v==2?"AUTO":"EDIT");
    if(index==0 || index==14) { number(row,40,v); text(row,42,index==0?"%":"Hz"); }
}
static void draw(void) {
    clear(); border(); text(1,19,"C O C O  3  E L I T E"); text(1,53,"SETTINGS"); text(2,3,"F12 EXIT");
    for(uint8_t c=0;c<CATEGORIES;c++){ text(4+c,2,c==cat?"> ":"  "); text(4+c,4,category[c]); }
    text(3,22,category[cat]);
    for(uint8_t i=first[cat],row=5;i<=last[cat] && row<25;i++,row++) { text(row,21,i==first[cat]+selected?"> ":"  "); text(row,23,option[i]); value_text(row,i); }
    text(26,2,"QUICK ACTIONS"); text(27,4,"[S] SOFT POWER   [H] HARD RESET   [R] REBOOT");
    text(28,2,"LEFT/RIGHT CATEGORY   UP/DOWN OPTION   ENTER EDIT");
    OSD_CONTROL=((uint32_t)(5+selected)<<8)|1u;
}
void settings_hw_read(uint8_t *v,uint16_t n){for(uint16_t i=0;i<n;i++)v[i]=0;} /* TODO: final RTL settings MMIO */
void settings_hw_write(const uint8_t *v,uint16_t n){(void)v;(void)n;} /* TODO: final RTL settings MMIO */
void settings_ui_run(void) {
    settings_hw_read(values,OPTIONS); for(uint8_t i=0;i<OPTIONS;i++) staged[i]=values[i];
    cat=0; selected=0; draw(); uint32_t previous=MENU_KEY_STATE;
    for(;;){ uint32_t now=MENU_KEY_STATE, pressed=now&~previous; previous=now;
        if(pressed&(KEY_ESCAPE|1u)){ OSD_CONTROL=0; return; }
        if(pressed&128u){ POWER_CONTROL=1u; } /* S: soft power */
        if(pressed&256u){ POWER_CONTROL=2u; } /* H: hard reset, confirmation belongs in key layer */
        if(pressed&512u){ POWER_CONTROL=4u; } /* R: reboot */
        if(pressed&KEY_UP){selected=selected?selected-1:last[cat]-first[cat];draw();}
        if(pressed&KEY_DOWN){selected=(selected==last[cat]-first[cat])?0:selected+1;draw();}
        if(pressed&KEY_ENTER){uint8_t i=first[cat]+selected;staged[i]=(staged[i]+1)&3;draw();}
        if(pressed&32u){if(cat)cat--;selected=0;draw();} /* left */
        if(pressed&64u){if(cat+1<CATEGORIES)cat++;selected=0;draw();} /* right */
    }
}
