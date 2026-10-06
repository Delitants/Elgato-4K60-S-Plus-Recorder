"""Exercise actual helper output, structural Matroska index order, and seek/decode."""
import json, pathlib, struct, subprocess as sp, sys, tempfile
helper=str(pathlib.Path(sys.argv[1]).resolve())
def run(args,**kw):return sp.run(args,check=True,capture_output=True,**kw)
def msg(t,pts,data=b''):return struct.pack('<IIq',0x454c4700|t,len(data),pts)+data
def raw(s):return bytes.fromhex(''.join(x.split(':',1)[1].split('  ')[0].replace(' ','') for x in s.strip().splitlines()))
def vint(b,p,keep=False):
 first=b[p];n=1
 while not first & (1 << (8-n)):n+=1
 value=int.from_bytes(b[p:p+n],'big')
 return (value if keep else value & ((1<<(7*n))-1)),p+n
def children(b,start,end):
 while start<end:
  offset=start;tag,start=vint(b,start,True);size,start=vint(b,start)
  yield tag,offset,start,start+size
  start+=size
with tempfile.TemporaryDirectory(prefix='elgato-network-') as tmp:
 root=pathlib.Path(tmp);source=root/'source.mp4'
 run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=160x90:rate=30','-t','5','-c:v','libx264','-preset','ultrafast','-g','30','-bf','0',str(source)])
 info=json.loads(run(['ffprobe','-v','error','-show_streams','-show_packets','-show_data','-of','json',str(source)]).stdout)
 payload=msg(0,0,raw(info['streams'][0]['extradata']))
 for packet in info['packets']:
  pts=round(float(packet['pts_time'])*1e6)
  payload+=msg(1,pts,raw(packet['data']))+msg(2,pts,struct.pack('<hh',1000,-1000)*1600)
 payload+=msg(3,0)
 baseline=None
 for name,opt,split in [('off',0,False),('on',1,False),('split',1,True),('size',1,True),('salvage',1,False)]:
  out=root/(name+'.mkv')
  args=[helper,'output='+str(out),'video=copy','audio=pcm_s16le','decoder=2','sourceN=30','sourceD=1','networkPlayback='+str(opt)]
  if split:args+=['split='+('2' if name=='size' else '1'),'splitValue='+('1' if name=='size' else '2')]
  body=payload if name!='salvage' else payload[:-16]+struct.pack('<IIq',0x454c4701,20*1024*1024,0)
  result=sp.run(args,input=body,capture_output=True)
  assert result.returncode==(1 if name=='salvage' else 0),(name,result.stderr)
  files=[pathlib.Path(line[6:]) for line in result.stdout.decode().splitlines() if line.startswith('SAVED ')]
  assert files and (len(files)>1 if split else len(files)==1),(name,result.stdout)
  for file in files:
   data=file.read_bytes();seg=next(x for x in children(data,0,len(data)) if x[0]==0x18538067)
   elements=list(children(data,seg[2],min(seg[3],len(data))))
   cues=next(x for x in elements if x[0]==0x1C53BB6B)
   cluster=next(x for x in elements if x[0]==0x1F43B675)
   assert (cues[1]<cluster[1])==bool(opt),(name,'Cues must precede media only when enabled',cues[1],cluster[1])
   assert list(children(data,cues[2],cues[3])), 'Empty cue index'
   run(['ffmpeg','-v','error','-xerror','-i',str(file),'-f','null','-'])
   run(['ffmpeg','-v','error','-xerror','-ss','0.5','-i',str(file),'-frames:v','1','-f','null','-'])
  if not split and name!='salvage':
   decoded=run(['ffmpeg','-v','error','-i',str(files[0]),'-map','0','-f','framemd5','-']).stdout
   if baseline is None:baseline=decoded
   else:assert decoded==baseline,'Network optimization changed decoded A/V'
  print('PASS',name,'index layout, full decode and seek;',len(files),'file(s)',flush=True)
 # Many all-intra pictures exercise the bounded-index fallback without a long soak.
 out=root/'many-keyframes.mkv'
 body=bytearray(msg(0,0,raw(info['streams'][0]['extradata'])))
 first=raw(info['packets'][0]['data'])
 for i in range(8300):body+=msg(1,round(i/30*1e6),first)
 result=run([helper,'output='+str(out),'video=copy','audio=pcm_s16le','decoder=2','sourceN=30','sourceD=1','networkPlayback=1'],input=body+msg(3,0))
 assert b'WARNING ' in result.stdout and b'index' in result.stdout,'Index capacity fallback must warn, not relocate media'
 data=out.read_bytes();seg=next(x for x in children(data,0,len(data)) if x[0]==0x18538067)
 elements=list(children(data,seg[2],min(seg[3],len(data))))
 assert next(x[1] for x in elements if x[0]==0x1C53BB6B)>next(x[1] for x in elements if x[0]==0x1F43B675),'Fallback must keep a valid end index'
 run(['ffmpeg','-v','error','-xerror','-i',str(out),'-map','0:v','-f','null','-'])
 run(['ffmpeg','-v','error','-xerror','-ss','240','-i',str(out),'-frames:v','1','-f','null','-'])
 print('PASS index capacity fallback: warning, valid end index, decode and seek; no media relocation',flush=True)
