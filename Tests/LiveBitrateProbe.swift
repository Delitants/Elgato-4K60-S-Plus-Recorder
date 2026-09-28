// Developer-only test: quit the GUI first. Saves at most 64 MiB of elementary
// video to the supplied temporary path; remove that file after probing it.
import Foundation
import AVFoundation
@main struct LiveBitrateProbe {
 static func main() throws {
  guard CommandLine.arguments.count==4,let target=Int32(CommandLine.arguments[2]) else{fatalError("Usage: probe h264|hevc targetMbps temporaryVideoPath")}
  let hevc=CommandLine.arguments[1]=="hevc"
  var error=[CChar](repeating:0,count:512)
  var opened=capture_open_config(hevc ? 1:0,1920,1080,target,&error,512)
  if opened==nil {Thread.sleep(forTimeInterval:1);opened=capture_open_config(hevc ? 1:0,1920,1080,target,&error,512)}
  guard let usb=opened else{print("Connection failed:",String(cString:error));exit(1)}
  defer{capture_close(usb)}
  let parser=PacketParser(),converter=MediaConverter(hevc:hevc),decoder=PreviewDecoder()
  decoder.tenBit=hevc;decoder.preference=1
  defer{decoder.close()}
  var bitrate=IncomingVideoBitrate(),buffer=[UInt8](repeating:0,count:16384),saved=Data()
  let started=ProcessInfo.processInfo.systemUptime
  var firstVideo:Double?,lastReport=started,decodedFormat:OSType?,frames=0
  var samples=[Double]()
  while ProcessInfo.processInfo.systemUptime-started<10 {
   let n=capture_read(usb,&buffer,Int32(buffer.count))
   guard n>=0 else{throw RecorderError(message:"USB read failed: \(n)")}
   if n>0 {for frame in parser.feed(Data(buffer.prefix(Int(n)))) {
    let now=ProcessInfo.processInfo.systemUptime
    bitrate.observe(type:frame.type,bytes:frame.data.count,now:now)
    guard frame.type==0xc1 else{continue}
    frames+=1;if firstVideo==nil{firstVideo=now}
    if now-firstVideo!<2,saved.count+frame.data.count<=64*1024*1024{saved.append(frame.data)}
    if let(sample,key)=try converter.convert(frame),decodedFormat==nil {
     decoder.decode(sample,key:key,synchronous:true)
     if let decoded=decoder.takeFrame(),let image=CMSampleBufferGetImageBuffer(decoded){decodedFormat=CVPixelBufferGetPixelFormatType(image)}
    }
   }}
   let now=ProcessInfo.processInfo.systemUptime
   if now-lastReport>=1 {
    if let rate=bitrate.mbps(now:now){print(String(format:"%.1f s: %.3f Mbps",now-started,rate));if now-started>5{samples.append(rate)}}
    lastReport=now
   }
  }
  try saved.write(to:URL(fileURLWithPath:CommandLine.arguments[3]))
  let depth=converter.videoFormat.flatMap{CMFormatDescriptionGetExtension($0,extensionKey:kCMFormatDescriptionExtension_BitsPerComponent) as? NSNumber}
  let pixelFormat=decodedFormat.map{String(format:"%08x",$0)} ?? "none"
  print("RESULT codec=\(hevc ? "HEVC":"H264") requestedMbps=\(target) meanReceivedMbps=\(samples.reduce(0,+)/Double(max(1,samples.count))) sourceFPS=\(converter.frameTiming.rate?.label ?? "unknown") bitDepth=\(depth?.stringValue ?? "unreported") decodedPixelFormat=\(pixelFormat) frames=\(frames) parserDiscards=\(parser.discarded) sampleBytes=\(saved.count)")
  guard frames>0,decodedFormat != nil,parser.discarded==0 else{exit(1)}
  if hevc{guard decodedFormat==kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange else{exit(2)}}
 }
}
