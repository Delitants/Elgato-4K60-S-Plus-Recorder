import Foundation
@main struct AdvancedProfileTests {
 static func main() throws {
  func invalid(_ p:RecordingProfile){do{try p.validate();fatalError("accepted invalid settings")}catch{}}
  let p=try JSONDecoder().decode(RecordingProfile.self,from:Data("{\"capture4K\":true,\"container\":0,\"audio\":1}".utf8))
  assert(p.capture4K && p.audio==1 && p.keyframeSeconds==0 && p.rateControl == .abr)
  var q=p;q.container=2;q.codec=4;q.audio=3;try q.validate()
  q.audio=4;try q.validate();q.encoder=1;invalid(q);q.encoder=2
  q.container=3;invalid(q);q.codec=1;q.audio=1;try q.validate()
  q.videoProfile="baseline";q.bFrames=2;invalid(q)
  q.bFrames=0;q.videoProfile="auto";q.codec=0;q.scale=1;invalid(q)
  do {_ = try JSONDecoder().decode(RecordingProfile.self,from:Data("{\"rateControl\":\"bogus\"}".utf8));fatalError("unknown enum accepted")}catch{}
  var hardware=RecordingProfile();hardware.codec=1;hardware.encoder=1;hardware.bFrames=1
  do{try hardware.validateRecording();fatalError("Hardware H.264 B-frames must be rejected before writing a file")}catch{assert(error.localizedDescription.contains("B-frames"))}
  hardware.encoder=2;try hardware.validateRecording()
  hardware.encoder=1;hardware.bFrames=0;try hardware.validateRecording()
  var software=RecordingProfile();software.codec=2;software.encoder=2
  assert(software.usesHelper,"Explicit software HEVC must use the bundled software encoder across containers")
  print("PASS advanced migration and compatibility")
 }
}
