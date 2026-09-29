"""Known picture IDs carried as 3:2 repeats; verifies picture order, not just FPS."""
import subprocess as sp, pathlib, tempfile, json,struct,sys,math
helper=str(pathlib.Path(sys.argv[1]).resolve())
def msg(t,pts,data=b''):return struct.pack('<IIq',0x454c4700|t,len(data),pts)+data
def unhex(s):return bytes.fromhex(''.join(x.split(':',1)[1].split('  ')[0].replace(' ','') for x in s.strip().splitlines()))
def run(cmd,**kw):return sp.run(cmd,check=True,capture_output=True,**kw)
with tempfile.TemporaryDirectory(prefix='elgato-film-cadence-') as temp:
 root=pathlib.Path(temp)
 # Each original picture has a distinct luma value; repeated carriers are exact copies.
 for phase,ten in [(i,False) for i in range(5)]+[(2,True)]:
  source=root/f'source{phase}-{ten}.mkv';out=root/f'output{phase}-{ten}.mkv'
  ids=[(i+phase)*2//5 for i in range(300)]
  raw=b''.join(bytes([16+id%200])*64*48+bytes([128])*(64*48//2) for id in ids)
  source_encoder=['-c:v','libx265','-pix_fmt','yuv420p10le','-x265-params','lossless=1:bframes=0:keyint=60:pools=1'] if ten else ['-c:v','libx264','-crf','0','-g','60','-bf','0']
  run(['ffmpeg','-v','error','-f','rawvideo','-pix_fmt','yuv420p','-s','64x48','-r','60000/1001','-i','-',*source_encoder,'-preset','ultrafast',str(source)],input=raw)
  info=json.loads(run(['ffprobe','-v','error','-show_streams','-show_packets','-show_data','-of','json',str(source)]).stdout)
  items=[(round(float(p['pts_time'])*1e6),1,unhex(p['data'])) for p in info['packets']]
  pcm=struct.pack('<hh',1234,-4321)*240240
  items += [(round(i/48000*1e6),2,pcm[i*4:(i+1024)*4]) for i in range(0,240240,1024)]
  payload=msg(0,0,unhex(info['streams'][0]['extradata']))+b''.join(msg(t,pts,b) for pts,t,b in sorted(items))+msg(3,0)
  result=sp.run([helper,'hevc='+str(int(ten)),'output='+str(out),'video=libx264','audio=pcm_s16le','encoder=2','decoder=2','sourceN=60000','sourceD=1001','fpsN=24000','fpsD=1001','cadence=film32','rc=crf','quality=0','preset=ultrafast'],input=payload,capture_output=True)
  assert result.returncode==0,result.stderr.decode()
  pixels=run(['ffmpeg','-v','error','-i',str(out),'-pix_fmt','yuv420p','-fps_mode','passthrough','-f','rawvideo','-']).stdout
  actual=[pixels[i]-16 for i in range(0,len(pixels),64*48*3//2)]
  # The first partial picture may be omitted, but no complete picture may repeat or disappear.
  steps=[b-a for a,b in zip(actual,actual[1:])]
  assert len(actual)==120,(phase,len(actual))
  assert all(x==1 for x in steps),(phase,'repeated/skipped original pictures',[(i+1,x) for i,x in enumerate(steps) if x!=1][:20])
  print('PASS 3:2 phase',phase,'HEVC10' if ten else 'H264','120 frames; no repeats or missing pictures including startup',flush=True)

  got=run(['ffmpeg','-v','error','-i',str(out),'-map','0:a','-f','s16le','-']).stdout
  assert got==pcm,(phase,'audio changed')
  if phase==2 and not ten:
   split_args=[helper,'output='+str(root/'split.mkv'),'video=libx264','audio=pcm_s16le','decoder=2','encoder=2','sourceN=60000','sourceD=1001','fpsN=24000','fpsD=1001','cadence=film32','split=1','splitValue=1','rc=crf','quality=0','preset=ultrafast']
   split=run(split_args,input=payload)
   parts=sorted(root.glob('split_part*.mkv'));assert len(parts)>=4,parts
   all_audio=b'';all_ids=[]
   for part in parts:
    partinfo=json.loads(run(['ffprobe','-v','error','-show_frames','-of','json',str(part)]).stdout)
    vf=[f for f in partinfo['frames'] if f['media_type']=='video'];assert vf[0]['key_frame']==1
    rawout=run(['ffmpeg','-v','error','-i',str(part),'-pix_fmt','yuv420p','-fps_mode','passthrough','-f','rawvideo','-']).stdout
    all_ids.extend(rawout[i]-16 for i in range(0,len(rawout),64*48*3//2))
    all_audio+=run(['ffmpeg','-v','error','-i',str(part),'-map','0:a','-f','s16le','-']).stdout
   assert all_ids==actual and all_audio==pcm,('split changed pictures/audio',len(all_ids),len(all_audio))
   print('PASS film split boundaries: exact picture sequence, independent keyframes and complete PCM',flush=True)
