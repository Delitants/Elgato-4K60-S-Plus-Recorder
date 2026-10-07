#include "../Helpers/Media/H264Level.h"
#include <cassert>
#include <iostream>
int main(){
 auto l=h264LevelLimits("4.1");
 validateH264Level(l,1920,1080,30000,1001,6000000);
 validateH264Level(l,1920,1080,30,1,50000000);
 auto rejects=[&](int w,int h,int n,int d,int64_t rate){try{validateH264Level(l,w,h,n,d,rate);assert(false);}catch(const std::runtime_error&){}};
 rejects(1920,1080,60000,1001,6000000);
 rejects(3840,2160,24,1,6000000);
 rejects(1920,1080,30,1,50000001);
 rejects(1920,1080,30,1,50000001);
 validateH264Level(h264LevelLimits("4.2"),1920,1080,60,1,6000000);
 validateH264Level(h264LevelLimits("5.1"),3840,2160,30,1,20000000);
 validateH264Level(h264LevelLimits("5.2"),3840,2160,60,1,20000000);
 for(auto bytes:{std::initializer_list<uint8_t>{1,100,0,41}, {0,0,1,0x67,100,0,41}, {0,0,0,1,0x67,100,0,41}}){assert(h264ConfigurationLevel(bytes.begin(),bytes.size())==41);}
 assert(h264ConfigurationLevel(nullptr,0)==-1);
 uint8_t shortSPS[]={0,0,1,0x67};assert(h264ConfigurationLevel(shortSPS,4)==-1);
 std::cout<<"PASS level 4.1/4.2 1080p boundaries, 4K levels, profile bitrate limits and SPS layouts\n";
}
