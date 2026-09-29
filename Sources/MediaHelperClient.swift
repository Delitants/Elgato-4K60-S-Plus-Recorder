import Foundation
import CoreMedia
import Darwin
struct BackendWriteError:LocalizedError {
 let diagnostic:String
 var errorDescription:String? {diagnostic.isEmpty ? "Recording backend stopped accepting media. The encoder may be stalled or too slow for these settings." : "Recording backend failed: " + diagnostic}
}
final class MediaHelperClient {
 private let process=Process(),input=Pipe(),output=Pipe(),errors=Pipe(),lock=NSLock()
 private var stdout: ProcessOutput?, stderr: ProcessOutput?
 private var started=false,format:CMFormatDescription?
 let url:URL,profile:RecordingProfile
 init(url:URL,profile:RecordingProfile){self.url=url;self.profile=profile}
 private func message(_ type:UInt32,_ pts:Int64,_ data:Data=Data())throws{
  var packet=Data();for var n in [UInt32(0x454c4700)|type,UInt32(data.count)]{n=n.littleEndian;withUnsafeBytes(of:&n){packet.append(contentsOf:$0)}}
  var time=pts.littleEndian;withUnsafeBytes(of:&time){packet.append(contentsOf:$0)};packet.append(data)
  let fd=input.fileHandleForWriting.fileDescriptor;let deadline=ProcessInfo.processInfo.systemUptime+2.0
  try packet.withUnsafeBytes{raw in var offset=0
   while offset<raw.count {
    let n=Darwin.write(fd,raw.baseAddress!.advanced(by:offset),raw.count-offset)
    if n>0 {offset+=n;continue}
    if errno==EINTR{continue}
    if errno==EAGAIN && ProcessInfo.processInfo.systemUptime<deadline{var p=pollfd(fd:fd,events:Int16(POLLOUT),revents:0);_ = poll(&p,1,10);continue}
    throw BackendWriteError(diagnostic:diagnostic)
   }
  }
 }
 var diagnostic:String{stderr?.text ?? ""}
 var lastSavedURL:URL?{guard let path=stdout?.text.split(separator:"\n").last(where:{$0.hasPrefix("SAVED ")}).map({String($0.dropFirst(6))}),FileManager.default.fileExists(atPath:path) else{return nil};return URL(fileURLWithPath:path)}
 func append(_ sample:CMSampleBuffer,type:UInt8,key:Bool)throws -> Bool {
  guard let f=CMSampleBufferGetFormatDescription(sample) else{return false}
  if !started {
   guard type==0xc1,key,let incoming=VideoRate.measured(period:CMSampleBufferGetDuration(sample).seconds) else{return false}
   let outputRate=profile.effectiveRate(incoming:incoming)
   if profile.codec==0 && outputRate.fps<incoming.fps-0.01 {throw RecorderError(message:"FPS downsampling requires H.264, HEVC, ProRes, or AV1. Original video preserves every compressed frame.")}
   let ext=(CMFormatDescriptionGetExtensions(f) as NSDictionary?) ?? NSDictionary()
   guard let atoms=ext[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [String:Any],let extra=atoms[profile.captureHEVC ? "hvcC":"avcC"] as? Data else{throw RecorderError(message:"Missing video codec configuration")}
   let executable=Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MediaHelper")
   guard FileManager.default.isExecutableFile(atPath:executable.path) else{throw RecorderError(message:"Media helper is missing from the app")}
   let software=profile.encoder==2
   let video=profile.codec==0 ? "copy":profile.codec==4 ? "libsvtav1":profile.codec==3 ? "prores_videotoolbox":profile.codec==1 ? (software ? "libx264":"h264_videotoolbox"):(software ? "libx265":"hevc_videotoolbox")
   let dimensions=CMVideoFormatDescriptionGetDimensions(f)
   let filmRecovery=(profile.sourceFPS == .fps23976 || profile.sourceFPS == .fps24) && outputRate == profile.sourceFPS.rate
   let settings:[String:String]=["cadence":filmRecovery ? "film32":"none","sourceN":String(incoming.numerator),"sourceD":String(incoming.denominator),"fpsN":String(outputRate.numerator),"fpsD":String(outputRate.denominator),"output":url.path,"video":video,"audio":["pcm_s16le","aac","alac","libopus","flac"][profile.audio],"hevc":profile.captureHEVC ? "1":"0","encoder":String(profile.encoder),"decoder":String(profile.decoder),"height":String(profile.scale==1 ? 1080:profile.scale==2 ? 720:Int(dimensions.height)),"filter":profile.scalingFilter.rawValue,"rc":profile.rateControl.rawValue,"bitrate":String(profile.helperVideoBitrate),"quality":String(profile.quality),"hardwareQuality":String(profile.hardwareQuality),"key":String(profile.keyframeSeconds),"bframes":String(profile.bFrames),"profile":profile.videoProfile,"preset":profile.preset,"aq":profile.spatialAQ == .auto ? "-1":profile.spatialAQ == .enabled ? "1":"0","audioRate":String(profile.audioKbps*1000),"compression":String(profile.compressionLevel),"audioMode":profile.audioMode=="cbr" ? "off":profile.audioMode=="constrained" ? "constrained":"on","split":String(profile.splitMode),"splitValue":String(profile.splitMode==1 ? profile.splitSeconds:profile.splitMB)]
   process.executableURL=executable;process.arguments=settings.sorted{$0.key<$1.key}.map{"\($0.key)=\($0.value)"}
   process.standardInput=input;process.standardOutput=output;process.standardError=errors
   stdout=ProcessOutput(pipe:output,capacity:32768);stderr=ProcessOutput(pipe:errors,capacity:8192)
   try process.run();input.fileHandleForReading.closeFile();output.fileHandleForWriting.closeFile();errors.fileHandleForWriting.closeFile()
   let fd=input.fileHandleForWriting.fileDescriptor;_ = fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);_ = fcntl(fd,F_SETNOSIGPIPE,1)
   started=true;format=f;try message(0,0,extra)
  }
  if type==0xc1,let format,!CMFormatDescriptionEqual(format,otherFormatDescription:f){throw RecorderError(message:"HDMI format changed. Start a new recording.")}
  guard let block=CMSampleBufferGetDataBuffer(sample) else{return false}
  var data=Data(count:CMBlockBufferGetDataLength(block));let count=data.count
  try data.withUnsafeMutableBytes{try check(CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:count,destination:$0.baseAddress!),"Read media")}
  try message(type==0xc1 ? 1:2,CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(sample),timescale:1_000_000,method:.default).value,data)
  return true
 }
 func finish()throws -> URL {
  guard started else{throw RecorderError(message:"No video keyframe arrived")}
  var error:Error?;do{try message(3,0)}catch let e{error=e};input.fileHandleForWriting.closeFile()
  let deadline=ProcessInfo.processInfo.systemUptime+30
  while process.isRunning && ProcessInfo.processInfo.systemUptime<deadline{Thread.sleep(forTimeInterval:0.02)}
  if process.isRunning{ProcessLifecycle.stop(process);throw RecorderError(message:"Recording backend timed out while finalizing")}
  // The process can exit before its final output callback. Require both EOFs.
  guard stdout?.waitForEOF()==true,stderr?.waitForEOF()==true else{throw RecorderError(message:"Recording backend output did not finish draining")}
  guard process.terminationStatus==0 else{throw RecorderError(message:diagnostic.isEmpty ? "Recording backend exited with status \(process.terminationStatus).":diagnostic)};if let error{throw error}
  guard let saved=lastSavedURL else{throw RecorderError(message:"Recording backend did not confirm a finalized file")}
  return saved
 }
 deinit {if started{ProcessLifecycle.stop(process)}}
}
