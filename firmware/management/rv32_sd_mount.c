#include <stdint.h>

// FAT32-to-DECB service for the RV32 manager.  The normal CoCo image never
// parses FAT or bit-bangs SPI: it reads the mounted cache directly and waits
// only when firmware flushes a completed write sector back to the DSK file.
#define REG32(a) (*(volatile uint32_t *)(a))
#define UART_DATA REG32(0x80000000u)
#define UART_STATUS REG32(0x80000004u)
#define SPI_CTRL REG32(0x80000100u)
#define SPI_XFER REG32(0x80000104u)
#define SPI_DATA REG32(0x80000108u)
#define FDC_STATE REG32(0x80000200u)
#define FDC_INFO REG32(0x80000204u)
#define FDC_BUFFER_RESET REG32(0x80000208u)
#define FDC_BUFFER_DATA REG32(0x8000020cu)
#define FDC_ACK REG32(0x80000210u)
#define MOUNT_STATUS REG32(0x80000214u)
#define FDC_BUFFER_PEEK REG32(0x80000218u)
#define FDC_DEBUG_WORD REG32(0x8000021cu)
#define FDC_BUFFER_DEBUG_ADDRESS REG32(0x80000220u)
#define FDC_BUFFER_DEBUG_DATA REG32(0x80000224u)
#define FDC_COMPLETED_DEBUG_WORD REG32(0x80000228u)
#define FDC_WRITE_ACK REG32(0x8000022cu)
#define DISK_CACHE_RESET REG32(0x80000230u)
#define DISK_CACHE_DATA REG32(0x80000234u)
#define DISK_CACHE_COMMIT REG32(0x80000238u)
#define DISK_CACHE_STATUS REG32(0x8000023cu)
#define FDC_WRITE_BUFFER_DEBUG_DATA REG32(0x80000240u)
#define DISK_CACHE_DEBUG_ADDRESS REG32(0x80000244u)
#define DISK_CACHE_DEBUG_DATA REG32(0x80000248u)
#define OSD_ADDRESS REG32(0x8000024cu)
#define OSD_DATA REG32(0x80000250u)
#define OSD_CONTROL REG32(0x80000254u)
#define MENU_KEY_STATE REG32(0x80000258u)

#define KEY_F12 1u
#define KEY_UP 2u
#define KEY_DOWN 4u
#define KEY_ENTER 8u
#define KEY_ESCAPE 16u
#define MAX_DSK_FILES 16u
#define OSD_COLS 48u
#define OSD_FIRST_FILE_ROW 4u
#define OSD_FILE_ROWS 13u

static uint8_t block_addressed, sectors_per_cluster, last_buffer_byte0;
static uint32_t disk_cache_crc32;
static uint32_t fat_lba, first_data_lba;
static uint8_t sector[512];

struct disk { char name[11]; uint32_t cluster, size; };
static const char zenix_name[11] = {'Z','E','N','I','X',' ',' ',' ','D','S','K'};
static struct disk browser_disks[MAX_DSK_FILES], mounted_disk;
static uint8_t browser_count;

