import Foundation
@main struct MonitoringTests {
 static func main() {
  var d=RecordingDeadline()
  assert(!d.expired(now:100))
  d.start(seconds:10,now:100)
  assert(d.remaining(now:103)==7)
  assert(!d.expired(now:109.999))
  assert(d.expired(now:110))
  assert(d.remaining(now:130)==0)
  d.clear();assert(!d.expired(now:10000))
  d.start(seconds:0,now:100);assert(d.remaining(now:200)==nil)
  print("PASS: duration limit, exact deadline, no-input elapsed time, clear, unlimited")
 }
}
