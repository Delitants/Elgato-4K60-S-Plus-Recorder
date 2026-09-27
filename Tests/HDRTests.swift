import Foundation
import AVFoundation
@main struct HDRCheck {
 static func main() throws {
  let nals=MediaConverter.nals(try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
  var units=[Data](),unit=Data()
  for nal in nals {if ((nal[0]>>1)&63)==35 && !unit.isEmpty {units.append(unit);unit=Data()};unit.append(contentsOf:[0,0,0,1]);unit.append(nal)}
  if !unit.isEmpty{units.append(unit)}
  let converter=MediaConverter(hevc:true),recorder=MovieRecorder(url:URL(fileURLWithPath:CommandLine.arguments[2]))
  for (i,data) in units.enumerated() {
   if let (sample,key)=try converter.convert(DeviceFrame(type:0xc1,timestamp:UInt64(i)*33333,data:data)) {try recorder.append(sample,type:0xc1,key:key,converter:converter)}
   if let (sample,key)=try converter.convert(DeviceFrame(type:0xc3,timestamp:UInt64(i)*33333,data:Data(repeating:0,count:6400))) {try recorder.append(sample,type:0xc3,key:key,converter:converter)}
   Thread.sleep(forTimeInterval:0.02)
  }
  guard let format=converter.videoFormat else {fatalError("No HEVC format")}
  let transfer=CMFormatDescriptionGetExtension(format,extensionKey:kCMFormatDescriptionExtension_TransferFunction) as? String
  assert(transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String))
  let sem=DispatchSemaphore(value:0)
  recorder.finish{url,error in assert(url != nil,error ?? "HDR file failed");sem.signal()}
  guard sem.wait(timeout:.now()+20) == .success else {fatalError("HDR writer timed out")}
  print("PASS: synthetic PQ HDR detected and HEVC samples saved",recorder.videoFrames)
  if CommandLine.arguments.count>3 {
   let sdr=MediaConverter(hevc:true)
   var firstUnit=Data(),seenAUD=false
   for nal in MediaConverter.nals(try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3]))) {
    if ((nal[0]>>1)&63)==35 {if seenAUD{break};seenAUD=true}
    firstUnit.append(contentsOf:[0,0,0,1]);firstUnit.append(nal)
   }
   let changing=MovieRecorder(url:URL(fileURLWithPath:CommandLine.arguments[2]+".transition.mov"))
   let (first,key)=try sdr.convert(DeviceFrame(type:0xc1,timestamp:0,data:firstUnit))!
   try changing.append(first,type:0xc1,key:key,converter:sdr)
   let (hdr,hdrKey)=try converter.convert(DeviceFrame(type:0xc1,timestamp:33333,data:units[0]))!
   var rejected=false
   do {try changing.append(hdr,type:0xc1,key:hdrKey,converter:converter)}
   catch {rejected=error.localizedDescription.contains("changed")}
   assert(rejected,"SDR to HDR transition was accepted")
   let done=DispatchSemaphore(value:0)
   changing.finish{url,error in assert(url != nil,error ?? "Transition file failed");done.signal()}
   guard done.wait(timeout:.now()+20) == .success else {fatalError("Transition writer timed out")}
   print("PASS: SDR to HDR change rejected during active recording")
  }
 }
}
