#include "settings_ui.h"

#define REG32(a) (*(volatile uint32_t *)(a))
#define OSD_ADDRESS REG32(0x8000024cu)
#define OSD_DATA REG32(0x80000250u)
#define OSD_CONTROL REG32(0x80000254u)
#define MENU_KEY_STATE REG32(0x80000258u)
#define OSD_FONT_STYLE REG32(0x80000278u)
#define VIDEO_SETTINGS REG32(0x8000027cu)
#define TEXT_SETTINGS REG32(0x80000280u)
#define SERIAL_MACHINE_CONTROL REG32(0x80000294u)

#define KEY_F12 1u
#define KEY_UP 2u
#define KEY_DOWN 4u
#define KEY_ENTER 8u
#define KEY_ESCAPE 16u
#define KEY_F11 32u
#define KEY_LEFT 64u
#define KEY_RIGHT 128u
#define KEY_TAB 256u
#define KEY_CONTROL 512u

#define COLS 72u
#define ROWS 28u
#define CATEGORIES 8u
#define MAX_OPTIONS 5u
#define CATEGORY_FIRST_ROW 5u
#define CATEGORY_DIVIDER 25u

#define GLYPH_HLINE 0x90u
#define GLYPH_VLINE 0x91u
#define GLYPH_TOP_LEFT 0x92u
#define GLYPH_TOP_RIGHT 0x93u
#define GLYPH_BOTTOM_LEFT 0x94u
#define GLYPH_BOTTOM_RIGHT 0x95u
#define GLYPH_T_DOWN 0x98u
#define GLYPH_T_UP 0x99u
#define GLYPH_LEFT_BORDER 0x9au
#define GLYPH_RIGHT_BORDER 0x9bu
#define GLYPH_RULE_LEFT_CAP 0x9cu
#define GLYPH_RULE_RIGHT_CAP 0x9du
#define GLYPH_LOGO_RED 0x9eu
#define GLYPH_LOGO_GREEN 0x9fu
#define GLYPH_LOGO_BLUE 0xa0u
#define GLYPH_ARROW_LEFT 0xa1u
#define GLYPH_ARROW_RIGHT 0xa2u

struct setup_item { const char *label; const char *value; };

static const char *category[CATEGORIES] = {
    "Audio", "Video", "Joystick", "Cassette",
    "Floppy", "Cartridge", "Serial", "Ethernet"
};
static const char *font_name[3] = { "Spleen", "Tamzen", "Terminus" };
static const char *artifact_mode_name[6] = {
    "Off", "Thin", "Classic", "MAME", "XRoar", "Two pass"
};
static const char *artifact_color_name[4] = {
    "Blue/orange", "Cyan/red", "Green/magenta", "Violet/lime"
};
static const char *coco2_palette_name[16] = {
    "Original", "Base", "C64", "Atari",
    "CGA", "Earth", "Amber", "Cool adv.",
    "CoCo art.", "Forest", "Fire", "Ice",
    "Purple dusk", "Game Boy", "Ocean/sunset", "Grayscale"
};
static const char *text_theme_name[10] = {
    "Original", "C64", "Atari", "VT100", "VT220 amber",
    "VT220 green", "IBM", "Apple II", "Amstrad", "Paperwhite"
};

static const struct setup_item page[CATEGORIES][MAX_OPTIONS] = {
    {{"Volume", "Fixed"}, {"Disk sounds", "On"},
     {"Tape playthrough", "Planned"}, {"Future audio", "Planned"}, {"", ""}},
    {{"Font", ""}, {"Artifact style", ""},
     {"Artifact model", ""}, {"CoCo 2 palette", ""}, {"Text colors", ""}},
    {{"Left keyboard", "F8"}, {"Right keyboard", "F7"},
     {"Physical ports", "Enabled"}, {"Autofire", "Planned"}, {"", ""}},
    {{"Input source", "Planned"}, {"Playthrough", "Planned"},
     {"Motor sense", "Planned"}, {"Image files", "Planned"}, {"", ""}},
    {{"Drive 0", "SD image"}, {"Write support", "Enabled"},
     {"Drives 1-2", "Planned"}, {"Shugart drive", "Planned"}, {"", ""}},
    {{"8K CCC", "Enabled"}, {"Cold start", "Enabled"},
     {"Banked carts", "Planned"}, {"Hardware slot", "Planned"}, {"", ""}},
    {{"Debug UART", "Enabled"}, {"Baud rate", "115200"},
     {"File transfer", "Planned"}, {"Flow control", "None"}, {"", ""}},
    {{"Adapter", "Planned"}, {"DHCP", "Planned"},
     {"File service", "Planned"}, {"Remote console", "Planned"}, {"", ""}}
};

