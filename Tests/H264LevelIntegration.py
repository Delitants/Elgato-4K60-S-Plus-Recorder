"""Exercise real encoders and inspect the resulting H.264 stream level."""
import json,pathlib,struct,subprocess as sp,sys,tempfile,re
helper=str(pathlib.Path(sys.argv[1]).resolve())
software_only='--software-only' in sys.argv
red='--red' in sys.argv
def run(a,**kw):return sp.run(a,check=True,capture_output=True,**kw)
def raw(s):return bytes.fromhex(''.join(x.split(':',1)[1].split('  ')[0].replace(' ','') for x in s.strip().splitlines()))
def msg(t,pts,b=b''):return struct.pack('<IIq',0x454c4700|t,len(b),pts)+b
with tempfile.TemporaryDirectory(prefix='elgato-level-') as tmp:
 root=pathlib.Path(tmp);src=root/'source.mp4'
 run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=640x360:rate=30','-t','1','-c:v','libx264','-preset','ultrafast','-g','30','-bf','0',str(src)])
 info=json.loads(run(['ffprobe','-v','error','-show_streams','-show_packets','-show_data','-of','json',str(src)]).stdout)
 body=bytearray(msg(0,0,raw(info['streams'][0]['extradata'])))
 for p in info['packets']:
  pts=round(float(p['pts_time'])*1e6);body+=msg(1,pts,raw(p['data']))+msg(2,pts,struct.pack('<hh',1000,-1000)*1600)
 body+=msg(3,0)
 def encode(name,codec,options,expect=True):
  out=root/(name+'.mp4')
  args=[helper,'output='+str(out),'video='+codec,'audio=aac','decoder=2','encoder=1','sourceN=30','sourceD=1','bitrate=6000000']+options
  r=sp.run(args,input=body,capture_output=True,timeout=30)
  if expect:assert r.returncode==0,(name,r.stdout,r.stderr)
  else:assert r.returncode!=0 and b'H.264 level' in r.stderr,(name,r.stdout,r.stderr)
  return out,r
 codecs=['libx264'] if software_only or red else ['libx264','h264_videotoolbox']
 for codec in codecs:
  levels=['4.1'] if red else ['3.0','3.1','3.2','4.0','4.1','4.2','5.0','5.1','5.2']
  for level in levels:
   for profile in (['high'] if red else ['auto','baseline','main','high']):
    out,r=encode(codec+level+profile,codec,['level='+level,'profile='+profile])
    v=json.loads(run(['ffprobe','-v','error','-select_streams','v:0','-count_frames','-show_streams','-of','json',str(out)]).stdout)['streams'][0]
    assert v['level']==round(float(level)*10),(codec,level,profile,v['level'])
    assert int(v['nb_read_frames'])==30,v
    run(['ffmpeg','-v','error','-xerror','-i',str(out),'-f','null','-'])
   print('PASS',codec,'level',level,'all profiles, SPS level and full decode',flush=True)
  if red:continue
  for ext in ['mov','mkv','ts']:
   path=root/(codec+'-container.'+ext)
   out,r=encode(codec+ext,codec,['level=4.1','profile=high','output='+str(path)])
   v=json.loads(run(['ffprobe','-v','error','-show_streams','-of','json',str(path)]).stdout)['streams'][0]
   assert v['level']==41
   run(['ffmpeg','-v','error','-xerror','-i',str(path),'-f','null','-'])
  print('PASS',codec,'MOV/MKV/MPEG-TS explicit level',flush=True)
  for rc in (['crf','cbr'] if codec=='libx264' else ['cq','cbr']):
   out,r=encode(codec+rc,codec,['level=4.1','profile=high','rc='+rc]+(['output='+str(root/(codec+rc+'.mkv'))] if rc=='cbr' else []))
   if rc=='cbr':out=root/(codec+rc+'.mkv')
   v=json.loads(run(['ffprobe','-v','error','-show_streams','-of','json',str(out)]).stdout)['streams'][0];assert v['level']==41
   run(['ffmpeg','-v','error','-xerror','-i',str(out),'-f','null','-'])
  if codec=='libx264':
   encode('ultrafast-high-over-limit',codec,['level=3.0','profile=high','preset=ultrafast','bitrate=12000000'],False)
  for name,opts in [('unknown',['level=9.9']),('mbps',['level=3.0','fpsN=60','sourceN=60']),('bitrate',['level=3.0','bitrate=30000000'])]:
   encode(codec+name,codec,opts,False)
  print('PASS',codec,'rate-control variants and invalid level/rate guards',flush=True)
 if not red:
  for codec in ['copy','libx265']:
   encode('wrong-'+codec,codec,['level=4.1'],False)
  print('PASS explicit level rejected for stream copy and non-H.264 codecs',flush=True)

 if not red:
  # Actual Full HD 60 -> 30 conversion at level 4.1, including a software
  # preset whose default reference-frame count would exceed the level budget.
  full=root/'fullhd.mp4'
  run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=1920x1080:rate=60','-t','1','-c:v','libx264','-preset','ultrafast','-g','60','-bf','0',str(full)])
  fullInfo=json.loads(run(['ffprobe','-v','error','-show_streams','-show_packets','-show_data','-of','json',str(full)]).stdout)
  body=bytearray(msg(0,0,raw(fullInfo['streams'][0]['extradata'])))
  for packet in fullInfo['packets']:
   pts=round(float(packet['pts_time'])*1e6);body+=msg(1,pts,raw(packet['data']))+msg(2,pts,struct.pack('<hh',1000,-1000)*800)
  body+=msg(3,0)
  for codec in codecs:
   extra=['preset=veryslow','bframes=4','encoder=2'] if codec=='libx264' else []
   out,result=encode('fullhd30-'+codec,codec,['level=4.1','profile=high','sourceN=60','fpsN=30']+extra)
   video=json.loads(run(['ffprobe','-v','error','-select_streams','v:0','-count_frames','-show_streams','-of','json',str(out)]).stdout)['streams'][0]
   assert video['level']==41 and video['width']==1920 and video['height']==1080 and int(video['nb_read_frames'])==30,video
   trace=run(['ffmpeg','-v','info','-i',str(out),'-map','0:v','-c','copy','-bsf:v','trace_headers','-f','null','-']).stderr.decode()
   refs=re.findall(r'(?:max_num_ref_frames|max_dec_frame_buffering)\s+.*?= (\d+)',trace)
   assert refs and all(int(x)<=4 for x in refs),(codec,refs)
   run(['ffmpeg','-v','error','-xerror','-i',str(out),'-f','null','-'])
   encode('fullhd60-rejected-'+codec,codec,['level=4.1','sourceN=60'],False)
   out,result=encode('fullhd60-'+codec,codec,['level=4.2','sourceN=60'])
   video=json.loads(run(['ffprobe','-v','error','-select_streams','v:0','-count_frames','-show_streams','-of','json',str(out)]).stdout)['streams'][0]
   assert video['level']==42 and int(video['nb_read_frames'])==60,video
   run(['ffmpeg','-v','error','-xerror','-i',str(out),'-f','null','-'])
   print('PASS',codec,'1080p60 -> level 4.1/30fps, DPB limit, 60fps rejection and level 4.2/60fps',flush=True)
