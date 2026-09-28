"""Verify frame CONTENT cadence under device PTS jitter, not just output FPS tags.
Usage: python3 Tests/JitterCadenceIntegration.py /path/to/MediaHelper
All generated media is temporary and removed, including on assertion failure.
"""
import subprocess as sp,sys,pathlib,struct,json,tempfile
from fractions import Fraction
helper=str(pathlib.Path(sys.argv[1]).resolve())
ff='/opt/homebrew/bin/ffmpeg';fp='/opt/homebrew/bin/ffprobe'
def probe(path,*args):return json.loads(sp.check_output([fp,'-v','error',*args,'-of','json',str(path)]))
def data(s):return bytes.fromhex(''.join(line.split(':',1)[1].split('  ')[0].replace(' ','') for line in s.strip().splitlines()))
def msg(t,pts,body=b''):return struct.pack('<IIq',0x454c4700|t,len(body),pts)+body
def raw(path):return sp.check_output([ff,'-v','error','-i',str(path),'-map','0:v','-fps_mode','passthrough','-pix_fmt','yuv420p','-f','rawvideo','-'])
with tempfile.TemporaryDirectory(prefix='elgato-cadence-') as temp:
 root=pathlib.Path(temp)
 for source,target in [('60','30'),('60000/1001','30000/1001'),('60','24'),('60','25'),('60','50'),('60','60')]:
  src=root/'source.mp4';out=root/'out.mkv'
  sp.run([ff,'-y','-v','error','-f','lavfi','-i',f'testsrc2=size=160x96:rate={source}','-frames:v','120','-c:v','libx264','-preset','ultrafast','-crf','0','-bf','0',str(src)],check=True)
  info=probe(src,'-show_streams','-show_packets','-show_data');sr=Fraction(source);tr=Fraction(target);frameBytes=160*96*3//2;sourcePixels=raw(src)
  packets=info['packets'];items=[];expected=[];last=-1
  for i,p in enumerate(packets):
   jitter=0 if i==0 else (-2200 if i%4==2 else 900)
   pts=round(i*1000000/sr)+jitter
   items.append((pts,1,data(p['data'])))
   slot=int(i*tr/sr)
   if slot>last:expected.append(i);last=slot
  count=round(120/sr*48000);pcm=struct.pack('<hh',1234,-4321)*count
  items += [(round(i/48000*1e6),2,pcm[i*4:(i+1024)*4]) for i in range(0,count,1024)]
  payload=msg(0,0,data(info['streams'][0]['extradata']))+b''.join(msg(t,pts,b) for pts,t,b in sorted(items))+msg(3,0)
  cmd=[helper,'output='+str(out),'video=libx264','audio=pcm_s16le','decoder=2','encoder=2',f'sourceN={sr.numerator}',f'sourceD={sr.denominator}',f'fpsN={tr.numerator}',f'fpsD={tr.denominator}','preset=ultrafast','rc=crf','quality=0']
  result=sp.run(cmd,input=payload,capture_output=True,timeout=30);assert result.returncode==0,result.stderr
  actual=raw(out);want=b''.join(sourcePixels[i*frameBytes:(i+1)*frameBytes] for i in expected)
  assert actual==want,(source,target,'wrong source-frame selection under PTS jitter',len(actual)//frameBytes,len(expected))
  times=[float(f['pts_time']) for f in probe(out,'-select_streams','v:0','-show_frames')['frames']]
  assert all(abs(t-i/float(tr))<=0.0011 for i,t in enumerate(times)),(source,target,'uneven output timeline')
  audio=sp.check_output([ff,'-v','error','-xerror','-i',str(out),'-map','0:a','-f','s16le','-']);assert audio==pcm,'audio continuity'
  print('PASS jittered',source,'→',target,len(expected),'exact source frames, uniform timestamps, exact PCM',flush=True)
  src.unlink();out.unlink()