static uint8_t option_count(uint8_t category_index){
    return category_index==1u?5u:4u;
}

static void character(uint8_t row,uint8_t column,uint8_t value){
    OSD_ADDRESS=(uint32_t)row*COLS+column;OSD_DATA=value;
}
static void text(uint8_t row,uint8_t column,const char *value){
    OSD_ADDRESS=(uint32_t)row*COLS+column;
    while(*value&&column<COLS-1u){OSD_DATA=(uint8_t)*value++;column++;}
}
static void center(uint8_t row,const char *value){
    uint8_t length=0;while(value[length])length++;
    text(row,(uint8_t)((COLS-length)/2u),value);
}
static void clear(void){
    OSD_ADDRESS=0;for(uint16_t n=0;n<COLS*ROWS;n++)OSD_DATA=' ';
}
static void logo(uint8_t row){
    const uint8_t left=(COLS-16u)/2u;
    text(row,left,"CoCo 3");character(row,left+7u,GLYPH_LOGO_RED);
    character(row,left+8u,GLYPH_LOGO_GREEN);character(row,left+9u,GLYPH_LOGO_BLUE);
    text(row,left+11u,"Elite");
}
static void outer_rule(uint8_t row,uint8_t left,uint8_t right){
    character(row,0,left);
    for(uint8_t column=1;column<COLS-1u;column++)character(row,column,GLYPH_HLINE);
    character(row,COLS-1u,right);
}
static void inner_rule(uint8_t row,uint8_t middle){
    character(row,1,GLYPH_RULE_LEFT_CAP);
    for(uint8_t column=2;column<COLS-2u;column++)character(row,column,GLYPH_HLINE);
    character(row,COLS-2u,GLYPH_RULE_RIGHT_CAP);
    if(middle)character(row,CATEGORY_DIVIDER,middle);
}
static void frame(void){
    for(uint8_t row=1;row<ROWS-1u;row++){
        character(row,0,GLYPH_LEFT_BORDER);character(row,COLS-1u,GLYPH_RIGHT_BORDER);
    }
    for(uint8_t row=4;row<24u;row++)character(row,CATEGORY_DIVIDER,GLYPH_VLINE);
    outer_rule(0,GLYPH_TOP_LEFT,GLYPH_TOP_RIGHT);inner_rule(3,GLYPH_T_DOWN);
    inner_rule(24,GLYPH_T_UP);outer_rule(ROWS-1u,GLYPH_BOTTOM_LEFT,GLYPH_BOTTOM_RIGHT);
}
static uint8_t option_value(uint8_t item,uint8_t font,uint8_t artifact_mode,
                            uint8_t artifact_color,uint8_t coco2_palette,
                            uint8_t text_theme){
    if(item==0u)return font;if(item==1u)return artifact_mode;
    if(item==2u)return artifact_color;if(item==3u)return coco2_palette;
    return text_theme;
}
static const char *video_value(uint8_t item,uint8_t font,uint8_t artifact_mode,
                               uint8_t artifact_color,uint8_t coco2_palette,
                               uint8_t text_theme){
    if(item==0u)return font_name[font];
    if(item==1u)return artifact_mode_name[artifact_mode];
    if(item==2u)return artifact_color_name[artifact_color];
    if(item==3u)return coco2_palette_name[coco2_palette];
    return text_theme_name[text_theme];
}
static void write_video(uint8_t font,uint8_t artifact_mode,
                        uint8_t artifact_color,uint8_t coco2_palette,
                        uint8_t text_theme){
    OSD_FONT_STYLE=font;
    /* Bits 1:0 and 7 select the decoder style. Bits 3:2 select the
       artifact model. CoCo 2 palette bits are 6:4 plus bit 8. */
    VIDEO_SETTINGS=((uint32_t)artifact_mode&3u)|
                   ((uint32_t)artifact_color<<2)|
                   (((uint32_t)coco2_palette&7u)<<4)|
                   (((uint32_t)artifact_mode&4u)<<5)|
                   (((uint32_t)coco2_palette&8u)<<5);
    TEXT_SETTINGS=text_theme;
}
static void draw(uint8_t category_index,uint8_t option_index,uint8_t option_pane,
                 uint8_t editing,uint8_t font,uint8_t artifact_mode,
                 uint8_t artifact_color,uint8_t coco2_palette,
                 uint8_t text_theme){
    write_video(font,artifact_mode,artifact_color,coco2_palette,text_theme);
    clear();frame();logo(1);center(2,"Settings");
    for(uint8_t item=0;item<CATEGORIES;item++)
        text((uint8_t)(CATEGORY_FIRST_ROW+item),3,category[item]);
    text(4,29,category[category_index]);
    for(uint8_t item=0;item<option_count(category_index);item++){
        uint8_t row=(uint8_t)(6u+item*2u);
        text(row,29,page[category_index][item].label);
        if(category_index==1u){
            character(row,55,GLYPH_ARROW_LEFT);
            text(row,58,video_value(item,font,artifact_mode,artifact_color,
                                    coco2_palette,text_theme));
            character(row,70,GLYPH_ARROW_RIGHT);
        }else text(row,58,page[category_index][item].value);
    }
    text(17,29,"Quick actions");text(19,29,"Soft power   Hard reset");
    text(20,29,"Reboot       Ctrl+Esc");
    if(editing)text(25,2,"Editing: left/right preview, Enter apply, Esc cancel");
    else if(option_pane)text(25,2,"Enter edit, Tab/left categories, up/down option");
    else text(25,2,"Tab/right/Enter settings, up/down category");
    center(26,"F11/F12 exit   Ctrl+Esc hard reset");
    if(option_pane)OSD_CONTROL=((uint32_t)(6u+option_index*2u)<<8)|5u;
    else OSD_CONTROL=((uint32_t)(CATEGORY_FIRST_ROW+category_index)<<8)|3u;
}
static uint8_t cycle_value(uint8_t item,uint8_t value,uint8_t forward){
    uint8_t count=(item==0u)?3u:((item==1u)?6u:
                  ((item==3u)?16u:((item==4u)?10u:4u)));
    if(forward)return (uint8_t)((value+1u==count)?0u:value+1u);
    return value?(uint8_t)(value-1u):(uint8_t)(count-1u);
}

