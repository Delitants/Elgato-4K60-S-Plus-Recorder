import Foundation
import AVFoundation
import VideoToolbox

enum RateControl:String,Codable,CaseIterable {case abr,cbr,crf,cq}
enum ScalingFilter:String,Codable,CaseIterable {case disabled,bilinear,area,bicubic,lanczos}
enum AQMode:String,Codable,CaseIterable {case auto,enabled,disabled}
struct RecordingProfile:Codable {
    var capture4K=false, captureHEVC=false
    var sourceFPS=FrameRateChoice.source, outputFPS=FrameRateChoice.source
    var deviceMbps=40
    var container=0 // MOV, MP4
    var codec=0 // Original, H.264, HEVC, ProRes 422
    var encoder=0 // Auto, hardware, software
    var decoder=0 // Auto, hardware, software
    var scale=0 // Original, 1080p, 720p
    var videoMbps=20
    var audio=0 // PCM, AAC, ALAC
    var audioKbps=192
    var rateControl=RateControl.abr
    var quality=23, keyframeSeconds=0, bFrames=0
    var hardwareQuality=65
    var videoProfile="auto", preset="auto"
    var spatialAQ=AQMode.auto, scalingFilter=ScalingFilter.bicubic
    var audioMode="vbr", compressionLevel=5
    var splitMode=0, splitSeconds=600, splitMB=1024
    var ndiEnabled=false, ndiName="Elgato Recorder", ndiScale=1
    var fileExtension:String { ["mov","mp4","mkv","ts"][min(3,max(0,container))] }
    var usesHelper:Bool {(encoder==2 && transcodes) || sourceFPS != .source || outputFPS != .source || container>=2 || codec==4 || audio>=3 || rateControl != .abr || keyframeSeconds != 0 || bFrames != 0 || videoProfile != "auto" || preset != "auto" || spatialAQ != .auto || (scale != 0 && scalingFilter != .bicubic) || splitMode != 0}

