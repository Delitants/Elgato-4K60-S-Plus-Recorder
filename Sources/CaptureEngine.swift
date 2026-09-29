import Foundation
import AVFoundation
struct CaptureState {
    var connected=false,connecting=false,recording=false,saving=false
    var status="Ready",detail="Connect the 4K60 S+ using USB 3.0."
    var videoFrames=0,audioFrames=0,discarded=0,bytes=0
    var writtenBytes:Int64=0,usbSpeed=0
    var seconds:Double=0,peak:Double=0
    var peakLeft:Double=0,peakRight:Double=0
    var audioSignal=false
    var format="Waiting for HDMI video"
    var incomingVideoMbps:Double?,requestedVideoMbps:Int?
    var remaining:Double?
    var monitoringError:String?
    var recordingWarning:String?
    var ndiStatus:String?
    var lastFile:URL?
}
final class CaptureEngine {
    private let lock=NSLock()
    private let worker=DispatchQueue(label:"Elgato.Capture",qos:.userInitiated)
    private var state=CaptureState(),running=false,workerActive=false
    private var previewFrames=PreviewFrameQueue<CMSampleBuffer>()
    private var requestedURL:URL?,stopRequested=false
    private var videoPreview=true,audioPreview=false,monitorVolume:Float=0.7
    private var requestedLimit:Double=0
    private var profile=RecordingProfile()
    func setProfile(_ value:RecordingProfile){lock.lock();profile=value;lock.unlock()}
    private var quitCompletion:(()->Void)?
    func snapshot()->(CaptureState,[CMSampleBuffer]) {
        lock.lock();defer{lock.unlock()};return(state,previewFrames.drain())
    }
    private func change(_ body:(inout CaptureState)->Void){lock.lock();body(&state);lock.unlock()}
    func connect(){
        #if PREVIEW_DIAGNOSTICS
        PreviewTrace.shared.reset()
        #endif
        lock.lock();guard !workerActive else{lock.unlock();return};running=true;workerActive=true
        requestedURL=nil;stopRequested=false;let lastFile=state.lastFile,lastWrittenBytes=state.writtenBytes
        state=CaptureState();state.lastFile=lastFile;state.writtenBytes=lastWrittenBytes
        state.connecting=true;state.status="Connecting…";state.detail="Opening the Elgato capture interface…";lock.unlock()
        worker.async{self.run()}
    }
    func disconnect(completion:(()->Void)?=nil){
        lock.lock();let wasRunning=workerActive;running=false;requestedURL=nil;stopRequested=false;if wasRunning{quitCompletion=completion};lock.unlock()
        if !wasRunning {completion?()}
    }
    func setPreview(video:Bool,audio:Bool,volume:Float){
        lock.lock();videoPreview=video;audioPreview=audio;monitorVolume=volume
        if !video { previewFrames.reset() };lock.unlock()
    }
    func startRecording(_ url:URL,limit:Double=0){
        lock.lock();defer{lock.unlock()}
        guard running,state.connected,!state.recording,!state.saving,requestedURL==nil else{return}
        requestedURL=url;requestedLimit=limit;state.recordingWarning=nil;state.recording=true
    }
    func stopRecording(){lock.lock();stopRequested=true;lock.unlock()}
    func setRecordingLimit(_ seconds:Double){lock.lock();requestedLimit=seconds.isFinite ? max(0,seconds):0;lock.unlock()}
    private func finish(_ recorder:RecordingSink){
        change{$0.seconds=recorder.duration;$0.recording=false;$0.remaining=nil;$0.saving=true;$0.status="Saving recording…"}

        recorder.finish{url,error in
            self.change{ s in
                // Finalization drains the recording queue; sample the final duration now.
                s.seconds=recorder.duration;s.writtenBytes=recorder.writtenBytes;s.recordingWarning=recorder.warning ?? s.recordingWarning;s.saving=false
                let result=RecordingCompletion(url:url,error:error)
                if let url=result.url{s.lastFile=url};s.status=result.status;s.detail=result.detail
            }
        }

    }
    private func run(){
        // Live USB transport must keep draining even when its window is occluded.
        // Recording owns a separate, stronger activity that prevents idle sleep.
        let activity=ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Receiving live HDMI video and audio")
        defer{ProcessInfo.processInfo.endActivity(activity)}
        lock.lock();let profile=self.profile;lock.unlock()
        var error=[CChar](repeating:0,count:512)
        var opened=capture_open_config(profile.captureHEVC ? 1 : 0,profile.capture4K ? 3840 : 1920,profile.capture4K ? 2160 : 1080,Int32(profile.deviceMbps),&error,Int32(error.count))
        if opened==nil {
            lock.lock();let retry=running;lock.unlock()
            if retry {
                change{$0.status="Retrying connection…";$0.detail="The device is settling after reconfiguration."}
                Thread.sleep(forTimeInterval:1)
                lock.lock();let retry=running;lock.unlock()
                if retry { opened=capture_open_config(profile.captureHEVC ? 1 : 0,profile.capture4K ? 3840 : 1920,profile.capture4K ? 2160 : 1080,Int32(profile.deviceMbps),&error,Int32(error.count)) }
            }
        }
        guard let usb=opened else {
            change{$0.connecting=false;$0.connected=false;$0.usbSpeed=Int(capture_last_usb_speed());$0.status="Connection failed";$0.detail=String(cString:error)}
            lock.lock();running=false;workerActive=false;let completion=quitCompletion;quitCompletion=nil;lock.unlock();completion?();return
        }
        let parser=PacketParser(),converter=MediaConverter(hevc:profile.captureHEVC)
        var ndi:NDIOutput?
        if profile.ndiEnabled{do{ndi=try NDIOutput(profile:profile)}catch{change{$0.ndiStatus=error.localizedDescription}}}
        let ndiOutput=ndi
        let decoder=PreviewDecoder();decoder.preference=profile.decoder;decoder.tenBit=profile.captureHEVC
        let previewSelector=PreviewSampleSelector()
        decoder.onFrame={ [weak self] sample in
            guard let self,let incoming=VideoRate.measured(period:CMSampleBufferGetDuration(sample).seconds) else{return}
            let effective=profile.effectiveRate(incoming:incoming)
            let film=(profile.sourceFPS == .fps23976 || profile.sourceFPS == .fps24) && effective==profile.sourceFPS.rate
            self.lock.lock()
            let outputs=previewSelector.select(sample,incoming:incoming,output:effective,film:film)
            for output in outputs where self.videoPreview {
                #if PREVIEW_DIAGNOSTICS
                PreviewTrace.shared.event(3,CMSampleBufferGetPresentationTimeStamp(output).seconds,0)
                #endif
                self.previewFrames.append(output,pts:CMSampleBufferGetPresentationTimeStamp(output).seconds)
            }
            self.lock.unlock()
            for output in outputs{ndiOutput?.offerVideo(output)}
        }
        let monitor=AudioMonitor()
        let timing=CaptureTiming()
        var deadline=RecordingDeadline()
        var meter=StereoPeakMeter()
        var audioSignal=AudioSignalIndicator()
        var videoBitrate=IncomingVideoBitrate()
        var recorder:RecordingSink?,buffer=[UInt8](repeating:0,count:16384)
        var lastFrame=Date(),lastStats=Date.distantPast,videoCount=0,audioCount=0,bytes=0
        change{$0.connected=true;$0.connecting=false;$0.requestedVideoMbps=profile.deviceMbps;$0.usbSpeed=Int(capture_last_usb_speed());$0.status="Waiting for HDMI…";$0.detail="Capture device connected."}
        var terminalError:String?
        var lastDiagnostics = ProcessInfo.processInfo.systemUptime
        while true {
            let loopStart=ProcessInfo.processInfo.systemUptime
            lock.lock();let keepRunning=running;let url=requestedURL;requestedURL=nil;let stop=stopRequested;stopRequested=false;let limit=requestedLimit;let showVideo=videoPreview;let listen=audioPreview;let volume=monitorVolume;lock.unlock()
            timing.observe("controlLock",seconds:ProcessInfo.processInfo.systemUptime-loopStart)
            if !keepRunning{break}
            if let startedAt=recorder?.startedAt{deadline.start(seconds:limit,now:startedAt)}
            if let r=recorder,r.error != nil{finish(r);recorder=nil;deadline.clear()}
            timing.measure("audioConfigure"){monitor.configure(enabled:listen,volume:volume);change{$0.monitoringError=monitor.error}}
            if stop || deadline.expired(now:ProcessInfo.processInfo.systemUptime),let r=recorder{finish(r);recorder=nil;deadline.clear()}
            if stop && recorder==nil {change{$0.recording=false}}
            if let url,!stop,recorder==nil {
                recorder=RecordingSink(url:url,profile:profile,initialRate:converter.frameTiming.rate)
                deadline.clear()
                change{$0.recording=true;$0.seconds=0;$0.writtenBytes=0;$0.remaining=nil;$0.status="Waiting for keyframe…";$0.detail="Recording will begin on the next video keyframe."}
            }
            let n=timing.measure("usbRead"){capture_read(usb,&buffer,Int32(buffer.count))}
            if n<0{terminalError="USB capture ended (error \(n)). Reconnect the device, then click Connect.";break}
            if n>0 {
                bytes+=Int(n)
                let frames=timing.measure("packetParser"){parser.feed(Data(buffer.prefix(Int(n))))}
                for frame in frames {
                    videoBitrate.observe(type:frame.type,bytes:frame.data.count,now:ProcessInfo.processInfo.systemUptime)
                    do {
                        guard let(sample,key)=try timing.measure("mediaConvert",{try converter.convert(frame)}) else{continue}
                        if let r=recorder,!r.offer(frame,key:key){finish(r);recorder=nil;deadline.clear();change{$0.status="Recording error";$0.detail=r.error?.localizedDescription ?? "Recording stopped"}}
                        if frame.type==0xc1 {
                            videoCount+=1;lastFrame=Date()
                            #if PREVIEW_DIAGNOSTICS
                            PreviewTrace.shared.event(1,CMSampleBufferGetPresentationTimeStamp(sample).seconds,Double(frame.data.count))
                            #endif
                            if showVideo || ndiOutput != nil {timing.measure("videoDecodeSubmit"){decoder.decode(sample,key:key)}} else {decoder.close()}
                        }else{
                            timing.measure("audioPlaybackSubmit"){monitor.append(frame.data,timestamp:frame.timestamp)};timing.measure("ndiAudioSubmit"){ndiOutput?.offerAudio(frame)}
                            audioCount+=frame.data.count/4;meter.append(frame.data)
                        }
                    }catch{if let r=recorder {finish(r);recorder=nil;deadline.clear()};change{$0.status="Media error";$0.detail=error.localizedDescription}}
                }
            }
            timing.observe("captureIteration",seconds:ProcessInfo.processInfo.systemUptime-loopStart)
            if let levels=meter.take(now:ProcessInfo.processInfo.systemUptime){
                let now=ProcessInfo.processInfo.systemUptime
                audioSignal.observe(peak:max(levels.left,levels.right),now:now)
                change{$0.peakLeft=levels.left;$0.peakRight=levels.right;$0.peak=max(levels.left,levels.right);$0.audioSignal=audioSignal.isActive(now:now)}
            }
            if Date().timeIntervalSince(lastStats)>0.2 {
                recorder?.refreshWrittenBytes()
                #if CAPTURE_DIAGNOSTICS
                if ProcessInfo.processInfo.systemUptime - lastDiagnostics > 5 {
                    var metrics: [String:Any] = monitor.diagnostics
                    metrics.merge(timing.snapshot){_,new in new}
                    metrics["parserDiscards"] = Double(parser.discarded)
                    metrics["uptime"] = ProcessInfo.processInfo.systemUptime
                    if let data = try? JSONSerialization.data(withJSONObject:metrics,options:.sortedKeys) {
                        try? data.write(to:FileManager.default.temporaryDirectory.appendingPathComponent("ElgatoRecorder-AudioDiagnostics.json"),options:.atomic)
                    }
                    lastDiagnostics = ProcessInfo.processInfo.systemUptime
                }
                #endif
                let stale=Date().timeIntervalSince(lastFrame)>3
                change{ s in
                    if let ndiOutput{s.ndiStatus=ndiOutput.status}
                    s.videoFrames=videoCount;s.audioFrames=audioCount;s.bytes=bytes
                    s.incomingVideoMbps=videoBitrate.mbps(now:ProcessInfo.processInfo.systemUptime)
                    if let recorder{s.writtenBytes=recorder.writtenBytes;s.recordingWarning=recorder.warning ?? s.recordingWarning}
                    s.discarded=parser.discarded+(recorder?.dropped ?? 0)
                    s.seconds=recorder?.duration ?? s.seconds
                    s.remaining=deadline.remaining(now:ProcessInfo.processInfo.systemUptime)
                    if let format=converter.videoFormat {let d=CMVideoFormatDescriptionGetDimensions(format);let transfer=CMFormatDescriptionGetExtension(format,extensionKey:kCMFormatDescriptionExtension_TransferFunction) as? String
                        let color=transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) ? "HDR PQ" : transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) ? "HDR HLG" : "HDR not signalled"
                        let rateText=converter.frameTiming.rate.map { incoming in
                            let effective=profile.effectiveRate(incoming:incoming)
                            return "Incoming \(incoming.label) fps · Output \(effective.label) fps"+(profile.sourceFPS.rate.map{" · cadence cap \($0.label)"} ?? "")
                        } ?? "Measuring incoming FPS…"
                        let codec=CMFormatDescriptionGetMediaSubType(format)==kCMVideoCodecType_HEVC ? "HEVC":"H.264"
                        let depth=(CMFormatDescriptionGetExtension(format,extensionKey:kCMFormatDescriptionExtension_BitsPerComponent) as? NSNumber).map{" · \($0.intValue)-bit"} ?? ""
                        s.format="Encoded \(d.width) × \(d.height) · \(codec)\(depth) · \(rateText) · \(color)"}
                    if stale{s.status="Waiting for HDMI…";s.detail="No recent video. Check the source and HDMI cable."}
                    else if let r=recorder,r.videoFrames>0{s.status="Recording";s.detail="Saving video and HDMI audio to \(profile.fileExtension.uppercased())."}
                    else if recorder==nil && s.status=="Waiting for HDMI…"{s.status="Live preview";s.detail="Ready to record video and HDMI audio."}
                };lastStats=Date()
            }
        }
        monitor.stop();ndiOutput?.stop()
        capture_close(usb)
        decoder.close()
        if let r=recorder{finish(r)}
        while snapshot().0.saving {Thread.sleep(forTimeInterval:0.02)}
        change{$0.connected=false;$0.connecting=false;$0.recording=false;$0.peak=0;$0.peakLeft=0;$0.peakRight=0;$0.audioSignal=false;$0.usbSpeed=0
            $0.incomingVideoMbps=nil;$0.requestedVideoMbps=nil
            $0.status=terminalError==nil ? "Disconnected" : "Device disconnected"
            $0.detail=terminalError ?? "Capture stopped. Saved recordings are available in your chosen folder."
        }
        lock.lock();running=false;workerActive=false;previewFrames.reset();let completion=quitCompletion;quitCompletion=nil;lock.unlock();completion?()
    }
}
