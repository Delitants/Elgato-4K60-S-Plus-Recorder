import Foundation
import CoreMedia
import CoreImage
import Darwin
final class NDIOutput {
 private let queue=DispatchQueue(label:"Elgato.NDI",qos:.userInitiated),lock=NSLock(),context=CIContext(options:[.cacheIntermediates:false])
 private let process=Process(),pipe=Pipe(),errors=Pipe(),output=Pipe()
 private var pendingVideo=0,pendingAudio=0,stopped=false,ready=false,failure:String?
 private let slotSize=3840*2160*4
 private var shared:UnsafeMutableRawPointer?,sharedFD:Int32 = -1,sharedName="",slots=[false,false],response=""
 private let profile:RecordingProfile
 var status:String{lock.lock();defer{lock.unlock()};return failure ?? (stopped ? "NDI off":ready ? "NDI sending · \(profile.ndiName)":"NDI starting…")}
 init(profile:RecordingProfile)throws{
  self.profile=profile
  sharedName="/elgato-"+String(UUID().uuidString.prefix(16))
  sharedFD=capture_shared_memory_open(sharedName)
  guard sharedFD>=0,ftruncate(sharedFD,off_t(slotSize*2))==0 else{throw RecorderError(message:"Cannot allocate NDI shared memory")}
  shared=mmap(nil,slotSize*2,PROT_READ|PROT_WRITE,MAP_SHARED,sharedFD,0)
  guard shared != MAP_FAILED else{shm_unlink(sharedName);Darwin.close(sharedFD);throw RecorderError(message:"Cannot map NDI shared memory")}
  let bundle=Bundle.main.bundleURL
  process.executableURL=bundle.appendingPathComponent("Contents/MacOS/NDISender")
  process.arguments=[bundle.appendingPathComponent("Contents/Frameworks/libndi.dylib").path,profile.ndiName,sharedName]
  process.standardInput=pipe;process.standardOutput=output;process.standardError=errors
  errors.fileHandleForReading.readabilityHandler={ [weak self] h in let data=h.availableData;guard let self,!data.isEmpty else{return};self.lock.lock();if self.failure==nil {self.failure=String(decoding:data.prefix(4096),as:UTF8.self)};self.lock.unlock() }
  output.fileHandleForReading.readabilityHandler={ [weak self] h in let d=h.availableData;guard let self,!d.isEmpty else{return};self.lock.lock();self.response+=String(decoding:d,as:UTF8.self);while let lineEnd=self.response.firstIndex(of:"\n"){let line=String(self.response[..<lineEnd]);self.response.removeSubrange(...lineEnd);if line.hasPrefix("READY "){self.ready=true};if line.hasPrefix("DONE "),let slot=Int(line.dropFirst(5)),(0...1).contains(slot){self.slots[slot]=false}};self.lock.unlock() }

  try process.run();output.fileHandleForWriting.closeFile();pipe.fileHandleForReading.closeFile();errors.fileHandleForWriting.closeFile()
  let fd=pipe.fileHandleForWriting.fileDescriptor;_ = fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);_ = fcntl(fd,F_SETNOSIGPIPE,1)
 }
 private func send(type:UInt32,width:Int,height:Int,pts:Int64,data:Data,videoBytes:Int?=nil,rate:VideoRate?=nil)throws{
  var message=Data();for var n in [type,UInt32(videoBytes ?? data.count),UInt32(width),UInt32(height)]{n=n.littleEndian;withUnsafeBytes(of:&n){message.append(contentsOf:$0)}};var pts=pts.littleEndian;withUnsafeBytes(of:&pts){message.append(contentsOf:$0)};for var n in [UInt32(rate?.numerator ?? 0),UInt32(rate?.denominator ?? 0)]{n=n.littleEndian;withUnsafeBytes(of:&n){message.append(contentsOf:$0)}};message.append(data)
  let deadline=ProcessInfo.processInfo.systemUptime+1.0,fd=pipe.fileHandleForWriting.fileDescriptor
  try message.withUnsafeBytes{raw in var offset=0;while offset<raw.count{let n=Darwin.write(fd,raw.baseAddress!.advanced(by:offset),raw.count-offset);if n>0{offset+=n;continue};if errno==EINTR{continue};if errno==EAGAIN && ProcessInfo.processInfo.systemUptime<deadline{var p=pollfd(fd:fd,events:Int16(POLLOUT),revents:0);_ = poll(&p,1,5);continue};throw RecorderError(message:"NDI sender stopped or cannot keep up (sent \(offset) of \(raw.count) bytes; errno \(errno)). Toggle NDI off/on to restart.")}}
 }
 private func fail(_ error:Error){lock.lock();failure=error.localizedDescription;stopped=true;lock.unlock();pipe.fileHandleForWriting.closeFile();ProcessLifecycle.stop(process)}
 func offerVideo(_ sample:CMSampleBuffer){
  lock.lock();guard !stopped,ready,let slot=slots.firstIndex(of:false) else{lock.unlock();return};slots[slot]=true;lock.unlock()
  queue.async{
   self.lock.lock();let active = !self.stopped;self.lock.unlock();guard active,let buffer=CMSampleBufferGetImageBuffer(sample) else{return}
   if let transfer=CVBufferCopyAttachment(buffer,kCVImageBufferTransferFunctionKey,nil) as? String,transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String) || transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String){self.fail(RecorderError(message:"HDR NDI output is not supported. Use an SDR HDMI source."));return}
   let source=CIImage(cvPixelBuffer:buffer),sh=CVPixelBufferGetHeight(buffer),sw=CVPixelBufferGetWidth(buffer)
   let height=min(sh,self.profile.ndiScale==1 ? 1080:self.profile.ndiScale==2 ? 720:sh),width=(sw*height/sh)/2*2
   let image=source.transformed(by:CGAffineTransform(scaleX:CGFloat(width)/CGFloat(sw),y:CGFloat(height)/CGFloat(sh)))
   guard let shared=self.shared else{return};self.context.render(image,toBitmap:shared.advanced(by:slot*self.slotSize),rowBytes:width*4,bounds:CGRect(x:0,y:0,width:width,height:height),format:.BGRA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB));var index=UInt32(slot).littleEndian;let data=withUnsafeBytes(of:&index){Data($0)}
   do{try self.send(type:0,width:width,height:height,pts:CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(sample),timescale:1_000_000,method:.default).value,data:data,videoBytes:width*height*4,rate:VideoRate.measured(period:CMSampleBufferGetDuration(sample).seconds))}catch{self.fail(error)}
  }
 }
 func offerAudio(_ frame:DeviceFrame){
  lock.lock();guard !stopped,ready,pendingAudio+frame.data.count<=19200 else{lock.unlock();return};pendingAudio+=frame.data.count;lock.unlock()
  queue.async{defer{self.lock.lock();self.pendingAudio-=frame.data.count;self.lock.unlock()};self.lock.lock();let active = !self.stopped;self.lock.unlock();guard active else{return};do{try self.send(type:1,width:0,height:0,pts:Int64(frame.timestamp),data:frame.data)}catch{self.fail(error)}}
 }
 func stop(){lock.lock();stopped=true;lock.unlock();queue.async{self.pipe.fileHandleForWriting.closeFile();ProcessLifecycle.stop(self.process)}}
 deinit{if let shared,shared != MAP_FAILED{munmap(shared,slotSize*2)};if sharedFD>=0{Darwin.close(sharedFD);shm_unlink(sharedName)};output.fileHandleForReading.readabilityHandler=nil;errors.fileHandleForReading.readabilityHandler=nil;ProcessLifecycle.stop(process)}
}
