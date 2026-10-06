import Foundation
import Darwin

struct RecordingCompletion {
 let url: URL?
 let status: String
 let detail: String
 init(url: URL?, error: String?) {
  self.url = url
  if let error { status="Recording error"; detail=error + (url.map { " Partial file: \($0.lastPathComponent)" } ?? "") }
  else if let url { status="Recording saved"; detail=url.lastPathComponent }
  else { status="Recording error"; detail="Could not finalize recording" }
 }
}

enum ProcessLifecycle {
 /// Call on a worker, never the main or USB capture queue.
 static func stop(_ process: Process, grace: Double = 0.5) {
  guard process.isRunning else { return }
  process.terminate()
  let end=ProcessInfo.processInfo.systemUptime+grace
  while process.isRunning && ProcessInfo.processInfo.systemUptime<end { Thread.sleep(forTimeInterval:0.01) }
  if process.isRunning { _ = kill(process.processIdentifier,SIGKILL) }
  process.waitUntilExit()
 }
}

/// Reads to EOF independently of the process owner, retaining only a bounded tail.
final class ProcessOutput {
 private let pipe: Pipe, capacity: Int, lock=NSLock(), done=DispatchSemaphore(value:0)
 private var data=Data(),retainedWarning:String?
 init(pipe: Pipe, capacity: Int) {
  self.pipe=pipe; self.capacity=capacity
  pipe.fileHandleForReading.readabilityHandler={ [weak self] handle in
   let chunk=handle.availableData
   guard let self else {return}
   if chunk.isEmpty { handle.readabilityHandler=nil; self.done.signal(); return }
   self.lock.lock(); self.data.append(chunk)
   if let warning=BackendProgress.warning(in:String(decoding:self.data,as:UTF8.self)){self.retainedWarning=warning}
   if self.data.count>self.capacity { self.data.removeFirst(self.data.count-self.capacity) }
   self.lock.unlock()
  }
 }
 var latestWarning:String?{lock.lock();defer{lock.unlock()};return retainedWarning}
 var text: String { lock.lock(); defer{lock.unlock()}; return String(decoding:data,as:UTF8.self) }
 func waitForEOF(seconds:Double=2)->Bool {done.wait(timeout:.now()+seconds) == .success}
 deinit { pipe.fileHandleForReading.readabilityHandler=nil }
}

/// Helper progress is newline-delimited; do not display a partial pipe read.
enum BackendProgress {
 static func finalizingMP4(in text:String)->String? {
  guard let line=text.split(separator:"\n",omittingEmptySubsequences:false).dropLast().last(where:{$0.hasPrefix("FINALIZING_MP4 ") || $0.hasPrefix("SAVED ") || $0.hasPrefix("FILE ")}),line.hasPrefix("FINALIZING_MP4 ") else{return nil}
  return String(line.dropFirst(15))
 }
 static func warning(in text:String)->String? {
  text.split(separator:"\n",omittingEmptySubsequences:false).dropLast().last(where:{$0.hasPrefix("WARNING ")}).map{String($0.dropFirst(8))}
 }
}

/// Keep the normal 30-second stall bound, but allow a file relocation that is
/// still writing. The caller supplies file identity, size and modification time.
struct BackendStallWatchdog {
 private var deadline:Double,nextProbe:Double,previous:String?
 init(now:Double){deadline=now+30;nextProbe=now}
 mutating func expired(now:Double,progress:()->String?)->Bool{
  if now>=nextProbe {
   nextProbe=now+0.25
   let token=progress()
   if let token,token != previous{deadline=now+30}
   previous=token
  }
  return now>=deadline
 }
}
