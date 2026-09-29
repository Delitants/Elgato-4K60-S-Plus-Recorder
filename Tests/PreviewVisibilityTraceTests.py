"""Check metadata captured by the diagnostic native UI during minimize/restore."""
import json,sys
r=json.load(open(sys.argv[1]))
visibility=[(x[1],x[2]==0 and x[3]==1) for x in r if x[0]==10]
assert any(not v for _,v in visibility),'Need an actual hidden-window interval'
restores=[t for (p,pv),(t,v) in zip(visibility,visibility[1:]) if v and not pv and t>5]
assert restores,'Need a restore transition'
v=True;last_change=0;hidden_enqueues=[]
reset_frames=set();last_scheduled=None
for x in r:
 if x[0]==8: last_scheduled=tuple(x)
 if x[0]==9 and x[3]==1 and last_scheduled: reset_frames.add(last_scheduled)
for x in r:
 if x[0]==10:
  new=x[2]==0 and x[3]==1
  if v!=new: last_change=x[1]
  v=new
 if x[0]==8 and not v and x[1]-last_change>0.1: hidden_enqueues.append(x)
assert not hidden_enqueues,f'{len(hidden_enqueues)} frames enqueued while window hidden'
for restored in restores:
 source=[x for x in r if x[0]==1 and restored<=x[1]<restored+3]
 assert len(source)>30,'Need live source video after restore'
 wall=source[-1][1]-source[0][1];media=source[-1][2]-source[0][2]
 assert 0.9<media/wall<1.1,f'USB capture replayed a backlog at {media/wall:.2f}x speed'
 scheduled=[x for x in r if x[0]==8 and restored<=x[1]<restored+3]
 assert len(scheduled)>20,'Preview failed to resume promptly'
 # Presentation must not replay the batch accumulated while UI was unavailable.
 latest=[x for x in r if x[0]==3 and x[1]<=scheduled[0][1]]
 assert latest and latest[-1][2]-scheduled[0][2]<0.05,'First restored frame is stale'
 deltas=[b[3]-a[3] for a,b in zip(scheduled,scheduled[1:])]
 assert all(d>0 for d in deltas),'Restored presentation clock went backwards'
 for a,b in zip(scheduled,scheduled[1:]):
  if tuple(b) in reset_frames: continue
  assert abs((b[3]-a[3])-(b[2]-a[2]))<0.00001,'Preview replayed at a different speed from source PTS'
  assert b[3]-a[3]>=0.015,'Preview compressed multiple frames into a catch-up burst' 
print(f'PASS hidden renderer suspension and fresh, forward-paced restore ({len(restores)} transitions)')
