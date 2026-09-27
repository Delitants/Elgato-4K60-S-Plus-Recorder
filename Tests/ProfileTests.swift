import Foundation
import AVFoundation
@main struct ProfileTests {
 static func main() throws {
  func invalid(_ p:RecordingProfile){do{try p.validate();fatalError("Invalid profile accepted")}catch{}}
  var p=RecordingProfile();try p.validate()
  p.container=1;invalid(p)
  p.audio=1;try p.validate()
  p.codec=3;invalid(p)
  p.container=0;try p.validate()
  p.encoder=2;invalid(p);p.encoder=0
  p.codec=0;p.scale=1;invalid(p)
  p.scale=0;p.captureHEVC=true;p.deviceMbps=141;invalid(p)
  p.deviceMbps=60;try p.validate()
  p.codec=1;p.scale=2
  var f:CMVideoFormatDescription?
  CMVideoFormatDescriptionCreate(allocator:kCFAllocatorDefault,codecType:kCMVideoCodecType_H264,width:3840,height:2160,extensions:nil,formatDescriptionOut:&f)
  let settings=try p.videoSettings(format:f!)!
  assert(settings[AVVideoWidthKey] as? Int==1280 && settings[AVVideoHeightKey] as? Int==720)
  let extensions=[kCMFormatDescriptionExtension_TransferFunction:kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ] as CFDictionary
  CMVideoFormatDescriptionCreate(allocator:kCFAllocatorDefault,codecType:kCMVideoCodecType_HEVC,width:3840,height:2160,extensions:extensions,formatDescriptionOut:&f)
  do{_ = try p.videoSettings(format:f!);fatalError("HDR transcode accepted")}catch{}
  p.codec=0;let passthrough=try p.videoSettings(format:f!);assert(passthrough==nil)
  print("PASS: container/audio compatibility, bitrate limits, downscale dimensions, HDR preservation guard")
 }
}
