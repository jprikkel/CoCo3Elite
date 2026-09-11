#include <stdint.h>
void *memcpy(void *dst,const void *src,unsigned long n){unsigned char *d=dst;const unsigned char *s=src;while(n--)*d++=*s++;return dst;}

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
#define MAX_DSK_FILES 32u
#define MAX_NAME 256u
#define OSD_COLS 48u
#define OSD_FIRST_FILE_ROW 4u
#define OSD_FILE_ROWS 13u

static uint8_t block_addressed, sectors_per_cluster, last_buffer_byte0;
static uint32_t disk_cache_crc32;
static uint32_t fat_lba, first_data_lba;
static uint8_t sector[512];

struct disk { char name[MAX_NAME]; uint32_t cluster, size; };
struct browser_entry { char name[MAX_NAME]; uint32_t cluster, size; uint8_t directory, parent; };
static struct browser_entry browser_entries[MAX_DSK_FILES];
static struct disk mounted_disk;
static uint8_t browser_count, card_online;
static uint32_t root_cluster, current_directory, parent_directory;
static uint32_t directory_stack[8];
static uint8_t directory_depth;
static char current_path[MAX_NAME];
static uint16_t lfn_utf16[260];
static uint8_t lfn_valid, lfn_expected, lfn_checksum;

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
static void media_lost(void){card_online=0;browser_count=0;mounted_disk.cluster=0;DISK_CACHE_RESET=0;MOUNT_STATUS=0;puts("SD OFFLINE\r\n");}
static int read_sector(uint32_t lba) {
    if(!card_online)return 0x7f;
    if(!block_addressed && lba>0x007fffffu)return 4;
    if(command(17,block_addressed ? lba : lba*512u)!=0){deselect();media_lost();return 1;}
    for(uint32_t n=0;n<100000u;++n){uint8_t t=xfer(0xff);if(t==0xfe)goto data;if(t!=0xff){deselect();media_lost();return 2;}}
    deselect();media_lost();return 3;
data:
    for(uint16_t n=0;n<512;++n)sector[n]=xfer(0xff);
    (void)xfer(0xff);(void)xfer(0xff);deselect();return 0;
}
// CMD24 single-block write.  The cache has already been updated by hardware;
// a failure leaves the in-session cache intact but reports write fault to the
// FDC so Disk BASIC does not mistake it for a durable save.
static int write_sector(uint32_t lba) {
    uint8_t response;
    if(!card_online)return 0x7f;
    if(!block_addressed && lba>0x007fffffu)return 4;
    if(command(24,block_addressed ? lba : lba*512u)!=0){deselect();media_lost();return 1;}
    (void)xfer(0xfe);
    for(uint16_t n=0;n<512;++n)(void)xfer(sector[n]);
    (void)xfer(0xff);(void)xfer(0xff);
    response=xfer(0xff);
    if((response&0x1fu)!=5u){deselect();media_lost();return 2;}
    if(!ready()){deselect();media_lost();return 3;}
    deselect();return 0;
}
static uint16_t le16(const uint8_t *p){return (uint16_t)p[0]|((uint16_t)p[1]<<8);}
static uint32_t le32(const uint8_t *p){return(uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static int next_cluster(uint32_t cluster,uint32_t *next){if(read_sector(fat_lba+(cluster>>7)))return 1;*next=le32(&sector[(cluster&127u)*4u])&0x0fffffffu;return *next<2||*next>=0x0ffffff8u;}
static void copy_disk(struct disk *to,const struct disk *from){for(uint16_t n=0;n<MAX_NAME;++n)to->name[n]=from->name[n];to->cluster=from->cluster;to->size=from->size;}
static int equal_name(const char *a,const char *b){while(*a&&*b){char x=*a++,y=*b++;if(x>='a'&&x<='z')x-=32;if(y>='a'&&y<='z')y-=32;if(x!=y)return 0;}return *a==0&&*b==0;}
static void lfn_reset(void){lfn_valid=0;lfn_expected=0;lfn_checksum=0;}
static uint8_t short_checksum(const uint8_t *e){uint8_t c=0;for(uint8_t n=0;n<11;++n)c=((c&1u)?0x80u:0u)+(c>>1)+e[n];return c;}
static void lfn_part(const uint8_t *e){uint8_t order=e[0]&0x1fu;if(e[0]&0x40u){lfn_reset();lfn_expected=order;lfn_checksum=e[13];lfn_valid=1;}if(!lfn_valid||order!=lfn_expected||e[13]!=lfn_checksum){lfn_reset();return;}uint16_t base=(uint16_t)(order-1u)*13u;uint8_t at=0;const uint8_t pos[]={1,3,5,7,9,14,16,18,20,22,24,28,30};for(uint8_t n=0;n<13;++n)lfn_utf16[base+n]=le16(&e[pos[n]]);lfn_expected--;}
static void short_text(const uint8_t *e,char *out){uint8_t at=0;for(uint8_t n=0;n<8&&e[n]!=' ';++n)out[at++]=(char)e[n];if(e[8]!=' '){out[at++]='.';for(uint8_t n=8;n<11&&e[n]!=' ';++n)out[at++]=(char)e[n];}out[at]=0;}
static void lfn_text(char *out){uint16_t at=0;uint8_t n=0;while(n<260&&lfn_utf16[n]&&lfn_utf16[n]!=0xffffu){uint16_t c=lfn_utf16[n++];out[at++]=(c<128u&&(c>=32u||c==' ') )?(char)c:'?';}out[at]=0;}
static int is_dsk_name(const char *name){uint16_t n=0;while(name[n])n++;return n>=4u&&name[n-4]=='.'&&((name[n-3]=='D'||name[n-3]=='d')&&(name[n-2]=='S'||name[n-2]=='s')&&(name[n-1]=='K'||name[n-1]=='k'));}
static void add_entry(const uint8_t *e,const char *name,uint8_t directory){if(browser_count>=MAX_DSK_FILES)return;if(!directory&&(!is_dsk_name(name)||le32(&e[28])!=161280u))return;struct browser_entry *b=&browser_entries[browser_count++];uint16_t n=0;while(name[n]&&n<MAX_NAME-1u){b->name[n]=name[n];n++;}b->name[n]=0;b->cluster=((uint32_t)le16(&e[20])<<16)|le16(&e[26]);b->size=le32(&e[28]);b->directory=directory;b->parent=0;}
static int scan_directory(uint32_t directory){uint32_t cluster=directory;browser_count=0;lfn_reset();if(directory!=root_cluster){struct browser_entry *b=&browser_entries[browser_count++];b->name[0]='.';b->name[1]='.';b->name[2]=0;b->cluster=parent_directory;b->size=0;b->directory=1;b->parent=1;}for(;;){for(uint8_t s=0;s<sectors_per_cluster;++s){if(read_sector(first_data_lba+(cluster-2u)*sectors_per_cluster+s))return 1;for(uint16_t o=0;o<512;o+=32){const uint8_t *e=&sector[o];if(!e[0])return 0;if(e[0]==0xe5){lfn_reset();continue;}if(e[11]==0x0f){lfn_part(e);continue;}if(e[11]&0x08){lfn_reset();continue;}char name[MAX_NAME];if(lfn_valid&&lfn_expected==0&&short_checksum(e)==lfn_checksum)lfn_text(name);else short_text(e,name);lfn_reset();if(name[0]=='.')continue;add_entry(e,name,(e[11]&0x10u)!=0);}}if(next_cluster(cluster,&cluster))break;}return 0;}
static int mount_disks(void) {
    uint32_t volume_lba;
    if(read_sector(0))return 0x10;
    if(sector[510]!=0x55||sector[511]!=0xaa)return 0x11;
    volume_lba=(sector[82]=='F'&&sector[83]=='A'&&sector[84]=='T'&&sector[85]=='3'&&sector[86]=='2')?0:le32(&sector[454]);
    if(read_sector(volume_lba))return 0x12;
    if(sector[510]!=0x55||sector[511]!=0xaa||le16(&sector[11])!=512)return 0x13;
    sectors_per_cluster=sector[13]; fat_lba=volume_lba+le16(&sector[14]);
    first_data_lba=fat_lba+(uint32_t)sector[16]*le32(&sector[36]); root_cluster=le32(&sector[44]);
    if(!sectors_per_cluster||root_cluster<2||!le32(&sector[36]))return 0x14;
    root_cluster=le32(&sector[44]);current_directory=root_cluster;parent_directory=root_cluster;directory_depth=0;current_path[0]='/';current_path[1]=0;
    if(scan_directory(root_cluster))return 0x15;
    for(uint8_t n=0;n<browser_count;++n)if(!browser_entries[n].directory&&equal_name(browser_entries[n].name,"ZENIX.DSK")){for(uint16_t k=0;k<MAX_NAME;++k)mounted_disk.name[k]=browser_entries[n].name[k];mounted_disk.cluster=browser_entries[n].cluster;mounted_disk.size=browser_entries[n].size;break;}
    if(!mounted_disk.cluster)for(uint8_t n=0;n<browser_count;++n)if(!browser_entries[n].directory){for(uint16_t k=0;k<MAX_NAME;++k)mounted_disk.name[k]=browser_entries[n].name[k];mounted_disk.cluster=browser_entries[n].cluster;mounted_disk.size=browser_entries[n].size;break;}
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
static void short_name(const struct disk *d,char *text){uint16_t n=0;while(d->name[n]&&n<MAX_NAME-1u){text[n]=d->name[n];n++;}text[n]=0;}
static void entry_line(const struct browser_entry *e,char *line){uint8_t at=0;line[at++]=e->parent?'[':(e->directory?'[':' ');if(e->parent){line[at++]=']';line[at]=0;return;}if(e->directory){line[at++]='D';line[at++]='I';line[at++]='R';line[at++]=']';line[at++]=' ';}else{line[at++]=' ';line[at++]=' ';line[at++]=' ';line[at++]=' ';line[at++]=' ';}uint16_t n=0;while(e->name[n]&&at<OSD_COLS-1u){line[at++]=e->name[n++];}line[at]=0;}
static void osd_clear(void){OSD_ADDRESS=0;for(uint16_t n=0;n<OSD_COLS*20u;++n)OSD_DATA=' ';}
static void osd_text(uint8_t row,uint8_t column,const char *text){
    OSD_ADDRESS=(uint32_t)row*OSD_COLS+column;
    while(*text&&column++<OSD_COLS)OSD_DATA=(uint8_t)*text++;
}
static uint8_t menu_selection,menu_top;
static void draw_menu(const char *status){
    char name[MAX_NAME],line[OSD_COLS];
    if(menu_selection<menu_top)menu_top=menu_selection;
    if(menu_selection>=menu_top+OSD_FILE_ROWS)menu_top=menu_selection-OSD_FILE_ROWS+1u;
    osd_clear();
    osd_text(0,2,"COCO3ELITE DISK MANAGER");
    osd_text(1,2,"DRIVE 0:");short_name(&mounted_disk,name);osd_text(1,11,name);
    osd_text(2,2,"PATH:");osd_text(2,8,current_path);
    osd_text(3,2,"SELECT DSK OR DIRECTORY");
    for(uint8_t row=0;row<OSD_FILE_ROWS;++row){
        uint8_t index=menu_top+row;
        if(index>=browser_count)break;
        entry_line(&browser_entries[index],line);
        osd_text(OSD_FIRST_FILE_ROW+row,2,
                 browser_entries[index].cluster==mounted_disk.cluster?"*":" ");
        osd_text(OSD_FIRST_FILE_ROW+row,4,line);
    }
    osd_text(18,2,status);
    osd_text(19,2,"UP/DOWN SELECT  ENTER MOUNT  ESC/F12 EXIT");
    OSD_CONTROL=((uint32_t)(OSD_FIRST_FILE_ROW+menu_selection-menu_top)<<8)|1u;
}
static int run_disk_menu(uint8_t *present){
    uint32_t previous,keys,pressed;
    char name[13];
    menu_selection=0;menu_top=0;
    for(uint8_t n=0;n<browser_count;++n)if(browser_entries[n].cluster==mounted_disk.cluster){menu_selection=n;break;}
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
            if(browser_entries[menu_selection].directory){
                if(browser_entries[menu_selection].parent){if(directory_depth){current_directory=directory_stack[--directory_depth];parent_directory=directory_depth?directory_stack[directory_depth-1u]:root_cluster;uint16_t p=0;while(current_path[p]&&p<MAX_NAME)p++;while(p>1u&&current_path[p-1u]!='/')p--;if(p==1u)current_path[1]=0;else current_path[p-1u]=0;scan_directory(current_directory);}}
                else {if(directory_depth<8u)directory_stack[directory_depth++]=current_directory;parent_directory=current_directory;current_directory=browser_entries[menu_selection].cluster;uint16_t p=0;while(current_path[p])p++;if(p>1&&current_path[p-1]!='/'){current_path[p++]='/';}for(uint16_t n=0;browser_entries[menu_selection].name[n]&&p<MAX_NAME-1u;n++)current_path[p++]=browser_entries[menu_selection].name[n];current_path[p]=0;scan_directory(current_directory);}
                menu_selection=0;menu_top=0;draw_menu("SELECT A DISK FOR DRIVE 0");continue;
            }
            struct disk candidate;
            for(uint16_t n=0;n<MAX_NAME;++n)candidate.name[n]=browser_entries[menu_selection].name[n];candidate.cluster=browser_entries[menu_selection].cluster;candidate.size=browser_entries[menu_selection].size;
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
    if(!error)card_online=1;
    if(!error)error=mount_disks();
    if(!error&&browser_count){
        puts("CACHE D0\r\n");error=load_disk_cache(&mounted_disk);if(!error)present=1;
    }
    if(error){puts("MOUNT ERR ");hex((uint8_t)error);puts("\r\n");}
    else { puts("DRIVES ");hex(present);puts(" DSK COUNT ");hex(browser_count);puts("\r\n"); }
    if(!error&&(present&1u))audit_disk_cache();
    if(!error&&(present&1u)){puts("CACHE CRC32 ");hex32(disk_cache_crc32);puts("\r\n");}
    MOUNT_STATUS=card_online?(0x100u|present):0;
    if(!error&&(present&1u))audit_drive0();
    uint32_t seen=FDC_STATE&1u, seen_complete=(FDC_STATE>>11)&1u, seen_write=(FDC_STATE>>12)&1u;
    uint32_t menu_previous=MENU_KEY_STATE, retry=0, probe=0;
    for(;;){
        if(!card_online){
            if(!retry--){
                if(!init_card()){card_online=1;error=mount_disks();present=0;if(!error&&mounted_disk.cluster&&!load_disk_cache(&mounted_disk)){present=1;puts("SD REINSERTED\r\n");MOUNT_STATUS=0x101u;}else if(error)media_lost();retry=3000000u;}
                else retry=3000000u;
            }
        }else if(++probe>=3000000u){
            probe=0;
            if(read_sector(0)){present=0;error=1;}
        }
        uint32_t state=FDC_STATE;
        if(((state>>11)&1u)!=seen_complete){uint32_t word=FDC_COMPLETED_DEBUG_WORD;
            puts("FDC CPU ");hex((uint8_t)(word>>24));putc(' ');hex((uint8_t)(word>>16));putc(' ');hex((uint8_t)(word>>8));putc(' ');hex((uint8_t)word);puts("\r\n");
            seen_complete=(state>>11)&1u;}
        if(((state>>12)&1u)!=seen_write){
            uint32_t info=FDC_INFO;uint8_t drive=info&3u,disk_sector=(info>>8)&0xffu,track=(info>>16)&0xffu;
            int ok=card_online&&error==0&&drive==0&&(present&1u)&&!flush_decb_sector(&mounted_disk,track,disk_sector);
            puts(ok ? "FDC WRITE OK " : "FDC WRITE ERR ");hex(drive);putc(' ');hex(track);putc(' ');hex(disk_sector);puts("\r\n");
            FDC_WRITE_ACK=ok?1:0;seen_write=(state>>12)&1u;
        }
        if((state&1u)!=seen){uint32_t info=FDC_INFO;uint8_t drive=info&3u, disk_sector=(info>>8)&0xffu, track=(info>>16)&0xffu, type1=info>>24;
            // D0 is already in the full-image cache. Future D1/D2 requests
            // will populate the owned sector banks here instead.
            int ok=card_online&&error==0&&drive==0&&(present&1u);
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