static void putc(char c) { while (UART_STATUS & 1u) {} UART_DATA = (uint8_t)c; }
static void puts(const char *s) { while (*s) putc(*s++); }
static void hex(uint8_t n) { static const char h[]="0123456789ABCDEF"; putc(h[n>>4]); putc(h[n&15]); }
static void hex32(uint32_t n) { hex((uint8_t)(n>>24)); hex((uint8_t)(n>>16)); hex((uint8_t)(n>>8)); hex((uint8_t)n); }
static uint32_t crc32_byte(uint32_t crc,uint8_t value){
    crc^=value;
    for(uint8_t bit=0;bit<8;++bit)crc=(crc>>1)^((crc&1u)?0xedb88320u:0u);
    return crc;
}
static void print_buffer_head(void) {
    for(uint8_t n=0;n<4;++n){
        if(n)putc(' ');
        FDC_BUFFER_DEBUG_ADDRESS=n;
        hex((uint8_t)FDC_BUFFER_DEBUG_DATA);
    }
}
static uint8_t xfer(uint8_t v) { SPI_XFER = v; return (uint8_t)SPI_DATA; }
static void deselect(void) { SPI_CTRL = 0x00004001u; (void)xfer(0xff); }
static void select(void) { SPI_CTRL = 0x00004000u; }
static uint8_t ready(void) { for (uint32_t n=0;n<100000u;++n) if (xfer(0xff)==0xff) return 1; return 0; }
static uint8_t command(uint8_t cmd, uint32_t arg) {
    deselect(); select(); if (cmd && !ready()) return 0xff;
    (void)xfer(0x40u|cmd); (void)xfer(arg>>24); (void)xfer(arg>>16); (void)xfer(arg>>8); (void)xfer(arg);
    (void)xfer(cmd==0 ? 0x95 : (cmd==8 ? 0x87 : 1));
    for (uint8_t n=0;n<16;++n) { uint8_t r=xfer(0xff); if (!(r&0x80)) return r; }
    return 0xff;
}
static int init_card(void) {
    SPI_CTRL=0x00004001u; for(uint8_t n=0;n<10;++n)(void)xfer(0xff);
    for(uint8_t n=0;n<32;++n) { if(command(0,0)==1) break; if(n==31)return 1; }
    if(command(8,0x1aau)!=1)return 2;
    if(xfer(0xff)||xfer(0xff)||xfer(0xff)!=1||xfer(0xff)!=0xaa)return 3;
    for(uint16_t n=0;n<2000;++n) { if(command(55,0)>1)return 4; if(command(41,0x40000000u)==0)break; if(n==1999)return 5; }
    if(command(58,0)!=0)return 6;
    { uint8_t ocr=xfer(0xff); (void)xfer(0xff);(void)xfer(0xff);(void)xfer(0xff); deselect();
      if(!(ocr&0x80))return 7; block_addressed=(ocr&0x40)!=0; }
    if(!block_addressed && command(16,512)!=0)return 8;
    deselect(); SPI_CTRL=0x00000801u; return 0;
}
static int read_sector(uint32_t lba) {
    if(!block_addressed && lba>0x007fffffu)return 4;
    if(command(17,block_addressed ? lba : lba*512u)!=0){deselect();return 1;}
    for(uint32_t n=0;n<100000u;++n){uint8_t t=xfer(0xff);if(t==0xfe)goto data;if(t!=0xff){deselect();return 2;}}
    deselect();return 3;
data:
    for(uint16_t n=0;n<512;++n)sector[n]=xfer(0xff);
    (void)xfer(0xff);(void)xfer(0xff);deselect();return 0;
}
// CMD24 single-block write.  The cache has already been updated by hardware;
// a failure leaves the in-session cache intact but reports write fault to the
// FDC so Disk BASIC does not mistake it for a durable save.
static int write_sector(uint32_t lba) {
    uint8_t response;
    if(!block_addressed && lba>0x007fffffu)return 4;
    if(command(24,block_addressed ? lba : lba*512u)!=0){deselect();return 1;}
    (void)xfer(0xfe);
    for(uint16_t n=0;n<512;++n)(void)xfer(sector[n]);
    (void)xfer(0xff);(void)xfer(0xff);
    response=xfer(0xff);
    if((response&0x1fu)!=5u){deselect();return 2;}
    if(!ready()){deselect();return 3;}
    deselect();return 0;
}
static uint16_t le16(const uint8_t *p){return (uint16_t)p[0]|((uint16_t)p[1]<<8);}
static uint32_t le32(const uint8_t *p){return(uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static int next_cluster(uint32_t cluster,uint32_t *next){if(read_sector(fat_lba+(cluster>>7)))return 1;*next=le32(&sector[(cluster&127u)*4u])&0x0fffffffu;return *next<2||*next>=0x0ffffff8u;}
static int name_is(const uint8_t *entry,const char *name){for(uint8_t n=0;n<11;++n)if(entry[n]!=(uint8_t)name[n])return 0;return 1;}
static int is_dsk(const uint8_t *entry){return entry[8]=='D'&&entry[9]=='S'&&entry[10]=='K';}
static void copy_name(char *to,const uint8_t *from){for(uint8_t n=0;n<11;++n)to[n]=(char)from[n];}
static void copy_disk(struct disk *to,const struct disk *from){copy_name(to->name,(const uint8_t *)from->name);to->cluster=from->cluster;to->size=from->size;}
static uint32_t scan_cluster;
static int mount_disks(void) {
    uint32_t volume_lba, root_cluster;
    if(read_sector(0))return 0x10;
    if(sector[510]!=0x55||sector[511]!=0xaa)return 0x11;
    volume_lba=(sector[82]=='F'&&sector[83]=='A'&&sector[84]=='T'&&sector[85]=='3'&&sector[86]=='2')?0:le32(&sector[454]);
    if(read_sector(volume_lba))return 0x12;
    if(sector[510]!=0x55||sector[511]!=0xaa||le16(&sector[11])!=512)return 0x13;
    sectors_per_cluster=sector[13]; fat_lba=volume_lba+le16(&sector[14]);
    first_data_lba=fat_lba+(uint32_t)sector[16]*le32(&sector[36]); root_cluster=le32(&sector[44]);
    if(!sectors_per_cluster||root_cluster<2||!le32(&sector[36]))return 0x14;
    scan_cluster=root_cluster;
    for(;;){
        for(uint8_t s=0;s<sectors_per_cluster;++s){
            if(read_sector(first_data_lba+(scan_cluster-2u)*sectors_per_cluster+s))return 0x15;
            for(uint16_t o=0;o<512;o+=32){const uint8_t *e=&sector[o];if(!e[0])goto done;
                if(e[0]!=0xe5&&e[11]!=0x0f&&!(e[11]&0x18)&&is_dsk(e)&&
                   le32(&e[28])==161280u&&browser_count<MAX_DSK_FILES){
                    struct disk *d=&browser_disks[browser_count++];
                    copy_name(d->name,e);
                    d->cluster=((uint32_t)le16(&e[20])<<16)|le16(&e[26]);
                    d->size=le32(&e[28]);
                }
            }
        }
        if(next_cluster(scan_cluster,&scan_cluster))break;
    }
done:
    if(browser_count){
        uint8_t selected=0;
        for(uint8_t n=0;n<browser_count;++n)if(name_is((const uint8_t *)browser_disks[n].name,zenix_name)){selected=n;break;}
        copy_disk(&mounted_disk,&browser_disks[selected]);
    }
    return 0;
}
static int copy_decb_sector(const struct disk *d,uint8_t track,uint8_t disk_sector){
    uint32_t offset=((uint32_t)track*18u+(uint32_t)(disk_sector-1u))*256u;
    uint32_t cluster=d->cluster, cluster_bytes=(uint32_t)sectors_per_cluster*512u;
    if(!cluster||disk_sector<1||disk_sector>18||offset+256u>d->size)return 1;
    while(offset>=cluster_bytes){offset-=cluster_bytes;if(next_cluster(cluster,&cluster))return 2;}
    if(read_sector(first_data_lba+(cluster-2u)*sectors_per_cluster+(offset>>9)))return 3;
    FDC_BUFFER_RESET=0;
    for(uint16_t n=0;n<256;++n)FDC_BUFFER_DATA=sector[(offset&511u)+n];
    FDC_BUFFER_DEBUG_ADDRESS=0;
    last_buffer_byte0=(uint8_t)FDC_BUFFER_DEBUG_DATA;
    return 0;
}
// Load drive 0 into the proven full-image BRAM path.  FAT32 and SD traffic
// happen only during mount and writeback, never in the timing-sensitive CoCo
// read-sector byte stream.
static int load_disk_cache(const struct disk *d){
    uint32_t cluster=d->cluster, remaining=d->size;
    uint32_t crc=0xffffffffu;
    if(!cluster||remaining!=161280u)return 1;
    DISK_CACHE_RESET=0;
    while(remaining){
        for(uint8_t s=0;s<sectors_per_cluster&&remaining;++s){
            uint16_t count=remaining>=512u?512u:(uint16_t)remaining;
            if(read_sector(first_data_lba+(cluster-2u)*sectors_per_cluster+s))return 2;
            for(uint16_t n=0;n<count;++n){
                uint8_t value=sector[n];
                crc=crc32_byte(crc,value);
                DISK_CACHE_DATA=value;
            }
            remaining-=count;
        }
        if(remaining&&next_cluster(cluster,&cluster))return 3;
    }
    DISK_CACHE_COMMIT=1;
    disk_cache_crc32=~crc;
    return (DISK_CACHE_STATUS&1u)?0:4;
}
static uint8_t disk_cache_byte(uint32_t address){
    DISK_CACHE_DEBUG_ADDRESS=address;
    return (uint8_t)DISK_CACHE_DEBUG_DATA;
}
static void audit_disk_cache(void){
    // DECB track 17 sector 2 is the GAT; sector 3 starts the directory.
    const uint32_t gat=((17u*18u)+1u)*256u;
    const uint32_t dir=((17u*18u)+2u)*256u;
    puts("CACHE GAT ");
    for(uint8_t n=0;n<4;++n){if(n)putc(' ');hex(disk_cache_byte(gat+n));}
    puts(" DIR ");
    for(uint8_t n=0;n<4;++n){if(n)putc(' ');hex(disk_cache_byte(dir+n));}
    puts("\r\n");
}
// Resolve a 512-byte-aligned position in a possibly fragmented FAT32 file.
// It deliberately follows the FAT chain rather than assuming the DSK is
// contiguous, so ordinary Windows/Linux copies remain writable.
static int disk_lba(const struct disk *d,uint32_t offset,uint32_t *lba){
    uint32_t cluster=d->cluster, cluster_bytes=(uint32_t)sectors_per_cluster*512u;
    if(!cluster||(offset&511u)||offset+512u>d->size)return 1;
    while(offset>=cluster_bytes){offset-=cluster_bytes;if(next_cluster(cluster,&cluster))return 2;}
    *lba=first_data_lba+(cluster-2u)*sectors_per_cluster+(offset>>9);
    return 0;
}
// FDC writes one 256-byte DECB sector.  Read its containing 512-byte FAT
// block, merge the FDC staging buffer into the appropriate half, then CMD24
// the exact original file block.  No FAT metadata changes are needed because
// ZENIX.DSK already has a fixed size and allocation.
static int flush_decb_sector(const struct disk *d,uint8_t track,uint8_t disk_sector){
    uint32_t offset=((uint32_t)track*18u+(uint32_t)(disk_sector-1u))*256u, lba;
    uint16_t half=(uint16_t)(offset&256u);
    if(disk_sector<1||disk_sector>18||disk_lba(d,offset&~511u,&lba))return 1;
    if(read_sector(lba))return 2;
    for(uint16_t n=0;n<256;++n){FDC_BUFFER_DEBUG_ADDRESS=n;sector[half+n]=(uint8_t)FDC_WRITE_BUFFER_DEBUG_DATA;}
    return write_sector(lba)?3:0;
}
static void print_decb_name(const uint8_t *entry){
    uint8_t n;
    for(n=0;n<8&&entry[n]!=' ';++n)putc((char)entry[n]);
    if(entry[8]!=' '){putc('.');for(n=8;n<11&&entry[n]!=' ';++n)putc((char)entry[n]);}
}
static uint32_t decb_file_size(const uint8_t *entry,const uint8_t *gat){
    uint8_t granule=entry[13], next; uint16_t hops=0;
    uint32_t bytes=0;
    while(hops++<68u){next=gat[granule];if(next>=0xc0u){
        uint8_t final_sectors=next&0x3fu;
        uint16_t last_bytes=((uint16_t)entry[14]<<8)|entry[15];
        if(!final_sectors)return bytes;
        return bytes+(uint32_t)(final_sectors-1u)*256u+last_bytes;
    }bytes+=2304u;granule=next;}
    return 0xffffffffu;
}
// Hardware-visible startup proof of the FAT32-to-DECB path.  It is separate
// from the WD1773 byte-stream capture: this verifies the mounted DSK's own
// directory records and granule allocation before the CoCo issues a command.
static void audit_drive0(void){
    uint8_t directory[64],n;
    if(copy_decb_sector(&mounted_disk,17,3))return;
    for(n=0;n<64;++n)directory[n]=sector[n];
    if(copy_decb_sector(&mounted_disk,17,2))return;
    for(n=0;n<2;++n){const uint8_t *entry=&directory[n*32u];
        if(entry[0]==0||entry[0]==0xff)return;
        // Track 17 sector 2 is the second 256-byte DECB sector in this
        // 512-byte FAT block, so the GAT begins at byte 256.
        puts("AUDIT D0 ");print_decb_name(entry);puts(" BYTES ");hex32(decb_file_size(entry,&sector[256]));puts("\r\n");
    }
}
static void short_name(const struct disk *d,char *text){
    uint8_t out=0,n;
    for(n=0;n<8&&d->name[n]!=' ';++n)text[out++]=d->name[n];
    if(d->name[8]!=' '){text[out++]='.';for(n=8;n<11&&d->name[n]!=' ';++n)text[out++]=d->name[n];}
    text[out]=0;
}
static void osd_clear(void){OSD_ADDRESS=0;for(uint16_t n=0;n<OSD_COLS*20u;++n)OSD_DATA=' ';}
static void osd_text(uint8_t row,uint8_t column,const char *text){
    OSD_ADDRESS=(uint32_t)row*OSD_COLS+column;
    while(*text&&column++<OSD_COLS)OSD_DATA=(uint8_t)*text++;
}
static uint8_t menu_selection,menu_top;
static void draw_menu(const char *status){
    char name[13];
    if(menu_selection<menu_top)menu_top=menu_selection;
    if(menu_selection>=menu_top+OSD_FILE_ROWS)menu_top=menu_selection-OSD_FILE_ROWS+1u;
    osd_clear();
    osd_text(0,2,"COCO3ELITE DISK MANAGER");
    osd_text(1,2,"DRIVE 0:");short_name(&mounted_disk,name);osd_text(1,11,name);
    osd_text(2,2,"SD CARD .DSK FILES");
    for(uint8_t row=0;row<OSD_FILE_ROWS;++row){
        uint8_t index=menu_top+row;
        if(index>=browser_count)break;
        short_name(&browser_disks[index],name);
        osd_text(OSD_FIRST_FILE_ROW+row,2,
                 browser_disks[index].cluster==mounted_disk.cluster?"*":" ");
        osd_text(OSD_FIRST_FILE_ROW+row,4,name);
    }
    osd_text(18,2,status);
    osd_text(19,2,"UP/DOWN SELECT  ENTER MOUNT  ESC/F12 EXIT");
    OSD_CONTROL=((uint32_t)(OSD_FIRST_FILE_ROW+menu_selection-menu_top)<<8)|1u;
}
static int run_disk_menu(uint8_t *present){
    uint32_t previous,keys,pressed;
    char name[13];
    menu_selection=0;menu_top=0;
    for(uint8_t n=0;n<browser_count;++n)if(browser_disks[n].cluster==mounted_disk.cluster){menu_selection=n;break;}
    draw_menu(browser_count?"SELECT A DISK FOR DRIVE 0":"NO COMPATIBLE 161280-BYTE DSK FILES");
    puts("MENU OPEN\r\n");
    while(MENU_KEY_STATE&KEY_F12){}
    previous=MENU_KEY_STATE;
    for(;;){
        keys=MENU_KEY_STATE;pressed=keys&~previous;previous=keys;
        if(pressed&(KEY_ESCAPE|KEY_F12)){
            while(MENU_KEY_STATE&(KEY_ESCAPE|KEY_F12)){}
            OSD_CONTROL=0;puts("MENU CLOSE\r\n");return 0;
        }
        if((pressed&KEY_UP)&&browser_count){
            menu_selection=menu_selection?menu_selection-1u:browser_count-1u;
            draw_menu("SELECT A DISK FOR DRIVE 0");
        }
        if((pressed&KEY_DOWN)&&browser_count){
            menu_selection=(menu_selection+1u==browser_count)?0:menu_selection+1u;
            draw_menu("SELECT A DISK FOR DRIVE 0");
        }
        if((pressed&KEY_ENTER)&&browser_count){
            struct disk candidate;
            copy_disk(&candidate,&browser_disks[menu_selection]);
            draw_menu("MOUNTING DRIVE 0 - PLEASE WAIT");
            MOUNT_STATUS=0;
            if(!load_disk_cache(&candidate)){
                copy_disk(&mounted_disk,&candidate);*present=1;MOUNT_STATUS=0x101u;
                short_name(&mounted_disk,name);puts("MOUNT D0 ");puts(name);puts(" CRC32 ");hex32(disk_cache_crc32);puts("\r\n");
                while(MENU_KEY_STATE&KEY_ENTER){}
                OSD_CONTROL=0;return 0;
            }
            *present=0;MOUNT_STATUS=0x100u;
            draw_menu("MOUNT FAILED - SELECT ANOTHER DISK");
        }
    }
}
int main(void){
    int error=init_card(); uint8_t present=0;
    puts("RV32 SD MOUNT\r\n");
    if(!error)error=mount_disks();
    if(!error&&browser_count){
        puts("CACHE D0\r\n");error=load_disk_cache(&mounted_disk);if(!error)present=1;
    }
    if(error){puts("MOUNT ERR ");hex((uint8_t)error);puts("\r\n");}
    else { puts("DRIVES ");hex(present);puts(" DSK COUNT ");hex(browser_count);puts("\r\n"); }
    if(!error&&(present&1u))audit_disk_cache();
    if(!error&&(present&1u)){puts("CACHE CRC32 ");hex32(disk_cache_crc32);puts("\r\n");}
    MOUNT_STATUS=0x100u|present;
    if(!error&&(present&1u))audit_drive0();
    uint32_t seen=FDC_STATE&1u, seen_complete=(FDC_STATE>>11)&1u, seen_write=(FDC_STATE>>12)&1u;
    uint32_t menu_previous=MENU_KEY_STATE;
    for(;;){
        uint32_t state=FDC_STATE;
        if(((state>>11)&1u)!=seen_complete){uint32_t word=FDC_COMPLETED_DEBUG_WORD;
            puts("FDC CPU ");hex((uint8_t)(word>>24));putc(' ');hex((uint8_t)(word>>16));putc(' ');hex((uint8_t)(word>>8));putc(' ');hex((uint8_t)word);puts("\r\n");
            seen_complete=(state>>11)&1u;}
        if(((state>>12)&1u)!=seen_write){
            uint32_t info=FDC_INFO;uint8_t drive=info&3u,disk_sector=(info>>8)&0xffu,track=(info>>16)&0xffu;
            int ok=error==0&&drive==0&&(present&1u)&&!flush_decb_sector(&mounted_disk,track,disk_sector);
            puts(ok ? "FDC WRITE OK " : "FDC WRITE ERR ");hex(drive);putc(' ');hex(track);putc(' ');hex(disk_sector);puts("\r\n");
            FDC_WRITE_ACK=ok?1:0;seen_write=(state>>12)&1u;
        }
        if((state&1u)!=seen){uint32_t info=FDC_INFO;uint8_t drive=info&3u, disk_sector=(info>>8)&0xffu, track=(info>>16)&0xffu, type1=info>>24;
            // D0 is already in the full-image cache. Future D1/D2 requests
            // will populate the owned sector banks here instead.
            int ok=error==0&&drive==0&&(present&1u);
            puts(ok ? "FDC CACHE " : "FDC ERR "); hex(drive);putc(' ');hex(track);putc(' ');hex(disk_sector);putc(' ');hex(type1);
            if(ok){puts(" BUF ");print_buffer_head();}
            puts("\r\n");
            FDC_ACK=ok?1:0; seen=state&1u;
        }
        {uint32_t keys=MENU_KEY_STATE;
         if((keys&KEY_F12)&&!(menu_previous&KEY_F12))error=run_disk_menu(&present);
         menu_previous=MENU_KEY_STATE;}
    }
}
