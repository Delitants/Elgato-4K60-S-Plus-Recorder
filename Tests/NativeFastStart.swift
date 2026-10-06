import Foundation
@main struct NativeFastStart {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let nal=try Data(contentsOf:root.appendingPathComponent("frame.h264"))
  for container in [0,1] {
   var profile=RecordingProfile();profile.container=container;profile.audio=1
   let recorder=MovieRecorder(url:root.appendingPathComponent("native."+profile.fileExtension),profile:profile)
   let converter=MediaConverter()
   for i in 0..<90 {
    let pts=UInt64(i)*1_000_000/30
    for frame in [DeviceFrame(type:0xc1,timestamp:pts,data:nal),DeviceFrame(type:0xc3,timestamp:pts,data:Data(repeating:0,count:1600*4))] {
     if let(sample,key)=try converter.convert(frame){try recorder.append(sample,type:frame.type,key:key,converter:converter)}
    }
    Thread.sleep(forTimeInterval:0.005)
   }
   let done=DispatchSemaphore(value:0)
   recorder.finish{url,error in guard url != nil,error==nil else{fatalError(error ?? "no file")};done.signal()}
   guard done.wait(timeout:.now()+30) == .success else{fatalError("native finalize timeout")}
   print("PASS native writer",profile.fileExtension)
  }
 }
}
