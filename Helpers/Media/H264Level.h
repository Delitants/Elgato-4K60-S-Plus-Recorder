#pragma once
#include <algorithm>
#include <cstdint>
#include <stdexcept>
#include <string>

// H.264 Annex A (tables A-1/A-2); common capture levels supported by both
// VideoToolbox and x264. Bitrates below use conservative VCL limits.
struct H264LevelLimits {
 const char *name; int id, frameMBs, secondMBs, dpbMBs, kbps, cpbKbits;
};
inline H264LevelLimits h264LevelLimits(const std::string &name) {
 static const H264LevelLimits levels[]={
  {"3.0",30,1620,40500,8100,10000,10000},
  {"3.1",31,3600,108000,18000,14000,14000},
  {"3.2",32,5120,216000,20480,20000,20000},
  {"4.0",40,8192,245760,32768,20000,25000},
  {"4.1",41,8192,245760,32768,50000,62500},
  {"4.2",42,8704,522240,34816,50000,62500},
  {"5.0",50,22080,589824,110400,135000,135000},
  {"5.1",51,36864,983040,184320,240000,240000},
  {"5.2",52,36864,2073600,184320,240000,240000}
 };
 for(auto level:levels)if(name==level.name)return level;
 throw std::runtime_error("Unknown H.264 level: "+name);
}
inline void validateH264Level(const H264LevelLimits &level,int width,int height,int rateN,int rateD,int64_t bitrate) {
 int64_t w=(width+15)/16,h=(height+15)/16,mb=w*h;
 if(w<=0 || h<=0 || rateN<=0 || rateD<=0 || mb>level.frameMBs || w*w>8LL*level.frameMBs || h*h>8LL*level.frameMBs || mb*rateN>int64_t(level.secondMBs)*rateD)
  throw std::runtime_error(std::string("H.264 level ")+level.name+" cannot support this output resolution/frame rate. Lower output FPS or resolution, or choose a higher level.");
 if(bitrate>int64_t(level.kbps)*1000)
  throw std::runtime_error(std::string("H.264 level ")+level.name+" cannot support the requested video bitrate. Lower bitrate or choose a higher level.");
}
inline int h264ConfigurationLevel(const uint8_t *data,int size) {
 if(!data || size<4)return -1;
 if(data[0]==1)return data[3]; // AVCDecoderConfigurationRecord
 for(int i=0;i+4<size;++i){
  int n=0;
  if(data[i]==0 && data[i+1]==0 && data[i+2]==1)n=i+3;
  else if(i+5<size && data[i]==0 && data[i+1]==0 && data[i+2]==0 && data[i+3]==1)n=i+4;
  if(n && n+3<size && (data[n]&31)==7)return data[n+3];
 }
 return -1;
}
