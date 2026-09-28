// Developer-only, no recordings: quit the GUI before using the device.
import Foundation
import AVFoundation
@main struct LivePreviewTimingProbe {
 static func main() throws {
  guard CommandLine.arguments.count>=2,let target=Int(CommandLine.arguments[1]) else{fatalError("Usage: probe targetMbps [preview-off]")}
  var p=RecordingProfile();p.deviceMbps=target;p.codec=1;p.encoder=1;p.decoder=1;p.outputFPS = .fps2997
  let engine=CaptureEngine(),showVideo=CommandLine.arguments.count==2
  engine.setProfile(p);engine.setPreview(video:showVideo,audio:false,volume:0);engine.connect()
  let begin=ProcessInfo.processInfo.systemUptime
  var lastReport=begin,lastFrames=0,previews=0,lastPreviews=0,baseline:Double?,drift=0.0
  while ProcessInfo.processInfo.systemUptime-begin<22 {
   let now=ProcessInfo.processInfo.systemUptime
   let(s,sample)=engine.snapshot()
   for sample in sample {
    previews+=1
    let offset=now-CMSampleBufferGetPresentationTimeStamp(sample).seconds
    if baseline==nil{baseline=offset}
    drift=offset-baseline!
   }
   if now-lastReport>=5 {
    let elapsed=now-lastReport
    print(String(format:"target=%d preview=%@ received=%.1fMbps frames/s=%.2f preview/s=%.2f latencyGrowth=%.3fs discards=%d",target,showVideo ? "on":"off",s.incomingVideoMbps ?? 0,Double(s.videoFrames-lastFrames)/elapsed,Double(previews-lastPreviews)/elapsed,drift,s.discarded))
    fflush(stdout);lastReport=now;lastFrames=s.videoFrames;lastPreviews=previews
   }
   if !s.connected && !s.connecting && now-begin>5{print(s.status,s.detail);break}
   RunLoop.current.run(until:Date().addingTimeInterval(0.002))
  }
  let finished=DispatchSemaphore(value:0);engine.disconnect{finished.signal()}
  guard finished.wait(timeout:.now()+10) == .success else{exit(1)}
 }
}
