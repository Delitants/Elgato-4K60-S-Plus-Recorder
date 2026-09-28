import Foundation
@main struct PreviewTimingTests {
 static func main(){
  for fps in [25.0,30000.0/1001,60000.0/1001] {
   var clock=PreviewPresentationClock(),previous:Double?
   for n in 0..<600 {
    let pts=Double(n)/fps
    // Decode arrival alternates by 20 ms, while prescribed display stays uniform.
    let arrival=10+pts+(n%2==0 ? 0:0.02)
    let p=clock.schedule(pts:pts,now:arrival)!
    if let previous{assert(abs(p.time-previous-1/fps)<1e-9);assert(!p.reset)}
    assert(p.time>=arrival);previous=p.time
   }
  }
  var clock=PreviewPresentationClock()
  let first=clock.schedule(pts:100,now:10)!
  assert(first.reset && abs(first.time-10.06)<1e-9)
  assert(clock.schedule(pts:100,now:10.01)==nil)
  assert(clock.schedule(pts:.nan,now:10)==nil)
  let recovery=clock.schedule(pts:100.04,now:20)!
  assert(recovery.reset && abs(recovery.time-20.06)<1e-9)
  let backward=clock.schedule(pts:0,now:21)!
  assert(backward.reset && abs(backward.time-21.06)<1e-9)
  let jump=clock.schedule(pts:20,now:21.01)!
  assert(jump.reset && jump.time<21.08)
  clock.reset();assert(clock.schedule(pts:0,now:30)!.reset)
  var frames=PreviewFrameQueue<Int>()
  frames.append(1,pts:0);frames.append(2,pts:0.04)
  assert(frames.first==1);frames.removeFirst();assert(frames.first==2);
  assert(frames.drain()==[2]);assert(frames.drain().isEmpty)
  for n in 0..<100{frames.append(n,pts:Double(n)/60)}
  let bounded=frames.drain();assert(bounded.count<=8 && bounded.first!>=92 && bounded.last==99)
  frames.append(1,pts:20);frames.append(2,pts:0);assert(frames.drain()==[2])
  frames.append(1,pts:.nan);assert(frames.drain().isEmpty)
  frames.append(1,pts:0);frames.reset();assert(frames.drain().isEmpty)
  print("PASS preview timing: jitter absorption, fractional cadence, bounded buffering, pause/discontinuity recovery and reset")
 }
}
