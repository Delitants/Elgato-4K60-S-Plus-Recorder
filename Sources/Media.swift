import Foundation
import AVFoundation
import AudioToolbox

struct RecorderError: LocalizedError {
    let message:String
    var errorDescription:String? { message }
}
func check(_ status:OSStatus,_ operation:String) throws {
    if status != noErr {throw RecorderError(message:"\(operation) failed (\(status)).")}
}
func dataBlock(_ data:Data) throws -> CMBlockBuffer {
    var buffer:CMBlockBuffer?
    try check(CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:data.count,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:data.count,flags:0,blockBufferOut:&buffer),"Allocate media buffer")
    guard let buffer else {throw RecorderError(message:"No media buffer")}
    try data.withUnsafeBytes { bytes in
        try check(CMBlockBufferReplaceDataBytes(with:bytes.baseAddress!,blockBuffer:buffer,offsetIntoDestination:0,dataLength:data.count),"Copy media buffer")
    }
    return buffer
}
final class MediaConverter {
    private var sps:Data?,pps:Data?,vps:Data?
    let hevc:Bool
    let frameTiming:FrameRateTracker
    private(set) var videoFormat:CMVideoFormatDescription?
    private(set) var audioFormat:CMAudioFormatDescription?
    init(hevc:Bool=false,initialRate:VideoRate?=nil) {
        frameTiming=FrameRateTracker(initialRate:initialRate)
        self.hevc=hevc
        var asbd=AudioStreamBasicDescription(mSampleRate:48000,mFormatID:kAudioFormatLinearPCM,mFormatFlags:kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked,mBytesPerPacket:4,mFramesPerPacket:1,mBytesPerFrame:4,mChannelsPerFrame:2,mBitsPerChannel:16,mReserved:0)
        CMAudioFormatDescriptionCreate(allocator:kCFAllocatorDefault,asbd:&asbd,layoutSize:0,layout:nil,magicCookieSize:0,magicCookie:nil,extensions:nil,formatDescriptionOut:&audioFormat)
    }
    static func nals(_ data:Data)->[Data] {
        let bytes=[UInt8](data);var starts=[(Int,Int)]();var i=0
        while i+3<=bytes.count {
            if bytes[i]==0 && bytes[i+1]==0 {
                if bytes[i+2]==1 {starts.append((i,i+3));i+=3;continue}
                if i+3<bytes.count && bytes[i+2]==0 && bytes[i+3]==1 {starts.append((i,i+4));i+=4;continue}
            };i+=1
        }
        return starts.enumerated().compactMap{idx,item in
            let end=idx+1<starts.count ? starts[idx+1].0 : bytes.count
            return end>item.1 ? Data(bytes[item.1..<end]) : nil
        }
    }
    func convert(_ frame:DeviceFrame) throws -> (CMSampleBuffer,Bool)? {
        let pts=CMTime(value:Int64(frame.timestamp),timescale:1_000_000)
        if frame.type==0xc3 {
            guard !frame.data.isEmpty,frame.data.count%4==0,let format=audioFormat else{return nil}
            let block=try dataBlock(frame.data);var sample:CMSampleBuffer?
            var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:48000),presentationTimeStamp:pts,decodeTimeStamp:.invalid)
            var size=4
            try check(CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:format,sampleCount:frame.data.count/4,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:1,sampleSizeArray:&size,sampleBufferOut:&sample),"Create audio sample")
            return sample.map{($0,false)}
        }
        frameTiming.observe(frame.timestamp)
        var avcc=Data();var key=false;var changed=false
        for nal in Self.nals(frame.data) {
            let type=hevc ? (nal.first!>>1)&63 : nal.first!&31
            if hevc && type==32 && vps != nal {vps=nal;changed=true}
            if type==(hevc ? 33 : 7) && sps != nal{sps=nal;changed=true}
            if type==(hevc ? 34 : 8) && pps != nal{pps=nal;changed=true}
            if hevc ? (16...21).contains(type) : type==5 {key=true}
            var size=UInt32(nal.count).bigEndian
            withUnsafeBytes(of:&size){avcc.append(contentsOf:$0)};avcc.append(nal)
        }
        if changed,let sps,let pps {
            var format:CMFormatDescription?
            var sets=[sps,pps]
            if hevc { guard let vps else{return nil};sets.insert(vps,at:0) }
            let allocations=sets.map { data -> UnsafeMutablePointer<UInt8> in
                let p=UnsafeMutablePointer<UInt8>.allocate(capacity:data.count);data.copyBytes(to:p,count:data.count);return p
            }
            defer { allocations.forEach{$0.deallocate()} }
            var pointers=allocations.map{UnsafePointer($0)},sizes=sets.map{$0.count}
            let status:OSStatus
            if hevc { status=CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator:kCFAllocatorDefault,parameterSetCount:3,parameterSetPointers:&pointers,parameterSetSizes:&sizes,nalUnitHeaderLength:4,extensions:nil,formatDescriptionOut:&format) }
            else { status=CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator:kCFAllocatorDefault,parameterSetCount:2,parameterSetPointers:&pointers,parameterSetSizes:&sizes,nalUnitHeaderLength:4,formatDescriptionOut:&format) }
            try check(status,"Read video format");videoFormat=format
        }
        guard let format=videoFormat,!avcc.isEmpty else{return nil}
        let block=try dataBlock(avcc);var sample:CMSampleBuffer?
        var timing=CMSampleTimingInfo(duration:frameTiming.rate?.duration ?? .invalid,presentationTimeStamp:pts,decodeTimeStamp:pts)
        var size=avcc.count
        try check(CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:format,sampleCount:1,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:1,sampleSizeArray:&size,sampleBufferOut:&sample),"Create video sample")
        if let sample,let array=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:true) {
            let dict=unsafeBitCast(CFArrayGetValueAtIndex(array,0),to:CFMutableDictionary.self)
            CFDictionarySetValue(dict,Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),Unmanaged.passUnretained(key ? kCFBooleanFalse : kCFBooleanTrue).toOpaque())
        }
        return sample.map{($0,key)}
    }
}
final class MovieRecorder {
    private var writer:AVAssetWriter?
    private var video:AVAssetWriterInput?,audio:AVAssetWriterInput?
    private var origin:CMTime?
    private var sourceVideoFormat:CMVideoFormatDescription?
    private var lastVideo=CMTime.invalid,lastAudio=CMTime.invalid
    private(set) var videoFrames=0
    private(set) var audioFrames=0
    private(set) var dropped=0
    private(set) var duration:Double=0
    let url:URL
    let profile:RecordingProfile
    init(url:URL,profile:RecordingProfile=RecordingProfile()){self.url=url;self.profile=profile}
    func append(_ sample:CMSampleBuffer,type:UInt8,key:Bool,converter:MediaConverter) throws {
        if type==0xc1,let previous=sourceVideoFormat,let current=converter.videoFormat,
           !CMFormatDescriptionEqual(previous,otherFormatDescription:current) {
            throw RecorderError(message:"The HDMI video format or HDR metadata changed. Recording stopped to keep the file consistent; start a new recording for the new signal.")
        }
        if writer==nil {
            guard type==0xc1 && key,let vf=converter.videoFormat,let af=converter.audioFormat else{return}
            let w=try AVAssetWriter(outputURL:url,fileType:profile.container==0 ? .mov : .mp4)
            let videoSettings=try profile.videoSettings(format:vf,frameRate:converter.frameTiming.rate?.fps)
            let v=AVAssetWriterInput(mediaType:.video,outputSettings:videoSettings,sourceFormatHint:profile.transcodes ? CMSampleBufferGetFormatDescription(sample) : vf)
            let a=AVAssetWriterInput(mediaType:.audio,outputSettings:profile.audioSettings,sourceFormatHint:af)
            v.expectsMediaDataInRealTime=true;a.expectsMediaDataInRealTime=true
            guard w.canAdd(v),w.canAdd(a) else{throw RecorderError(message:"Cannot add recording tracks")}
            w.add(v);w.add(a);guard w.startWriting() else{throw w.error ?? RecorderError(message:"Cannot start file")}
            w.startSession(atSourceTime:.zero)
            sourceVideoFormat=vf;origin=CMSampleBufferGetPresentationTimeStamp(sample);writer=w;video=v;audio=a
        }
        guard let writer,let origin else{return}
        guard writer.status == .writing else{throw writer.error ?? RecorderError(message:"Recording stopped unexpectedly")}
        let timestamp=CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample),origin)
        guard timestamp >= .zero else{return}
        let last=type==0xc1 ? lastVideo : lastAudio
        guard !last.isValid || timestamp>last else {dropped+=1;return}
        let input=type==0xc1 ? video! : audio!
        // Allow bounded encoder startup/backpressure, never discard a compressed reference frame.
        let deadline=ProcessInfo.processInfo.systemUptime+0.1
        while !input.isReadyForMoreMediaData && writer.status == .writing && ProcessInfo.processInfo.systemUptime<deadline {Thread.sleep(forTimeInterval:0.001)}
        guard input.isReadyForMoreMediaData else {throw RecorderError(message:"The \(type==0xc1 ? "video" : "audio") encoder or disk cannot keep up (\(videoFrames) video frames, \(audioFrames) audio samples). Recording stopped to avoid dropping media. Lower the resolution/bitrate or select hardware encoding.")}
        var timing=CMSampleTimingInfo(duration:CMSampleBufferGetDuration(sample),presentationTimeStamp:timestamp,decodeTimeStamp:type==0xc1 ? timestamp : .invalid)
        if type==0xc3 {timing.duration=CMTime(value:1,timescale:48000)}
        var copy:CMSampleBuffer?
        try check(CMSampleBufferCreateCopyWithNewTiming(allocator:kCFAllocatorDefault,sampleBuffer:sample,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleBufferOut:&copy),"Timestamp recording")
        guard let copy,input.append(copy) else{throw writer.error ?? RecorderError(message:"Could not write media sample")}
        if type==0xc1 {lastVideo=timestamp;videoFrames+=1}else{lastAudio=timestamp;audioFrames+=CMSampleBufferGetNumSamples(sample)}
        duration=max(duration,timestamp.seconds)
    }
    func finish(_ completion:@escaping(URL?,String?)->Void){
        guard let writer else{completion(nil,"No video keyframe arrived; no recording was created.");return}
        guard writer.status == .writing else{completion(nil,writer.error?.localizedDescription ?? "Recording failed");return}
        video?.markAsFinished();audio?.markAsFinished()
        writer.finishWriting {
            completion(writer.status == .completed ? self.url : nil,writer.error?.localizedDescription)
        }
    }
}

