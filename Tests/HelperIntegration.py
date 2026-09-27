import subprocess,sys,pathlib,struct,json,os
root=pathlib.Path(sys.argv[1]);helper=str(pathlib.Path(sys.argv[2]).resolve())
# Malformed IPC must fail without allocating its declared payload.
for body in (b'bad!',struct.pack('<IIq',0x454c4701,20*1024*1024,0)):
 r=subprocess.run([helper,'output='+str(root/'bad.mkv')],input=body,capture_output=True)
 assert r.returncode!=0
print('PASS malformed helper protocol')
ff='/opt/homebrew/bin/ffmpeg';fp='/opt/homebrew/bin/ffprobe'
src=root/'source.mp4'
hevc=os.environ.get('TEST_HEVC')=='1'
subprocess.run([ff,'-v','error','-f','lavfi','-i','testsrc2=size=320x180:rate=60','-t','2','-c:v',('libx265' if hevc else 'libx264'),'-preset','ultrafast','-bf','0','-g','30','-pix_fmt','yuv420p',str(src)],check=True)
info=json.loads(subprocess.check_output([fp,'-v','error','-show_streams','-show_packets','-show_data','-of','json',str(src)]))
def hexdata(s):
 return bytes.fromhex(''.join(line.split(':',1)[1].split('  ')[0].replace(' ','') for line in s.strip().splitlines()))
extra=hexdata(info['streams'][0]['extradata'])
def msg(t,pts,data=b''):return struct.pack('<IIq',0x454c4700|t,len(data),pts)+data
items=[]
for p in info['packets']:items.append((round(float(p['pts_time'])*1e6),1,hexdata(p['data'])))
import math
for start in range(0,96000,1024):
 n=min(1024,96000-start);pcm=b''.join(struct.pack('<hh',int(8000*math.sin((start+j)*2*math.pi*440/48000)),int(8000*math.sin((start+j)*2*math.pi*440/48000))) for j in range(n))
 items.append((round(start/48000*1e6),2,pcm))
payload=msg(0,0,extra)+b''.join(msg(t,pts,data) for pts,t,data in sorted(items))+msg(3,0)
cases=[('libx265','flac','mkv',['profile=main10','rc=crf']),('copy','pcm_s16le','mkv',['split=1','splitValue=1']),('libsvtav1','libopus','mkv',[]),('libsvtav1','flac','mkv',[]),('libx264','aac','ts',['bframes=2']),('copy','aac','mkv',[]),('libx264','aac','mkv',['split=1','splitValue=1','bframes=2']),('libx264','aac','mp4',['rc=crf','quality=24','filter=lanczos','height=90']),('libsvtav1','flac','mkv',['rc=crf','quality=32','profile=main']),('libx265','aac','mkv',['rc=crf','profile=main','aq=1','bframes=2']),('libx264','aac','mkv',['split=2','splitValue=1','rc=cbr','bitrate=12000000','preset=ultrafast']),('h264_videotoolbox','aac','mkv',['encoder=1','rc=cbr','profile=high','aq=1']),('hevc_videotoolbox','alac','mov',['encoder=1','profile=main10']),('prores_videotoolbox','pcm_s16le','mov',['encoder=1','profile=hq'])]
for i,(v,a,ext,opts) in enumerate(cases):
 dest=root/f'case{i}.{ext}'
 r=subprocess.run([helper,'output='+str(dest),'video='+v,'audio='+a,('decoder=1' if hevc else 'decoder=2'),'hevc='+str(int(hevc)),'encoder=2']+opts,input=payload,capture_output=True,timeout=90)
 if r.returncode and os.environ.get('ALLOW_UNAVAILABLE_HW')=='1' and 'encoder=1' in opts and any(code in r.stderr.decode() for code in ('-12908','-12906')):
  print('UNAVAILABLE required hardware encoder',v,'(reported explicitly)');continue
 assert r.returncode==0,(v,a,r.stderr.decode())
 files=list(root.glob(f'case{i}*.{ext}'));assert files
 if any(o.startswith('split=') for o in opts): assert len(files)>=2,('split did not occur',v,opts,[f.stat().st_size for f in files])
 total_frames=0
 split_pcm=[]
 for f in sorted(files):
  decoded=subprocess.run([ff,'-v','error','-xerror','-i',str(f),'-f','null','-'],capture_output=True)
  assert decoded.returncode==0 and not decoded.stderr,decoded.stderr.decode()
  streams=json.loads(subprocess.check_output([fp,'-v','error','-show_streams','-count_frames','-of','json',str(f)]))['streams']
  assert len(streams)==2
  video=next(s for s in streams if s['codec_type']=='video');audio=next(s for s in streams if s['codec_type']=='audio')
  if 'profile=main10' in opts: assert video['pix_fmt']=='yuv420p10le',video
  assert audio['sample_rate']=='48000' and audio['channels']==2
  total_frames+=int(video['nb_read_frames'])
  if a=='pcm_s16le' and 'split=1' in opts:
   pcm=subprocess.check_output([ff,'-v','error','-i',str(f),'-map','0:a','-f','s16le','-'])
   assert len(pcm)==48000*4,('PCM split boundary',f.name,len(pcm)//4)
   split_pcm.append(pcm)
 if split_pcm: assert b''.join(split_pcm)==b''.join(data for pts,t,data in sorted(items) if t==2)

 assert total_frames==120,(v,a,'frame count',total_frames)
 print('PASS',v,a,ext,len(files),'file(s)')
