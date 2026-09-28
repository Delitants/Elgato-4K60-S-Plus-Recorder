import Foundation
@main struct HardwareCQProfileTests {
 static func profile(_ edits:[String:Any]=[:]) throws -> RecordingProfile {
  var values:[String:Any]=["codec":2,"encoder":1,"audio":1,"rateControl":"cq","hardwareQuality":65]
  values.merge(edits){_,new in new}
  return try JSONDecoder().decode(RecordingProfile.self,from:JSONSerialization.data(withJSONObject:values))
 }
 static func invalid(_ values:[String:Any]) throws {
  let p=try profile(values)
  do{try p.validate();throw NSError(domain:"Accepted invalid CQ profile",code:1)}catch let error as RecorderError{assert(!error.message.isEmpty)}
 }
 static func run() throws {
  for codec in [1,2] {for encoder in [0,1] {for container in 0...3 {
   let p=try profile(["codec":codec,"encoder":encoder,"container":container])
   try p.validate();assert(p.usesHelper,"CQ must reach the quality-aware helper for every container")
   #if arch(arm64)
   try p.validateRecording()
   #else
   do{try p.validateRecording();throw NSError(domain:"Intel CQ accepted",code:1)}catch let error as RecorderError{assert(error.message.contains("Apple Silicon"))}
   #endif
  }}}
  for value in [0,100] {try profile(["hardwareQuality":value]).validate()}
  // Inactive bitrate/CRF fields must not block applying hardware CQ.
  try profile(["videoMbps":0,"quality":63]).validate()
  let inactiveExtreme=try profile(["videoMbps":Int.max])
  try inactiveExtreme.validate();assert(inactiveExtreme.helperVideoBitrate==0,"CQ must ignore inactive bitrate without multiplying or overflowing")
  try profile(["rateControl":"abr","hardwareQuality":101]).validateRecording()
  for value in [-1,101] {try invalid(["hardwareQuality":value])}
  try invalid(["encoder":2])
  for codec in [0,3,4] {try invalid(["codec":codec,"container":2])}
  let saved=try profile(["quality":17,"hardwareQuality":80])
  let data=try JSONEncoder().encode(saved)
  let restored=try JSONDecoder().decode(RecordingProfile.self,from:data)
  try restored.validate()
  let fields=try JSONSerialization.jsonObject(with:JSONEncoder().encode(restored)) as! [String:Any]
  assert(fields["quality"] as? Int == 17 && fields["hardwareQuality"] as? Int == 80,"CRF and hardware quality must round-trip independently")
  let legacy=try JSONDecoder().decode(RecordingProfile.self,from:Data("{\"codec\":1,\"encoder\":1,\"videoMbps\":7,\"rateControl\":\"abr\"}".utf8))
  try legacy.validateRecording();assert(legacy.videoMbps==7 && legacy.rateControl == .abr)
  print("PASS hardware CQ profile migration, routing, independent quality values, ranges and platform/codec guards")
 }
 static func main(){do{try run()}catch{print("FAIL hardware CQ profiles:",error);exit(1)}}
}
