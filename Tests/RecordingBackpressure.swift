import Foundation
struct BackpressureFixture:Decodable {let type:UInt8;let timestamp:UInt64;let data:Data}
@main struct RecordingBackpressure {
 static func main()throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let frames=try JSONDecoder().decode([BackpressureFixture].self,from:Data(contentsOf:root.appendingPathComponent("frames.json")))
  var p=RecordingProfile();p.container=2;p.audio=1;p.decoder=2;p.codec=1;p.encoder=2;p.preset="ultrafast"
  if ProcessInfo.processInfo.environment["TEST_HEVC"]=="1" {p.captureHEVC=true}
  let mode=ProcessInfo.processInfo.environment["TEST_MODE"] ?? "software"
  if mode=="copy" {p.codec=0;p.preset="auto"}
  if mode=="film" {p.sourceFPS = .fps23976}
  if mode=="hardware" {p.encoder=1;p.preset="auto";p.rateControl = .cq;p.hardwareQuality=63;p.sourceFPS = .fps23976;p.decoder=1}
  let padding=Int(ProcessInfo.processInfo.environment["TEST_PADDING"] ?? "0") ?? 0
  let filler=Data([0,0,0,1,12])+Data(repeating:255,count:padding)+Data([128])
  let stopAt=Double(ProcessInfo.processInfo.environment["TEST_STOP_AT"] ?? "99") ?? 99
  let terminal=ProcessInfo.processInfo.environment["TEST_TERMINAL"]=="1"
  let sink=RecordingSink(url:root.appendingPathComponent("result.mkv"),profile:p,initialRate:VideoRate(numerator:60,denominator:1))
  let start=ProcessInfo.processInfo.systemUptime
  for f in frames {
   let wait=Double(f.timestamp)/1e6-(ProcessInfo.processInfo.systemUptime-start)
   if wait>0{Thread.sleep(forTimeInterval:wait)}
   if Double(f.timestamp)/1e6>=stopAt {break}
   let data=f.type==193 && padding>0 && f.timestamp>=10_500_000 && f.timestamp<13_000_000 ? f.data+filler:f.data
   guard sink.offer(DeviceFrame(type:f.type,timestamp:f.timestamp,data:data)) else{break}
  }
  let done=DispatchSemaphore(value:0);var failure:String?,saved:URL?
  sink.finish{url,error in saved=url;failure=error;done.signal()}
  guard done.wait(timeout:.now()+40) == .success else{print("FAIL finish timeout");exit(1)}
  if terminal {
   guard failure != nil else{print("FAIL permanent stall did not report failure");exit(1)}
   print("PASS terminal stall finalized=\(saved != nil) error=\(failure!)");return
  }
  guard failure==nil,let saved else{print("FAIL \(failure ?? "no file")");exit(1)}
  guard sink.dropped>0,sink.warning?.contains("backlog")==true else{print("FAIL missing recovery warning or skips");exit(1)}
  print("PASS \(saved.lastPathComponent) duration=\(sink.duration) warning=\(sink.warning!)")
 }
}
