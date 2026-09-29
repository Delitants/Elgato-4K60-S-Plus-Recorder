import Foundation
import CoreMedia
final class RecordingSink {
 private let queue=DispatchQueue(label:"Elgato.Recording",qos:.userInitiated),lock=NSLock(),budget:QueueBudget
 private let converter:MediaConverter,decoder=PreviewDecoder(),native:MovieRecorder?,helper:MediaHelperClient?
 private var recordingRate:VideoRate?
 private var timingWarning:String?,recoveryWarning:String?
 private var recovering=false,recoveryCount=0,skipped=0
 private var recordingActivity:NSObjectProtocol?
 private var failure:Error?,ended=false,frames=0,elapsed=0.0,origin:UInt64?
 private var acceptedAt:Double?,fileSize:Int64=0,refreshPending=false
 private lazy var fileBytes=RecordingFileBytes(url:url,split:profile.splitMode != 0)
 let url:URL
 var startedAt:Double?{lock.lock();defer{lock.unlock()};return acceptedAt}
 var writtenBytes:Int64{lock.lock();defer{lock.unlock()};return fileSize}
 var duration:Double{lock.lock();defer{lock.unlock()};return elapsed}
 var videoFrames:Int{lock.lock();defer{lock.unlock()};return frames}
 var dropped:Int{lock.lock();defer{lock.unlock()};return skipped}
 var warning:String?{
  lock.lock();let timing=timingWarning,recovery=recoveryWarning;lock.unlock()
  let messages=[recovery,timing,helper?.warning].compactMap{$0}
  return messages.isEmpty ? nil:messages.joined(separator:" · ")
 }
 var error:Error?{lock.lock();defer{lock.unlock()};return failure}
 private let profile:RecordingProfile
 init(url:URL,profile:RecordingProfile,initialRate:VideoRate?=nil){self.url=url;self.profile=profile;converter=MediaConverter(hevc:profile.captureHEVC,initialRate:initialRate);decoder.preference=profile.decoder;decoder.tenBit=profile.captureHEVC
  budget=QueueBudget(startupGrace:profile.usesHelper ? 10_000_000:0)
  native=profile.usesHelper ? nil:MovieRecorder(url:url,profile:profile);helper=profile.usesHelper ? MediaHelperClient(url:url,profile:profile):nil
  do{
   try profile.validateRecording()
   // Capture must remain active while hidden. Keep App Nap and idle system sleep
   // disabled until all queued media and the container trailer are finalized.
   // Display sleep is deliberately allowed.
   recordingActivity=ProcessInfo.processInfo.beginActivity(options:.userInitiated,reason:"Recording HDMI video and audio")
  }catch{failure=error}
  queue.async{_ = self.fileBytes}
 }
 private func endRecordingActivity(){
  lock.lock();let activity=recordingActivity;recordingActivity=nil;lock.unlock()
  if let activity{ProcessInfo.processInfo.endActivity(activity)}
 }
 deinit{endRecordingActivity()}
 // The capture worker requests a refresh but never performs filesystem I/O.
 func refreshWrittenBytes(){
  lock.lock();guard !refreshPending,!ended else{lock.unlock();return};refreshPending=true;lock.unlock()
  queue.async{self.updateWrittenBytes();self.lock.lock();self.refreshPending=false;self.lock.unlock()}
 }
 private func updateWrittenBytes(){let count=fileBytes.measure();lock.lock();fileSize=count;lock.unlock()}
 func offer(_ frame:DeviceFrame,key:Bool?=nil)->Bool{
  let offeredAt=ProcessInfo.processInfo.systemUptime
  lock.lock();defer{lock.unlock()};guard !ended,failure==nil else{return false}
  var resume=false
  if recovering {
   // Drain all accepted packets first. Audio and predictive video are skipped
   // together until a fresh random-access picture; source timestamps retain the gap.
   let keyframe=frame.type==0xc1 && (key ?? MediaConverter.nals(frame.data).contains{nal in
    guard let byte=nal.first else{return false}
    return profile.captureHEVC ? (16...21).contains((byte>>1)&63):byte&31==5
   })
   guard budget.bytes==0,keyframe else{skipped+=1;return true}
   resume=true
  }
  guard budget.reserve(bytes:frame.data.count) else{
   if !recovering {
    recoveryCount+=1;let backlog=budget.backlog
    recoveryWarning=String(format:"Recording backlog %.1f s / %.1f MB; recovering at the next keyframe (event %d)",backlog.seconds,Double(backlog.bytes)/1e6,recoveryCount)
    NSLog("%@",recoveryWarning!)
   }
   recovering=true;skipped+=1;return true
  }
  if resume {
   recovering=false
   recoveryWarning="Recording recovered at a keyframe · \(recoveryCount) backlog event(s), \(skipped) input packets skipped; a brief A/V gap may be visible"
   NSLog("%@",recoveryWarning!)
  }
  queue.async{defer{self.budget.release(bytes:frame.data.count)}
   do {
    guard self.error==nil else{return}
    if resume {self.decoder.close();try self.helper?.resumeAfterGap()}
    guard let(sample,key)=try self.converter.convert(frame) else{return}
    if frame.type==0xc1,let rate=self.converter.frameTiming.rate {
     if let previous=self.recordingRate,abs(previous.fps-rate.fps)/previous.fps>0.01 {
      // FPS is a rolling estimate, not a codec-format change. Keep the existing
      // encoder/output configuration and source PTS instead of aborting the file.
      self.lock.lock()
      if self.timingWarning==nil{self.timingWarning="Incoming timing varied (\(previous.label) → \(rate.label) fps); recording continued using source timestamps"}
      self.lock.unlock()
     }
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
    self.updateWrittenBytes();self.endRecordingActivity();completion(result.0,result.1)
   }
   else if let native=self.native{native.finish{url,error in self.queue.async{self.updateWrittenBytes();self.endRecordingActivity();completion(url,self.error?.localizedDescription ?? error)}}}
  }
 }
}
