// Explicit developer-only device test. Requires an idle connected 4K60 S+ delivering ~60 fps.
import Foundation
@main struct LiveFPSProbe {
 static func main() {
  guard CommandLine.arguments.count==2 else{fatalError("Output recording path required")}
  let engine=CaptureEngine();var p=RecordingProfile()
  p.container=2;p.codec=1;p.encoder=1;p.audio=3;p.outputFPS = .fps30
  p.ndiEnabled=true;p.ndiName="Elgato FPS test";p.ndiScale=1
  engine.setProfile(p);engine.setPreview(video:true,audio:false,volume:0);engine.connect()
  let start=Date();var started=false,lastReport=Date.distantPast,frames=0,firstPreview:Date?,lastPreview:Date?,finished=false
  while Date().timeIntervalSince(start)<25 {
   let(s,frame)=engine.snapshot()
   if !frame.isEmpty {frames+=frame.count;if firstPreview==nil{firstPreview=Date()};lastPreview=Date()}
   if Date().timeIntervalSince(lastReport)>1{print(s.status,"|",s.format,"|",s.detail);fflush(stdout);lastReport=Date()}
   if !started && Date().timeIntervalSince(start)>4 && s.connected {engine.startRecording(URL(fileURLWithPath:CommandLine.arguments[1]),limit:4);started=true}
   if started && !s.recording && !s.saving && (s.lastFile != nil || s.status.contains("error")) {print("RESULT",s.status,s.detail);finished=s.lastFile != nil && !s.status.contains("error");break}
   RunLoop.current.run(until:Date().addingTimeInterval(0.005))
  }
  let sem=DispatchSemaphore(value:0);engine.disconnect{sem.signal()};_ = sem.wait(timeout:.now()+10)
  if let firstPreview,let lastPreview {let fps=Double(frames-1)/lastPreview.timeIntervalSince(firstPreview);print("PREVIEW_FPS",fps,"FRAMES",frames);if fps<27||fps>31{exit(2)}}else{exit(3)}
  exit(finished ? 0:1)
 }
}
