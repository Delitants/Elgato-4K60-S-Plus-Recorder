"""Runs real RecordingSink cases, decodes each output, and deletes all media.
Usage: OutputMatrix.py /path/to/app/Contents/MacOS/OutputMatrix report.jsonl [all|hevc|controls|4k]
The Swift executable must share the app bundle with its recording helper.
"""
import base64,json,math,pathlib,shutil,struct,subprocess,sys,tempfile
binary=pathlib.Path(sys.argv[1]).resolve();report=pathlib.Path(sys.argv[2]).resolve();mode=sys.argv[3] if len(sys.argv)>3 else 'all'
ff=shutil.which('ffmpeg');fp=shutil.which('ffprobe');assert ff and fp
assert mode in ['all','hevc','controls','4k','hdr','hardware'],mode
failures=0
hevc='hevc' in mode or mode=='hdr'
size='3840x2160' if mode=='4k' else '320x180' if mode in ('controls','hevc','hdr','hardware') else '1920x1080'
duration=1;frames_count=60
with tempfile.TemporaryDirectory(prefix='elgato-output-matrix-') as directory:
 root=pathlib.Path(directory);src=root/('source.hevc' if hevc else 'source.h264')
 encoder=['-c:v','libx265','-preset','ultrafast','-pix_fmt','yuv420p10le','-x265-params','aud=1:repeat-headers=1:bframes=0:keyint=30:log-level=error:pools=2'] if hevc else ['-c:v','libx264','-preset','ultrafast','-bf','0','-g','30','-x264-params','aud=1:repeat-headers=1']
 if mode=='hdr':encoder[-1]+=':colorprim=9:transfer=16:colormatrix=9:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400'
 subprocess.run([ff,'-v','error','-f','lavfi','-i',f'testsrc2=size={size}:rate=60','-t',str(duration)]+encoder+['-f','hevc' if hevc else 'h264',str(src)],check=True)
 d=json.loads(subprocess.check_output([fp,'-v','error','-show_packets','-show_data','-of','json',str(src)]))
 def raw(s):return bytes.fromhex(''.join(l.split(':',1)[1].split('  ')[0].replace(' ','') for l in s.strip().splitlines()))
 frames=[dict(type=193,timestamp=round(i*1e6/60),data=base64.b64encode(raw(p['data'])).decode()) for i,p in enumerate(d['packets'])]
 pcm=b''.join(struct.pack('<hh',*[int(8000*math.sin(j*2*math.pi*440/48000))]*2) for j in range(48000*duration))
 for start in range(0,48000*duration,1024):frames.append(dict(type=195,timestamp=round(start*1e6/48000),data=base64.b64encode(pcm[start*4:(start+1024)*4]).decode()))
 frames.sort(key=lambda f:f['timestamp']+(10000 if f['type']==195 else 0));(root/'frames.json').write_text(json.dumps(frames))
 process=subprocess.Popen([str(binary),str(root),mode],stdout=subprocess.PIPE,stderr=open(str(report)+'.stderr','w'),text=True)
 with report.open('w') as log:
  for line in process.stdout:
   if not line.startswith('{'):print(line.strip(),flush=True);continue
   result=json.loads(line);p=result['profile'];result['verification']='FAIL'
   try:
    if mode=='hdr' and p['codec']!=0:
     assert 'HDR transcoding' in result['error'],result['error'];assert not result['file']
     assert not list(root.glob(result['id']+'.*')),'Rejected HDR created an output file'
     result['verification']='PASS';result['expectedRejection']=True
     log.write(json.dumps(result)+'\n');log.flush();print(result['id'],'PASS expected HDR rejection',flush=True);continue
    assert not result['error'],result['error'];f=pathlib.Path(result['file']);assert f.exists()
    streams=json.loads(subprocess.check_output([fp,'-v','error','-count_frames','-show_streams','-of','json',str(f)],timeout=30))['streams']
    v=next(s for s in streams if s['codec_type']=='video');a=next(s for s in streams if s['codec_type']=='audio')
    assert v['codec_name']==['hevc' if hevc else 'h264','h264','hevc','prores','av1'][p['codec']],v['codec_name']
    assert a['codec_name']==['pcm_s16le','aac','alac','opus','flac'][p['audio']],a['codec_name']
    def rate(x):return {'source':60,'23.976':24000/1001,'29.97':30000/1001,'59.94':60000/1001}.get(x,float(x) if x!='source' else 60)
    fps=min(60,rate(p['sourceFPS']),rate(p['outputFPS']))
    # Literal counts for the one-second fixture (PTS 0 through 983333 us).
    # At 59.94, slot 59 starts at 984317 us, after the final source frame.
    expected={15:15,23.976:24,24:24,25:25,29.97:30,30:30,50:50,59.94:59,60:60}[round(fps,3)]
    assert int(v['nb_read_frames'])==expected,('video frames',v['nb_read_frames'],expected)
    assert a['sample_rate']=='48000' and a['channels']==2
    source_width,source_height=map(int,size.split('x'));height=min(source_height,[source_height,1080,720][p['scale']]);width=(source_width*height//source_height)//2*2
    assert (v['width'],v['height'])==(width,height),(v['width'],v['height'],width,height)
    if hevc and p['codec']==0:assert v['pix_fmt']=='yuv420p10le',v['pix_fmt']
    if mode=='hdr':assert v.get('color_transfer')=='smpte2084' and v.get('color_primaries')=='bt2020',v
    expected_profiles={1:{'baseline':['Constrained Baseline','Baseline'],'main':['Main'],'high':['High']},2:{'main':['Main'],'main10':['Main 10']},3:{'proxy':['Proxy'],'lt':['LT'],'standard':['Standard'],'hq':['HQ']},4:{'main':['Main']}}
    if p['videoProfile']!='auto':assert v.get('profile') in expected_profiles[p['codec']][p['videoProfile']],('profile',v.get('profile'),p['videoProfile'])
    decoded=subprocess.run([ff,'-v','error','-xerror','-i',str(f),'-f','null','-'],capture_output=True,timeout=60)
    assert decoded.returncode==0 and not decoded.stderr,decoded.stderr.decode()
    if p['audio'] in [0,2,4]:
     decoded_pcm=subprocess.check_output([ff,'-v','error','-i',str(f),'-map','0:a','-f','s16le','-'],timeout=30)
     assert decoded_pcm==pcm,('lossless audio differs',len(decoded_pcm),len(pcm))
    result['verification']='PASS';result['videoFrames']=int(v['nb_read_frames']);result['inputSize']=size
   except Exception as e:result['failure']=str(e);failures+=1
   finally:
    for f in root.glob(result['id']+'.*'):
     if f.suffix in ['.mov','.mp4','.mkv','.ts']:f.unlink(missing_ok=True)
   log.write(json.dumps(result)+'\n');log.flush();print(result['id'],result['verification'],result.get('failure','')[:180],flush=True)
 status=process.wait();assert status==0,('matrix process',status)
print(f'All temporary media deleted. Failed cases: {failures}',flush=True)
sys.exit(1 if failures else 0)
