import Foundation
@main struct FastStartWatchdogTests {
 static func main(){
  assert(BackendProgress.finalizingMP4(in:"FINALIZING_MP4 /tmp/a file.mp4\n")=="/tmp/a file.mp4")
  assert(BackendProgress.finalizingMP4(in:"FINALIZING_MP4 /tmp/a\nSAVED /tmp/a\n")==nil)
  assert(BackendProgress.finalizingMP4(in:"FINALIZING_MP4 /tmp/a\nFILE /tmp/b\n")==nil)
  assert(BackendProgress.finalizingMP4(in:"FINALIZING_MP4 incomplete")==nil)
  var fixed=BackendStallWatchdog(now:0)
  assert(!fixed.expired(now:29){nil});assert(fixed.expired(now:30){nil})
  var moving=BackendStallWatchdog(now:0)
  assert(!moving.expired(now:20){"file-size100-mtime1"})
  assert(!moving.expired(now:40){"file-size100-mtime2"},"Same-size relocation writes extend the deadline")
  assert(!moving.expired(now:69){"file-size100-mtime2"})
  assert(moving.expired(now:70){"file-size100-mtime2"},"Stalled finalization remains bounded")
  var stopped=BackendStallWatchdog(now:0)
  assert(!stopped.expired(now:1){"file-size100-mtime1"})
  assert(stopped.expired(now:31){nil},"Leaving finalization does not reset the deadline")
  print("PASS fast-start phase parsing and progress-aware stall deadline")
 }
}
