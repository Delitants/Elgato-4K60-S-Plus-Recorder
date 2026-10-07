import Foundation
@main struct H264LevelProfileTests {
 static func profile(_ fields:[String:Any]) throws -> RecordingProfile {try JSONDecoder().decode(RecordingProfile.self,from:JSONSerialization.data(withJSONObject:fields))}
 static func invalid(_ fields:[String:Any]) throws {do{try profile(fields).validate();throw NSError(domain:"Invalid level accepted",code:1)}catch is RecorderError{}}
 static func main() throws {
  let old=try profile(["codec":1,"audio":1])
  let legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as! [String:Any]
  precondition(legacy["h264Level"] as? String == "auto","Legacy settings must default H.264 level to Auto")
  for level in ["3.0","3.1","3.2","4.0","4.1","4.2","5.0","5.1","5.2"] {
   for encoder in 0...2 {for container in 0...3 {
    let p=try profile(["codec":1,"audio":1,"encoder":encoder,"container":container,"h264Level":level,"videoMbps":6])
    try p.validate();precondition(p.usesHelper,"Explicit levels must use level-aware encoder")
    let saved=try JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as! [String:Any]
    precondition(saved["h264Level"] as? String == level)
   }}
  }
  try invalid(["codec":1,"h264Level":"9.9"])
  for codec in [0,2,3,4] {try invalid(["codec":codec,"container":2,"h264Level":"4.1"])}
  print("PASS H.264 level migration, persistence, routing and codec guards")
 }
}
