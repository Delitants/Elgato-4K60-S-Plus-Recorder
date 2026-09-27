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
 private var data=Data()
 init(pipe: Pipe, capacity: Int) {
  self.pipe=pipe; self.capacity=capacity
  pipe.fileHandleForReading.readabilityHandler={ [weak self] handle in
   let chunk=handle.availableData
   guard let self else {return}
   if chunk.isEmpty { handle.readabilityHandler=nil; self.done.signal(); return }
   self.lock.lock(); self.data.append(chunk)
   if self.data.count>self.capacity { self.data.removeFirst(self.data.count-self.capacity) }
   self.lock.unlock()
  }
 }
 var text: String { lock.lock(); defer{lock.unlock()}; return String(decoding:data,as:UTF8.self) }
 func waitForEOF(seconds:Double=2)->Bool {done.wait(timeout:.now()+seconds) == .success}
 deinit { pipe.fileHandleForReading.readabilityHandler=nil }
}
