#include <stdint.h>

// Read-only FAT32-to-DECB service for the RV32 manager.  The normal CoCo
// image never parses FAT and never bit-bangs SPI: it asks for an already
// mounted raw 256-byte sector through the small FDC mailbox.
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
#define DISK_CACHE_RESET REG32(0x80000230u)
#define DISK_CACHE_DATA REG32(0x80000234u)
#define DISK_CACHE_COMMIT REG32(0x80000238u)
#define DISK_CACHE_STATUS REG32(0x8000023cu)

static uint8_t block_addressed, sectors_per_cluster, last_buffer_byte0;
static uint32_t fat_lba, first_data_lba;
static uint8_t sector[512];

struct disk { const char *name; uint32_t cluster, size; };
static const char zenix_name[11] = {'Z','E','N','I','X',' ',' ',' ','D','S','K'};
static const char games_name[11] = {'G','A','M','E','S',' ',' ',' ','D','S','K'};
static const char fpgatest_name[11] = {'F','P','G','A','T','E','S','T','D','S','K'};
static struct disk disks[3] = {{zenix_name,0,0},{games_name,0,0},{fpgatest_name,0,0}};

static void putc(char c) { while (UART_STATUS & 1u) {} UART_DATA = (uint8_t)c; }
static void puts(const char *s) { while (*s) putc(*s++); }
static void hex(uint8_t n) { static const char h[]="0123456789ABCDEF"; putc(h[n>>4]); putc(h[n&15]); }
static void hex32(uint32_t n) { hex((uint8_t)(n>>24)); hex((uint8_t)(n>>16)); hex((uint8_t)(n>>8)); hex((uint8_t)n); }
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
static uint16_t le16(const uint8_t *p){return (uint16_t)p[0]|((uint16_t)p[1]<<8);}
static uint32_t le32(const uint8_t *p){return(uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static int next_cluster(uint32_t cluster,uint32_t *next){if(read_sector(fat_lba+(cluster>>7)))return 1;*next=le32(&sector[(cluster&127u)*4u])&0x0fffffffu;return *next<2||*next>=0x0ffffff8u;}
static int name_is(const uint8_t *entry,const char *name){for(uint8_t n=0;n<11;++n)if(entry[n]!=(uint8_t)name[n])return 0;return 1;}
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
                if(e[0]!=0xe5&&e[11]!=0x0f&&!(e[11]&0x18))for(uint8_t d=0;d<3;++d)if(!disks[d].cluster&&name_is(e,disks[d].name)){disks[d].cluster=((uint32_t)le16(&e[20])<<16)|le16(&e[26]);disks[d].size=le32(&e[28]);}
            }
        }
        if(next_cluster(scan_cluster,&scan_cluster))break;
    }
done: return 0;
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
// Populate the FPGA's one-drive BRAM cache in FAT file order.  The cache has
// the raw 161,280-byte DECB layout, so the FDC can subsequently address it
// exactly as it addressed a bitstream-initialized DSK image.
static int load_disk_cache(const struct disk *d){
    uint32_t cluster=d->cluster, remaining=d->size;
    if(!cluster||remaining!=161280u)return 1;
    DISK_CACHE_RESET=0;
    while(remaining){
        for(uint8_t s=0;s<sectors_per_cluster&&remaining;++s){
            uint16_t count=remaining>=512u?512u:(uint16_t)remaining;
            if(read_sector(first_data_lba+(cluster-2u)*sectors_per_cluster+s))return 2;
            for(uint16_t n=0;n<count;++n)DISK_CACHE_DATA=sector[n];
            remaining-=count;
        }
        if(remaining&&next_cluster(cluster,&cluster))return 3;
    }
    DISK_CACHE_COMMIT=1;
    return (DISK_CACHE_STATUS&1u)?0:4;
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
    if(copy_decb_sector(&disks[0],17,3))return;
    for(n=0;n<64;++n)directory[n]=sector[n];
    if(copy_decb_sector(&disks[0],17,2))return;
    for(n=0;n<2;++n){const uint8_t *entry=&directory[n*32u];
        if(entry[0]==0||entry[0]==0xff)return;
        // Track 17 sector 2 is the second 256-byte DECB sector in this
        // 512-byte FAT block, so the GAT begins at byte 256.
        puts("AUDIT D0 ");print_decb_name(entry);puts(" BYTES ");hex32(decb_file_size(entry,&sector[256]));puts("\r\n");
    }
}
int main(void){
    int error=init_card(); uint8_t present=0;
    puts("RV32 SD MOUNT\r\n");
    if(!error)error=mount_disks();
    if(!error&&disks[0].cluster&&disks[0].size==161280u){puts("CACHE D0\r\n");error=load_disk_cache(&disks[0]);if(!error)present=1;}
    if(error){puts("MOUNT ERR ");hex((uint8_t)error);puts("\r\n");}
    else { puts("DRIVES ");hex(present);puts(" ZENIX,GAMES,FPGATEST\r\n"); }
    MOUNT_STATUS=0x100u|present;
    if(!error&&(present&1u))audit_drive0();
    uint32_t seen=FDC_STATE&1u, seen_complete=(FDC_STATE>>11)&1u;
    for(;;){
        uint32_t state=FDC_STATE;
        if(((state>>11)&1u)!=seen_complete){uint32_t word=FDC_COMPLETED_DEBUG_WORD;
            puts("FDC CPU ");hex((uint8_t)(word>>24));putc(' ');hex((uint8_t)(word>>16));putc(' ');hex((uint8_t)(word>>8));putc(' ');hex((uint8_t)word);puts("\r\n");
            seen_complete=(state>>11)&1u;}
        if((state&1u)!=seen){uint32_t info=FDC_INFO;uint8_t drive=info&3u, disk_sector=(info>>8)&0xffu, track=(info>>16)&0xffu, type1=info>>24;
            int ok=error==0&&drive==0&&(present&1u);
            puts(ok ? "FDC CACHE " : "FDC ERR "); hex(drive);putc(' ');hex(track);putc(' ');hex(disk_sector);putc(' ');hex(type1);
            puts("\r\n");
            FDC_ACK=ok?1:0; seen=state&1u;
        }
    }
}
