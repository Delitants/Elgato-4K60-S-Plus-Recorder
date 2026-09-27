import Foundation
@main struct FrameSelectionTests {
 static func main() throws {
  for (n,d,target,want) in [(60,1,FrameRateChoice.fps30,60),(60,1,.fps24,48),(60000,1001,.fps2997,60),(30,1,.fps60,60),(30,1,.source,60)] {
   let incoming=VideoRate(numerator:Int32(n),denominator:Int32(d));var p=RecordingProfile();p.outputFPS=target
   let rate=p.effectiveRate(incoming:incoming);var selector=FrameSelector(),times=[Int64]()
   for i in 0..<(n==60000 ? 120:n*2) {let pts=Int64((Double(i)*1e6*Double(d)/Double(n)).rounded());if let t=selector.select(timestamp:pts,rate:rate){times.append(t)}}
   assert(times.count==want,"Wrong frame count \(n)/\(d) -> \(target): \(times.count)")
   assert(times.first==0 && zip(times,times.dropFirst()).allSatisfy{$0<$1})
  }
  var gate=FrameSelector();let thirty=VideoRate(numerator:30,denominator:1)
  assert(gate.select(timestamp:0,rate:thirty)==0)
  assert(gate.select(timestamp:1_000_000,rate:thirty)==1_000_000,"A stall must remain a gap, not be sped up or filled")
  var p=RecordingProfile();p.sourceFPS = .fps30;p.outputFPS = .fps60
  assert(p.effectiveRate(incoming:VideoRate(numerator:60,denominator:1))==thirty)
  let old=try JSONDecoder().decode(RecordingProfile.self,from:Data("{}".utf8));assert(old.sourceFPS == .source && old.outputFPS == .source)
  let copy=try JSONDecoder().decode(RecordingProfile.self,from:JSONEncoder().encode(p));assert(copy.sourceFPS == .fps30 && copy.outputFPS == .fps60 && copy.usesHelper)
  let tracker=FrameRateTracker();for i in 0..<100{tracker.observe(UInt64((Double(i)*1e6/30).rounded()))};assert(tracker.rate==thirty)
  tracker.observe(3_500_000);assert(tracker.rate==thirty,"Single gap must not halve incoming rate")
  let changed=FrameRateTracker();for i in 0..<100{changed.observe(UInt64(i)*16667)};for i in 0..<100{changed.observe(UInt64(1_666_700+i*33333))};assert(changed.rate==thirty)
  let jittered=FrameRateTracker();var pts:UInt64=0
  let pattern:[UInt64]=[14000,18000,16000,18000,17333]
  jittered.observe(pts);for i in 0..<180{pts+=pattern[i%pattern.count];jittered.observe(pts)}
  assert(jittered.rate==VideoRate(numerator:60,denominator:1),"Device timestamp jitter must not inflate 60 fps to 62.5")
  pts+=500_000;jittered.observe(pts)
  for i in 0..<100 {pts+=pattern[i%pattern.count];jittered.observe(pts);assert(jittered.rate==VideoRate(numerator:60,denominator:1),"A single gap must not produce a false cadence change during jitter recovery")}
  print("PASS FPS selection, fractional cadence, no upsampling, gap recovery, source override and migration")
 }
}
