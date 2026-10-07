import pathlib,subprocess as s,tempfile,json,struct
import sys
helper=str(pathlib.Path(sys.argv[1]).resolve())
def run(args,**kw):
 r=s.run(args,capture_output=True,**kw)
 if r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout
def raw(v):return bytes.fromhex(''.join(x.split(':',1)[1].split('  ')[0].replace(' ','') for x in v.strip().splitlines()))
def msg(t,p,b=b''):return struct.pack('<IIq',0x454c4700|t,len(b),p)+b
with tempfile.TemporaryDirectory(prefix='elgato-cq-container-') as temp:
 root=pathlib.Path(temp);src=root/'source.mp4'
 run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=1920x1080:rate=24000/1001','-t','4','-c:v','libx264','-preset','ultrafast','-g','48','-bf','0',str(src)])
 info=json.loads(run(['ffprobe','-v','error','-show_streams','-show_packets','-show_data','-of','json',str(src)]))
 body=bytearray(msg(0,0,raw(info['streams'][0]['extradata'])))
 for p in info['packets']:
  ts=round(float(p['pts_time'])*1e6);body+=msg(1,ts,raw(p['data']))+msg(2,ts,struct.pack('<hh',1000,-1000)*2002)
 body+=msg(3,0)
 results={}
 for level in ['auto','4.1']:
  for ext in ['mkv','mp4']:
   out=root/(level+'.'+ext)
   run([helper,'output='+str(out),'video=h264_videotoolbox','audio=aac','decoder=2','encoder=1','sourceN=24000','sourceD=1001','profile=main','level='+level,'rc=cq','hardwareQuality=62','key=2','aq=1'],input=body,timeout=45)
   info=json.loads(run(['ffprobe','-v','error','-select_streams','v:0','-show_streams','-show_packets','-show_entries','packet=size:stream=level,width,height','-of','json',str(out)]))
   assert len(info['packets'])==96,info['streams']
   if level=='4.1':assert info['streams'][0]['level']==41,info['streams']
   size=sum(int(p['size']) for p in info['packets']);results[level,ext]=size
   run(['ffmpeg','-v','error','-xerror','-i',str(out),'-f','null','-'])
   print(level,ext,'video bytes',size,flush=True)
 for level in ['auto','4.1']:
  assert abs(results[level,'mp4']/results[level,'mkv']-1)<0.01,results
 ratio=results['4.1','mp4']/results['auto','mp4']
 # This generated motion is well below level 4.1 limits. A nonbinding
 # compatibility level must not more than double the same CQ encoding.
 assert 0.8<ratio<1.2,('Explicit level inflated CQ output',ratio,results)
 print('PASS hardware CQ: explicit level preserves size within 20%, correct SPS, full decode, MP4/MKV video sizes within 1%',flush=True)
print('Temporary probe recordings deleted.')
