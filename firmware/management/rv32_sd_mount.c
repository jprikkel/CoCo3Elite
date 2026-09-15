#include <stdint.h>
#include "decb_bin_format.h"
#include "decb_bin_loader_image.h"
#include "settings_ui.h"
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
#define CARTRIDGE_ADDRESS REG32(0x8000025cu)
#define CARTRIDGE_DATA REG32(0x80000260u)
#define CARTRIDGE_CONTROL REG32(0x80000264u)
#define CARTRIDGE_SIGNATURE REG32(0x80000268u)
#define BIN_FIFO_DATA REG32(0x8000026cu)
#define BIN_FIFO_CONTROL REG32(0x80000270u)
#define BIN_FIFO_STATUS REG32(0x80000274u)

#define KEY_F12 1u
#define KEY_UP 2u
#define KEY_DOWN 4u
#define KEY_ENTER 8u
#define KEY_ESCAPE 16u
#define KEY_F11 32u
#define MAX_DSK_FILES 32u
#define MAX_NAME 256u
#define OSD_COLS 72u
#define OSD_ROWS 28u
#define OSD_FIRST_FILE_ROW 7u
#define OSD_FILE_ROWS 17u
#define OSD_LIST_RIGHT 46u
#define OSD_DETAIL_COLUMN 50u
#define OSD_GLYPH_PARENT 0x80u
#define OSD_GLYPH_FOLDER 0x81u
#define OSD_GLYPH_DISK 0x82u
#define OSD_GLYPH_CARTRIDGE 0x83u
#define OSD_GLYPH_BINARY 0x84u
#define OSD_GLYPH_HLINE 0x90u
#define OSD_GLYPH_VLINE 0x91u
#define OSD_GLYPH_TOP_LEFT 0x92u
#define OSD_GLYPH_TOP_RIGHT 0x93u
#define OSD_GLYPH_BOTTOM_LEFT 0x94u
#define OSD_GLYPH_BOTTOM_RIGHT 0x95u
#define OSD_GLYPH_T_RIGHT 0x96u
#define OSD_GLYPH_T_LEFT 0x97u
#define OSD_GLYPH_T_DOWN 0x98u
#define OSD_GLYPH_T_UP 0x99u
#define OSD_GLYPH_LEFT_BORDER 0x9au
#define OSD_GLYPH_RIGHT_BORDER 0x9bu
#define OSD_GLYPH_RULE_LEFT_CAP 0x9cu
#define OSD_GLYPH_RULE_RIGHT_CAP 0x9du
#define OSD_GLYPH_LOGO_RED 0x9eu
#define OSD_GLYPH_LOGO_GREEN 0x9fu
#define OSD_GLYPH_LOGO_BLUE 0xa0u

static uint8_t block_addressed, sectors_per_cluster, spi_divider;
static uint32_t disk_cache_crc32;
static uint32_t fat_lba, first_data_lba;
static uint8_t sector[512];

