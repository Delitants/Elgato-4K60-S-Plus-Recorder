import Foundation
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func block(_ seq: UInt8, _ type: UInt8, _ payload: Data) -> Data {
    var b=Data([255,254,253,seq,type,UInt8(payload.count&255),UInt8(payload.count>>8)])
    b.append(payload); b.append(Data(repeating:0,count:1024-b.count)); return b
}
func header(_ timestamp: UInt64, _ size: UInt32) -> Data {
    var d=Data([1]); for v in [timestamp,timestamp] { for s in stride(from:0,to:64,by:8){d.append(UInt8(truncatingIfNeeded:v>>s))} }
    for s in stride(from:0,to:32,by:8){d.append(UInt8(truncatingIfNeeded:size>>s))}; return d
}
@main struct ParserTests {
 static func main() throws {
    if CommandLine.arguments.count>1 {
    let fixture=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
    let p=PacketParser();let frames=p.feed(fixture)
    require(frames.filter{$0.type==0xc1}.count==513,"real capture must produce 513 complete video frames")
    require(frames.filter{$0.type==0xc3}.count==401,"real capture must produce 401 complete audio frames")
    require(frames.first?.timestamp==6295567485,"preserve device timestamps")
    let q=PacketParser();var fragmented=[DeviceFrame]();var offset=0
    while offset<fixture.count { let end=min(offset+733,fixture.count);fragmented += q.feed(fixture.subdata(in:offset..<end));offset=end }
    require(fragmented.map{$0.data}==frames.map{$0.data},"arbitrary USB read boundaries must preserve frames")
    }
    let missing=PacketParser()
    var start=header(1000,2000);start.append(Data(repeating:7,count:996))
    require(missing.feed(block(0,0xc1,start)+block(2,0xc1,Data(repeating:8,count:1004))).isEmpty,"missing continuation must discard incomplete frame")
    let huge=PacketParser()
    require(huge.feed(block(0,0xc1,header(1000,UInt32.max))).isEmpty,"reject unbounded advertised lengths")
    let sync=PacketParser();var small=header(1234,3);small.append(contentsOf:[1,2,3])
    let recovered=sync.feed(Data([17,18,19])+block(0,0xc1,small))
    require(recovered.count==1 && recovered[0].data==Data([1,2,3]),"recover block alignment after garbage")
    let wrap=PacketParser();let size=996+256*1017;var bytes=Data();var h=header(9000,UInt32(size));h.append(Data(repeating:9,count:996));bytes.append(block(0,0xc1,h))
    for i in 1...256 {bytes.append(block(UInt8(1+(i-1)%255),0xc1,Data(repeating:9,count:1017)))}
    let wrapped=wrap.feed(bytes);require(wrapped.count==1 && wrapped[0].data.count==size,"counter wrap must not truncate large video frames")
    print("PASS: parser regressions (and original capture fixture when supplied)")
 }
}
