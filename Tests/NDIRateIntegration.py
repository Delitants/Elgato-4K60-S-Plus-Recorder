import subprocess as sp,sys,struct,time
sender,runtime,receiver=sys.argv[1:]
p=sp.Popen([sender,runtime,'Elgato FPS test'],stdin=sp.PIPE,stdout=sp.PIPE,stderr=sp.PIPE)
r=None
try:
 assert p.stdout.readline().startswith(b'READY ')
 r=sp.Popen([receiver,runtime],stdout=sp.PIPE,stderr=sp.PIPE)
 for i in range(180):
  pts=round(i*1e6/30);bgra=bytes([30,60,90,255])*160*90;pcm=struct.pack('<hh',1000,-1000)*1600
  for kind,w,h,body,n,d in [(0,160,90,bgra,30,1),(1,0,0,pcm,0,0)]:p.stdin.write(struct.pack('<IIIIqII',kind,len(body),w,h,pts,n,d)+body)
  p.stdin.flush();time.sleep(1/30)
 p.stdin.close();p.wait(timeout=5);assert p.returncode==0,p.stderr.read().decode()
 out,err=r.communicate(timeout=15);assert r.returncode==0,(out.decode(),err.decode());print(out.decode())
finally:
 for child in [r,p]:
  if child is not None and child.poll() is None:child.kill();child.wait()
