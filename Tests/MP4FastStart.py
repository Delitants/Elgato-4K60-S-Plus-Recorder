"""Real muxer regression: only MP4 gets front moov, including every split part."""
import json,pathlib,struct,subprocess as sp,sys,tempfile
helper=str(pathlib.Path(sys.argv[1]).resolve())
def run(args,**kw):return sp.run(args,check=True,capture_output=True,**kw)
def raw(s):return bytes.fromhex(''.join(x.split(':',1)[1].split('  ')[0].replace(' ','') for x in s.strip().splitlines()))
def msg(t,pts,b=b''):return struct.pack('<IIq',0x454c4700|t,len(b),pts)+b
def boxes(path):
 b=path.read_bytes();p=0;result=[]
 while p<len(b):
  n,tag=struct.unpack_from('>I4s',b,p)
  if n==1:n=struct.unpack_from('>Q',b,p+8)[0]
  if n==0:n=len(b)-p
  assert n>=8 and p+n<=len(b),(path,p,n)
  result.append(tag);p+=n
 return result
with tempfile.TemporaryDirectory(prefix='elgato-mp4-') as tmp:
 root=pathlib.Path(tmp);src=root/'source.mp4'
 run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=160x90:rate=30','-t','4','-c:v','libx264','-preset','ultrafast','-g','30','-bf','0',str(src)])
 info=json.loads(run(['ffprobe','-v','error','-show_streams','-show_packets','-show_data','-of','json',str(src)]).stdout)
 body=bytearray(msg(0,0,raw(info['streams'][0]['extradata'])))
 for p in info['packets']:
  pts=round(float(p['pts_time'])*1e6);body+=msg(1,pts,raw(p['data']))+msg(2,pts,struct.pack('<hh',1000,-1000)*1600)
 body+=msg(3,0)
 hashes=[]
 for ext,split in [('mov',0),('mp4',0),('mp4',1)]:
  out=root/(str(split)+'.'+ext)
  r=run([helper,'output='+str(out),'video=copy','audio=aac','decoder=2','sourceN=30','sourceD=1','split='+str(split),'splitValue=2'],input=body)
  files=list(dict.fromkeys(pathlib.Path(x[6:]) for x in r.stdout.decode().splitlines() if x.startswith('SAVED ')))
  assert len(files)==(2 if split else 1),r.stdout
  for f in files:
   order=boxes(f);assert (order.index(b'moov')<order.index(b'mdat'))==(ext=='mp4'),(f.name,order)
   run(['ffmpeg','-v','error','-xerror','-i',str(f),'-f','null','-'])
   run(['ffmpeg','-v','error','-xerror','-ss','0.5','-i',str(f),'-frames:v','1','-f','null','-'])
  if not split:hashes.append(run(['ffmpeg','-v','error','-i',str(files[0]),'-map','0','-f','framemd5','-']).stdout)
  print('PASS helper',ext,'split',split,'box order, decode and seek',flush=True)
 assert hashes[0]==hashes[1],'MOV and MP4 decoded content changed'
 # At a live split, close the part quickly without relocating it. Optimize only
 # once Stop arrives, so a large-part rewrite cannot consume the capture queue.
 out=root/'deferred.mp4'
 p=sp.Popen([helper,'output='+str(out),'video=copy','audio=aac','decoder=2','sourceN=30','sourceD=1','split=1','splitValue=2'],stdin=sp.PIPE,stdout=sp.PIPE,stderr=sp.PIPE)
 try:
  p.stdin.write(body[:-16]);p.stdin.flush()
  while True:
   line=p.stdout.readline();assert line,'Helper exited before split completed'
   if line.startswith(b'SAVED '):
    part=pathlib.Path(line[6:].decode().strip());order=boxes(part)
    assert order.index(b'mdat')<order.index(b'moov'),'Live split must not perform fast-start relocation'
    break
  before=run(['ffmpeg','-v','error','-i',str(part),'-map','0','-f','framemd5','-']).stdout
  p.stdin.write(msg(3,0));p.stdin.close();p.stdin=None
  stdout,stderr=p.communicate(timeout=30);assert p.returncode==0,stderr
  order=boxes(part);assert order.index(b'moov')<order.index(b'mdat')
  after=run(['ffmpeg','-v','error','-i',str(part),'-map','0','-f','framemd5','-']).stdout
  assert before==after,'Deferred optimization changed decoded media/timestamps'
  assert not list(root.glob('*.faststart-*')),'Temporary MP4 copies leaked'
  print('PASS deferred MP4 split: tail index during capture, front index after Stop, identical decoded content',flush=True)
 finally:
  if p.poll() is None:p.kill()
  p.communicate()

 # Test binary injects a final output-close error in the embedded optimizer.
 if len(sys.argv)<3:sys.exit(0)
 result=run([sys.argv[2],'output='+str(root/'fallback.mp4'),'video=copy','audio=aac','decoder=2','sourceN=30','sourceD=1','split=1','splitValue=2'],input=body)
 assert b'original playable part retained' in result.stdout,result.stdout
 parts=list(root.glob('fallback_part*.mp4'));assert len(parts)==2
 for part in parts:
  order=boxes(part);assert order.index(b'mdat')<order.index(b'moov')
  run(['ffmpeg','-v','error','-xerror','-i',str(part),'-f','null','-'])
 assert not list(root.glob('*.faststart-*'))
 print('PASS optimizer close failure: original MP4 parts retained, warning, full decode, temporary copies cleaned',flush=True)
