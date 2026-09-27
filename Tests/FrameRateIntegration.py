# Regressions: hard-coded 59.94, duplicated low-rate input, dropped audio, broken splits.
import subprocess as sp,sys,pathlib,struct,json,math
root=pathlib.Path(sys.argv[1]);helper=str(pathlib.Path(sys.argv[2]).resolve())
ff='/opt/homebrew/bin/ffmpeg';fp='/opt/homebrew/bin/ffprobe'
def probe(path,*args):return json.loads(sp.check_output([fp,'-v','error',*args,'-of','json',str(path)]))
def data(s):return bytes.fromhex(''.join(line.split(':',1)[1].split('  ')[0].replace(' ','') for line in s.strip().splitlines()))
def msg(t,pts,body=b''):return struct.pack('<IIq',0x454c4700|t,len(body),pts)+body
for source,target,frames in [('60','30',60),('30','30',60),('30000/1001','30000/1001',60),('60000/1001','30000/1001',60),('60','24',48),('60','15',30),('30','60',60)]:
 tag=source.replace('/','_')+'to'+target.replace('/','_');src=root/(tag+'.mp4')
 n=120 if source in ['60','60000/1001'] else 60
 sp.run([ff,'-v','error','-f','lavfi','-i',f'testsrc2=size=160x90:rate={source}','-frames:v',str(n),'-c:v','libx264','-preset','ultrafast','-bf','0','-g',str(round(float(source.split('/')[0])/float(source.split('/')[1]) if '/' in source else float(source))),str(src)],check=True)
 info=probe(src,'-show_streams','-show_packets','-show_data');stream=info['streams'][0]
 sn,sd=map(int,stream['r_frame_rate'].split('/'));tn,td=map(int,(target if '/' in target else target+'/1').split('/'))
 duration=n*sd/sn;count=round(duration*48000)
 pcm=b''.join(struct.pack('<hh',int(7000*math.sin(i*2*math.pi*440/48000)),i%30000-15000) for i in range(count))
 items=[(round(float(p['pts_time'])*1e6),1,data(p['data'])) for p in info['packets']]
 items += [(round(i/48000*1e6),2,pcm[i*4:(i+1024)*4]) for i in range(0,count,1024)]
 payload=msg(0,0,data(stream['extradata']))+b''.join(msg(t,pts,b) for pts,t,b in sorted(items))+msg(3,0)
 out=root/(tag+'.mkv')
 command=[helper,'output='+str(out),'video=libx264','audio=pcm_s16le','decoder=2','encoder=2',f'sourceN={sn}',f'sourceD={sd}',f'fpsN={tn}',f'fpsD={td}','preset=ultrafast']
 r=sp.run(command,input=payload,capture_output=True,timeout=30);assert r.returncode==0,r.stderr.decode()
 check=probe(out,'-show_streams','-show_frames');v=next(s for s in check['streams'] if s['codec_type']=='video')
 vf=[f for f in check['frames'] if f['media_type']=='video'];assert len(vf)==frames,(tag,'frames',len(vf),frames)
 expected=min(sn/sd,tn/td);a,b=map(int,v['avg_frame_rate'].split('/'));assert abs(a/b-expected)<0.01,(tag,v['avg_frame_rate'])
 assert abs(float(vf[-1]['pts_time'])-(frames-1)/expected)<0.002,(tag,'timeline')
 got=sp.check_output([ff,'-v','error','-xerror','-i',str(out),'-map','0:a','-f','s16le','-']);assert got==pcm,(tag,'audio changed')
 decoded=sp.run([ff,'-v','error','-xerror','-i',str(out),'-enc_time_base:v','1:1000000','-f','null','-'],capture_output=True);assert decoded.returncode==0 and not decoded.stderr,decoded.stderr
 print('PASS FPS',tag,frames,'frames, original audio, unchanged duration',flush=True)
# Last fixture is 30 fps. Original copy must preserve 60 frames and the complete PCM.
for codec,target_n,split in [('copy',30,0),('copy',15,0),('libx264',15,1)]:
 dest=root/f'extra-{codec}-{target_n}-{split}.mkv'
 cmd=[helper,'output='+str(dest),'video='+codec,'audio=pcm_s16le','decoder=2','encoder=2','sourceN=30','sourceD=1',f'fpsN={target_n}','fpsD=1',f'split={split}','splitValue=1','preset=ultrafast']
 result=sp.run(cmd,input=payload,capture_output=True,timeout=30)
 if codec=='copy' and target_n==15:
  assert result.returncode!=0 and b'downsampling requires' in result.stderr
  assert not dest.exists();print('PASS compressed frame dropping rejected');continue
 assert result.returncode==0,result.stderr
 files=sorted(root.glob(dest.stem+'*'+dest.suffix));assert len(files)==(2 if split else 1)
 all_pcm=b'';total=0
 for f in files:
  info=probe(f,'-show_streams','-count_frames');v=next(s for s in info['streams'] if s['codec_type']=='video');total+=int(v['nb_read_frames'])
  all_pcm+=sp.check_output([ff,'-v','error','-xerror','-i',str(f),'-map','0:a','-f','s16le','-'])
  decode=sp.run([ff,'-v','error','-xerror','-i',str(f),'-enc_time_base:v','1:1000000','-f','null','-'],capture_output=True);assert decode.returncode==0 and not decode.stderr
 assert total==target_n*2 and all_pcm==pcm,(codec,total,len(all_pcm),len(pcm))
 print('PASS FPS passthrough/split',codec,target_n,len(files),'part(s)')

# Source keys at odd/non-selected frame positions must not postpone splitting.
src=root/'unaligned.mp4'
sp.run([ff,'-v','error','-f','lavfi','-i','testsrc2=size=160x90:rate=60','-frames:v','300','-c:v','libx264','-preset','ultrafast','-bf','0','-g','61','-keyint_min','61','-sc_threshold','0',str(src)],check=True)
info=probe(src,'-show_streams','-show_packets','-show_data')
items=[(round(float(p['pts_time'])*1e6),1,data(p['data'])) for p in info['packets']]
pcm=struct.pack('<hh',1234,-4321)*240000
items += [(round(i/48000*1e6),2,pcm[i*4:(i+1024)*4]) for i in range(0,240000,1024)]
payload=msg(0,0,data(info['streams'][0]['extradata']))+b''.join(msg(t,pts,b) for pts,t,b in sorted(items))+msg(3,0)
dest=root/'unaligned.mkv'
r=sp.run([helper,'output='+str(dest),'video=libx264','audio=pcm_s16le','decoder=2','encoder=2','sourceN=60','sourceD=1','fpsN=15','fpsD=1','split=1','splitValue=1','preset=ultrafast'],input=payload,capture_output=True,timeout=30)
assert r.returncode==0,r.stderr
files=sorted(root.glob('unaligned_part*.mkv'));assert len(files)>=3,('unaligned keys postponed splits',files)
all_pcm=b'';frames=0
for f in files:
 info=probe(f,'-show_format','-show_frames');vf=[x for x in info['frames'] if x['media_type']=='video'];frames+=len(vf)
 assert vf[0]['key_frame']==1
 assert float(info['format']['duration'])<2.1,('split bound',f,info['format']['duration'])
 all_pcm+=sp.check_output([ff,'-v','error','-xerror','-i',str(f),'-map','0:a','-f','s16le','-'])
assert frames==75 and all_pcm==pcm,(frames,len(all_pcm))
print('PASS unaligned source keyframes: bounded splits, 75 frames and exact PCM')
