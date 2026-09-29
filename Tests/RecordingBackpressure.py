"""Pause only the disposable real helper; always resume it, including on failure."""
import base64,json,pathlib,subprocess as sp,sys,tempfile,time,os,signal,re
binary=str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix='elgato-backpressure-') as tmp:
 root=pathlib.Path(tmp);src=root/'source.h264'
 hevc=os.environ.get('TEST_HEVC')=='1'
 cmd=['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=160x90:rate=60','-t','22','-c:v','libx265' if hevc else 'libx264','-preset','ultrafast','-g','60','-bf','0']
 if hevc:cmd+=['-x265-params','log-level=error:pools=1']
 sp.run(cmd+['-f','hevc' if hevc else 'h264',str(src)],check=True)
 packets=json.loads(sp.check_output(['ffprobe','-v','error','-show_packets','-of','json',str(src)]))['packets']
 data=src.read_bytes();frames=[]
 for i,p in enumerate(packets):
  payload=data[int(p['pos']):int(p['pos'])+int(p['size'])]
  frames.append(dict(type=193,timestamp=round(i*1e6/60),data=base64.b64encode(payload).decode()))
 for s in range(0,22*48000,1024):
  n=min(1024,22*48000-s)
  frames.append(dict(type=195,timestamp=round(s*1e6/48000),data=base64.b64encode(b'\xd2\x04\x2e\xfb'*n).decode()))
 frames.sort(key=lambda x:(x['timestamp'],x['type']));(root/'frames.json').write_text(json.dumps(frames))
 run=sp.Popen([binary,str(root)],stdout=sp.PIPE,stderr=sp.PIPE,text=True)
 stopped=None
 try:
  started=time.monotonic()
  time.sleep(11)
  if run.poll() is not None:
   stdout,stderr=run.communicate();raise AssertionError('Test recorder exited before stall: '+stdout+stderr)
  children=sp.check_output(['pgrep','-P',str(run.pid),'-x','MediaHelper'],text=True).split()
  assert len(children)==1,children
  child=int(children[0])
  for at,duration in [map(float,item.split(':')) for item in os.environ.get('TEST_STALLS','11:4').split(',')]:
   time.sleep(max(0,started+at-time.monotonic()))
   stopped=child;os.kill(stopped,signal.SIGSTOP);time.sleep(duration)
   try:os.kill(stopped,signal.SIGCONT)
   except ProcessLookupError:pass
   stopped=None
  stdout,stderr=run.communicate(timeout=55);print(stdout,end='');print(stderr,end='')
  assert run.returncode==0,run.returncode
  if int(os.environ.get('TEST_PADDING','0')):
   backlogs=[(float(a),float(b)) for a,b in re.findall(r'backlog ([0-9.]+) s / ([0-9.]+) MB',stderr)]
   assert any(age<2 and 60<size<=64*1024*1024/1e6 for age,size in backlogs),backlogs
  if ',' in os.environ.get('TEST_STALLS',''):
   assert '2 backlog event(s)' in stdout,stdout
 finally:
  if stopped:
   try:os.kill(stopped,signal.SIGCONT)
   except ProcessLookupError:pass
  if run.poll() is None:run.terminate();run.wait(timeout=45)
 path=root/'result.mkv'
 info=json.loads(sp.check_output(['ffprobe','-v','error','-show_packets','-show_format','-of','json',str(path)]))
 for typ in ['video','audio']:
  packets=[p for p in info['packets'] if p['codec_type']==typ]
  ts=[float(p['pts_time']) for p in packets]
  assert all(b>a for a,b in zip(ts,ts[1:])),(typ,'timestamps')
  if 'TEST_STOP_AT' not in os.environ and 'TEST_TERMINAL' not in os.environ:assert ts[-1]>21.8,(typ,'did not resume to end',ts[-1])
 if 'TEST_STOP_AT' not in os.environ and 'TEST_TERMINAL' not in os.environ:assert abs(float(info['format']['duration'])-22)<.15
 r=sp.run(['ffmpeg','-v','error','-xerror','-i',str(path),'-enc_time_base:v','1:1000000','-fps_mode','passthrough','-f','null','-'],capture_output=True,text=True)
 assert r.returncode==0 and not r.stderr,r.stderr
 print('PASS stalled real helper: monotonic A/V and full decode;',os.environ.get('TEST_MODE','software'),os.environ.get('TEST_STALLS','11:4'))
