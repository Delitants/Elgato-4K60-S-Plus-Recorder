import Foundation
import CoreMedia
final class RecordingSink {
 private let queue=DispatchQueue(label:"Elgato.Recording",qos:.userInitiated),lock=NSLock(),budget=QueueBudget()
 private let converter:MediaConverter,decoder=PreviewDecoder(),native:MovieRecorder?,helper:MediaHelperClient?
 private var recordingRate:VideoRate?
 private var failure:Error?,ended=false,frames=0,elapsed=0.0,origin:UInt64?
 private var acceptedAt:Double?,fileSize:Int64=0,refreshPending=false
 private lazy var fileBytes=RecordingFileBytes(url:url,split:profile.splitMode != 0)
 let url:URL
 var startedAt:Double?{lock.lock();defer{lock.unlock()};return acceptedAt}
 var writtenBytes:Int64{lock.lock();defer{lock.unlock()};return fileSize}
 var duration:Double{lock.lock();defer{lock.unlock()};return elapsed}
 var videoFrames:Int{lock.lock();defer{lock.unlock()};return frames}
 var dropped:Int{0}
 var error:Error?{lock.lock();defer{lock.unlock()};return failure}
 private let profile:RecordingProfile
 init(url:URL,profile:RecordingProfile,initialRate:VideoRate?=nil){self.url=url;self.profile=profile;converter=MediaConverter(hevc:profile.captureHEVC,initialRate:initialRate);decoder.preference=profile.decoder;decoder.tenBit=profile.captureHEVC
  native=profile.usesHelper ? nil:MovieRecorder(url:url,profile:profile);helper=profile.usesHelper ? MediaHelperClient(url:url,profile:profile):nil
  do{try profile.validateRecording()}catch{failure=error}
  queue.async{_ = self.fileBytes}
 }
 // The capture worker requests a refresh but never performs filesystem I/O.
 func refreshWrittenBytes(){
  lock.lock();guard !refreshPending,!ended else{lock.unlock();return};refreshPending=true;lock.unlock()
  queue.async{self.updateWrittenBytes();self.lock.lock();self.refreshPending=false;self.lock.unlock()}
 }
 private func updateWrittenBytes(){let count=fileBytes.measure();lock.lock();fileSize=count;lock.unlock()}
 func offer(_ frame:DeviceFrame)->Bool{
  let offeredAt=ProcessInfo.processInfo.systemUptime
  lock.lock();defer{lock.unlock()};guard !ended,failure==nil else{return false}
  guard budget.reserve(bytes:frame.data.count) else{failure=RecorderError(message:"Recording cannot keep up. Lower encoder effort or output resolution.");return false}
  queue.async{defer{self.budget.release(bytes:frame.data.count)}
   do {
    guard self.error==nil,let(sample,key)=try self.converter.convert(frame) else{return}
    if frame.type==0xc1,let rate=self.converter.frameTiming.rate {
     if let previous=self.recordingRate,abs(previous.fps-rate.fps)/previous.fps>0.01 {throw RecorderError(message:"Incoming frame rate changed. Start a new recording for the new signal.")}
     if self.recordingRate==nil && key {self.recordingRate=rate}
    }
    if let helper=self.helper {guard try helper.append(sample,type:frame.type,key:key) else{return}}
    else if let native=self.native {
     let previousVideo=native.videoFrames,previousAudio=native.audioFrames
     if frame.type==0xc1 && self.profile.transcodes{self.decoder.decode(sample,key:key,synchronous:true);if let error=self.decoder.lastError{throw RecorderError(message:error)};guard let image=self.decoder.takeFrame() else{return};try native.append(image,type:frame.type,key:key,converter:self.converter)}
     else{try native.append(sample,type:frame.type,key:key,converter:self.converter)}
     guard native.videoFrames>previousVideo || native.audioFrames>previousAudio else{return}
    }
    self.lock.lock();if self.origin==nil && frame.type==0xc1 && key{self.origin=frame.timestamp;self.acceptedAt=offeredAt};if let origin=self.origin,frame.timestamp>=origin{self.elapsed=Double(frame.timestamp-origin)/1e6;if frame.type==0xc1{self.frames+=1}};self.lock.unlock()
   }catch{self.lock.lock();self.failure=error;self.lock.unlock()}
  };return true
 }
 func finish(_ completion:@escaping(URL?,String?)->Void){
  lock.lock();guard !ended else{lock.unlock();return};ended=true;lock.unlock()
  queue.async{
   self.decoder.close()
   if let helper=self.helper{
    let result:(URL?,String?)
    do{let url=try helper.finish();result=(url,self.error?.localizedDescription)}catch{result=(helper.lastSavedURL,self.error is BackendWriteError ? error.localizedDescription : (self.error?.localizedDescription ?? error.localizedDescription))}
    self.updateWrittenBytes();completion(result.0,result.1)
   }
   else if let native=self.native{native.finish{url,error in self.queue.async{self.updateWrittenBytes();completion(url,self.error?.localizedDescription ?? error)}}}
  }
 }
}