    static var hardwareCQBuildSupported:Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    var recordingWarning:String? {
        if rateControl == .cq {
            if (codec != 1 && codec != 2) || encoder==2{return "Hardware CQ requires H.264 or HEVC with Automatic or Require hardware encoding."}
            if !Self.hardwareCQBuildSupported{return "Hardware CQ requires the native Apple Silicon app. The Intel build supports ABR/CBR or software CRF instead."}
        }
        if codec==1 && encoder != 2 && bFrames>0 {
            return "Hardware H.264/AVC B-frames are unavailable in this version because the hardware encoder can return invalid timestamps. Disable B-frames or choose Software encoding."
        }
        return nil
    }
    func validateRecording() throws {try validate();if let warning=recordingWarning{throw RecorderError(message:warning)}}
    var transcodes:Bool { codec != 0 }
    // CQ ignores the bitrate field entirely, including stale or out-of-range input.
    var helperVideoBitrate:Int {rateControl == .cq ? 0:videoMbps*1_000_000}
    func validate() throws {
        func require(_ ok:Bool,_ message:String)throws{if !ok{throw RecorderError(message:message)}}
        try require((0...3).contains(container) && (0...4).contains(codec) && (0...4).contains(audio),"Unknown codec or container.")
        try require((0...2).contains(encoder) && (0...2).contains(decoder) && (0...2).contains(scale),"Unknown encoder, decoder, or resolution.")
        try require((1...(captureHEVC ? 140 : 200)).contains(deviceMbps),"Device bitrate must be 1–200 Mbps for H.264, or 1–140 Mbps for HEVC.")
        try require(rateControl == .cq || (1...200).contains(videoMbps),"Video bitrate must be 1–200 Mbps.")
        try require((64...320).contains(audioKbps),"Audio bitrate must be 64–320 kbps.")
        try require(!(codec==3 && encoder==2),"Software ProRes is not supported. Choose Automatic or Require hardware.")
        try require(!(codec==0 && scale != 0),"Choose a Mac video encoder to rescale.")
        try require(!(codec==0 && (rateControl != .abr || keyframeSeconds != 0 || bFrames != 0 || videoProfile != "auto" || preset != "auto" || spatialAQ != .auto)),"Original video cannot change encoder controls.")
        try require(container != 1 || (audio==1 && codec != 3 && codec != 4),"MP4 currently requires AAC and H.264/HEVC.")
        try require(container != 0 || (audio<3 && codec != 4),"Use MKV for AV1, Opus, or FLAC.")
        try require(container != 3 || (audio==1 && codec != 3 && codec != 4),"MPEG-TS requires H.264/HEVC and AAC.")
        try require(!(container==1 && encoder==2 && rateControl == .cbr),"Software CBR with HRD requires MKV or MPEG-TS. Use ABR/CRF for MP4.")
        try require(codec != 4 || encoder != 1,"AV1 hardware encoding is unavailable on this Mac.")
        try require(rateControl != .crf || ((codec==1 || codec==2) && encoder==2) || codec==4,"CRF requires software H.264, HEVC, or AV1.")
        try require(rateControl != .cq || ((codec==1 || codec==2) && encoder != 2),"Hardware CQ requires H.264 or HEVC with Automatic or Require hardware encoding.")
        try require(rateControl != .cq || (0...100).contains(hardwareQuality),"Hardware CQ quality must be 0–100. Higher means better quality and larger files; 100 is not lossless.")
        try require(rateControl == .cq || ((0...63).contains(quality) && ((codec==4) || quality<=51)),"Quality is outside the encoder range.")
        try require((0...60).contains(keyframeSeconds) && (0...4).contains(bFrames),"Keyframe interval must be Auto (0) or 1–60 seconds; B-frames 0–4.")
        try require(videoProfile != "baseline" || bFrames==0,"Baseline H.264 cannot use B-frames.")
        let profiles=codec==1 ? ["auto","baseline","main","high"] : codec==2 ? ["auto","main","main10"] : codec==3 ? ["auto","proxy","lt","standard","hq"] : codec==4 ? ["auto","main"] : ["auto"]
        try require(profiles.contains(videoProfile),"Unsupported video profile for this codec.")
        let presets=codec==4 ? ["auto"]+(0...13).map(String.init) : ["auto","ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow"]
        try require(presets.contains(preset),"Unsupported compression preset.")
        try require(preset=="auto" || encoder==2 || codec==4,"Compression presets require software encoding.")
        try require(codec != 4 || (bFrames==0 && spatialAQ == .auto && rateControl != .cbr),"AV1 currently supports ABR/CRF; B-frame and spatial AQ overrides are unavailable.")
        try require(codec != 3 || (rateControl == .abr && bFrames==0 && spatialAQ == .auto),"ProRes uses quality profiles, not rate control or B-frames.")
        try require((0...12).contains(compressionLevel) && (audio != 3 || compressionLevel<=10),"Compression level must be 0–12 for FLAC or 0–10 for Opus.")
        try require(["vbr","cbr","constrained"].contains(audioMode),"Unsupported audio bitrate mode.")
        try require((0...2).contains(splitMode) && splitSeconds>0 && splitMB>0,"Split duration and size must be positive.")
        try require((0...2).contains(ndiScale) && !ndiName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,"Choose an NDI name and valid output resolution.")
    }
    init() {}
    enum CodingKeys:String,CodingKey {case sourceFPS,outputFPS,capture4K,captureHEVC,deviceMbps,container,codec,encoder,decoder,scale,videoMbps,audio,audioKbps,rateControl,quality,hardwareQuality,keyframeSeconds,bFrames,videoProfile,preset,spatialAQ,scalingFilter,audioMode,compressionLevel,splitMode,splitSeconds,splitMB,ndiEnabled,ndiName,ndiScale}
    init(from sourceDecoder:Decoder)throws {
        let c=try sourceDecoder.container(keyedBy:CodingKeys.self)
        sourceFPS=try c.decodeIfPresent(FrameRateChoice.self,forKey:.sourceFPS) ?? .source
        outputFPS=try c.decodeIfPresent(FrameRateChoice.self,forKey:.outputFPS) ?? .source
        capture4K=try c.decodeIfPresent(Bool.self,forKey:.capture4K) ?? capture4K
        captureHEVC=try c.decodeIfPresent(Bool.self,forKey:.captureHEVC) ?? captureHEVC
        deviceMbps=try c.decodeIfPresent(Int.self,forKey:.deviceMbps) ?? deviceMbps
        container=try c.decodeIfPresent(Int.self,forKey:.container) ?? container
        codec=try c.decodeIfPresent(Int.self,forKey:.codec) ?? codec
        encoder=try c.decodeIfPresent(Int.self,forKey:.encoder) ?? encoder
        decoder=try c.decodeIfPresent(Int.self,forKey:.decoder) ?? decoder
        scale=try c.decodeIfPresent(Int.self,forKey:.scale) ?? scale
        videoMbps=try c.decodeIfPresent(Int.self,forKey:.videoMbps) ?? videoMbps
        audio=try c.decodeIfPresent(Int.self,forKey:.audio) ?? audio
        audioKbps=try c.decodeIfPresent(Int.self,forKey:.audioKbps) ?? audioKbps
        rateControl=try c.decodeIfPresent(RateControl.self,forKey:.rateControl) ?? rateControl
        quality=try c.decodeIfPresent(Int.self,forKey:.quality) ?? quality
        hardwareQuality=try c.decodeIfPresent(Int.self,forKey:.hardwareQuality) ?? hardwareQuality
        keyframeSeconds=try c.decodeIfPresent(Int.self,forKey:.keyframeSeconds) ?? keyframeSeconds
        bFrames=try c.decodeIfPresent(Int.self,forKey:.bFrames) ?? bFrames
        videoProfile=try c.decodeIfPresent(String.self,forKey:.videoProfile) ?? videoProfile
        preset=try c.decodeIfPresent(String.self,forKey:.preset) ?? preset
        spatialAQ=try c.decodeIfPresent(AQMode.self,forKey:.spatialAQ) ?? spatialAQ
        scalingFilter=try c.decodeIfPresent(ScalingFilter.self,forKey:.scalingFilter) ?? scalingFilter
        audioMode=try c.decodeIfPresent(String.self,forKey:.audioMode) ?? audioMode
        compressionLevel=try c.decodeIfPresent(Int.self,forKey:.compressionLevel) ?? compressionLevel
        splitMode=try c.decodeIfPresent(Int.self,forKey:.splitMode) ?? splitMode
        splitSeconds=try c.decodeIfPresent(Int.self,forKey:.splitSeconds) ?? splitSeconds
        splitMB=try c.decodeIfPresent(Int.self,forKey:.splitMB) ?? splitMB
        ndiEnabled=try c.decodeIfPresent(Bool.self,forKey:.ndiEnabled) ?? ndiEnabled
        ndiName=try c.decodeIfPresent(String.self,forKey:.ndiName) ?? ndiName
        ndiScale=try c.decodeIfPresent(Int.self,forKey:.ndiScale) ?? ndiScale
    }
    func effectiveRate(incoming:VideoRate)->VideoRate {
        [incoming,sourceFPS.rate,outputFPS.rate].compactMap{$0}.min(by:{$0.fps<$1.fps})!
    }
    func videoSettings(format:CMVideoFormatDescription,frameRate:Double?=nil) throws -> [String:Any]? {
        guard transcodes else { return nil }
        let dimensions=CMVideoFormatDescriptionGetDimensions(format)
        let targetHeight=scale==1 ? 1080 : scale==2 ? 720 : Int(dimensions.height)
        let height=min(Int(dimensions.height),targetHeight)
        let width=Int((Double(dimensions.width)*Double(height)/Double(dimensions.height))/2)*2
        let transfer=CMFormatDescriptionGetExtension(format,extensionKey:kCMFormatDescriptionExtension_TransferFunction) as? String
        let hdr=transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
        if hdr { throw RecorderError(message:"Use Original video for HDR preservation. HDR transcoding and tone mapping are not yet validated.") }
        let type:AVVideoCodecType=codec==1 ? .h264 : codec==2 ? .hevc : .proRes422
        var compression:[String:Any]=[:]
        if let frameRate {compression[AVVideoExpectedSourceFrameRateKey]=frameRate}
        if codec != 3 { compression[AVVideoAverageBitRateKey]=videoMbps*1_000_000;compression[AVVideoAllowFrameReorderingKey]=false }
        var spec:[String:Any]=[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String:encoder != 2]
        if encoder==1 { spec[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String]=true }
        return [AVVideoCodecKey:type,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:compression,AVVideoEncoderSpecificationKey:spec]
    }
    var audioSettings:[String:Any]? {
        if audio==0 { return nil }
        var settings:[String:Any]=[AVFormatIDKey:audio==1 ? kAudioFormatMPEG4AAC : kAudioFormatAppleLossless,AVSampleRateKey:48000,AVNumberOfChannelsKey:2]
        if audio==1 { settings[AVEncoderBitRateKey]=audioKbps*1000 }
        else { settings[AVEncoderBitDepthHintKey]=16 }
        return settings
    }
}
