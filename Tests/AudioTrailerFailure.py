"""A link-time test double reports I/O failure after the real trailer deinitializes.
The recorder must never call that trailer a second time during salvage.
"""
import subprocess as sp,pathlib,sys,tempfile,json,struct
helper=str(pathlib.Path(sys.argv[1]).resolve())
def run(c,**kw):return sp.run(c,capture_output=True,check=True,**kw)
def raw(s):return bytes.fromhex(''.join(l.split(':',1)[1].split('  ')[0].replace(' ','') for l in s.strip().splitlines()))
def msg(t,p,b=b''):return struct.pack('<IIq',0x454c4700|t,len(b),p)+b
with tempfile.TemporaryDirectory(prefix='elgato-trailer-') as d:
 root=pathlib.Path(d);src=root/'source.mp4';out=root/'out.mkv'
 run(['ffmpeg','-v','error','-f','lavfi','-i','color=size=64x48:rate=30','-t','1','-c:v','libx264','-g','1','-bf','0',str(src)])
 info=json.loads(run(['ffprobe','-v','error','-show_streams','-show_packets','-show_data','-of','json',str(src)]).stdout)
 payload=msg(0,0,raw(info['streams'][0]['extradata']))
 for i,p in enumerate(info['packets']):
  pts=round(i*1e6/30);payload+=msg(1,pts,raw(p['data']))+msg(2,pts,bytes(1600*4))
 result=sp.run([helper,'output='+str(out),'video=copy','audio=pcm_s16le','decoder=2','sourceN=30','sourceD=1'],input=payload+msg(3,0),capture_output=True)
 assert result.returncode==1,result.stderr
 assert result.stderr.count(b'TRAILER_CALL')==1,result.stderr
 run(['ffmpeg','-v','error','-xerror','-i',str(out),'-f','null','-'])
 print('PASS failed trailer is never retried after muxer deinitialization')
