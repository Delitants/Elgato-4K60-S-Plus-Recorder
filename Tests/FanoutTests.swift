import Foundation
@main struct FanoutTests {
 static func main(){
  let b=QueueBudget(maxBytes:10,maxAge:500_000)
  assert(b.reserve(bytes:6,timestamp:0));assert(!b.reserve(bytes:5,timestamp:1))
  b.release(bytes:6);assert(b.reserve(bytes:2,timestamp:0));assert(!b.reserve(bytes:1,timestamp:500_001))
  b.release(bytes:2);assert(b.reserve(bytes:10,timestamp:800_000));b.release(bytes:10)
  assert(b.bytes==0);print("PASS bounded bytes, age, and release")
 }
}
