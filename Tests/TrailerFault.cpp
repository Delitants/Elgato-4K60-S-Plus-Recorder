extern "C" {
#include <libavformat/avformat.h>
}
#include <cstdio>
extern "C" int recorder_test_trailer(AVFormatContext*ctx){
 static int calls=0;fprintf(stderr,"TRAILER_CALL %d\n",++calls);
 int result=av_write_trailer(ctx);
 return result<0?result:AVERROR(EIO);
}
