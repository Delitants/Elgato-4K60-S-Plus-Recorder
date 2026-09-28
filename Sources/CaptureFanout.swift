import Foundation
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
