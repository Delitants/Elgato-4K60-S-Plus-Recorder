import Foundation

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
 private let lock=NSLock(), maxBytes:Int, maxAge:UInt64
 private let clock:()->UInt64
 private var entries:[(Int,UInt64)]=[]
 private var used=0
 init(maxBytes:Int=64*1024*1024,maxAge:UInt64=2_000_000,clock:@escaping()->UInt64={DispatchTime.now().uptimeNanoseconds/1000}){self.maxBytes=maxBytes;self.maxAge=maxAge;self.clock=clock}
 var bytes:Int{lock.lock();defer{lock.unlock()};return used}
 func reserve(bytes:Int)->Bool{
  lock.lock();defer{lock.unlock()}
  guard bytes>=0,bytes<=maxBytes-used else{return false}
  // Media PTS can interleave and jump; only monotonic residence time measures backlog.
  let now=clock()
  if let first=entries.first,now>=first.1,now-first.1>maxAge{return false}
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
