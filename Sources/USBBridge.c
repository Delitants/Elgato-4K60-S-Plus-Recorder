/* GPL-2.0. Capture controls adapted from Saddytech/elgato4k60sp-linux. */
#include "USBBridge.h"
#include <libusb.h>
#include <stdlib.h>
#include <stdio.h>
struct CaptureHandle { libusb_context *context; libusb_device_handle *device; int claimed; int enabled; };
static int write_control(CaptureHandle*h,int request,int value,unsigned char*data,int size){
 int r=libusb_control_transfer(h->device,0x41,request,value,0,data,size,1200);
 /* These are idempotent volatile configuration writes; retry one transient timeout. */
 if(r==LIBUSB_ERROR_TIMEOUT)r=libusb_control_transfer(h->device,0x41,request,value,0,data,size,1200);
 return r==size?0:(r<0?r:LIBUSB_ERROR_IO);
}
void capture_close(CaptureHandle*h){
 if(!h)return;
 if(h->device){
  if(h->enabled){unsigned char stop[4]={0};write_control(h,0x31,0x80,stop,4);}
  if(h->claimed)libusb_release_interface(h->device,0);
  libusb_close(h->device);
 }
 if(h->context)libusb_exit(h->context);free(h);
}
CaptureHandle *capture_open(char*error,int size){return capture_open_config(0,1920,1080,40,error,size);}
CaptureHandle *capture_open_config(int hevc,int width,int height,int mbps,char*error,int size){
 if((hevc!=0&&hevc!=1)||(width!=1920&&width!=3840)||(height!=1080&&height!=2160)||mbps<1||mbps>(hevc?140:200)){snprintf(error,size,"Invalid capture profile");return NULL;}
 CaptureHandle*h=calloc(1,sizeof(*h));if(!h){snprintf(error,size,"Out of memory");return NULL;}
 char stage_buffer[80];
 int r=libusb_init(&h->context);const char*stage="USB initialization";
 if(r<0)goto fail;
 h->device=libusb_open_device_with_vid_pid(h->context,0x0fd9,0x0075);
 if(!h->device)h->device=libusb_open_device_with_vid_pid(h->context,0x0fd9,0x0068);
 if(!h->device){snprintf(error,size,"Cannot open 4K60 S+. Check USB connection and close other capture apps.");capture_close(h);return NULL;}
 if(libusb_get_device_speed(libusb_get_device(h->device))<LIBUSB_SPEED_SUPER){snprintf(error,size,"USB 3 connection required. Use a 5 Gbps data cable.");capture_close(h);return NULL;}
 int cfg=0;stage="Read USB configuration";r=libusb_get_configuration(h->device,&cfg);if(r<0)goto fail;
 if(cfg!=2){stage="Select USB configuration";r=libusb_set_configuration(h->device,2);if(r<0)goto fail;}
 stage="Claim USB capture interface";r=libusb_claim_interface(h->device,0);if(r<0)goto fail;h->claimed=1;
 unsigned char tmp[8]={0},z[4]={0},audio[4]={128,128,128,128},fmt[3]={1,0,2},vol[4]={176,0,0,0},en[4]={1,0,0,0},post[3]={1,0,6};
 unsigned char video[]={0,0xf7,0xa6,0,0,1,0x0f,0,0,0,3,0,0x29,0,8,0x80,7,0,0,0x38,4,0,0,1,0x70,0x17};
 /* Volatile encoder configuration. Layout verified against the vendor driver and a
    3840x2160 HEVC Main 10 capture; no firmware or persistent settings written. */
 video[0]=(unsigned char)hevc;video[14]=hevc?10:8;
 video[12]=hevc?153:(width==3840?52:41);
 unsigned bitrate=(unsigned)mbps*1000;
 for(int i=0;i<4;i++){video[1+i]=(bitrate>>(8*i))&255;video[15+i]=((unsigned)width>>(8*i))&255;video[19+i]=((unsigned)height>>(8*i))&255;}
 /* Reference reads are optional and can time out on a healthy device. */
 libusb_control_transfer(h->device,0xc1,0x30,0x40,0,tmp,8,300);
 libusb_control_transfer(h->device,0xc1,0x30,0x90,0,tmp,4,300);
 libusb_control_transfer(h->device,0xc1,0x30,0xa0,0,tmp,4,300);
 #define W(req,val,b,n) do{snprintf(stage_buffer,sizeof(stage_buffer),"Configure capture (request %02x, register %04x)",req,val);stage=stage_buffer;r=write_control(h,req,val,b,n);if(r<0)goto fail;}while(0)
 W(0x31,0x84,z,4);W(0x31,0xb8,audio,4);W(0x31,0xb4,z,1);W(0x38,0,z,1);
 W(0x3e,0x300,fmt,3);W(0x31,0x88,vol,4);W(0x31,0x50,video,26);
 h->enabled=1;W(0x31,0x80,en,4);write_control(h,0x3e,0x8002,post,3);return h;
 fail:snprintf(error,size,"%s: %s",stage,libusb_error_name(r));capture_close(h);return NULL;
}
int capture_read(CaptureHandle*h,uint8_t*buffer,int capacity){
 int count=0;int r=libusb_bulk_transfer(h->device,0x81,buffer,capacity,&count,100);
 if(count>0)return count;if(r==LIBUSB_ERROR_TIMEOUT)return 0;return r<0?r:0;
}

#include <sys/mman.h>
#include <fcntl.h>
int capture_shared_memory_open(const char *name) { return shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600); }
