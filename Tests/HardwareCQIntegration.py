"""Exercise real bundled hardware encoders; all fixtures live in TemporaryDirectory."""
import json, pathlib, re, struct, subprocess, sys, tempfile

helper=str(pathlib.Path(sys.argv[1]).resolve())
intel='--intel' in sys.argv
ff='ffmpeg';fp='ffprobe'
def run(args,**kwargs):return subprocess.run(args,capture_output=True,timeout=90,**kwargs)
def hexdata(s):return bytes.fromhex(''.join(line.split(':',1)[1].split('  ')[0].replace(' ','') for line in s.strip().splitlines()))
def msg(t,pts,data=b''):return struct.pack('<IIq',0x454c4700|t,len(data),pts)+data
with tempfile.TemporaryDirectory(prefix='elgato-hardware-cq-') as temp:
 root=pathlib.Path(temp);src=root/'source.mp4'
 subprocess.run([ff,'-v','error','-f','lavfi','-i','testsrc2=size=640x360:rate=30','-t','2','-c:v','libx264','-crf','0','-preset','ultrafast','-bf','0','-g','30',str(src)],check=True)
 info=json.loads(subprocess.check_output([fp,'-v','error','-show_streams','-show_packets','-show_data','-of','json',str(src)]))
 packets=[(round(float(p['pts_time'])*1e6),1,hexdata(p['data'])) for p in info['packets']]
 for start in range(0,96000,1024):packets.append((round(start/48000*1e6),2,b'\0'*min(1024,96000-start)*4))
 payload=msg(0,0,hexdata(info['streams'][0]['extradata']))+b''.join(msg(t,pts,data) for pts,t,data in sorted(packets))+msg(3,0)
 def encode(codec,q,tag,ext='mkv',extras=()):
  dest=root/f'{tag}.{ext}'
  r=run([helper,'output='+str(dest),'video='+codec,'audio=aac','decoder=2','encoder=1','rc=cq','hardwareQuality='+str(q),'bitrate=1000000','sourceN=30','sourceD=1','fpsN=30','fpsD=1',*extras],input=payload)
  return dest,r
 if intel:
  for codec in ['h264_videotoolbox','hevc_videotoolbox']:
   dest,r=encode(codec,65,codec)
   assert r.returncode!=0 and b'Apple Silicon' in r.stderr and not dest.exists(),r.stderr.decode()
  print('PASS Intel explicitly rejects hardware CQ before creating output')
 else:
  for codec in ['h264_videotoolbox','hevc_videotoolbox']:
   sizes=[];qualities=[]
   for q in [20,80]:
    dest,r=encode(codec,q,f'{codec}-{q}')
    assert r.returncode==0,r.stderr.decode()
    streams=json.loads(subprocess.check_output([fp,'-v','error','-count_frames','-show_streams','-of','json',str(dest)]))['streams']
    video=next(s for s in streams if s['codec_type']=='video')
    assert int(video['nb_read_frames'])==60 and video['width']==640 and video['height']==360
    sizes.append(dest.stat().st_size)
    decoded=run([ff,'-v','error','-xerror','-i',str(dest),'-f','null','-']);assert decoded.returncode==0 and not decoded.stderr,decoded.stderr.decode()
    # AAC priming/container timestamp rounding can offset frame timestamps.
    # Quality must compare corresponding images; timing has separate assertions.
    comparison=run([ff,'-i',str(src),'-i',str(dest),'-lavfi','[0:v]settb=1/30,setpts=N[ref];[1:v]settb=1/30,setpts=N[enc];[ref][enc]psnr','-f','null','-'])
    assert comparison.returncode==0,comparison.stderr.decode()
    qualities.append(float(re.search(r'average:([0-9.]+)',comparison.stderr.decode()).group(1)))
   assert sizes[1]>sizes[0]*1.15 and qualities[1]>qualities[0]+1,('CQ quality must affect actual compression, not silently use ABR',codec,sizes,qualities)
   print('PASS',codec,'CQ 20/80 bytes',sizes,'PSNR',qualities)
  for ext in ['mov','mp4','ts']:
   dest,r=encode('hevc_videotoolbox',65,'container-'+ext,ext)
   assert r.returncode==0,r.stderr.decode()
   decoded=run([ff,'-v','error','-xerror','-i',str(dest),'-f','null','-']);assert decoded.returncode==0 and not decoded.stderr,decoded.stderr.decode()
   print('PASS hardware HEVC CQ',ext)
  for q in [0,100]:
   dest,r=encode('h264_videotoolbox',q,'boundary-'+str(q))
   assert r.returncode==0,r.stderr.decode()
  dest,r=encode('hevc_videotoolbox',65,'main10','mkv',['profile=main10','fpsN=15'])
  assert r.returncode==0,r.stderr.decode()
  info=json.loads(subprocess.check_output([fp,'-v','error','-count_frames','-show_streams','-of','json',str(dest)]))
  video=next(s for s in info['streams'] if s['codec_type']=='video')
  assert video['pix_fmt']=='yuv420p10le' and int(video['nb_read_frames'])==30,video
  print('PASS CQ quality endpoints, HEVC Main 10 and FPS downsampling')
 for codec,q in [('copy',65),('libx264',65),('prores_videotoolbox',65),('h264_videotoolbox',-1),('hevc_videotoolbox',101)]:
  dest,r=encode(codec,q,f'invalid-{codec}-{q}')
  assert r.returncode!=0 and not dest.exists(),(codec,q,r.stderr.decode())
 print('PASS unsupported CQ configurations fail without output; all temporary media cleaned on exit')
