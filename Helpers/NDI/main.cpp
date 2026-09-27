// This independently usable raw video/audio sender is MIT licensed; see LICENSE.txt.
#include <cstddef>
#include "Processing.NDI.Lib.h"
#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <iostream>
#include <vector>
#include <stdexcept>
#include <cstring>
#include <string>
#include <cstdint>
using namespace std;
template<class T>T symbol(void*h,const char*n){auto p=dlsym(h,n);if(!p)throw runtime_error(string("Missing NDI symbol: ")+n);return reinterpret_cast<T>(p);}
static uint32_t u32(const uint8_t*p){return p[0]|uint32_t(p[1])<<8|uint32_t(p[2])<<16|uint32_t(p[3])<<24;}
static int64_t i64(const uint8_t*p){uint64_t v=0;for(int i=7;i>=0;--i)v=(v<<8)|p[i];return int64_t(v);}
int main(int argc,char**argv){ios::sync_with_stdio(false);cin.tie(nullptr);try{
 if(argc<3)throw runtime_error("Usage: NDISender runtime-path name-or---probe; stdin: framed BGRA/PCM");
 void*h=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!h)throw runtime_error(dlerror());
 auto init=symbol<decltype(&NDIlib_initialize)>(h,"NDIlib_initialize");auto destroy=symbol<decltype(&NDIlib_destroy)>(h,"NDIlib_destroy");
 auto version=symbol<decltype(&NDIlib_version)>(h,"NDIlib_version");if(!init())throw runtime_error("NDI initialization failed");
 if(string(argv[2])=="--probe"){cout<<"PASS bundled runtime "<<version()<<" from "<<argv[1]<<endl;destroy();dlclose(h);return 0;}
 const size_t slotSize=3840*2160*4;uint8_t*shared=nullptr;int sharedFD=-1;
 if(argc>3){sharedFD=shm_open(argv[3],O_RDONLY,0);if(sharedFD<0)throw runtime_error("Cannot open shared frame memory");struct stat st;if(fstat(sharedFD,&st)||st.st_size!=int64_t(slotSize*2))throw runtime_error("Invalid shared frame memory size");shared=(uint8_t*)mmap(nullptr,slotSize*2,PROT_READ,MAP_SHARED,sharedFD,0);if(shared==MAP_FAILED)throw runtime_error("Cannot map shared frames");}
 auto create=symbol<decltype(&NDIlib_send_create)>(h,"NDIlib_send_create");auto close=symbol<decltype(&NDIlib_send_destroy)>(h,"NDIlib_send_destroy");
 auto video=symbol<decltype(&NDIlib_send_send_video_v2)>(h,"NDIlib_send_send_video_v2");auto audio=symbol<decltype(&NDIlib_util_send_send_audio_interleaved_16s)>(h,"NDIlib_util_send_send_audio_interleaved_16s");
 NDIlib_send_create_t settings;settings.p_ndi_name=argv[2];settings.clock_video=false;settings.clock_audio=false;auto sender=create(&settings);if(!sender)throw runtime_error("Cannot create NDI sender");cout<<"READY "<<version()<<endl;
 while(true){uint8_t header[24];cin.read((char*)header,24);if(cin.gcount()==0&&cin.eof())break;if(cin.gcount()!=24)throw runtime_error("Truncated header");auto type=u32(header),size=u32(header+4),w=u32(header+8),hgt=u32(header+12);auto pts=i64(header+16);
  if(size>3840*2160*4 || type>1)throw runtime_error("Invalid frame length/type");
  if(type==0 && (w==0||hgt==0||w>3840||hgt>2160||uint64_t(w)*hgt*4!=size))throw runtime_error("Invalid BGRA dimensions");
  if(type==1 && (size==0||size%4||size>4800*4))throw runtime_error("Invalid PCM frame");
  vector<uint8_t>data;uint8_t*bytes=nullptr;uint32_t slot=0;
  if(type==0 && shared){uint8_t index[4];cin.read((char*)index,4);if(cin.gcount()!=4)throw runtime_error("Missing slot");slot=u32(index);if(slot>1)throw runtime_error("Invalid slot");bytes=shared+slot*slotSize;}
  else {data.resize(size);cin.read((char*)data.data(),size);if(cin.gcount()!=size)throw runtime_error("Truncated payload");bytes=data.data();}
  if(type==0){NDIlib_video_frame_v2_t f;f.xres=w;f.yres=hgt;f.FourCC=NDIlib_FourCC_type_BGRA;f.frame_rate_N=60000;f.frame_rate_D=1001;f.picture_aspect_ratio=float(w)/hgt;f.frame_format_type=NDIlib_frame_format_type_progressive;f.timecode=pts*10;f.p_data=bytes;f.line_stride_in_bytes=w*4;video(sender,&f);if(shared)cout<<"DONE "<<slot<<endl;}
  else{NDIlib_audio_frame_interleaved_16s_t f;f.sample_rate=48000;f.no_channels=2;f.no_samples=size/4;f.timecode=pts*10;f.p_data=(int16_t*)bytes;audio(sender,&f);}
 }
 close(sender);if(shared)munmap(shared,slotSize*2);if(sharedFD>=0)::close(sharedFD);destroy();dlclose(h);return 0;
 }catch(const exception&e){cerr<<"NDI ERROR "<<e.what()<<endl;return 1;}}