struct disk { char name[MAX_NAME]; uint32_t cluster, size; };
struct browser_entry { char name[MAX_NAME]; uint32_t cluster, size; uint8_t directory, parent, cartridge, binary; };
static struct browser_entry browser_entries[MAX_DSK_FILES];
static struct disk mounted_disk;
static struct disk pending_bin;
static uint8_t bin_pending;
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
static void deselect(void) { SPI_CTRL = ((uint32_t)spi_divider<<8)|1u; (void)xfer(0xff); }
static void select(void) { SPI_CTRL = (uint32_t)spi_divider<<8; }
static uint8_t ready(void) { for (uint32_t n=0;n<100000u;++n) if (xfer(0xff)==0xff) return 1; return 0; }
static uint8_t command(uint8_t cmd, uint32_t arg) {
    deselect(); select(); if (cmd && !ready()) return 0xff;
    (void)xfer(0x40u|cmd); (void)xfer(arg>>24); (void)xfer(arg>>16); (void)xfer(arg>>8); (void)xfer(arg);
    (void)xfer(cmd==0 ? 0x95 : (cmd==8 ? 0x87 : 1));
    for (uint8_t n=0;n<16;++n) { uint8_t r=xfer(0xff); if (!(r&0x80)) return r; }
    return 0xff;
}
static int init_card(void) {
    // Start at the SD initialization rate.  Once initialized, retain the
    // faster divider across every select/deselect instead of accidentally
    // restoring the slow divider for each command.
    spi_divider=0x40u;SPI_CTRL=((uint32_t)spi_divider<<8)|1u;for(uint8_t n=0;n<10;++n)(void)xfer(0xff);
    for(uint8_t n=0;n<32;++n) { if(command(0,0)==1) break; if(n==31)return 1; }
    if(command(8,0x1aau)!=1)return 2;
    if(xfer(0xff)||xfer(0xff)||xfer(0xff)!=1||xfer(0xff)!=0xaa)return 3;
    for(uint16_t n=0;n<2000;++n) { if(command(55,0)>1)return 4; if(command(41,0x40000000u)==0)break; if(n==1999)return 5; }
    if(command(58,0)!=0)return 6;
    { uint8_t ocr=xfer(0xff); (void)xfer(0xff);(void)xfer(0xff);(void)xfer(0xff); deselect();
      if(!(ocr&0x80))return 7;
      block_addressed=(ocr&0x40)!=0; }
    if(!block_addressed && command(16,512)!=0)return 8;
    deselect();spi_divider=8u;SPI_CTRL=((uint32_t)spi_divider<<8)|1u;return 0;
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

// Sequential FAT cursor shared by validation and delivery.  It follows a
// fragmented cluster chain once, so large BIN files do not repeatedly walk
// from the directory entry for every 512-byte block.
struct fat_file_reader {
    uint32_t cluster, offset, size;
    uint16_t sector_offset, sector_bytes;
    uint8_t sector_in_cluster;
};
static void file_reader_init(struct fat_file_reader *reader,const struct disk *file){reader->cluster=file->cluster;reader->offset=0;reader->size=file->size;reader->sector_offset=0;reader->sector_bytes=0;reader->sector_in_cluster=0;}
static int file_reader_byte(void *context,uint8_t *value){
    struct fat_file_reader *reader=context;
    if(reader->offset>=reader->size)return 1;
    if(reader->sector_offset>=reader->sector_bytes){
        if(reader->sector_in_cluster>=sectors_per_cluster){
            if(next_cluster(reader->cluster,&reader->cluster))return 2;
            reader->sector_in_cluster=0;
        }
        if(read_sector(first_data_lba+(reader->cluster-2u)*sectors_per_cluster+reader->sector_in_cluster))return 3;
        reader->sector_in_cluster++;
        reader->sector_offset=0;
        reader->sector_bytes=(reader->size-reader->offset)>=512u?512u:(uint16_t)(reader->size-reader->offset);
    }
    *value=sector[reader->sector_offset++];reader->offset++;return 0;
}
static void copy_disk(struct disk *to,const struct disk *from){for(uint16_t n=0;n<MAX_NAME;++n)to->name[n]=from->name[n];to->cluster=from->cluster;to->size=from->size;}
static void lfn_reset(void){lfn_valid=0;lfn_expected=0;lfn_checksum=0;}
static uint8_t short_checksum(const uint8_t *e){uint8_t c=0;for(uint8_t n=0;n<11;++n)c=((c&1u)?0x80u:0u)+(c>>1)+e[n];return c;}
static void lfn_part(const uint8_t *e){uint8_t order=e[0]&0x1fu;if(e[0]&0x40u){lfn_reset();lfn_expected=order;lfn_checksum=e[13];lfn_valid=1;}if(!lfn_valid||order!=lfn_expected||e[13]!=lfn_checksum){lfn_reset();return;}uint16_t base=(uint16_t)(order-1u)*13u;const uint8_t pos[]={1,3,5,7,9,14,16,18,20,22,24,28,30};for(uint8_t n=0;n<13;++n)lfn_utf16[base+n]=le16(&e[pos[n]]);lfn_expected--;}
static void short_text(const uint8_t *e,char *out){uint8_t at=0;for(uint8_t n=0;n<8&&e[n]!=' ';++n)out[at++]=(char)e[n];if(e[8]!=' '){out[at++]='.';for(uint8_t n=8;n<11&&e[n]!=' ';++n)out[at++]=(char)e[n];}out[at]=0;}
static void lfn_text(char *out){uint16_t at=0,n=0;while(n<260&&lfn_utf16[n]&&lfn_utf16[n]!=0xffffu){uint16_t c=lfn_utf16[n++];out[at++]=(c>=32u&&c<128u)?(char)c:'?';}out[at]=0;}
static int is_dsk_name(const char *name){uint16_t n=0;while(name[n])n++;return n>=4u&&name[n-4]=='.'&&((name[n-3]=='D'||name[n-3]=='d')&&(name[n-2]=='S'||name[n-2]=='s')&&(name[n-1]=='K'||name[n-1]=='k'));}
static int is_ccc_name(const char *name){uint16_t n=0;while(name[n])n++;return n>=4u&&name[n-4]=='.'&&((name[n-3]=='C'||name[n-3]=='c')&&(name[n-2]=='C'||name[n-2]=='c')&&(name[n-1]=='C'||name[n-1]=='c'));}
static int is_bin_name(const char *name){uint16_t n=0;while(name[n])n++;return n>=4u&&name[n-4]=='.'&&((name[n-3]=='B'||name[n-3]=='b')&&(name[n-2]=='I'||name[n-2]=='i')&&(name[n-1]=='N'||name[n-1]=='n'));}
static void add_entry(const uint8_t *e,const char *name,uint8_t directory){uint8_t cartridge=!directory&&is_ccc_name(name),binary=!directory&&is_bin_name(name);uint32_t size=le32(&e[28]);if(browser_count>=MAX_DSK_FILES)return;if(!directory&&((!is_dsk_name(name)&&!cartridge&&!binary)||(is_dsk_name(name)&&size!=161280u)||(cartridge&&size!=2048u&&size!=4096u&&size!=8192u)||(binary&&(size<5u||size>262144u))))return;struct browser_entry *b=&browser_entries[browser_count++];uint16_t n=0;while(name[n]&&n<MAX_NAME-1u){b->name[n]=name[n];n++;}b->name[n]=0;b->cluster=((uint32_t)le16(&e[20])<<16)|le16(&e[26]);b->size=size;b->directory=directory;b->parent=0;b->cartridge=cartridge;b->binary=binary;}
static int scan_directory(uint32_t directory){uint32_t cluster=directory;browser_count=0;lfn_reset();if(directory!=root_cluster){struct browser_entry *b=&browser_entries[browser_count++];b->name[0]='.';b->name[1]='.';b->name[2]=0;b->cluster=parent_directory;b->size=0;b->directory=1;b->parent=1;}for(;;){for(uint8_t s=0;s<sectors_per_cluster;++s){if(read_sector(first_data_lba+(cluster-2u)*sectors_per_cluster+s))return 1;for(uint16_t o=0;o<512;o+=32){const uint8_t *e=&sector[o];if(!e[0])return 0;if(e[0]==0xe5){lfn_reset();continue;}if(e[11]==0x0f){lfn_part(e);continue;}if(e[11]&0x08){lfn_reset();continue;}char name[MAX_NAME];if(lfn_valid&&lfn_expected==0&&short_checksum(e)==lfn_checksum)lfn_text(name);else short_text(e,name);lfn_reset();if(name[0]=='.')continue;add_entry(e,name,(e[11]&0x10u)!=0);}}if(next_cluster(cluster,&cluster))break;}return 0;}
static int mount_filesystem(void) {
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
    // A card being present does not imply that a disk is mounted.  Defer the
    // directory scan and full-image cache load until the user opens F12 and
    // explicitly selects a DSK.
    browser_count=0;mounted_disk.name[0]=0;mounted_disk.cluster=0;mounted_disk.size=0;DISK_CACHE_RESET=0;
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
static void short_name(const struct disk *d,char *text){uint16_t n=0;while(d->name[n]&&n<MAX_NAME-1u){text[n]=d->name[n];n++;}text[n]=0;}
static void osd_text(uint8_t row,uint8_t column,const char *text);
static void entry_line(const struct browser_entry *e,char *line){
    uint8_t at=0;
    const uint8_t width=OSD_LIST_RIGHT-4u;
    if(e->parent){line[at++]='.';line[at++]='.';line[at]=0;return;}
    for(uint16_t n=0;e->name[n]&&at<width;n++)line[at++]=e->name[n];
    if(e->name[at]&&width>=3u){line[width-3u]='.';line[width-2u]='.';line[width-1u]='.';at=width;}
    line[at]=0;
}
/* Codes 80-84 select project-owned 8x16 icons in manager_osd.  Keeping the
 * file type graphical here removes the old [DIR]/[CCC]/[BIN] prefixes and
 * leaves more of the narrow list pane available for long FAT32 names. */
static const char *entry_icon(const struct browser_entry *e){
    static const char parent_icon[]={ (char)OSD_GLYPH_PARENT,0 };
    static const char folder_icon[]={ (char)OSD_GLYPH_FOLDER,0 };
    static const char disk_icon[]={ (char)OSD_GLYPH_DISK,0 };
    static const char cartridge_icon[]={ (char)OSD_GLYPH_CARTRIDGE,0 };
    static const char binary_icon[]={ (char)OSD_GLYPH_BINARY,0 };
    if(e->parent)return parent_icon;
    if(e->directory)return folder_icon;
    if(e->cartridge)return cartridge_icon;
    if(e->binary)return binary_icon;
    return disk_icon;
}
static void draw_entry_icon(uint8_t row,const struct browser_entry *e){
    osd_text(row,2,entry_icon(e));
}
static uint32_t cartridge_signature_step(uint32_t signature,uint16_t address,uint8_t value){
    return ((signature<<1)|(signature>>31))^((uint32_t)address<<8)^value;
}
static int load_cartridge(const struct browser_entry *e){
    uint32_t offset=0,lba,signature=0;
    uint16_t n,copy;
    CARTRIDGE_CONTROL=0;
    while(offset<e->size){
        if(disk_lba((const struct disk *)e,offset&~511u,&lba))return 1;
        if(read_sector(lba))return 2;
        for(n=0;n<512u&&offset+n<e->size;++n)
            for(copy=offset+n;copy<8192u;copy+=e->size){
                uint8_t value=sector[(offset+n)&511u];
                CARTRIDGE_ADDRESS=copy;
                CARTRIDGE_DATA=value;
                signature=cartridge_signature_step(signature,copy,value);
            }
        offset=(offset&~511u)+512u;
    }
    if(CARTRIDGE_SIGNATURE!=signature)return 3;
    CARTRIDGE_CONTROL=3;
    return 0;
}
static int install_bin_loader(void){
    uint32_t signature=0;
    CARTRIDGE_CONTROL=0;
    for(uint16_t address=0;address<DECB_BIN_LOADER_SIZE;++address){
        uint8_t value=decb_bin_loader_image[address];
        CARTRIDGE_ADDRESS=address;CARTRIDGE_DATA=value;
        signature=cartridge_signature_step(signature,address,value);
    }
    return CARTRIDGE_SIGNATURE==signature?0:1;
}
static int prepare_bin(const struct browser_entry *entry,struct decb_bin_info *info){
    struct fat_file_reader reader;
    struct disk file;
    for(uint16_t n=0;n<MAX_NAME;++n)file.name[n]=entry->name[n];
    file.cluster=entry->cluster;file.size=entry->size;
    file_reader_init(&reader,&file);
    int result=decb_bin_validate(file_reader_byte,&reader,file.size,info);
    if(result)return result;
    if(install_bin_loader())return 0x20;
    copy_disk(&pending_bin,&file);bin_pending=1;
    pending_bin.size=info->stream_bytes; // Disk BASIC ignores granule padding after the postamble.
    BIN_FIFO_CONTROL=3;        // reset FIFO and mark producer active
    CARTRIDGE_CONTROL=3;       // proven cold-start/CART launch sequence
    return 0;
}
static int stream_bin(void){
    struct fat_file_reader reader;
    uint8_t value;
    file_reader_init(&reader,&pending_bin);
    while(reader.offset<reader.size){
        uint32_t status;
        if(file_reader_byte(&reader,&value)){BIN_FIFO_CONTROL=8;return 1;}
        do {status=BIN_FIFO_STATUS;if(status&(1u<<20))return 2;} while((status&31u)==16u);
        BIN_FIFO_DATA=value;
    }
    BIN_FIFO_CONTROL=4;        // all source bytes queued; let the loader drain
    for(;;){
        uint32_t status=BIN_FIFO_STATUS;
        if(status&(1u<<16))return 0;
        if(status&(1u<<20))return 2;
    }
}
static void osd_clear(void){OSD_ADDRESS=0;for(uint16_t n=0;n<OSD_COLS*OSD_ROWS;++n)OSD_DATA=' ';}
static void osd_char(uint8_t row,uint8_t column,char value){OSD_ADDRESS=(uint32_t)row*OSD_COLS+column;OSD_DATA=(uint8_t)value;}
static void osd_text_to(uint8_t row,uint8_t column,uint8_t last,const char *text){
    OSD_ADDRESS=(uint32_t)row*OSD_COLS+column;
    while(*text&&column<=last&&column<OSD_COLS){OSD_DATA=(uint8_t)*text++;column++;}
}
static void osd_text(uint8_t row,uint8_t column,const char *text){osd_text_to(row,column,OSD_COLS-2u,text);}
static void osd_center(uint8_t row,const char *text){
    uint8_t length=0;while(text[length])length++;
    osd_text(row,(uint8_t)((OSD_COLS-length)/2u),text);
}
static void osd_logo(uint8_t row){
    /* 16 cells: "CoCo 3", gap, RGB slashes, gap, "Elite". */
    const uint8_t left=(OSD_COLS-16u)/2u;
    osd_text(row,left,"CoCo 3");
    osd_char(row,left+7u,(char)OSD_GLYPH_LOGO_RED);
    osd_char(row,left+8u,(char)OSD_GLYPH_LOGO_GREEN);
    osd_char(row,left+9u,(char)OSD_GLYPH_LOGO_BLUE);
    osd_text(row,left+11u,"Elite");
}
static void osd_outer_rule(uint8_t row,uint8_t left,uint8_t right){
    osd_char(row,0,(char)left);
    for(uint8_t column=1;column<OSD_COLS-1u;column++)osd_char(row,column,(char)OSD_GLYPH_HLINE);
    osd_char(row,OSD_COLS-1u,(char)right);
}
static void osd_inner_rule(uint8_t row,uint8_t middle){
    // Leave five clear pixels between each rule cap and the three-pixel
    // rounded outer frame.  The border cells themselves remain untouched.
    osd_char(row,1,(char)OSD_GLYPH_RULE_LEFT_CAP);
    for(uint8_t column=2;column<OSD_COLS-2u;column++)osd_char(row,column,(char)OSD_GLYPH_HLINE);
    osd_char(row,OSD_COLS-2u,(char)OSD_GLYPH_RULE_RIGHT_CAP);
    if(middle)osd_char(row,OSD_LIST_RIGHT+1u,(char)middle);
}
static void osd_frame(void){
    for(uint8_t row=1;row<OSD_ROWS-1u;row++){osd_char(row,0,(char)OSD_GLYPH_LEFT_BORDER);osd_char(row,OSD_COLS-1u,(char)OSD_GLYPH_RIGHT_BORDER);}
    for(uint8_t row=OSD_FIRST_FILE_ROW;row<24u;row++)osd_char(row,OSD_LIST_RIGHT+1u,(char)OSD_GLYPH_VLINE);
    osd_outer_rule(0,OSD_GLYPH_TOP_LEFT,OSD_GLYPH_TOP_RIGHT);
    osd_inner_rule(3,0);
    osd_inner_rule(6,OSD_GLYPH_T_DOWN);
    osd_inner_rule(24,OSD_GLYPH_T_UP);
    osd_outer_rule(OSD_ROWS-1u,OSD_GLYPH_BOTTOM_LEFT,OSD_GLYPH_BOTTOM_RIGHT);
}
static void osd_tail(uint8_t row,uint8_t column,uint8_t width,const char *text){
    uint16_t length=0;while(text[length])length++;
    if(length<=width){osd_text_to(row,column,(uint8_t)(column+width-1u),text);return;}
    osd_text_to(row,column,(uint8_t)(column+width-1u),"...");
    osd_text_to(row,(uint8_t)(column+3u),(uint8_t)(column+width-1u),text+length-(width-3u));
}
static void osd_size(uint8_t row,uint8_t column,uint32_t value){
    char text[17];uint8_t at=0;
    if(!value)text[at++]='0';
    else {while(value&&at<10u){text[at++]=(char)('0'+value%10u);value/=10u;}for(uint8_t left=0,right=at-1u;left<right;left++,right--){char c=text[left];text[left]=text[right];text[right]=c;}}
    text[at++]=' ';text[at++]='b';text[at++]='y';text[at++]='t';text[at++]='e';text[at++]='s';text[at]=0;
    osd_text_to(row,column,OSD_COLS-2u,text);
}
static const char *entry_type(const struct browser_entry *entry){
    if(entry->parent)return "Parent";
    if(entry->directory)return "Directory";
    if(entry->cartridge)return "Cartridge";
    if(entry->binary)return "DECB binary";
    return "DSK image";
}
static const char *entry_action(const struct browser_entry *entry){
    if(entry->parent)return "Up one level";
    if(entry->directory)return "Enter to open";
    if(entry->cartridge||entry->binary)return "Ready to run";
    if(entry->cluster==mounted_disk.cluster&&mounted_disk.cluster)return "Mounted D0";
    return "Ready to mount";
}
static void draw_details(const struct browser_entry *entry){
    osd_text(7,OSD_DETAIL_COLUMN,"Type");osd_text(8,OSD_DETAIL_COLUMN,entry_type(entry));
    if(!entry->directory){osd_text(10,OSD_DETAIL_COLUMN,"Size");osd_size(11,OSD_DETAIL_COLUMN,entry->size);}
    osd_text(13,OSD_DETAIL_COLUMN,entry_action(entry));
    if(entry->cartridge)osd_text(14,OSD_DETAIL_COLUMN,"Cold start");
    else if(entry->binary)osd_text(14,OSD_DETAIL_COLUMN,"Check on run");
    else if(!entry->directory)osd_text(14,OSD_DETAIL_COLUMN,"CRC on mount");
}
static uint8_t menu_selection,menu_top;
static void draw_menu(const char *status){
    char name[MAX_NAME],line[OSD_COLS];
    if(menu_selection<menu_top)menu_top=menu_selection;
    if(menu_selection>=menu_top+OSD_FILE_ROWS)menu_top=menu_selection-OSD_FILE_ROWS+1u;
    osd_clear();osd_frame();
    osd_logo(1);osd_center(2,"Disk browser");
    osd_text(4,2,"Drive 0:");short_name(&mounted_disk,name);osd_text_to(4,11,OSD_COLS-2u,name[0]?name:"<empty>");
    osd_text(5,2,"Path:");osd_tail(5,8,OSD_COLS-10u,current_path);
    for(uint8_t row=0;row<OSD_FILE_ROWS;++row){
        uint8_t index=menu_top+row;
        if(index>=browser_count)break;
        entry_line(&browser_entries[index],line);
        osd_text(OSD_FIRST_FILE_ROW+row,1,
                 browser_entries[index].cluster==mounted_disk.cluster?"*":" ");
        draw_entry_icon(OSD_FIRST_FILE_ROW+row,&browser_entries[index]);
        osd_text(OSD_FIRST_FILE_ROW+row,4,line);
    }
    if(browser_count)draw_details(&browser_entries[menu_selection]);
    osd_text_to(25,2,OSD_COLS-2u,status);
    osd_center(26,"Up/down select   Enter mount/run   Esc/F12 exit");
    OSD_CONTROL=((uint32_t)(browser_count?(OSD_FIRST_FILE_ROW+menu_selection-menu_top):31u)<<8)|1u;
}
static int run_disk_menu(uint8_t *present){
    uint32_t previous,keys,pressed;
    char name[MAX_NAME];
    uint8_t scan_failed=0;
    menu_selection=0;menu_top=0;browser_count=0;
    draw_menu("Reading SD directory - please wait");
    puts("MENU OPEN\r\n");
    if(!card_online||scan_directory(current_directory)){
        scan_failed=1;draw_menu("SD directory read failed - Esc/F12 to exit");
    }else{
        for(uint8_t n=0;n<browser_count;++n)if(browser_entries[n].cluster==mounted_disk.cluster){menu_selection=n;break;}
        draw_menu(browser_count?"Select DSK, CCC, BIN or directory":"No compatible DSK, CCC or BIN files");
    }
    while(MENU_KEY_STATE&KEY_F12){}
    previous=MENU_KEY_STATE;
    for(;;){
        keys=MENU_KEY_STATE;pressed=keys&~previous;previous=keys;
        if(pressed&(KEY_ESCAPE|KEY_F12)){
            while(MENU_KEY_STATE&(KEY_ESCAPE|KEY_F12)){}
            OSD_CONTROL=0;puts("MENU CLOSE\r\n");return scan_failed;
        }
        if((pressed&KEY_UP)&&browser_count){
            menu_selection=menu_selection?menu_selection-1u:browser_count-1u;
            draw_menu("Select a disk for drive 0");
        }
        if((pressed&KEY_DOWN)&&browser_count){
            menu_selection=(menu_selection+1u==browser_count)?0:menu_selection+1u;
            draw_menu("Select a disk for drive 0");
        }
        if((pressed&KEY_ENTER)&&browser_count){
            if(browser_entries[menu_selection].directory){
                if(browser_entries[menu_selection].parent){if(directory_depth){current_directory=directory_stack[--directory_depth];parent_directory=directory_depth?directory_stack[directory_depth-1u]:root_cluster;uint16_t p=0;while(current_path[p]&&p<MAX_NAME)p++;while(p>1u&&current_path[p-1u]!='/')p--;if(p==1u)current_path[1]=0;else current_path[p-1u]=0;scan_directory(current_directory);}}
                else {if(directory_depth<8u)directory_stack[directory_depth++]=current_directory;parent_directory=current_directory;current_directory=browser_entries[menu_selection].cluster;uint16_t p=0;while(current_path[p])p++;if(p>1&&current_path[p-1]!='/'){current_path[p++]='/';}for(uint16_t n=0;browser_entries[menu_selection].name[n]&&p<MAX_NAME-1u;n++)current_path[p++]=browser_entries[menu_selection].name[n];current_path[p]=0;scan_directory(current_directory);}
                menu_selection=0;menu_top=0;draw_menu("Select a disk for drive 0");continue;
            }
            if(browser_entries[menu_selection].cartridge){
                draw_menu("Loading cartridge - please wait");
                if(!load_cartridge(&browser_entries[menu_selection])){puts("CARTRIDGE LOADED ");puts(browser_entries[menu_selection].name);puts("\r\n");while(MENU_KEY_STATE&KEY_ENTER){}OSD_CONTROL=0;return 0;}
                draw_menu("Cartridge load failed");continue;
            }
            if(browser_entries[menu_selection].binary){
                struct decb_bin_info info;
                draw_menu("Validating DECB BIN - please wait");
                int result=prepare_bin(&browser_entries[menu_selection],&info);
                if(!result){puts("BIN READY ");puts(browser_entries[menu_selection].name);puts(" EXEC ");hex((uint8_t)(info.execution_address>>8));hex((uint8_t)info.execution_address);puts("\r\n");while(MENU_KEY_STATE&KEY_ENTER){}OSD_CONTROL=0;return 0;}
                draw_menu(result==DECB_BIN_LOADER_OVERLAP?"BIN uses reserved FE00-FEFF":"Invalid or unsupported DECB BIN");continue;
            }
            struct disk candidate;
            for(uint16_t n=0;n<MAX_NAME;++n)candidate.name[n]=browser_entries[menu_selection].name[n];
            candidate.cluster=browser_entries[menu_selection].cluster;candidate.size=browser_entries[menu_selection].size;
            draw_menu("Mounting drive 0 - please wait");
            MOUNT_STATUS=0;
            if(!load_disk_cache(&candidate)){
                copy_disk(&mounted_disk,&candidate);*present=1;MOUNT_STATUS=0x101u;
                short_name(&mounted_disk,name);puts("MOUNT D0 ");puts(name);puts(" CRC32 ");hex32(disk_cache_crc32);puts("\r\n");
                while(MENU_KEY_STATE&KEY_ENTER){}
                OSD_CONTROL=0;return 0;
            }
            *present=0;MOUNT_STATUS=0x100u;
            draw_menu("Mount failed - select another disk");
        }
    }
}
int main(void){
    int error=init_card(); uint8_t present=0;
    puts("RV32 SD MOUNT\r\n");
    if(!error)card_online=1;
    if(!error)error=mount_filesystem();
    if(error){puts("MOUNT ERR ");hex((uint8_t)error);puts("\r\n");}
    else puts("SD READY - F12\r\n");
    MOUNT_STATUS=card_online?(0x100u|present):0;
    uint32_t seen=FDC_STATE&1u, seen_complete=(FDC_STATE>>11)&1u, seen_write=(FDC_STATE>>12)&1u;
    // Treat F12 held during SD initialization as the first menu request.
    uint32_t menu_previous=0, retry=0, probe=0;
    for(;;){
        if(!card_online){
            if(!retry--){
                if(!init_card()){card_online=1;error=mount_filesystem();present=0;if(!error){puts("SD REINSERTED - F12\r\n");MOUNT_STATUS=0x100u;}else media_lost();retry=3000000u;}
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
         if((keys&KEY_F11)&&!(menu_previous&KEY_F11)){
             puts("SETUP OPEN\r\n");settings_ui_run();puts("SETUP CLOSE\r\n");
         } else if((keys&KEY_F12)&&!(menu_previous&KEY_F12)){
             error=run_disk_menu(&present);
             if(bin_pending){int result=stream_bin();bin_pending=0;puts(result?"BIN LOAD CANCELLED\r\n":"BIN STARTED\r\n");}
         }
         menu_previous=MENU_KEY_STATE;}
    }
}
