import Foundation
@main struct BitrateTests {
 static func main() {
  var meter=IncomingVideoBitrate()
  func close(_ value:Double?,_ expected:Double){assert(value != nil && abs(value!-expected)<0.000001,"Expected \(expected), got \(String(describing:value))")}
  meter.observe(type:0xc3,bytes:192_000,now:0)
  assert(meter.mbps(now:10)==nil,"Audio cannot start the video meter")
  for tick in 0..<10 {meter.observe(type:0xc1,bytes:125_000,now:20+Double(tick)/10+0.01)}
  assert(meter.mbps(now:20.9)==nil,"Warm up for one second")
  close(meter.mbps(now:21),10)
  // A large keyframe in the unfinished bucket must not create a tiny-denominator spike.
  meter.observe(type:0xc1,bytes:1_000_000,now:21.01)
  meter.observe(type:0xc3,bytes:9_000_000,now:21.02)
  close(meter.mbps(now:21.09),10)
  close(meter.mbps(now:23),6)
  close(meter.mbps(now:24.1),0)
  meter=IncomingVideoBitrate()
  assert(meter.mbps(now:100)==nil,"Reconnect must clear the previous reading")
  for tick in 0..<10_000 {meter.observe(type:0xc1,bytes:250_000,now:100+Double(tick)/10+0.01)}
  close(meter.mbps(now:1100),20)
  close(meter.mbps(now:1103),0)
  print("PASS video-only Mbps, warmup, keyframe smoothing, idle decay, reset and bounded long-run buckets")
 }
}
