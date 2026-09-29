import Foundation
import AVFoundation
@main struct PreviewCadenceTests {
 static let carrier=VideoRate(numerator:60000,denominator:1001),filmRate=VideoRate(numerator:24000,denominator:1001)
 static func sample(_ picture:Int,_ tick:Int,tenBit:Bool=false,pts:Int64?=nil)->CMSampleBuffer {
  var image:CVPixelBuffer?
  precondition(CVPixelBufferCreate(kCFAllocatorDefault,64,36,tenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,nil,&image)==kCVReturnSuccess)
  CVPixelBufferLockBaseAddress(image!,[])
  for plane in 0..<2 {
   let base=CVPixelBufferGetBaseAddressOfPlane(image!,plane)!,size=CVPixelBufferGetBytesPerRowOfPlane(image!,plane)*CVPixelBufferGetHeightOfPlane(image!,plane)
   if tenBit{for offset in stride(from:0,to:size,by:2){base.storeBytes(of:UInt16(plane==0 ? 16+picture*3:128)<<8,toByteOffset:offset,as:UInt16.self)}}
   else{memset(base,plane==0 ? Int32(16+picture*3):128,size)}
  }
  CVPixelBufferUnlockBaseAddress(image!,[])
  var format:CMVideoFormatDescription?;CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:image!,formatDescriptionOut:&format)
  var timing=CMSampleTimingInfo(duration:carrier.duration,presentationTimeStamp:pts.map{CMTime(value:$0,timescale:1_000_000)} ?? CMTime(value:Int64(tick)*1001,timescale:60000),decodeTimeStamp:.invalid)
  var sample:CMSampleBuffer?;CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:image!,formatDescription:format!,sampleTiming:&timing,sampleBufferOut:&sample)
  return sample!
 }
 static func picture(_ sample:CMSampleBuffer)->Int {
  let image=CMSampleBufferGetImageBuffer(sample)!;CVPixelBufferLockBaseAddress(image,.readOnly);defer{CVPixelBufferUnlockBaseAddress(image,.readOnly)}
  let base=CVPixelBufferGetBaseAddressOfPlane(image,0)!
  let value=CVPixelBufferGetPixelFormatType(image)==kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ? Int(base.load(as:UInt16.self)>>8):Int(base.load(as:UInt8.self))
  return (value-16)/3
 }
 static func main() {
  // The old timestamp-only preview sampler repeats/skips film pictures depending on phase.
  for tenBit in [false,true] {for phase in 0..<5 {
   let selector=PreviewSampleSelector();var seen=[Int](),times=[Double]()
   for tick in 0..<100 {
    let source=(tick+phase)*2/5
    for out in selector.select(sample(source,tick,tenBit:tenBit),incoming:carrier,output:filmRate,film:true){seen.append(picture(out));times.append(CMSampleBufferGetPresentationTimeStamp(out).seconds)}
   }
   guard zip(seen,seen.dropFirst()).allSatisfy({$1==$0+1}) else{print("FAIL film phase \(phase): repeated/skipped pictures \(seen)");exit(1)}
   precondition(seen.count==40)
   precondition(zip(times,times.dropFirst()).allSatisfy{abs(($1-$0)-1001.0/24000)<0.00001})
  }
  }
  // Real metadata-only device timing includes valid ~9.95 ms short intervals.
  // Those are jitter, not evidence that the carrier stopped being 59.94 Hz.
  let times=try! JSONDecoder().decode([Int64].self,from:Data(contentsOf:URL(fileURLWithPath:"Tests/Fixtures/film-carrier-timestamps.json")))
  for phase in 0..<5 {
   let jittered=PreviewSampleSelector();var seen=[Int]()
   for tick in 0..<100 {
    for out in jittered.select(sample((tick+phase)*2/5,tick,pts:times[tick]),incoming:carrier,output:filmRate,film:true){seen.append(picture(out))}
   }
   guard seen.count==40 && zip(seen,seen.dropFirst()).allSatisfy({$1==$0+1}) else{print("FAIL real timing jitter disrupted film phase \(phase): \(seen)");exit(1)}
  }
  // A static title then motion must acquire the new phase without dropping pictures.
  for phase in 0..<5 {
   let selector=PreviewSampleSelector();var moving=[Int]()
   for tick in 0..<100 {
    let source=tick<30 ? 0:(tick-30+phase)*2/5+1
    for out in selector.select(sample(source,tick),incoming:carrier,output:filmRate,film:true){let p=picture(out);if p>0{moving.append(p)}}
   }
   precondition(zip(moving,moving.dropFirst()).allSatisfy{$1==$0+1})
  }
  // A paused/restarted input clears retained pictures and returns to the new live edge.
  let resume=PreviewSampleSelector();var resumed=[CMSampleBuffer]()
  for tick in 0..<20 {_ = resume.select(sample(tick*2/5,tick),incoming:carrier,output:filmRate,film:true)}
  for tick in 300..<320 {resumed += resume.select(sample((tick-300)*2/5,tick),incoming:carrier,output:filmRate,film:true)}
  precondition(resumed.count==8 && CMSampleBufferGetPresentationTimeStamp(resumed[0]).seconds>=5)
  resumed=[]
  for tick in 0..<20 {resumed += resume.select(sample(tick*2/5,tick),incoming:carrier,output:filmRate,film:true)}
  precondition(resumed.count==8 && CMSampleBufferGetPresentationTimeStamp(resumed[0]).seconds<0.01)
  for missingEvery in [4,5] {
   let interrupted=PreviewSampleSelector();var output=[CMSampleBuffer]()
   for tick in 0..<100 where tick%missingEvery != missingEvery-1 {
    output += interrupted.select(sample(tick*2/5,tick),incoming:carrier,output:filmRate,film:true)
   }
   guard output.count>=30 else{print("FAIL recurring missing carriers froze preview: every \(missingEvery), outputs \(output.count)");exit(1)}
   let before=output.count
   for tick in 100..<200 {output += interrupted.select(sample((tick-100)*2/5,tick),incoming:carrier,output:filmRate,film:true)}
   precondition(output.count-before>=35,"Film recovery must resume after stable carrier")
  }
  let ordinary=PreviewSampleSelector();var seen=[Int]()
  for tick in 0..<60 {for out in ordinary.select(sample(tick,tick),incoming:carrier,output:carrier,film:false){seen.append(picture(out))}}
  precondition(seen==Array(0..<60),"Automatic preview must retain every real motion frame")
  print("PASS decoded preview: 8/10-bit five film phases, static-to-motion, gap/reset, uniform timestamps, full-rate non-film")
 }
}
