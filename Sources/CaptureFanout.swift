import Foundation

/// Received elementary video bytes, before decode, preview or recording filters.
/// Fixed 100 ms buckets bound memory and exclude the unfinished bucket so a
/// keyframe arriving in a short USB burst cannot produce a misleading spike.
struct IncomingVideoBitrate {
 private struct Bucket {var tick:Int64 = -1;var bytes:Double=0}
 private var buckets=Array(repeating:Bucket(),count:31)
 private var firstTick:Int64?
 mutating func observe(type:UInt8,bytes:Int,now:Double) {
  guard type==0xc1,bytes>0,now.isFinite,now>=0 else{return}
  let tick=Int64(floor(now*10)),index=Int(tick%31)
  if firstTick==nil{firstTick=tick}
  if buckets[index].tick != tick{buckets[index]=Bucket(tick:tick)}
  buckets[index].bytes+=Double(bytes)
 }
 func mbps(now:Double)->Double? {
  guard let firstTick,now.isFinite,now>=0 else{return nil}
  let tick=Int64(floor(now*10)),span=min(30,tick-firstTick)
  guard span>=10 else{return nil}
  let bytes=buckets.reduce(0.0){sum,bucket in
   sum+(bucket.tick>=tick-span && bucket.tick<tick ? bucket.bytes:0)
  }
  return bytes*8/(Double(span)/10)/1_000_000
 }
}

/// Logical output sizes, measured only by the serial recording queue.
final class RecordingFileBytes {
 private let url:URL,split:Bool,existing:Set<String>
 private var part=1,completed:Int64=0
 init(url:URL,split:Bool) {
  self.url=url;self.split=split
  // Both writers reject an existing output. Snapshot names once before any write;
  // never enumerate a large output folder during normal capture.
  if split{existing=Set((try? FileManager.default.contentsOfDirectory(atPath:url.deletingLastPathComponent().path)) ?? [])}
  else{existing=FileManager.default.fileExists(atPath:url.path) ? [url.lastPathComponent]:[]}
 }
 private func partURL(_ number:Int)->URL {
  url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent+String(format:"_part%03d",number)+"."+url.pathExtension)
 }
 private func size(_ file:URL)->Int64? {
  guard !existing.contains(file.lastPathComponent),
   let attributes=try? FileManager.default.attributesOfItem(atPath:file.path),
   attributes[.type] as? FileAttributeType == .typeRegular,
   let bytes=attributes[.size] as? NSNumber else{return nil}
  return bytes.int64Value
 }
 func measure()->Int64 {
  guard split else{return size(url) ?? 0}
  guard var currentSize=size(partURL(part)) else{return completed}
  while let nextSize=size(partURL(part+1)) {
   // The helper closes and flushes each part before creating the next one.
   // Re-stat after seeing that next file so the accumulated size includes its trailer.
   completed+=size(partURL(part)) ?? currentSize
   part+=1;currentSize=nextSize
  }
  return completed+currentSize
 }
}
// Includes the item being processed: a blocked pipe cannot hide outside this budget.
final class QueueBudget {
 private let lock=NSLock(), maxBytes:Int, maxAge:UInt64, startupGrace:UInt64
 private let clock:()->UInt64
 private var entries:[(Int,UInt64)]=[]
 private var used=0
 private var firstOffer:UInt64?
 init(maxBytes:Int=64*1024*1024,maxAge:UInt64=2_000_000,startupGrace:UInt64=0,clock:@escaping()->UInt64={DispatchTime.now().uptimeNanoseconds/1000}){self.maxBytes=maxBytes;self.maxAge=maxAge;self.startupGrace=startupGrace;self.clock=clock}
 var bytes:Int{lock.lock();defer{lock.unlock()};return used}
 var backlog:(bytes:Int,seconds:Double){
  lock.lock();defer{lock.unlock()};let now=clock()
  return (used,entries.first.map{now >= $0.1 ? Double(now-$0.1)/1e6:0} ?? 0)
 }
 func reserve(bytes:Int)->Bool{
  lock.lock();defer{lock.unlock()}
  guard bytes>=0,bytes<=maxBytes-used else{return false}
  // Media PTS can interleave and jump; only monotonic residence time measures backlog.
  let now=clock()
  if firstOffer==nil{firstOffer=now}
  // Permit cold helper startup once, while retaining the hard byte bound.
  // Draining the queue must never renew the startup allowance.
  let starting=now>=firstOffer! && now-firstOffer!<startupGrace
  if !starting,let first=entries.first,now>=first.1,now-first.1>maxAge{return false}
  used+=bytes;entries.append((bytes,now));return true
 }
 func release(bytes:Int){lock.lock();defer{lock.unlock()};precondition(entries.first?.0==bytes);used-=bytes;entries.removeFirst()}
}

/// Bounded, metadata-only timing diagnostics; never retains video or audio contents.
final class CaptureTiming {
 private var maxima=[String:Double](),events=[[String:Any]]()
 func measure<T>(_ name:String,_ body:() throws ->T) rethrows ->T {
  #if CAPTURE_DIAGNOSTICS
  let start=ProcessInfo.processInfo.systemUptime
  let result=try body()
  observe(name,seconds:ProcessInfo.processInfo.systemUptime-start)
  return result
  #else
  return try body()
  #endif
 }
 func observe(_ name:String,seconds:Double) {
  #if CAPTURE_DIAGNOSTICS
  maxima[name]=max(maxima[name] ?? 0,seconds*1000)
  if seconds>0.05 {events.append(["stage":name,"ms":seconds*1000,"uptime":ProcessInfo.processInfo.systemUptime]);if events.count>64{events.removeFirst()}}
  #endif
 }
 var snapshot:[String:Any]{["maxStageMs":maxima,"slowEvents":events]}
}

#if PREVIEW_DIAGNOSTICS
/// Timing metadata only; never stores images, audio or encoded media.
final class PreviewTrace {
 static let shared=PreviewTrace()
 private let lock=NSLock(),writer=DispatchQueue(label:"Elgato.PreviewTrace")
 private var events=[[Double]](),start=ProcessInfo.processInfo.systemUptime
 func reset(){lock.lock();events.removeAll(keepingCapacity:true);start=ProcessInfo.processInfo.systemUptime;lock.unlock()}
 func event(_ stage:Double,_ pts:Double = -1,_ value:Double = 0){
  lock.lock();defer{lock.unlock()}
  if events.count<50000{events.append([stage,ProcessInfo.processInfo.systemUptime-start,pts,value])}
 }
 func save(){
  lock.lock();let copy=events;lock.unlock()
  writer.async{if let data=try? JSONSerialization.data(withJSONObject:copy){try? data.write(to:FileManager.default.temporaryDirectory.appendingPathComponent("ElgatoPreviewTrace.json"),options:.atomic)}}
 }
}
#endif