void settings_ui_run(void){
    /* The management CPU keeps running while the CoCo and OSD are active, so
       menu position can persist between openings without nonvolatile state. */
    static uint8_t saved_category_index=0;
    static uint8_t saved_option_index=0;
    static uint8_t saved_option_pane=0;
    uint8_t category_index=saved_category_index;
    uint8_t option_index=saved_option_index;
    uint8_t option_pane=saved_option_pane;
    uint8_t editing=0,original=0;
    uint8_t font=(uint8_t)(OSD_FONT_STYLE&3u);
    uint32_t video=VIDEO_SETTINGS;
    uint8_t artifact_mode=(uint8_t)((video&3u)|((video>>5)&4u));
    uint8_t artifact_color=(uint8_t)((video>>2)&3u);
    uint8_t coco2_palette=(uint8_t)(((video>>4)&7u)|((video>>5)&8u));
    uint8_t text_theme=(uint8_t)(TEXT_SETTINGS&15u);
    uint32_t previous,keys,pressed;
    if(artifact_mode>5u)artifact_mode=1u;
    if(font>2u)font=1u;
    if(text_theme>9u)text_theme=0u;
    draw(category_index,option_index,option_pane,editing,font,artifact_mode,
         artifact_color,coco2_palette,text_theme);
    while(MENU_KEY_STATE&KEY_F11){}
    previous=MENU_KEY_STATE;
    for(;;){
        keys=MENU_KEY_STATE;pressed=keys&~previous;previous=keys;
        /* Give the reset chord priority over Escape's edit-cancel and menu
           close actions.  The manager reset register cold-resets only the
           CoCo; SD service, mounted-disk state, and this firmware survive. */
        if((keys&(KEY_CONTROL|KEY_ESCAPE))==(KEY_CONTROL|KEY_ESCAPE)&&
           (pressed&(KEY_CONTROL|KEY_ESCAPE))){
            saved_category_index=category_index;
            saved_option_index=option_index;
            saved_option_pane=option_pane;
            OSD_CONTROL=0;
            SERIAL_MACHINE_CONTROL=3u;
            return;
        }
        if(editing&&(pressed&KEY_ESCAPE)){
            if(option_index==0u)font=original;
            else if(option_index==1u)artifact_mode=original;
            else if(option_index==2u)artifact_color=original;
            else if(option_index==3u)coco2_palette=original;
            else text_theme=original;
            editing=0;
            draw(category_index,option_index,option_pane,editing,font,artifact_mode,
                 artifact_color,coco2_palette,text_theme);continue;
        }
        if(!editing&&(pressed&(KEY_ESCAPE|KEY_F11|KEY_F12))){
            while(MENU_KEY_STATE&(KEY_ESCAPE|KEY_F11|KEY_F12)){}
            saved_category_index=category_index;
            saved_option_index=option_index;
            saved_option_pane=option_pane;
            OSD_CONTROL=0;return;
        }
        if(editing){
            uint8_t value=option_value(option_index,font,artifact_mode,
                                       artifact_color,coco2_palette,text_theme);
            if(pressed&KEY_LEFT)value=cycle_value(option_index,value,0);
            if(pressed&KEY_RIGHT)value=cycle_value(option_index,value,1);
            if(option_index==0u)font=value;
            else if(option_index==1u)artifact_mode=value;
            else if(option_index==2u)artifact_color=value;
            else if(option_index==3u)coco2_palette=value;
            else text_theme=value;
            if(pressed&KEY_ENTER)editing=0;
            if(pressed&(KEY_LEFT|KEY_RIGHT|KEY_ENTER))
                draw(category_index,option_index,option_pane,editing,font,
                     artifact_mode,artifact_color,coco2_palette,text_theme);
            continue;
        }
        if(pressed&KEY_TAB)option_pane=(uint8_t)!option_pane;
        if(!option_pane){
            if(pressed&KEY_UP)category_index=category_index?category_index-1u:CATEGORIES-1u;
            if(pressed&KEY_DOWN)category_index=(category_index+1u==CATEGORIES)?0u:category_index+1u;
            if(option_index>=option_count(category_index))
                option_index=(uint8_t)(option_count(category_index)-1u);
            if(pressed&(KEY_RIGHT|KEY_ENTER)){option_pane=1;option_index=0;}
        }else{
            uint8_t count=option_count(category_index);
            if(pressed&KEY_UP)option_index=option_index?option_index-1u:count-1u;
            if(pressed&KEY_DOWN)option_index=(option_index+1u==count)?0u:option_index+1u;
            if(pressed&KEY_LEFT)option_pane=0;
            if((pressed&(KEY_ENTER|KEY_RIGHT))&&category_index==1u){
                original=option_value(option_index,font,artifact_mode,
                                      artifact_color,coco2_palette,text_theme);
                editing=1;
            }
        }
        if(pressed&(KEY_TAB|KEY_UP|KEY_DOWN|KEY_LEFT|KEY_RIGHT|KEY_ENTER))
            draw(category_index,option_index,option_pane,editing,font,
                 artifact_mode,artifact_color,coco2_palette,text_theme);
    }
}
