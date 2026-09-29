import Foundation
@main struct CompletionTests {
 static func main()throws{
  let url=URL(fileURLWithPath:"/tmp/partial.mkv")
  let result=RecordingCompletion(url:url,error:"Recording cannot keep up")
  assert(result.status=="Recording error");assert(result.detail.contains("cannot keep up"));assert(result.url==url)
  assert(BackendProgress.warning(in:"FILE /tmp/file.mkv\nWARNING 1 · Clock corrected\n")=="1 · Clock corrected")
  assert(BackendProgress.warning(in:"WARNING unfinished")==nil,"Partial pipe lines must not appear as complete warnings")
  assert(BackendProgress.warning(in:"WARNING 1 · Old\nSAVED /tmp/file\nWARNING 2 · New\n")=="2 · New")
  let p=Process();p.executableURL=URL(fileURLWithPath:"/bin/sleep");p.arguments=["60"];try p.run();kill(p.processIdentifier,SIGSTOP);ProcessLifecycle.stop(p,grace:0.05);assert(!p.isRunning)
  let pipe=Pipe();let reader=ProcessOutput(pipe:pipe,capacity:1024)
  let finalLine="SAVED /tmp/録画_part002.mkv\n"
  let bytes=Data(finalLine.utf8)
  DispatchQueue.global().async {
   for byte in bytes {try! pipe.fileHandleForWriting.write(contentsOf:Data([byte]))}
   try! pipe.fileHandleForWriting.close()
  }
  assert(reader.waitForEOF());assert(reader.text==finalLine)
  let warningPipe=Pipe();let bounded=ProcessOutput(pipe:warningPipe,capacity:128)
  try warningPipe.fileHandleForWriting.write(contentsOf:Data("WARNING 1 · Recovered\n".utf8))
  Thread.sleep(forTimeInterval:0.05)
  for _ in 0..<100{try warningPipe.fileHandleForWriting.write(contentsOf:Data("SAVED /tmp/part.mkv\n".utf8))}
  try warningPipe.fileHandleForWriting.close();assert(bounded.waitForEOF())
  assert(!bounded.text.contains("WARNING"));assert(bounded.latestWarning=="1 · Recovered","Warnings must survive bounded log eviction")
  print("PASS EOF drain and fragmented UTF-8;  partial-file errors and stopped-child cleanup")
 }
}
