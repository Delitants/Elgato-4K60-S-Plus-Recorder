import Foundation
@main struct FanoutTests {
 static func main() throws {
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
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent("ElgatoFileBytes-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  defer{try? FileManager.default.removeItem(at:folder)}
  func write(_ name:String,_ count:Int)throws{try Data(repeating:7,count:count).write(to:folder.appendingPathComponent(name))}
  try write("session_part004.mov",999)
  let parts=RecordingFileBytes(url:folder.appendingPathComponent("session.mov"),split:true)
  assert(parts.measure()==0,"Existing recordings must not count toward this session")
  try write("session_part001.mov",13);try write("session_part002.mov",29)
  try write("session-other_part001.mov",1000);try write("session_part003.mov.bak",1000)
  try write("session_part1.mov",1000);try write("session.mov",1000)
  assert(parts.measure()==42,"Only this session's exact split names count")
  try write("session_part002.mov",50)
  assert(parts.measure()==63,"File growth must replace the prior size, not add it again")
  try write("session_part002.mov",57);try write("session_part003.mov",11)
  assert(parts.measure()==81,"Closed split totals include trailers and exclude a pre-existing next part")
  assert(parts.measure()==81,"Closed parts must not be counted more than once")
  try write("session_part003.mov",19)
  assert(parts.measure()==89,"Final flush growth must count alongside all closed parts")
  let singleURL=folder.appendingPathComponent("single.mkv")
  let single=RecordingFileBytes(url:singleURL,split:false)
  assert(single.measure()==0)
  try write("single.mkv",17);try write("single_part001.mkv",200)
  assert(single.measure()==17,"An unsplit recording counts only its actual output")
  try write("single.mkv",31)
  assert(single.measure()==31,"Final container flush bytes must be visible")
  print("PASS bounded bytes, monotonic queue age, interleaving and release")
  print("PASS logical file bytes, session isolation, splits, growth and final flush")
 }
}
