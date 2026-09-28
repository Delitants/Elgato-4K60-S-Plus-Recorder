import Foundation
@main struct MonitoringTests {
 static func main() {
  var d=RecordingDeadline()
  assert(!d.expired(now:100))
  d.start(seconds:10,now:100)
  assert(d.remaining(now:103)==7)
  assert(!d.expired(now:109.999))
  assert(d.expired(now:110))
  assert(d.remaining(now:130)==0)
  d.clear();assert(!d.expired(now:10000))
  d.start(seconds:0,now:100);assert(d.remaining(now:200)==nil)
  // Changing the selected duration must keep the first accepted keyframe's origin.
  d.start(seconds:30,now:110);assert(d.remaining(now:110)==20,"Enabling a timer must count existing recording time")
  d.start(seconds:60,now:115);assert(d.remaining(now:115)==45,"Extending a timer must not restart it")
  d.start(seconds:0,now:120);assert(d.remaining(now:120)==nil)
  d.start(seconds:10,now:125);assert(d.expired(now:125),"A shortened or re-enabled limit can already be expired")
  d.clear();d.start(seconds:5,now:300);assert(d.remaining(now:301)==4)
  var meter=StereoPeakMeter()
  // Two interleaved signed little-endian stereo frames, including Int16.min.
  meter.append(Data([0x00,0x40,0x00,0x20,0x00,0x80,0x00,0x00]))
  let first=meter.take(now:100)!
  assert(first.left==1 && first.right==0.25,"Each channel must retain its own peak")
  assert(meter.take(now:100.01)==nil,"Publish at a bounded 20 ms cadence")
  meter.append(Data([0x00,0x20,0x00,0x60]))
  let next=meter.take(now:100.021)!
  assert(next.left==0.25 && next.right==0.75,"A prior window must not hold a channel's peak")
  let silence=meter.take(now:100.042)!
  assert(silence.left==0 && silence.right==0,"Silence must clear both channels")
  print("PASS: duration limit, exact deadline, no-input elapsed time, clear, unlimited, live limit changes anchored to recording start")
  print("PASS: independent stereo peaks, signed full scale, 20 ms publish cadence and reset")
 }
}
