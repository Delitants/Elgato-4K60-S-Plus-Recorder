"""Exercise the real Swift sink, not just the standalone helper, through rate changes."""
import base64,json,pathlib,subprocess as sp,sys,tempfile
binary=str(pathlib.Path(sys.argv[1]).resolve())
ff='/opt/homebrew/bin/ffmpeg';fp='/opt/homebrew/bin/ffprobe'
with tempfile.TemporaryDirectory(prefix='elgato-rate-recovery-') as tmp:
 root=pathlib.Path(tmp);src=root/'frame.h264'
 sp.run([ff,'-v','error','-f','lavfi','-i','testsrc2=size=160x90:rate=60','-frames:v','1','-c:v','libx264','-preset','ultrafast','-f','h264',str(src)],check=True)
 nal=base64.b64encode(src.read_bytes()).decode()
 # Deliberately exaggerated transient timing slope, then an actual rate change.
 # Codec parameters stay identical. Old RecordingSink aborts at the first >1% estimate.
 frames=[];pts=0.0
 for rate,count in [(60000/1001,120),(56,120),(60000/1001,120),(30,90),(60000/1001,120)]:
  for i in range(count):
   frames.append(dict(type=0xc1,timestamp=round(pts),data=nal));pts+=1e6/rate
 samples=round(pts*48000/1e6)
 for start in range(0,samples,1024):
  n=min(1024,samples-start)
  frames.append(dict(type=0xc3,timestamp=round(start*1e6/48000),data=base64.b64encode(b'\xd2\x04\x2e\xfb'*n).decode()))
 frames.sort(key=lambda f:(f['timestamp'],f['type']))
 (root/'frames.json').write_text(json.dumps(frames))
 run=sp.run([binary,str(root)],capture_output=True,text=True,timeout=90)
 print(run.stdout,end='');print(run.stderr,end='')
 if run.returncode:sys.exit(run.returncode)
 for mode,ext in [('native','mov'),('copy','mkv'),('film','mkv')]:
  path=root/(mode+'.'+ext)
  info=json.loads(sp.check_output([fp,'-v','error','-show_packets','-show_streams','-show_format','-of','json',str(path)]))
  v=[p for p in info['packets'] if p['codec_type']=='video'];a=[p for p in info['packets'] if p['codec_type']=='audio']
  for packets in [v,a]:
   times=[float(p['pts_time']) for p in packets]
   assert all(y>x for x,y in zip(times,times[1:])),(mode,'non-monotonic timestamps')
  assert abs(float(info['format']['duration'])-pts/1e6)<.1,(mode,'wrong duration')
  if mode!='film':assert len(v)==570,(mode,'dropped compressed frames',len(v))
  else:
   # After an actual 60->30 transition, film grouping must disengage and the
   # configured 23.976 output must remain a cap rather than passing 30 frames/s.
   middle=[p for p in v if 6.5<=float(p['pts_time'])<8.5]
   assert len(middle)<=49,(mode,'output cap exceeded after carrier change',len(middle))
  # All audio remains aligned; slight resampler corrections only in helper paths.
  assert abs(float(a[-1]['pts_time'])+float(a[-1].get('duration_time',0))-pts/1e6)<.1
  sp.run([ff,'-v','error','-xerror','-i',str(path),'-enc_time_base:v','1:1000000','-f','null','-'],check=True)
  print('PASS decode, monotonic A/V, preserved duration:',mode)
