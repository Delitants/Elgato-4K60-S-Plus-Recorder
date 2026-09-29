import Foundation
struct RateFixture:Decodable {let type:UInt8;let timestamp:UInt64;let data:Data}
@main struct RecordingRateRecovery {
 static func main()throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let frames=try JSONDecoder().decode([RateFixture].self,from:Data(contentsOf:root.appendingPathComponent("frames.json")))
  for mode in ["native","copy","film"] {
   var p=RecordingProfile();p.container=mode=="native" ? 0:2;p.audio=0;p.decoder=2
   if mode=="film"{p.codec=1;p.encoder=2;p.preset="ultrafast";p.sourceFPS = .fps23976}
   let sink=RecordingSink(url:root.appendingPathComponent(mode+"."+p.fileExtension),profile:p,initialRate:VideoRate(numerator:60000,denominator:1001))
   for f in frames {
    guard sink.offer(DeviceFrame(type:f.type,timestamp:f.timestamp,data:f.data)) else{break}
    Thread.sleep(forTimeInterval:Double(ProcessInfo.processInfo.environment["FIXTURE_PACE"] ?? "0.001") ?? 0.001)
   }
   let done=DispatchSemaphore(value:0);var failure:String?,saved:URL?
   sink.finish{url,error in saved=url;failure=error;done.signal()}
   guard done.wait(timeout:.now()+30) == .success else{print("FAIL finish timeout");exit(1)}
   guard failure==nil,let saved else{print("FAIL \(mode): \(failure ?? "no saved file")");exit(1)}
   guard sink.warning != nil else{print("FAIL rate recovery must report a warning");exit(1)}
   print("PASS \(mode) \(saved.lastPathComponent) accepted=\(sink.videoFrames) warning=\(sink.warning!)")
  }
 }
}
