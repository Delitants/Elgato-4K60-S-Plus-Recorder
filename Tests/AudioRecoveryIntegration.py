"""Real helper regression: clock skew, missing/overlapping PCM and long media time.
Fixtures are tiny video plus generated audio in a disposable directory, never HDMI media.
"""
import pathlib,subprocess as sp,struct,json,tempfile,sys,math,os
helper=str(pathlib.Path(sys.argv[1]).resolve())
def msg(t,pts,b=b''):return struct.pack('<IIq',0x454c4700|t,len(b),pts)+b
def unhex(s):return bytes.fromhex(''.join(l.split(':',1)[1].split('  ')[0].replace(' ','') for l in s.strip().splitlines()))
def run(cmd,**kw):return sp.run(cmd,check=True,capture_output=True,**kw)
with tempfile.TemporaryDirectory(prefix='elgato-audio-recovery-') as d:
 root=pathlib.Path(d);src=root/'source.mp4'
 run(['ffmpeg','-v','error','-f','lavfi','-i','color=size=64x48:rate=30','-t','1','-c:v','libx264','-preset','ultrafast','-g','1','-bf','0',str(src)])
 info=json.loads(run(['ffprobe','-v','error','-show_streams','-show_packets','-show_data','-of','json',str(src)]).stdout)
 extra=unhex(info['streams'][0]['extradata']);video=unhex(info['packets'][0]['data'])
 cases=[('gap',8,0,0.25),('overlap',8,0,-0.25),('large-gap',8,0,3),('backward',8,0,-0.25),('large-gap-pcm',8,0,3),('drift-fast',3300,60e-6,0),('drift-slow',3300,-60e-6,0),('drift-slow-aac',3300,-60e-6,0)]
 if os.environ.get('QUICK'):cases=cases[:5]
 for name,seconds,drift,jump in cases:
  out=root/(name+'.mkv');log=root/(name+'.log');err=root/(name+'.err')
  n=1024;pcm=struct.pack('<hh',10000,-10000)*n
  with open(log,'wb') as stdout,open(err,'wb') as stderr:
   p=sp.Popen([helper,'output='+str(out),'video=copy','audio='+('pcm_s16le' if name.endswith('pcm') else 'aac' if name.endswith('aac') else 'flac'),'decoder=2','sourceN=30','sourceD=1','fpsN=30','fpsD=1'],stdin=sp.PIPE,stdout=stdout,stderr=stderr)
   broken=False
   try:
    p.stdin.write(msg(0,0,extra));v=0;a=0
    # Order by arrival time, preserving the injected timestamp discontinuity.
    while min(v/30,a/48000)<seconds:
     if v/30<=a/48000:
      p.stdin.write(msg(1,round(v/30*1e6),video));v+=1
     else:
      t=a/48000;pts=t*(1+drift)+(jump if t>=2 else 0)
      if name=='backward' and 2<=t<2.1:pts=t-0.25
      elif name=='backward':pts=t
      p.stdin.write(msg(2,round(pts*1e6),pcm));a+=n
    p.stdin.write(msg(3,0));p.stdin.close()
   except BrokenPipeError:
    broken=True
    try:p.stdin.close()
    except BrokenPipeError:pass
   p.wait(timeout=120)
  assert p.returncode==0 and not broken,(name,err.read_text())
  assert 'SAVED ' in log.read_text(),(name,'not finalized')
  assert 'WARNING ' in log.read_text(),(name,'recovery must be surfaced')
  run(['ffmpeg','-v','error','-xerror','-i',str(out),'-f','null','-'])
  data=json.loads(run(['ffprobe','-v','error','-select_streams','a','-show_packets','-show_entries','packet=pts_time,duration_time','-of','json',str(out)]).stdout)['packets']
  starts=[float(x['pts_time']) for x in data];assert all(y>x for x,y in zip(starts,starts[1:])),name
  end=starts[-1]+float(data[-1]['duration_time']);expected=seconds*(1+drift)+jump
  if name=='backward':expected=seconds
  assert abs(end-expected)<0.06,(name,end,expected)
  # Real output audio must return after the anomaly, not be dropped forever.
  tail=run(['ffmpeg','-v','error','-sseof','-1','-i',str(out),'-map','0:a','-f','s16le','-']).stdout
  samples=struct.unpack('<'+'h'*(len(tail)//2),tail);assert samples and max(samples)>9000 and min(samples)<-9000,name
  print('PASS',name,'media seconds',seconds,'audio end',end,flush=True)

 # Fatal malformed IPC still produces a finalized partial file, while failed
 # initialization must return an ordinary error rather than crash in salvage.
 payload=msg(0,0,extra)
 for i in range(60):
  payload+=msg(1,round(i/30*1e6),video)+msg(2,round(i/30*1e6),struct.pack('<hh',10000,-10000)*1600)
 for audio in ['aac','not_an_encoder']:
  out=root/('fatal-'+audio+'.mkv')
  p=sp.run([helper,'output='+str(out),'video=copy','audio='+audio,'decoder=2','sourceN=30','sourceD=1'],input=payload+struct.pack('<IIq',0x454c4701,20*1024*1024,0),capture_output=True)
  assert p.returncode==1,(audio,p.returncode,p.stderr)
  if audio=='aac':
   assert b'SAVED ' in p.stdout,p.stdout
   fmt=json.loads(run(['ffprobe','-v','error','-show_format','-of','json',str(out)]).stdout)['format'];assert float(fmt['duration'])>1.5
   run(['ffmpeg','-v','error','-xerror','-i',str(out),'-f','null','-'])
  print('PASS fatal partial finalization / invalid initialization:',audio,flush=True)
