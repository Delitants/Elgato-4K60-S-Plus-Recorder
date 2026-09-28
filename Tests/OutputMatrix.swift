import Foundation
struct Fixture:Decodable {let type:UInt8;let timestamp:UInt64;let data:Data}
@main struct OutputMatrix {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);let fixtures=try JSONDecoder().decode([Fixture].self,from:Data(contentsOf:root.appendingPathComponent("frames.json")))
  let only=CommandLine.arguments.count>2 ? CommandLine.arguments[2]:"all"
  let hevc=only.contains("hevc") || only=="hdr"
  var cases=[(String,RecordingProfile)](),rejected=0
  for container in 0...3 {for codec in 0...4 {for audio in 0...4 {for encoder in 0...2 {for decoder in 0...2 {
   var p=RecordingProfile();p.captureHEVC=hevc;p.container=container;p.codec=codec;p.audio=audio;p.encoder=encoder;p.decoder=decoder
   let id="c\(container)-v\(codec)-a\(audio)-e\(encoder)-d\(decoder)"
   do{try p.validateRecording();cases.append((id,p))}catch{rejected+=1}
  }}}}}
  if only=="controls" {
   cases=[]
   func add(_ id:String,_ p:RecordingProfile){do{try p.validateRecording();cases.append((id,p))}catch{rejected+=1}}
   var anchor=RecordingProfile();anchor.container=2;anchor.codec=1;anchor.audio=1;anchor.encoder=2
   for codec in [1,2,4] {for rc in RateControl.allCases {var p=anchor;p.codec=codec;p.rateControl=rc;add("rate-v\(codec)-\(rc.rawValue)",p)}}
   for codec in [1,2] {for count in 0...4 {var p=anchor;p.codec=codec;p.bFrames=count;add("bframes-v\(codec)-\(count)",p)}}
   for count in 0...4 {var p=anchor;p.codec=2;p.encoder=1;p.bFrames=count;add("hardware-hevc-b\(count)",p)}
   for codec in [1,2,3,4] {
    let profiles=codec==1 ? ["auto","baseline","main","high"]:codec==2 ? ["auto","main","main10"]:codec==3 ? ["auto","proxy","lt","standard","hq"]:["auto","main"]
    for name in profiles{var p=anchor;p.codec=codec;p.videoProfile=name;if codec==3{p.encoder=1};add("profile-v\(codec)-\(name)",p)}
    if codec != 3 {let presets=codec==4 ? ["auto"]+(0...13).map(String.init):["auto","ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow"]
     for name in presets {var p=anchor;p.codec=codec;p.preset=name;add("preset-v\(codec)-\(name)",p)}}
   }
   for audio in [3,4] {for compression in 0...(audio==3 ? 10:12) {var p=anchor;p.codec=0;p.audio=audio;p.compressionLevel=compression;add("audio-a\(audio)-level\(compression)",p)}}
   for mode in ["vbr","cbr","constrained"] {for rate in [64,192,320] {var p=anchor;p.codec=0;p.audio=3;p.audioMode=mode;p.audioKbps=rate;add("opus-\(mode)-\(rate)",p)}}
   for encoder in [1,2] {for codec in [1,2] {for aq in AQMode.allCases{var p=anchor;p.encoder=encoder;p.codec=codec;p.spatialAQ=aq;add("aq-e\(encoder)-v\(codec)-\(aq.rawValue)",p)}}}
   for rate in FrameRateChoice.allCases {var p=anchor;p.encoder=1;p.outputFPS=rate;add("fps-\(rate.rawValue)",p)}
   for source in FrameRateChoice.allCases {var p=anchor;p.encoder=1;p.sourceFPS=source;p.outputFPS = .fps30;add("source-\(source.rawValue)",p)}
   for filter in ScalingFilter.allCases {var p=anchor;p.scalingFilter=filter;p.scale=2;add("scale-\(filter.rawValue)",p)}
   for key in [0,1,2,60] {var p=anchor;p.keyframeSeconds=key;add("key-\(key)",p)}
  }
  if only=="hardware" {
   cases=[]
   for codec in [1,2] {for encoder in [0,1] {for rc in [RateControl.abr,.cbr] {
    for profile in (codec==1 ? ["auto","baseline","main","high"]:["auto","main","main10"]) {
     var p=RecordingProfile();p.container=2;p.audio=1;p.codec=codec;p.encoder=encoder;p.rateControl=rc;p.videoProfile=profile
     try p.validateRecording();cases.append(("hardware-v\(codec)-e\(encoder)-\(rc.rawValue)-\(profile)",p))
    }
   }}}
   for codec in [1,2] {for rc in [RateControl.abr,.cbr] {for rate in [1,200] {
    var p=RecordingProfile();p.container=2;p.audio=1;p.codec=codec;p.encoder=1;p.rateControl=rc;p.videoMbps=rate
    try p.validateRecording();cases.append(("bitrate-v\(codec)-\(rc.rawValue)-\(rate)",p))
   }}}
   for container in [0,2] {for rate in [64,320] {var p=RecordingProfile();p.container=container;p.audio=1;p.audioKbps=rate;cases.append(("aac-c\(container)-\(rate)",p))}}
  }
  if only=="hdr" {
   cases=[]
   for container in 0...3 {var p=RecordingProfile();p.captureHEVC=true;p.container=container;p.audio=1;cases.append(("hdr-original-c\(container)",p))}
   for codec in 1...4 {var p=RecordingProfile();p.captureHEVC=true;p.codec=codec;p.container=2;p.audio=1;p.encoder=codec==4 ? 2:1;cases.append(("hdr-reject-v\(codec)",p))}
  }
  if only=="4k" {
   cases=[]
   for codec in 0...3 {for scale in 0...2 {for filter in ScalingFilter.allCases {
    var p=RecordingProfile();p.capture4K=true;p.container=2;p.codec=codec;p.audio=1;p.encoder=1;p.scale=scale;p.scalingFilter=filter
    if codec != 0 {p.outputFPS = .fps30}
    do{try p.validateRecording();cases.append(("4k-v\(codec)-s\(scale)-\(filter.rawValue)",p))}catch{}
   }}}
   for codec in [1,2,4] {for scale in 0...2 {
    var p=RecordingProfile();p.capture4K=true;p.container=2;p.codec=codec;p.audio=1;p.encoder=2;p.scale=scale;p.outputFPS = .fps15;p.preset=codec==4 ? "13":"ultrafast"
    try p.validateRecording();cases.append(("4k-software-v\(codec)-s\(scale)",p))
   }}
  }
  if only=="user" {var p=try JSONDecoder().decode(RecordingProfile.self,from:Data(contentsOf:root.appendingPathComponent("user-profile.json")));p.ndiEnabled=false;cases=[("user",p)]}
  if let selected=ProcessInfo.processInfo.environment["ELGATO_MATRIX_CASE"]{cases=cases.filter{$0.0==selected};precondition(!cases.isEmpty,"Unknown matrix case")}
  print("MATRIX accepted=\(cases.count) rejected=\(rejected)");fflush(stdout)
  for (id,p) in cases {
   let url=root.appendingPathComponent(id+"."+p.fileExtension)
   let sink=RecordingSink(url:url,profile:p,initialRate:VideoRate(numerator:60,denominator:1))
   let start=ProcessInfo.processInfo.systemUptime
   for f in fixtures {
    let delay=Double(f.timestamp)/1e6-(ProcessInfo.processInfo.systemUptime-start)
    if delay>0{Thread.sleep(forTimeInterval:delay)}
    if !sink.offer(DeviceFrame(type:f.type,timestamp:f.timestamp,data:f.data)){break}
   }
   let done=DispatchSemaphore(value:0);var failure:String?,saved:URL?
   sink.finish{u,e in saved=u;failure=e;done.signal()}
   guard done.wait(timeout:.now()+40) == .success else{fatalError("Finalize timeout \(id)")}
   let result:[String:Any] = ["id":id,"profile":try JSONSerialization.jsonObject(with:JSONEncoder().encode(p)),"error":failure ?? "","file":saved?.path ?? "","frames":sink.videoFrames,"seconds":ProcessInfo.processInfo.systemUptime-start]
   let line=try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]);print(String(data:line,encoding:.utf8)!);fflush(stdout)
  }
 }
}
