import Foundation
import CoreMedia

struct VideoRate: Equatable {
    let numerator:Int32, denominator:Int32
    var fps:Double {Double(numerator)/Double(denominator)}
    var duration:CMTime {CMTime(value:Int64(denominator),timescale:numerator)}
    var label:String {denominator==1 ? String(numerator) : String(format:"%.3f",fps).replacingOccurrences(of:"0+$",with:"",options:.regularExpression)}
    static let standard:[VideoRate] = [(15,1),(24000,1001),(24,1),(25,1),(30000,1001),(30,1),(50,1),(60000,1001),(60,1)].map{VideoRate(numerator:$0.0,denominator:$0.1)}
    static func measured(period:Double)->VideoRate? {
        guard period.isFinite,period>0 else{return nil}
        let fps=1/period
        guard fps>=1,fps<=240 else{return nil}
        if let closest=standard.min(by:{abs($0.fps-fps)<abs($1.fps-fps)}),abs(closest.fps-fps)/fps<0.005{return closest}
        return VideoRate(numerator:Int32((fps*1000).rounded()),denominator:1000)
    }
}
enum FrameRateChoice:String,Codable,CaseIterable {
    case source, fps15="15",fps23976="23.976",fps24="24",fps25="25",fps2997="29.97",fps30="30",fps50="50",fps5994="59.94",fps60="60"
    var rate:VideoRate? {guard self != .source else{return nil};return VideoRate.standard[Self.allCases.firstIndex(of:self)!-1]}
    var title:String {self == .source ? "Match incoming stream" : rawValue+" fps"}
}

/// Device timestamps, not USB arrival times, determine the encoded-stream cadence.
/// This does not identify a physical HDMI signal if the encoder repeats frames.
final class FrameRateTracker {
    private var previous:UInt64?,intervals=[Double]()
    private(set) var rate:VideoRate?
    init(initialRate:VideoRate?=nil){rate=initialRate}
    func observe(_ timestamp:UInt64) {
        defer{previous=timestamp}
        guard let previous else{return}
        guard timestamp>previous else{intervals.removeAll();rate=nil;return}
        let delta=Double(timestamp-previous)
        guard delta>=4000,delta<=1_000_000 else{intervals.removeAll();rate=nil;return}
        intervals.append(delta);if intervals.count>90{intervals.removeFirst()}
        guard intervals.count>=30 else{return}
        let ordered=intervals.sorted(),median=ordered[ordered.count/2]
        // Fit the timestamp timeline rather than averaging only short intervals.
        // This tolerates the encoder's alternating timing jitter and accounts for
        // isolated missing frames without declaring a lower source rate.
        let baseline=rate.map{1e6/$0.fps} ?? median
        var x=0.0,y=0.0,sx=0.0,sy=0.0,sxx=0.0,sxy=0.0
        for delta in intervals {
            x += delta>median*1.6 ? (delta/baseline).rounded() : 1
            y += delta;sx+=x;sy+=y;sxx+=x*x;sxy+=x*y
        }
        let count=Double(intervals.count+1),denominator=count*sxx-sx*sx
        if denominator>0 {rate=VideoRate.measured(period:(count*sxy-sx*sy)/denominator/1e6)}
    }
}

/// Selects at most one source frame per rational output interval. Gaps remain gaps;
/// it never duplicates frames or changes the timeline's speed.
struct FrameSelector {
    private var origin:Int64?,lastSlot:Int64 = -1,lastPTS:Int64?,rate:VideoRate?
    mutating func select(timestamp:Int64,rate:VideoRate)->Int64? {
        if self.rate != rate || (lastPTS != nil && timestamp<lastPTS!) {origin=nil;lastSlot = -1;self.rate=rate}
        lastPTS=timestamp
        if origin==nil{origin=timestamp}
        let elapsed=timestamp-origin!
        // One microsecond tolerance handles quantized device timestamps.
        let slot=Int64((Double(elapsed)+1)*Double(rate.numerator)/(1e6*Double(rate.denominator)))
        guard slot>lastSlot else{return nil};lastSlot=slot
        return origin!+Int64((Double(slot)*1e6*Double(rate.denominator)/Double(rate.numerator)).rounded())
    }
}
