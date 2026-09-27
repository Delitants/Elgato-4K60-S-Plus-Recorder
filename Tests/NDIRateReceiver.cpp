#include <cstddef>
#include "Processing.NDI.Lib.h"
#include <dlfcn.h>
#include <iostream>
#include <chrono>
#include <cmath>
#include <cstring>
int main(int n,char**v){auto h=dlopen(v[1],RTLD_NOW|RTLD_LOCAL);if(!h){std::cerr<<dlerror();return 1;}
#define FN(x) auto x=(decltype(&NDIlib_##x))dlsym(h,"NDIlib_" #x)
FN(initialize);FN(find_create_v2);FN(find_wait_for_sources);FN(find_get_current_sources);FN(recv_create_v3);FN(recv_capture_v3);FN(recv_free_video_v2);FN(recv_free_audio_v3);FN(recv_destroy);FN(find_destroy);FN(destroy);
if(!initialize())return 2;NDIlib_find_create_t f;f.show_local_sources=true;auto finder=find_create_v2(&f);NDIlib_source_t chosen;bool found=false;
for(int i=0;i<12&&!found;++i){find_wait_for_sources(finder,1000);uint32_t count=0;auto s=find_get_current_sources(finder,&count);for(uint32_t j=0;j<count;++j){std::cout<<"SOURCE "<<s[j].p_ndi_name<<std::endl;if(strstr(s[j].p_ndi_name,"Elgato FPS test")){chosen=s[j];found=true;break;}}}
if(!found){std::cerr<<"No recorder source found\n";return 3;}
NDIlib_recv_create_v3_t r;r.source_to_connect_to=chosen;r.color_format=NDIlib_recv_color_format_BGRX_BGRA;r.bandwidth=NDIlib_recv_bandwidth_highest;auto recv=recv_create_v3(&r);int frames=0,audioFrames=0,badRate=0;double peak=0;auto start=std::chrono::steady_clock::now();
while(std::chrono::steady_clock::now()-start<std::chrono::seconds(3)){NDIlib_video_frame_v2_t vf;NDIlib_audio_frame_v3_t af;auto type=recv_capture_v3(recv,&vf,&af,nullptr,200);if(type==NDIlib_frame_type_video){++frames;if(vf.frame_rate_N!=30||vf.frame_rate_D!=1)++badRate;recv_free_video_v2(recv,&vf);}if(type==NDIlib_frame_type_audio){++audioFrames;auto p=(float*)af.p_data;for(int i=0;i<af.no_samples;++i)peak=std::max(peak,double(fabs(p[i])));recv_free_audio_v3(recv,&af);}}
std::cout<<"RECEIVED video="<<frames<<" audio="<<audioFrames<<" badRate="<<badRate<<" peak="<<peak<<std::endl;recv_destroy(recv);find_destroy(finder);destroy();return frames>=30&&audioFrames>0&&badRate==0?0:4;}
