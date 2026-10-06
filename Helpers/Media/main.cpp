// Standalone GPL-compatible recording helper; no NDI library is linked here.
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/hwcontext.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
}
#include <iostream>
#include <fstream>
#include <vector>
#include <map>
#include <deque>
#include <string>
#include <stdexcept>
#include <filesystem>
#include <algorithm>
#include <unistd.h>
#include "FilmCadence.h"
using namespace std;
static const AVRational US={1,1000000};
static void ck(int r,const char*what){if(r<0){char e[256];av_strerror(r,e,sizeof(e));throw runtime_error(string(what)+": "+e);}}
static map<string,string> args;
static string opt(string k,string d=""){auto i=args.find(k);return i==args.end()?d:i->second;}
static int num(string k,int d=0){return stoi(opt(k,to_string(d)));}
static uint32_t u32(const uint8_t*p){return p[0]|uint32_t(p[1])<<8|uint32_t(p[2])<<16|uint32_t(p[3])<<24;}
static int64_t i64(const uint8_t*p){uint64_t v=0;for(int i=7;i>=0;--i)v=(v<<8)|p[i];return (int64_t)v;}
static bool exact(uint8_t*p,size_t n,bool eof=false){cin.read((char*)p,n);auto got=cin.gcount();if(!got&&eof&&cin.eof())return false;if(got!=(streamsize)n)throw runtime_error("Truncated IPC message");return true;}
struct Message{int type;int64_t pts;vector<uint8_t> data;};
static bool readMessage(Message&m){uint8_t h[16];if(!exact(h,16,true))return false;uint32_t tag=u32(h),len=u32(h+4);if((tag&0xffffff00)!=0x454c4700 || (tag&255)>4 || len>16*1024*1024)throw runtime_error("Invalid IPC header or oversized payload");m.type=tag&255;m.pts=i64(h+8);m.data.resize(len);exact(m.data.data(),len);return true;}
class Recorder {
 struct AudioChunk {int64_t pts; vector<uint8_t> data; int offset=0;};
 deque<AudioChunk> audioPending;size_t audioPendingBytes=0;
 AVCodecContext *dec=nullptr,*ve=nullptr,*ae=nullptr; AVFormatContext*out=nullptr;
 AVStream *vs=nullptr,*as=nullptr; SwsContext*scaler=nullptr; SwrContext*resampler=nullptr;AVAudioFifo*fifo=nullptr;
 AVBufferRef*hw=nullptr;vector<uint8_t>extra; map<int64_t,AVPacket*> pending; int part=0;int64_t origin=0,audioNext=AV_NOPTS_VALUE,lastV=-1,lastA=-1;bool started=false;
 AVRational sourceRate={0,1},outputRate={0,1};int64_t selectionOrigin=AV_NOPTS_VALUE,lastSlot=-1;
 FilmCadence filmCadence;FilmTimeline filmTimeline;std::vector<AVFrame*> filmFrames;std::array<double,5> filmDifferences{NAN,NAN,NAN,NAN,NAN};
 std::vector<uint8_t> filmPrevious;int64_t filmOrigin=AV_NOPTS_VALUE,filmLastPTS=AV_NOPTS_VALUE;
 std::deque<double> carrierIntervals;bool filmCarrierValid=true,videoTimingWarning=false;
 int64_t lastWrittenVideoPTS=AV_NOPTS_VALUE;
 bool filmKey=false,trailerAttempted=false;
 bool frontIndex=false;uint64_t indexEntries=0;
 static constexpr int indexReserve=1048576;
 int recoveryCount=0;bool softClockWarning=false;
 int width=0,height=0; string output; bool copy; int64_t segmentStart=0,segmentPayloadBytes=0; bool splitPending=false,splitReady=false;
 static AVPixelFormat hardwareFormat(AVCodecContext*c,const AVPixelFormat*fmts){for(auto p=fmts;*p!=AV_PIX_FMT_NONE;++p)if(*p==AV_PIX_FMT_VIDEOTOOLBOX)return *p;return num("decoder")==1?AV_PIX_FMT_NONE:fmts[0];}
 void indexPacket(const AVPacket*p){
  if(!frontIndex || p->stream_index!=vs->index || !(p->flags&AV_PKT_FLAG_KEY))return;
  // This app writes one video and one audio track. FFmpeg 8 cues only video
  // keyframes here. 128 bytes per entry plus 1 KiB covers the EBML integer,
  // element and CRC overhead conservatively, even with 64-bit timestamps.
  if(++indexEntries>(indexReserve-1024)/128){
   // The reserved area remains a valid Void. FFmpeg's ordinary trailer path
   // appends Cues instead, avoiding a full-file relocation during Stop/split.
   ck(av_opt_set_int(out->priv_data,"reserve_index_space",0,0),"Use standard MKV seek index");
   frontIndex=false;
   warning("MKV seek index exceeded the safe front-index budget; saved a standard end index without rewriting media");
  }
 }
 void packet(AVCodecContext*c,AVStream*s){AVPacket*p=av_packet_alloc();while(true){int r=avcodec_receive_packet(c,p);if(r==AVERROR(EAGAIN)||r==AVERROR_EOF)break;ck(r,"Receive encoded packet");av_packet_rescale_ts(p,c->time_base,s->time_base);p->stream_index=s->index;segmentPayloadBytes+=p->size;indexPacket(p);ck(av_interleaved_write_frame(out,p),"Write packet");}av_packet_free(&p);}
 void audioFrames(bool drain){if(!ae)return;int frameSize=ae->frame_size?ae->frame_size:1024;while(av_audio_fifo_size(fifo)>=frameSize || (drain&&av_audio_fifo_size(fifo)>0)){int n=min(frameSize,av_audio_fifo_size(fifo));AVFrame*f=av_frame_alloc();f->format=ae->sample_fmt;f->sample_rate=ae->sample_rate;av_channel_layout_copy(&f->ch_layout,&ae->ch_layout);f->nb_samples=n;ck(av_frame_get_buffer(f,0),"Audio frame");av_audio_fifo_read(fifo,(void**)f->data,n);f->pts=audioNext;audioNext+=n;ck(avcodec_send_frame(ae,f),"Encode audio");av_frame_free(&f);packet(ae,as);}}
 void configureRate(){
  if(sourceRate.num)return;
  sourceRate={num("sourceN",dec->framerate.num),num("sourceD",dec->framerate.den)};
  outputRate={num("fpsN",sourceRate.num),num("fpsD",sourceRate.den)};
  for(auto r:{sourceRate,outputRate})if(r.num<=0||r.den<=0||av_q2d(r)<1||av_q2d(r)>240)throw runtime_error("Valid source and output frame rates are required");
  if(av_cmp_q(outputRate,sourceRate)>0)outputRate=sourceRate;
  if(copy && av_cmp_q(outputRate,sourceRate)<0)throw runtime_error("FPS downsampling requires a video encoder; Original video cannot drop compressed frames");
 }
 void openOutput(AVFrame*source,int64_t pts){
  frontIndex=false;indexEntries=0;origin=pts;segmentStart=pts;segmentPayloadBytes=0;audioNext=AV_NOPTS_VALUE;trailerAttempted=false;
  string path=opt("output");if(num("split")!=0){filesystem::path p(path);char suffix[32];snprintf(suffix,sizeof(suffix),"_part%03d",++part);path=(p.parent_path()/(p.stem().string()+suffix+p.extension().string())).string();}
  if(filesystem::exists(path))throw runtime_error("Output already exists: "+path);
  ck(avformat_alloc_output_context2(&out,nullptr,nullptr,path.c_str()),"Create container");output=path;
  vs=avformat_new_stream(out,nullptr);if(!vs)throw runtime_error("Allocate video stream");
  vs->avg_frame_rate=outputRate;vs->r_frame_rate=outputRate;
  if(copy){ck(avcodec_parameters_from_context(vs->codecpar,dec),"Copy source format");vs->codecpar->codec_tag=0;vs->time_base=US;}
  else {
   string codec=opt("video","h264_videotoolbox");const AVCodec*c=avcodec_find_encoder_by_name(codec.c_str());if(!c)throw runtime_error("Encoder unavailable: "+codec);ve=avcodec_alloc_context3(c);
   int target=num("height",source->height);ve->height=min(source->height,target);ve->width=(source->width*ve->height/source->height)/2*2;
   ve->time_base=US;ve->framerate=outputRate;ve->sample_aspect_ratio=source->sample_aspect_ratio;
   bool ten=opt("profile")=="main10" || (source->format==AV_PIX_FMT_YUV420P10LE && codec=="libsvtav1");
   ve->pix_fmt=codec.find("prores")!=string::npos ? AV_PIX_FMT_P210LE : ten?(codec.find("videotoolbox")!=string::npos?AV_PIX_FMT_P010LE:AV_PIX_FMT_YUV420P10LE):AV_PIX_FMT_YUV420P;
   ve->color_primaries=source->color_primaries;ve->color_trc=source->color_trc;ve->colorspace=source->colorspace;ve->color_range=source->color_range;
   if(source->color_trc==AVCOL_TRC_SMPTE2084||source->color_trc==AVCOL_TRC_ARIB_STD_B67)throw runtime_error("HDR transcoding is not validated. Use Original video.");
   string rc=opt("rc","abr");ve->bit_rate=(rc=="crf"||rc=="cq")?0:num("bitrate",20000000);int key=num("key");if(key>0)ve->gop_size=max(1,int(av_rescale_q(key,{1,1},av_inv_q(outputRate))));
   // VideoToolbox maps qscale / (FF_QP2LAMBDA * 100) to Quality 0...1.
   // Keep QSCALE set even at zero so it cannot fall back to average bitrate.
   if(rc=="cq"){ve->flags|=AV_CODEC_FLAG_QSCALE;ve->global_quality=num("hardwareQuality",65)*FF_QP2LAMBDA;}
   ve->max_b_frames=num("bframes");if(out->oformat->flags&AVFMT_GLOBALHEADER)ve->flags|=AV_CODEC_FLAG_GLOBAL_HEADER;
   AVDictionary*d=nullptr;auto set=[&](string k,string v){av_dict_set(&d,k.c_str(),v.c_str(),0);};
   if(rc=="crf")set("crf",opt("quality","23"));
   if(opt("preset","auto")!="auto")set("preset",opt("preset"));else if(codec=="libsvtav1")set("preset","10");else if(codec=="libx264"||codec=="libx265")set("preset","veryfast");
   string profile=opt("profile","auto");if(profile!="auto") {if(codec.find("prores")!=string::npos){map<string,string>p={{"proxy","0"},{"lt","1"},{"standard","2"},{"hq","3"}};set("profile",p.at(profile));}else set("profile",profile);}
   if(codec.find("videotoolbox")!=string::npos){set("realtime","1");set("allow_sw",(num("encoder")==1||rc=="cq")?"0":"1");set("spatial_aq",opt("aq","-1"));if(rc=="cbr")set("constant_bit_rate","1");}
   else if(codec=="libx264"||codec=="libx265") {string params;if(rc=="cbr"){ve->rc_max_rate=ve->bit_rate;ve->rc_min_rate=ve->bit_rate;ve->rc_buffer_size=int(ve->bit_rate);params="vbv-maxrate="+to_string(ve->bit_rate/1000)+":vbv-bufsize="+to_string(ve->bit_rate/1000);if(codec=="libx264")params+=":nal-hrd=cbr";}if(opt("aq","-1")!="-1"){if(!params.empty())params+=":";params+="aq-mode="+opt("aq");}if(!params.empty())set(codec=="libx264"?"x264-params":"x265-params",params);}
   ck(avcodec_open2(ve,c,&d),rc=="cq"?"Open hardware CQ encoder (no bitrate or software fallback)":"Open video encoder");if(av_dict_count(d)){string unknown=av_dict_get(d,"",nullptr,AV_DICT_IGNORE_SUFFIX)->key;av_dict_free(&d);throw runtime_error("Encoder did not accept option: "+unknown);}av_dict_free(&d);
   ck(avcodec_parameters_from_context(vs->codecpar,ve),"Video output format");vs->time_base=ve->time_base;
  }
  string ac=opt("audio","aac");const AVCodec*a=avcodec_find_encoder_by_name(ac.c_str());if(!a)throw runtime_error("Audio encoder unavailable");ae=avcodec_alloc_context3(a);ae->sample_rate=48000;av_channel_layout_default(&ae->ch_layout,2);ae->time_base={1,48000};ae->sample_fmt=ac=="aac"?AV_SAMPLE_FMT_FLTP:ac=="alac"?AV_SAMPLE_FMT_S16P:AV_SAMPLE_FMT_S16;
  ae->bit_rate=num("audioRate",192000);if(ac=="flac"||ac=="libopus")ae->compression_level=num("compression",5);if(out->oformat->flags&AVFMT_GLOBALHEADER)ae->flags|=AV_CODEC_FLAG_GLOBAL_HEADER;
  AVDictionary*ad=nullptr;if(ac=="libopus")av_dict_set(&ad,"vbr",opt("audioMode","on").c_str(),0);ck(avcodec_open2(ae,a,&ad),"Open audio encoder");av_dict_free(&ad);
  as=avformat_new_stream(out,nullptr);as->time_base=ae->time_base;ck(avcodec_parameters_from_context(as->codecpar,ae),"Audio output format");
  AVChannelLayout input=AV_CHANNEL_LAYOUT_STEREO;ck(swr_alloc_set_opts2(&resampler,&ae->ch_layout,ae->sample_fmt,48000,&input,AV_SAMPLE_FMT_S16,48000,0,nullptr),"Audio converter");ck(av_opt_set_double(resampler,"async",48,0),"Audio clock compensation");ck(av_opt_set_double(resampler,"min_comp",0.001,0),"Audio clock tolerance");ck(av_opt_set_double(resampler,"min_hard_comp",0.1,0),"Audio hard correction");ck(swr_init(resampler),"Audio converter init");fifo=av_audio_fifo_alloc(ae->sample_fmt,2,4096);
  if(num("networkPlayback") && string(out->oformat->name)=="matroska"){
   // Front Cues use reserved space only; never relocate media while recording.
   frontIndex=true;
   ck(av_opt_set_int(out->priv_data,"reserve_index_space",indexReserve,0),"Reserve MKV seek index");
   ck(av_opt_set_int(out->priv_data,"cues_to_front",0,0),"Place MKV seek index first");
  }
  ck(avio_open(&out->pb,path.c_str(),AVIO_FLAG_WRITE),"Open output file");ck(avformat_write_header(out,nullptr),"Write container header");started=true;cout<<"FILE "<<path<<endl;
 }
 void warning(const string&text){cout<<"WARNING "<<++recoveryCount<<" · "<<text<<endl;}
 int convertAudio(const uint8_t*data,int n){
  int capacity=swr_get_out_samples(resampler,n);ck(capacity,"Audio conversion capacity");capacity=max(32,capacity);
  AVFrame*f=av_frame_alloc();f->format=ae->sample_fmt;f->sample_rate=48000;f->nb_samples=capacity;
  av_channel_layout_copy(&f->ch_layout,&ae->ch_layout);ck(av_frame_get_buffer(f,0),"PCM conversion buffer");
  const uint8_t*in[]={data};int converted=swr_convert(resampler,f->data,capacity,data?in:nullptr,n);ck(converted,"Convert PCM");
  if(converted>0){ck(av_audio_fifo_realloc(fifo,av_audio_fifo_size(fifo)+converted),"Grow audio queue");
  av_audio_fifo_write(fifo,(void**)f->data,converted);}av_frame_free(&f);audioFrames(false);return converted;
 }
 void drainResampler(){if(resampler)while(convertAudio(nullptr,0)>0){}}
 void writeAudio(int64_t pts,const uint8_t*data,int n){
  if(n<=0)return;
  int64_t target=av_rescale_q(pts-origin,US,{1,48000});
  if(audioNext==AV_NOPTS_VALUE)audioNext=target;
  int64_t expected=audioNext+av_audio_fifo_size(fifo)+swr_get_delay(resampler,48000);
  int64_t delta=target-expected;
  // Bound hard correction work. Large forward gaps keep their timestamp gap
  // rather than allocating/generating arbitrary amounts of silent audio.
  if(delta>96000){
   drainResampler();
   int remainder=av_audio_fifo_size(fifo);
   if(remainder && ae->frame_size>0){
    int pad=ae->frame_size-remainder;AVFrame*z=av_frame_alloc();z->format=ae->sample_fmt;z->sample_rate=48000;z->nb_samples=pad;
    av_channel_layout_copy(&z->ch_layout,&ae->ch_layout);ck(av_frame_get_buffer(z,0),"Gap alignment");
    av_samples_set_silence(z->data,0,pad,2,ae->sample_fmt);ck(av_audio_fifo_realloc(fifo,remainder+pad),"Gap queue");av_audio_fifo_write(fifo,(void**)z->data,pad);av_frame_free(&z);audioFrames(false);
   }
   if(remainder && ae->frame_size==0)audioFrames(true);
   audioNext=max(audioNext,target);swr_close(resampler);ck(swr_init(resampler),"Reset audio clock");
   warning("Audio gap of "+to_string(delta/48)+" ms; resumed at the next audio timestamp");
  }else if(delta < -96000){warning("Discarded stale audio while keeping video recording");return;}
  else if(llabs(delta)>=4800){warning(string(delta>0?"Filled missing audio with silence":"Trimmed overlapping audio")+" ("+to_string(llabs(delta)/48)+" ms)");}
  else if(llabs(delta)>=48 && !softClockWarning){softClockWarning=true;warning("Audio clock drift corrected automatically");}
  // libswresample aligns the PCM sample clock to device timestamps. Small
  // differences stretch/squeeze gradually; larger ones insert/drop samples.
  swr_next_pts(resampler,target*int64_t(48000));
  convertAudio(data,n);
 }
 void flushAudioUntil(int64_t boundary){
  if(!started)return;
  while(!audioPending.empty()){
   auto &a=audioPending.front();int total=int(a.data.size()/4);
   int lower=int(clamp<int64_t>(av_rescale_q(origin-a.pts,US,{1,48000}),0,total));
   a.offset=max(a.offset,lower);
   int upper=boundary==INT64_MAX?total:int(clamp<int64_t>(av_rescale_q(boundary-a.pts,US,{1,48000}),0,total));
   if(upper>a.offset){int64_t pts=a.pts+av_rescale_q(a.offset,{1,48000},US);writeAudio(pts,a.data.data()+a.offset*4,upper-a.offset);a.offset=upper;}
   if(a.offset==total){audioPendingBytes-=a.data.size();audioPending.pop_front();}else break;
  }
 }
 void finishSegment(){if(!out)return;if(ve){ck(avcodec_send_frame(ve,nullptr),"Drain video");packet(ve,vs);}drainResampler();audioFrames(true);if(ae){ck(avcodec_send_frame(ae,nullptr),"Drain audio");packet(ae,as);}trailerAttempted=true;ck(av_write_trailer(out),"Finalize container");avio_closep(&out->pb);avformat_free_context(out);out=nullptr;avcodec_free_context(&ve);avcodec_free_context(&ae);swr_free(&resampler);av_audio_fifo_free(fifo);fifo=nullptr;started=false;cout<<"SAVED "<<output<<endl;}
 bool recoverFilm()const{return !copy && opt("cadence")=="film32" && std::abs(av_q2d(sourceRate)/av_q2d(outputRate)-2.5)<0.015;}
 double filmDifference(AVFrame*f){
  std::vector<uint8_t> pixels;pixels.reserve(2304);
  const AVPixFmtDescriptor*desc=av_pix_fmt_desc_get((AVPixelFormat)f->format);
  if(!desc || !(desc->flags&AV_PIX_FMT_FLAG_PLANAR) || (desc->flags&AV_PIX_FMT_FLAG_RGB))throw runtime_error("Unsupported pixel format for film cadence recovery");
  int depth=desc->comp[0].depth,shift=desc->comp[0].shift;
  for(int y=0;y<36;y++)for(int x=0;x<64;x++){
   const uint8_t*p=f->data[0]+(y*f->height/36)*f->linesize[0]+(x*f->width/64)*(depth>8?2:1);
   unsigned value=depth>8 ? unsigned(p[0])|(unsigned(p[1])<<8):p[0];
   pixels.push_back(uint8_t((value>>shift)>>(std::max(8,depth)-8)));
  }
  double difference=filmPrevious.empty()?NAN:0;if(filmPrevious.size()==pixels.size())for(size_t i=0;i<pixels.size();i++)difference+=std::abs(int(pixels[i])-int(filmPrevious[i]));
  filmPrevious=std::move(pixels);return difference/2304;
 }
 void emitFilm(){
  if(filmFrames.empty())return;
  auto selected=filmCadence.observe(filmDifferences);
  int64_t cyclePTS=filmTimeline.cycle(filmFrames.front()->pts,1e6/av_q2d(outputRate));int picture=0;
  // A final partial cycle ends at its available picture; never invent a full cycle.
  for(int index:selected){if(index>=int(filmFrames.size()))continue;
   AVFrame*f=filmFrames[index];int64_t pts=cyclePTS+av_rescale_q(picture++,av_inv_q(outputRate),US);
   videoFrame(f,pts,filmKey||!started,nullptr,true);filmKey=false;
  }
  for(auto*f:filmFrames)av_frame_free(&f);filmFrames.clear();filmDifferences.fill(NAN);
 }
 void videoFrame(AVFrame*src,int64_t pts,bool key,AVPacket*input,bool filmSelected=false){
  configureRate();
  if(recoverFilm() && !filmSelected){
   // A real carrier-rate change is recoverable. Do not interpret every 30 Hz
   // frame as a separate partial 3:2 cycle and accidentally exceed the FPS cap.
   bool valid=filmCarrierValid;
   if(filmLastPTS!=AV_NOPTS_VALUE){
    double period=1e6/av_q2d(sourceRate),delta=double(pts-filmLastPTS);
    // Legitimate short ~10 ms intervals are paired with longer intervals.
    // Detect faster rates from the window mean, never a single short interval.
    if(delta<=0 || delta>period*1.6){carrierIntervals.clear();valid=false;}
    else{
     carrierIntervals.push_back(delta);if(carrierIntervals.size()>30)carrierIntervals.pop_front();
     if(carrierIntervals.size()==30){double sum=0;for(auto x:carrierIntervals)sum+=x;valid=std::abs(sum/30/period-1)<0.08;}
    }
   }
   if(valid!=filmCarrierValid){
    emitFilm();filmOrigin=AV_NOPTS_VALUE;filmTimeline=FilmTimeline();filmCadence=FilmCadence();filmPrevious.clear();
    filmCarrierValid=valid;
    warning(valid?"Film carrier timing restored; cadence recovery resumed":"Video timing changed; continued with timestamp-based FPS conversion");
   }
   filmLastPTS=pts;
   if(filmCarrierValid){
   if(filmOrigin==AV_NOPTS_VALUE){if(!key && !started)return;filmOrigin=pts;}
   AVFrame*held=av_frame_alloc();if(!held)throw runtime_error("Allocate film cadence frame");
   filmFrames.push_back(held);
   if(src->format==AV_PIX_FMT_VIDEOTOOLBOX){ck(av_hwframe_transfer_data(held,src,0),"Read film cadence frame");av_frame_copy_props(held,src);}
   else ck(av_frame_ref(held,src),"Retain film cadence frame");
   held->pts=pts;filmDifferences[filmFrames.size()-1]=filmDifference(held);filmKey=filmKey||key;
   if(filmFrames.size()==5)emitFilm();return;
   }
  }
  if(started&&num("split")){
   int64_t bytes=max(avio_tell(out->pb),segmentPayloadBytes);
   if((num("split")==1&&pts-segmentStart>=int64_t(num("splitValue"))*1000000)||(num("split")==2&&bytes>=int64_t(num("splitValue"))*1000000))splitPending=true;
   if(splitPending&&key)splitReady=true;
  }
  if(!copy && !filmSelected){
   if(selectionOrigin==AV_NOPTS_VALUE)selectionOrigin=pts;
   // Device PTS has sub-frame jitter. First recover the source frame position;
   // otherwise 60→30 may select frames 0,3,4,7 instead of 0,2,4,6.
   int64_t tick=av_rescale_q_rnd(pts-selectionOrigin,US,av_inv_q(sourceRate),AV_ROUND_NEAR_INF);
   int64_t slot=av_rescale_q_rnd(tick,av_inv_q(sourceRate),av_inv_q(outputRate),AV_ROUND_DOWN);
   if(slot<=lastSlot){flushAudioUntil(pts);return;}
   lastSlot=slot;pts=selectionOrigin+av_rescale_q(slot,av_inv_q(outputRate),US);
  }
  if(!copy && lastWrittenVideoPTS!=AV_NOPTS_VALUE && pts<=lastWrittenVideoPTS){
   if(!videoTimingWarning){videoTimingWarning=true;warning("Skipped an overlapping video timestamp during timing recovery");}
   return;
  }
  AVFrame*cpu=nullptr;if(!copy && src->format==AV_PIX_FMT_VIDEOTOOLBOX){cpu=av_frame_alloc();ck(av_hwframe_transfer_data(cpu,src,0),"Download decoded frame");av_frame_copy_props(cpu,src);src=cpu;}
  if(width && (src->width!=width||src->height!=height))throw runtime_error("HDMI format changed; start a new recording");width=src->width;height=src->height;
  if(splitReady){flushAudioUntil(pts);finishSegment();splitPending=false;splitReady=false;key=true;}
  if(!started){if(!key){av_frame_free(&cpu);return;}openOutput(src,pts);}
  flushAudioUntil(pts);
  if(copy){AVPacket*p=av_packet_clone(input);if(key)p->flags|=AV_PKT_FLAG_KEY;p->pts=p->dts=pts-origin;p->duration=av_rescale_q(1,av_inv_q(sourceRate),US);av_packet_rescale_ts(p,US,vs->time_base);p->stream_index=vs->index;segmentPayloadBytes+=p->size;indexPacket(p);ck(av_interleaved_write_frame(out,p),"Write original video");av_packet_free(&p);}
  else {int flags=SWS_BICUBIC;string f=opt("filter");if(f=="bilinear")flags=SWS_BILINEAR;else if(f=="area")flags=SWS_AREA;else if(f=="lanczos")flags=SWS_LANCZOS;
   scaler=sws_getCachedContext(scaler,src->width,src->height,(AVPixelFormat)src->format,ve->width,ve->height,ve->pix_fmt,flags,nullptr,nullptr,nullptr);if(!scaler)throw runtime_error("Scaler unavailable");
   AVFrame*dst=av_frame_alloc();dst->format=ve->pix_fmt;dst->width=ve->width;dst->height=ve->height;ck(av_frame_get_buffer(dst,32),"Allocate video frame");sws_scale(scaler,src->data,src->linesize,0,src->height,dst->data,dst->linesize);av_frame_copy_props(dst,src);dst->pts=av_rescale_q(pts-origin,US,ve->time_base);dst->pict_type=AV_PICTURE_TYPE_NONE;
   ck(avcodec_send_frame(ve,dst),"Encode video");av_frame_free(&dst);packet(ve,vs);
  }lastWrittenVideoPTS=pts;av_frame_free(&cpu);
 }
 void receiveFrames(){AVFrame*f=av_frame_alloc();int r;while((r=avcodec_receive_frame(dec,f))>=0){auto it=pending.find(f->pts);if(it==pending.end())throw runtime_error("Decoded timestamp has no source packet");videoFrame(f,f->pts,(f->flags&AV_FRAME_FLAG_KEY)!=0,it->second);av_packet_free(&it->second);pending.erase(it);av_frame_unref(f);}av_frame_free(&f);if(r!=AVERROR(EAGAIN)&&r!=AVERROR_EOF)ck(r,"Read decoded frame");}
public:
 Recorder():copy(opt("video")=="copy"){
  if(opt("rc")=="cq"){
   if((opt("video")!="h264_videotoolbox" && opt("video")!="hevc_videotoolbox") || num("encoder")==2)throw runtime_error("Hardware CQ requires a hardware H.264 or HEVC encoder");
   if(num("hardwareQuality",65)<0||num("hardwareQuality",65)>100)throw runtime_error("Hardware CQ quality must be 0-100");
   #if !defined(__aarch64__)
   throw runtime_error("Hardware CQ requires the native Apple Silicon app; use ABR/CBR or software CRF in the Intel build");
   #endif
  }
  if(opt("video")=="h264_videotoolbox" && num("bframes")>0)throw runtime_error("Hardware H.264 B-frames are unavailable: disable B-frames or choose software encoding");
 }
 ~Recorder(){for(auto*f:filmFrames)av_frame_free(&f);for(auto &entry:pending)av_packet_free(&entry.second);if(out){if(out->pb)avio_closep(&out->pb);avformat_free_context(out);}avcodec_free_context(&ve);avcodec_free_context(&ae);avcodec_free_context(&dec);av_buffer_unref(&hw);sws_freeContext(scaler);swr_free(&resampler);if(fifo)av_audio_fifo_free(fifo);}
 void setup(vector<uint8_t>e){if(dec||e.empty())throw runtime_error("Invalid or repeated setup");extra=move(e);auto c=avcodec_find_decoder(num("hevc")?AV_CODEC_ID_HEVC:AV_CODEC_ID_H264);dec=avcodec_alloc_context3(c);dec->pkt_timebase=US;dec->extradata=(uint8_t*)av_mallocz(extra.size()+AV_INPUT_BUFFER_PADDING_SIZE);memcpy(dec->extradata,extra.data(),extra.size());dec->extradata_size=int(extra.size());dec->thread_count=1;dec->flags|=AV_CODEC_FLAG_LOW_DELAY;
  if(num("decoder")!=2){int r=av_hwdevice_ctx_create(&hw,AV_HWDEVICE_TYPE_VIDEOTOOLBOX,nullptr,nullptr,0);if(r>=0){dec->hw_device_ctx=av_buffer_ref(hw);dec->get_format=hardwareFormat;}else if(num("decoder")==1)ck(r,"Required hardware decoder");}
  ck(avcodec_open2(dec,c,nullptr),"Open source decoder");}
 void process(Message&m){if(m.type==0){setup(move(m.data));return;}if(!dec)throw runtime_error("Missing source setup");if(m.pts<0)throw runtime_error("Negative source timestamp");if(m.type==3)return;
  if(m.type==4){
   // A complete IPC control message precedes the next random-access packet.
   // Flush delayed pre-gap pictures, then discard decoder reference state.
   ck(avcodec_send_packet(dec,nullptr),"Drain decoder before recovery");receiveFrames();emitFilm();
   avcodec_flush_buffers(dec);for(auto &entry:pending)av_packet_free(&entry.second);pending.clear();
   filmTimeline=FilmTimeline();filmCadence=FilmCadence();filmPrevious.clear();filmOrigin=AV_NOPTS_VALUE;filmLastPTS=AV_NOPTS_VALUE;filmKey=false;carrierIntervals.clear();
   warning("Recording input resumed at a keyframe after a backlog; timestamps preserve the gap");return;
  }
  if(m.type==1){if(m.pts<=lastV)throw runtime_error("Video timestamp discontinuity");lastV=m.pts;AVPacket*p=av_packet_alloc();ck(av_new_packet(p,int(m.data.size())),"Allocate source packet");memcpy(p->data,m.data.data(),m.data.size());p->pts=p->dts=m.pts;if(pending.size()>120)throw runtime_error("Source decoder backlog");pending[m.pts]=av_packet_clone(p);ck(avcodec_send_packet(dec,p),"Decode source");receiveFrames();av_packet_free(&p);
  }else if(m.type==2){
   if(m.pts<=lastA){warning("Discarded an out-of-order audio packet");return;}lastA=m.pts;
   if(m.data.size()%4)throw runtime_error("Unaligned PCM");
   audioPendingBytes+=m.data.size();audioPending.push_back({m.pts,move(m.data),0});
   if(audioPendingBytes>48000*4*3){
    if(started){warning("Video timing stalled; preserved queued audio and continued recording");flushAudioUntil(INT64_MAX);}
    else{warning("Waiting for a video keyframe; skipped oldest buffered audio");while(audioPendingBytes>48000*4*3){audioPendingBytes-=audioPending.front().data.size();audioPending.pop_front();}}
   }
  }}
 void salvage()noexcept{
  // An unrecoverable I/O/codec failure must still attempt a playable trailer.
  if(!started || trailerAttempted)return;
  audioPending.clear();audioPendingBytes=0;
  try{finishSegment();}catch(...){
   if(out && out->pb && !trailerAttempted){trailerAttempted=true;if(av_write_trailer(out)>=0){avio_flush(out->pb);cout<<"SAVED "<<output<<endl;}}
  }
 }
 void finish(){if(dec){ck(avcodec_send_packet(dec,nullptr),"Flush source decoder");receiveFrames();}emitFilm();if(!started)throw runtime_error("No video keyframe arrived");flushAudioUntil(INT64_MAX);finishSegment();}
};
int main(int argc,char**argv){ios::sync_with_stdio(false);cin.tie(nullptr);av_log_set_level(AV_LOG_ERROR);try{for(int i=1;i<argc;++i){string a=argv[i];auto n=a.find('=');if(n!=string::npos)args[a.substr(0,n)]=a.substr(n+1);}Recorder r;try{Message m;bool end=false;while(readMessage(m)){if(m.type==3){end=true;break;}r.process(m);}if(!end)throw runtime_error("Helper input ended without finish");r.finish();return 0;}catch(...){r.salvage();throw;}}catch(const exception&e){cerr<<"ERROR "<<e.what()<<endl;return 1;}}