import VideoToolbox
final class PreviewDecoder {
    private var session:VTDecompressionSession?
    var preference=0
    var tenBit=false
    private var waitingForKey=true
    private let outputLock=NSLock()
    private var decoded:CMSampleBuffer?
    private(set) var lastError:String?
    func takeFrame()->CMSampleBuffer? {outputLock.lock();defer{outputLock.unlock()};let frame=decoded;decoded=nil;return frame}
    var onFrame:((CMSampleBuffer)->Void)?
    func decode(_ sample:CMSampleBuffer,key:Bool=true,synchronous:Bool=false){
        if waitingForKey && !key {return};waitingForKey=false
        lastError=nil
        guard let format=CMSampleBufferGetFormatDescription(sample) else{return}
        if let s=session,!VTDecompressionSessionCanAcceptFormatDescription(s,formatDescription:format){close()}
        if session==nil {
            var callback=VTDecompressionOutputCallbackRecord(decompressionOutputCallback:{ref,_,status,_,image,pts,duration in
                guard status==noErr,let image,let ref else{return}
                let decoder=Unmanaged<PreviewDecoder>.fromOpaque(ref).takeUnretainedValue()
                #if PREVIEW_DIAGNOSTICS
                PreviewTrace.shared.event(2,pts.seconds)
                #endif
                var format:CMVideoFormatDescription?
                guard CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:image,formatDescriptionOut:&format)==noErr,let format else{return}
                var timing=CMSampleTimingInfo(duration:duration,presentationTimeStamp:pts,decodeTimeStamp:.invalid)
                var output:CMSampleBuffer?
                if CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:image,formatDescription:format,sampleTiming:&timing,sampleBufferOut:&output)==noErr,let output{decoder.outputLock.lock();decoder.decoded=output;decoder.outputLock.unlock();decoder.onFrame?(output)}
            },decompressionOutputRefCon:Unmanaged.passUnretained(self).toOpaque())
            let attributes=[kCVPixelBufferPixelFormatTypeKey:tenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary
            var spec:[String:Any]=[kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String:preference != 2]
            if preference==1 {spec[kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder as String]=true}
            let creation=VTDecompressionSessionCreate(allocator:kCFAllocatorDefault,formatDescription:format,decoderSpecification:spec as CFDictionary,imageBufferAttributes:attributes,outputCallback:&callback,decompressionSessionOut:&session)
            guard creation==noErr else{lastError="Decoder unavailable (\(creation)). Choose another decoding option.";return}
        }
        if let session{
            let result=VTDecompressionSessionDecodeFrame(session,sampleBuffer:sample,flags:synchronous ? [] : [._EnableAsynchronousDecompression],frameRefcon:nil,infoFlagsOut:nil)
            if synchronous {VTDecompressionSessionWaitForAsynchronousFrames(session)}
            if result != noErr {lastError="Video decode failed (\(result))."}
        }
    }
    func close(){if let session{VTDecompressionSessionWaitForAsynchronousFrames(session);VTDecompressionSessionInvalidate(session)};session=nil;waitingForKey=true;outputLock.lock();decoded=nil;outputLock.unlock()}
    deinit{close()}
}
