import Foundation
struct DeviceFrame { let type: UInt8; let timestamp: UInt64; let data: Data }
final class PacketParser {
    // Keep one owner of the accumulating Data buffer. A value-type Assembly copied
    // out of the dictionary forces Data to copy the entire frame on every packet.
    private final class Assembly {
        let timestamp: UInt64, size: Int
        var sequence: UInt8=0
        var data=Data()
        init(timestamp:UInt64,size:Int) {
            self.timestamp=timestamp;self.size=size
            data.reserveCapacity(size)
        }
    }
    private var pending=[UInt8]()
    private var streams=[UInt8:Assembly]()
    private(set) var discarded=0
    func feed(_ data: Data) -> [DeviceFrame] {
        pending.append(contentsOf:data); var offset=0; var result=[DeviceFrame]()
        while pending.count-offset>=1024 {
            guard pending[offset]==255 && pending[offset+1]==254 && pending[offset+2]==253 else {offset+=1;continue}
            let seq=pending[offset+3],type=pending[offset+4]
            let count=Int(pending[offset+5]) | Int(pending[offset+6])<<8
            guard count>0 && count<=1017 else {offset+=1;discarded+=1;continue}
            let payload=Array(pending[(offset+7)..<(offset+7+count)]);offset+=1024
            guard type==0xc1 || type==0xc3 else {continue}
            var start=0
            func number(_ pos:Int,_ size:Int)->UInt64 {
                var v:UInt64=0;for i in 0..<size{v |= UInt64(payload[pos+i]) << (8*i)};return v
            }
            if seq==0 && count>=21 && number(1,8)==number(9,8) {
                let size=Int(number(17,4))
                if size>0 && size<=8*1024*1024 {
                    if streams[type] != nil {discarded+=1}
                    streams[type]=Assembly(timestamp:number(1,8),size:size)
                    start=21
                } else if streams[type]==nil {discarded+=1;continue}
            }
            guard let a=streams[type] else {continue}
            guard a.sequence==seq else {streams[type]=nil;discarded+=1;continue}
            let available=count-start,needed=a.size-a.data.count
            guard available<=needed else {streams[type]=nil;discarded+=1;continue}
            a.data.append(contentsOf:payload[start..<count]);a.sequence = seq == 255 ? 1 : seq+1
            if a.data.count==a.size {result.append(DeviceFrame(type:type,timestamp:a.timestamp,data:a.data));streams[type]=nil}
        }
        if offset>0 {pending.removeFirst(offset)}
        return result
    }
}
