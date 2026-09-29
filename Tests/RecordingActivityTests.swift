import Foundation
import IOKit.pwr_mgt

@main struct RecordingActivityTests {
 static func recordingAssertions()->Int {
  var raw:Unmanaged<CFDictionary>?
  precondition(IOPMCopyAssertionsByProcess(&raw)==kIOReturnSuccess,"Cannot inspect power assertions")
  let all=raw!.takeRetainedValue() as NSDictionary
  let rows=all[NSNumber(value:getpid())] as? [[String:Any]] ?? []
  return rows.filter{($0["AssertName"] as? String)=="Recording HDMI video and audio" && ($0["AssertType"] as? String)=="PreventUserIdleSystemSleep"}.count
 }
 static func main()throws {
  assert(recordingAssertions()==0)
  for container in [0,2] {
  var profile=RecordingProfile();profile.container=container
  var sink:RecordingSink?=RecordingSink(url:URL(fileURLWithPath:"/tmp/activity-test-\(UUID().uuidString).mkv"),profile:profile)
  assert(recordingAssertions()==1,"An active recorder must hold a macOS user-initiated activity while hidden")
  let done=DispatchSemaphore(value:0)
  sink!.finish{_,error in assert(error != nil);assert(recordingAssertions()==0,"Failed startup must release activity after finalization");done.signal()}
  assert(done.wait(timeout:.now()+5) == .success)
  sink=nil
  // Abandonment must release the same assertion even if finish is never called.
  sink=RecordingSink(url:URL(fileURLWithPath:"/tmp/activity-abandon-\(UUID().uuidString).mkv"),profile:profile)
  assert(recordingAssertions()==1);sink=nil
  let deadline=Date().addingTimeInterval(2)
  while recordingAssertions()>0 && Date()<deadline {Thread.sleep(forTimeInterval:0.01)}
  assert(recordingAssertions()==0,"Abandonment leaked recording activity")
  }
  var invalid=RecordingProfile();invalid.deviceMbps=0
  let rejected=RecordingSink(url:URL(fileURLWithPath:"/tmp/rejected-\(UUID().uuidString).mov"),profile:invalid)
  assert(rejected.error != nil && recordingAssertions()==0,"Invalid settings must not acquire recording activity")
  print("PASS actual macOS recording assertions: native/helper failure, abandonment and invalid profile")
 }
}
