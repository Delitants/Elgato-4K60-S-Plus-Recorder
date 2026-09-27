import Foundation
@main struct ParserPerformanceTests {
 static func main() {
  let size=1_048_576,iterations=12
  var bytes=Data(),offset=0,sequence:UInt8=0
  while offset<size {
   var payload=Data()
   if offset==0 {
    payload.append(1)
    for _ in 0..<2 {for shift in stride(from:0,to:64,by:8){payload.append(UInt8(truncatingIfNeeded:UInt64(1000)>>shift))}}
    for shift in stride(from:0,to:32,by:8){payload.append(UInt8(truncatingIfNeeded:size>>shift))}
   }
   let n=min(1017-payload.count,size-offset)
   payload.append(Data(repeating:0x57,count:n));offset+=n
   var packet=Data([255,254,253,sequence,0xc1,UInt8(payload.count&255),UInt8(payload.count>>8)])
   packet.append(payload);packet.append(Data(repeating:0,count:1024-packet.count));bytes.append(packet)
   sequence=sequence==255 ? 1 : sequence+1
  }
  // Match live 2048-byte USB reads, not a single giant feed call.
  let chunks=stride(from:0,to:bytes.count,by:2048).map{bytes.subdata(in:$0..<min($0+2048,bytes.count))}
  let parser=PacketParser();var count=0,retained:Data?
  let start=ProcessInfo.processInfo.systemUptime
  for _ in 0..<iterations {
   for chunk in chunks {
    for frame in parser.feed(chunk) {
     guard frame.data.count==size,frame.data.first==0x57,frame.data.last==0x57 else{fatalError("Corrupt frame")}
     if retained==nil{retained=frame.data};count+=1
    }
   }
  }
  let elapsed=ProcessInfo.processInfo.systemUptime-start
  let rate=Double(size*iterations)/elapsed/1_000_000
  guard count==iterations,parser.discarded==0,retained==Data(repeating:0x57,count:size) else{fatalError("Frame integrity failed")}
  print(String(format:"Reassembly: %.1f MB/s; %.3f s for %d large frames",rate,elapsed,count))
  // 2x headroom above the device's 200 Mbps maximum, on the target Mac.
  guard rate>=50 else {fputs("FAIL: parser cannot sustain 2x maximum capture bitrate\n",stderr);exit(1)}
  print("PASS: large-frame reassembly throughput and retained-frame integrity")
 }
}
