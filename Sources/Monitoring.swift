import Foundation
import AVFoundation

/// Capture-worker meter; independent of playback volume and the audio render callback.
struct StereoPeakMeter {
 private var left=0,right=0,lastPublication:Double?
 private var hasSamples=false
 mutating func append(_ data:Data) {
  guard data.count>=4 else{return}
  hasSamples=true
  data.withUnsafeBytes{raw in
   let bytes=raw.bindMemory(to:UInt8.self)
   for offset in stride(from:0,to:bytes.count-bytes.count%4,by:4) {
    left=max(left,abs(Int(Int16(bitPattern:UInt16(bytes[offset])|UInt16(bytes[offset+1])<<8))))
    right=max(right,abs(Int(Int16(bitPattern:UInt16(bytes[offset+2])|UInt16(bytes[offset+3])<<8))))
   }
  }
 }
 mutating func take(now:Double)->(left:Double,right:Double)? {
  if let lastPublication,now-lastPublication<0.02{return nil}
  // USB packets arrive in bursts; an empty poll is not PCM silence.
  if !hasSamples,let lastPublication,now-lastPublication<0.15{return nil}
  lastPublication=now
  defer{left=0;right=0;hasSamples=false}
  return (Double(left)/32768,Double(right)/32768)
 }
}

/// A duration limit uses monotonic time, so loss of HDMI and clock changes cannot extend it.
struct RecordingDeadline {
    private var startedAt: Double?
    private(set) var end: Double?
    // Repeated updates change the duration while retaining the accepted keyframe's time.
    mutating func start(seconds: Double, now: Double) {
        if startedAt == nil { startedAt = now }
        end = seconds.isFinite && seconds > 0 ? startedAt! + seconds : nil
    }
    mutating func clear() { startedAt = nil; end = nil }
    func remaining(now: Double) -> Double? { end.map { max(0, $0 - now) } }
    func expired(now: Double) -> Bool { end.map { now >= $0 } ?? false }
}

/// Preallocated stereo float ring. The render callback never waits for a lock.
final class PCMPlaybackRing {
 private let lock=NSLock(),capacity:Int,prime:Int,samples:UnsafeMutablePointer<Float>
 private var head=0,count=0,playing=false,enabled=false,volume:Float=1
 private var underruns=0,overruns=0
 init(capacity:Int=16384,prime:Int=3072) {
  precondition(capacity>=prime && prime>0)
  self.capacity=capacity;self.prime=prime;samples = .allocate(capacity:capacity*2)
  samples.initialize(repeating:0,count:capacity*2)
 }
 deinit{samples.deinitialize(count:capacity*2);samples.deallocate()}
 func setEnabled(_ value:Bool){lock.lock();defer{lock.unlock()};if enabled != value{enabled=value;head=0;count=0;playing=false}}
 func setVolume(_ value:Float){lock.lock();volume=max(0,min(1,value));lock.unlock()}
 func append(_ data:Data) {
  guard data.count>0,data.count%4==0 else{return}
  lock.lock();defer{lock.unlock()};guard enabled else{return}
  let frames=min(capacity,data.count/4),skip=data.count/4-frames
  if count+frames>capacity{head=0;count=0;playing=false;overruns+=1}
  data.withUnsafeBytes{raw in
   let bytes=raw.bindMemory(to:UInt8.self)
   for frame in 0..<frames {
    let slot=(head+count+frame)%capacity
    for channel in 0..<2 {
     let p=(frame+skip)*4+channel*2
     samples[slot*2+channel]=Float(Int16(bitPattern:UInt16(bytes[p])|UInt16(bytes[p+1])<<8))/32768
    }
   }
  }
  count+=frames
 }
 func read(left:UnsafeMutablePointer<Float>,right:UnsafeMutablePointer<Float>,frames:Int)->Int {
  left.update(repeating:0,count:frames);right.update(repeating:0,count:frames)
  guard lock.try() else{return 0};defer{lock.unlock()}
  guard enabled else{return 0}
  if !playing {guard count>=prime else{return 0};playing=true}
  let n=min(frames,count)
  for frame in 0..<n {let slot=(head+frame)%capacity;left[frame]=samples[slot*2]*volume;right[frame]=samples[slot*2+1]*volume}
  head=(head+n)%capacity;count-=n
  if n<frames {playing=false;underruns+=1}
  return n
 }
 var diagnostics:[String:Double]{lock.lock();defer{lock.unlock()};return ["queueEmptyEvents":Double(underruns),"queueResets":Double(overruns),"queuedPackets":Double(count)/1024]}
}

/// USB ingestion only copies PCM. All engine lifecycle operations use another queue.
final class AudioMonitor {
 private let engine=AVAudioEngine(),ring=PCMPlaybackRing(),control=DispatchQueue(label:"Elgato.AudioControl",qos:.userInitiated),errorLock=NSLock()
 private var source:AVAudioSourceNode!
 private var enabled=false,appliedVolume:Float?,failure:String?
 private var previousPTS:UInt64?,previousSamples=0,lastArrival:Double?,maxArrivalGap=0.0,sourceGaps=0,packets=0
 var error:String?{errorLock.lock();defer{errorLock.unlock()};return failure}
 init() {
  let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,ring=self.ring
  source=AVAudioSourceNode(format:format){silence,_,frames,list in
   let buffers=UnsafeMutableAudioBufferListPointer(list)
   guard buffers.count==2,let l=buffers[0].mData,let r=buffers[1].mData else{
    for b in buffers{if let p=b.mData{memset(p,0,Int(b.mDataByteSize))}};silence.pointee=true;return noErr
   }
   let count=ring.read(left:l.assumingMemoryBound(to:Float.self),right:r.assumingMemoryBound(to:Float.self),frames:Int(frames))
   silence.pointee=ObjCBool(count==0);return noErr
  }
  engine.attach(source);engine.connect(source,to:engine.mainMixerNode,format:format)
 }
 func configure(enabled:Bool,volume:Float) {
  if appliedVolume != volume{ring.setVolume(volume);appliedVolume=volume}
  guard self.enabled != enabled else{return};self.enabled=enabled;ring.setEnabled(enabled)
  control.async {
   do{if enabled{try self.engine.start()}else{self.engine.pause()};self.errorLock.lock();self.failure=nil;self.errorLock.unlock()}
   catch{self.errorLock.lock();self.failure=error.localizedDescription;self.errorLock.unlock()}
  }
 }
 func append(_ data:Data,timestamp:UInt64) {
  let now=ProcessInfo.processInfo.systemUptime
  if let lastArrival{maxArrivalGap=max(maxArrivalGap,now-lastArrival)};lastArrival=now
  if let previousPTS,abs(Double(timestamp)-Double(previousPTS)-Double(previousSamples)*1e6/48000)>100{sourceGaps+=1}
  previousPTS=timestamp;previousSamples=data.count/4;packets+=1
  ring.append(data)
 }
 var diagnostics:[String:Double]{var d=ring.diagnostics;d["audioPackets"]=Double(packets);d["maxArrivalGapMs"]=maxArrivalGap*1000;d["sourceTimestampGaps"]=Double(sourceGaps);return d}
 func stop(){configure(enabled:false,volume:appliedVolume ?? 1)}
 deinit{engine.stop()}
}

/// The label describes recent audible signal, not individual PCM sample windows.
struct AudioSignalIndicator {
 private var lastSound:Double?
 mutating func observe(peak:Double,now:Double){
  if peak.isFinite && peak>=0.0001{lastSound=now}
 }
 func isActive(now:Double)->Bool{lastSound.map{now-$0<0.75} ?? false}
}
