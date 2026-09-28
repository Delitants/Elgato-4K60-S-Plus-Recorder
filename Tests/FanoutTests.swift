import Foundation
@main struct FanoutTests {
 static func main(){
  var now:UInt64=0
  let b=QueueBudget(maxBytes:10,maxAge:500_000,clock:{now})
  assert(b.reserve(bytes:6));assert(!b.reserve(bytes:5))
  b.release(bytes:6);assert(b.reserve(bytes:2));now=500_001;assert(!b.reserve(bytes:1))
  b.release(bytes:2);assert(b.reserve(bytes:10));b.release(bytes:10)
  assert(b.bytes==0)
  // Interleaved media PTS, discontinuities and device uptime cannot age this queue.
  let interleaved=QueueBudget(clock:{now})
  for _ in [UInt64(1_000_000),990_000,9_000_000,0] {assert(interleaved.reserve(bytes:100))}
  for _ in 0..<4 {interleaved.release(bytes:100)}
  assert(interleaved.bytes==0)
  now=0;let startup=QueueBudget(clock:{now})
  assert(startup.reserve(bytes:1024));now=750_000
  assert(startup.reserve(bytes:1024),"Cold encoder startup must not fail after half a second")
  now=2_000_001;assert(!startup.reserve(bytes:1),"A stalled recorder must remain bounded")
  print("PASS bounded bytes, monotonic queue age, interleaving and release")
 }
}
