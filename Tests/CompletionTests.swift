import Foundation
@main struct CompletionTests {
 static func main()throws{
  let url=URL(fileURLWithPath:"/tmp/partial.mkv")
  let result=RecordingCompletion(url:url,error:"Recording cannot keep up")
  assert(result.status=="Recording error");assert(result.detail.contains("cannot keep up"));assert(result.url==url)
  let p=Process();p.executableURL=URL(fileURLWithPath:"/bin/sleep");p.arguments=["60"];try p.run();kill(p.processIdentifier,SIGSTOP);ProcessLifecycle.stop(p,grace:0.05);assert(!p.isRunning)
  let pipe=Pipe();let reader=ProcessOutput(pipe:pipe,capacity:1024)
  let finalLine="SAVED /tmp/録画_part002.mkv\n"
  let bytes=Data(finalLine.utf8)
  DispatchQueue.global().async {
   for byte in bytes {try! pipe.fileHandleForWriting.write(contentsOf:Data([byte]))}
   try! pipe.fileHandleForWriting.close()
  }
  assert(reader.waitForEOF());assert(reader.text==finalLine)
  print("PASS EOF drain and fragmented UTF-8;  partial-file errors and stopped-child cleanup")
 }
}
