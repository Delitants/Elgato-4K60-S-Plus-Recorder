import Foundation
import CoreMedia
@main struct FrameTimingTests {
 static func main() throws {
  let nal=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
  let converter=MediaConverter()
  var sample:CMSampleBuffer?
  for i in 0..<90 { sample=try converter.convert(DeviceFrame(type:0xc1,timestamp:UInt64((Double(i)*1_000_000/30).rounded()),data:nal))?.0 }
  guard let sample else{fatalError("No converted video")}
  let duration=CMSampleBufferGetDuration(sample).seconds
  guard abs(duration-1.0/30)<0.00001 else{fatalError("30 fps input must have 1/30 s sample duration, got \(duration)")}
  var p=RecordingProfile();p.container=2
  let sink=RecordingSink(url:URL(fileURLWithPath:CommandLine.arguments[1]+".mkv"),profile:p)
  assert(sink.offer(DeviceFrame(type:0xc1,timestamp:0,data:nal)))
  let done=DispatchSemaphore(value:0)
  sink.finish{url,_ in assert(url==nil);done.signal()}
  assert(done.wait(timeout:.now()+5) == .success)
  assert(sink.videoFrames==0 && sink.duration==0,"An unaccepted startup keyframe must not be counted as recorded")
  print("PASS 30 fps sample timing and honest recording startup")
 }
}
