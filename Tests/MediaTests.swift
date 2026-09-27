import Foundation
import AVFoundation
@main struct MediaTests {
 static func main() throws {
    let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
    let frames=PacketParser().feed(data),converter=MediaConverter()
    let url=URL(fileURLWithPath:CommandLine.arguments[2])
    let recorder=MovieRecorder(url:url)
    for frame in frames {
        if let (sample,key)=try converter.convert(frame){try recorder.append(sample,type:frame.type,key:key,converter:converter)}
    }
    let sem=DispatchSemaphore(value:0)
    recorder.finish{u,e in
        if let e {fputs("FAIL: \(e)\n",stderr);exit(1)}
        guard u != nil else{exit(1)};sem.signal()
    }
    guard sem.wait(timeout:.now()+20) == .success else{fatalError("finalize timeout")}
    guard recorder.videoFrames==513,recorder.audioFrames>400000,recorder.dropped==0 else{fatalError("sample count mismatch")}
    print("PASS: native MOV writer: \(recorder.videoFrames) video frames; \(recorder.audioFrames) audio frames; dropped=\(recorder.dropped)")
 }
}
