import AppKit
import AVFoundation

final class PreviewView:NSView {
    let videoLayer=AVSampleBufferDisplayLayer()
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=NSColor.black.cgColor;videoLayer.videoGravity = .resizeAspect;layer?.addSublayer(videoLayer)}
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();CATransaction.begin();CATransaction.setDisableActions(true);videoLayer.frame=bounds;CATransaction.commit()}
    private var clock=PreviewPresentationClock()
    private var pending=PreviewFrameQueue<CMSampleBuffer>()
    private var presentationActive=false,resumeAtLiveEdge=true
    private var lastDelivery:Double?
    func setPresentationActive(_ active:Bool){
        guard active != presentationActive else{return}
        presentationActive=active;clear()
    }
    func clear(){clock.reset();pending.reset();lastDelivery=nil;resumeAtLiveEdge=true;videoLayer.sampleBufferRenderer.flush(removingDisplayedImage:true,completionHandler:nil)}
    func show(_ samples:[CMSampleBuffer]){
        guard presentationActive else{return}
        let now=CMClockGetTime(CMClockGetHostTimeClock()).seconds
        // A blocked main run loop can miss visibility events (minimize animation,
        // workspace switch). Resume at the live edge instead of replaying its batch.
        if let lastDelivery,now-lastDelivery>0.2{clear()}
        lastDelivery=now
        let fresh=resumeAtLiveEdge ? Array(samples.suffix(1)):samples
        if !fresh.isEmpty{resumeAtLiveEdge=false}
        for sample in fresh{pending.append(sample,pts:CMSampleBufferGetPresentationTimeStamp(sample).seconds)}
        while let sample=pending.first{
            guard showFrame(sample) else{break}
            pending.removeFirst()
        }
    }
    private func showFrame(_ sample:CMSampleBuffer)->Bool{
        let renderer=videoLayer.sampleBufferRenderer
        #if PREVIEW_DIAGNOSTICS
        PreviewTrace.shared.event(5,CMSampleBufferGetPresentationTimeStamp(sample).seconds,renderer.isReadyForMoreMediaData ? 0:1)
        #endif
        if renderer.status == .failed{renderer.flush();clock.reset()}
        guard renderer.isReadyForMoreMediaData else{return false}
        let pts=CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let now=CMClockGetTime(CMClockGetHostTimeClock()).seconds
        guard let presentation=clock.schedule(pts:pts,now:now) else{return true}
        if presentation.reset{renderer.flush()}
        var timing=CMSampleTimingInfo(duration:CMSampleBufferGetDuration(sample),presentationTimeStamp:CMTime(seconds:presentation.time,preferredTimescale:1_000_000),decodeTimeStamp:.invalid)
        var adjusted:CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator:kCFAllocatorDefault,sampleBuffer:sample,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleBufferOut:&adjusted)==noErr,let adjusted else{return true}
        if let a=CMSampleBufferGetSampleAttachmentsArray(adjusted,createIfNecessary:true){
            let d=unsafeBitCast(CFArrayGetValueAtIndex(a,0),to:CFMutableDictionary.self)
            CFDictionarySetValue(d,Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),Unmanaged.passUnretained(kCFBooleanFalse).toOpaque())
        }
        #if PREVIEW_DIAGNOSTICS
        PreviewTrace.shared.event(8,pts,presentation.time)
        PreviewTrace.shared.event(9,presentation.time-now,presentation.reset ? 1:0)
        #endif
        renderer.enqueue(adjusted);return true
    }
}
// Peak amplitude is displayed on a logarithmic dBFS scale, independent of monitor volume.
final class StereoMeterView:NSView {
    private var levels=[Double](repeating:-60,count:2),peaks=[Double](repeating:-60,count:2)
    private var holdUntil=[Double](repeating:0,count:2)
    private var lastUpdate=ProcessInfo.processInfo.systemUptime
    override var intrinsicContentSize:NSSize{NSSize(width:300,height:54)}
    override init(frame:NSRect){super.init(frame:frame);setAccessibilityLabel("HDMI stereo peak meter in dBFS")}
    required init?(coder:NSCoder){fatalError()}
    func update(left:Double,right:Double){
        let now=ProcessInfo.processInfo.systemUptime,elapsed=max(0,now-lastUpdate);lastUpdate=now
        for (channel,amplitude) in [left,right].enumerated(){
            let db=amplitude.isFinite && amplitude>0 ? max(-60,min(0,20*log10(amplitude))) : -60
            levels[channel]=max(db,levels[channel]-48*elapsed)
            if db>=peaks[channel]{peaks[channel]=db;holdUntil[channel]=now+1}
            else if now>holdUntil[channel]{peaks[channel]=max(levels[channel],peaks[channel]-20*elapsed)}
        }
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect){
        super.draw(dirtyRect)
        let x:CGFloat=18,width=max(1,bounds.width-24),height:CGFloat=11
        func position(_ db:Double)->CGFloat{x+CGFloat((db+60)/60)*width}
        let text:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedSystemFont(ofSize:9,weight:.regular),.foregroundColor:NSColor.secondaryLabelColor]
        for channel in 0..<2 {
            let y:CGFloat=channel==0 ? 36:21
            (channel==0 ? "L":"R").draw(at:NSPoint(x:0,y:y),withAttributes:text)
            NSColor.quaternaryLabelColor.setFill();NSBezierPath(rect:NSRect(x:x,y:y,width:width,height:height)).fill()
            for (low,high,color) in [(-60.0,-20.0,NSColor.systemGreen),(-20.0,-9.0,NSColor.systemYellow),(-9.0,0.0,NSColor.systemRed)] {
                let end=min(levels[channel],high)
                if end>low {color.setFill();NSBezierPath(rect:NSRect(x:position(low),y:y,width:position(end)-position(low),height:height)).fill()}
            }
            if peaks[channel] > -60 {
                (peaks[channel]>=(-9) ? NSColor.systemRed:NSColor.labelColor).setFill()
                NSBezierPath(rect:NSRect(x:min(x+width-2,position(peaks[channel])),y:y-1,width:2,height:height+2)).fill()
            }
        }
        for db in [-60,-40,-20,-9,0] {
            let label=db==0 ? "0 dBFS":String(db)
            let labelWidth=(label as NSString).size(withAttributes:text).width
            label.draw(at:NSPoint(x:min(bounds.width-labelWidth,max(0,position(Double(db))-labelWidth/2)),y:3),withAttributes:text)
        }
    }
}
final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate,NSTextFieldDelegate {
    let engine=CaptureEngine()
    var window:NSWindow!,timer:Timer?
    let preview=PreviewView(frame:.zero)
    let status=NSTextField(labelWithString:"Connecting…")
    let detail=NSTextField(wrappingLabelWithString:"Opening your Elgato 4K60 S+.")
    let format=NSTextField(labelWithString:"Waiting for video")
    let bitrate=NSTextField(wrappingLabelWithString:"Device video bitrate · waiting for connection")
    let clock=NSTextField(labelWithString:"00:00")
    let stats=NSTextField(labelWithString:"")
    let audioLabel=NSTextField(labelWithString:"HDMI audio · awaiting packets")
    let meter=StereoMeterView(frame:.zero)
    let usbBadge=NSTextField(labelWithString:" USB · checking ")
    let folderLabel=NSTextField(labelWithString:"")
    let connect=NSButton(title:"Disconnect",target:nil,action:nil)
    let record=NSButton(title:"Record",target:nil,action:nil)
    let reveal=NSButton(title:"Show Last Recording",target:nil,action:nil)
    let videoToggle=NSButton(checkboxWithTitle:"Video preview",target:nil,action:nil)
    let audioToggle=NSButton(checkboxWithTitle:"Audio preview",target:nil,action:nil)
    let volume=NSSlider(value:0.7,minValue:0,maxValue:1,target:nil,action:nil)
    let durationToggle=NSButton(checkboxWithTitle:"Stop after",target:nil,action:nil)
    let durationField=NSTextField(string:"00:30:00")
    let countdown=NSTextField(labelWithString:"")
    private var appliedRecordingLimit:Double?
    private var durationValidation:String?
    var profile=RecordingProfile()
    var settingsController:RecordingSettings?
    let settings=NSButton(title:"Settings…",target:nil,action:nil)
    var current=CaptureState()
    var folder=FileManager.default.urls(for:.moviesDirectory,in:.userDomainMask)[0].appendingPathComponent("Elgato Recordings",isDirectory:true)
    func applicationDidFinishLaunching(_ notification:Notification){
        if let path=UserDefaults.standard.string(forKey:"recordingFolder"){folder=URL(fileURLWithPath:path,isDirectory:true)}
        if let data=UserDefaults.standard.data(forKey:"recordingProfile"),let saved=try? JSONDecoder().decode(RecordingProfile.self,from:data),(try? saved.validate()) != nil {profile=saved;engine.setProfile(saved)}
        setupMenu()
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:860),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Elgato Recorder";window.subtitle="4K60 S+ · USB capture";window.minSize=NSSize(width:720,height:700);window.delegate=self
        let root=NSView();window.contentView=root
        let title=NSTextField(labelWithString:"Elgato Recorder");title.font = .systemFont(ofSize:23,weight:.semibold)
        let device=NSTextField(labelWithString:"GAME CAPTURE 4K60 S+");device.font = .systemFont(ofSize:11,weight:.medium);device.textColor = .secondaryLabelColor
        let identity=NSStackView(views:[device,title]);identity.orientation = .vertical;identity.alignment = .leading;identity.spacing=4
        status.font = .systemFont(ofSize:14,weight:.medium)
        let icon=NSImageView();icon.image=Bundle.main.url(forResource:"Recorder",withExtension:"icns").flatMap{NSImage(contentsOf:$0)} ?? NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown;icon.widthAnchor.constraint(equalToConstant:52).isActive=true;icon.heightAnchor.constraint(equalToConstant:52).isActive=true
        usbBadge.font = .systemFont(ofSize:11,weight:.semibold);usbBadge.alignment = .center;usbBadge.wantsLayer=true;usbBadge.layer?.cornerRadius=5;usbBadge.layer?.borderWidth=1
        let connectionStatus=NSStackView(views:[usbBadge,status]);connectionStatus.orientation = .vertical;connectionStatus.alignment = .trailing;connectionStatus.spacing=6
        let top=NSStackView(views:[icon,identity,NSView(),connectionStatus]);top.orientation = .horizontal;top.distribution = .fill;top.spacing=12
        format.font = .monospacedSystemFont(ofSize:12,weight:.regular);format.textColor = .secondaryLabelColor
        bitrate.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium)
        bitrate.toolTip="Measured compressed video received from the device, averaged over up to 3 seconds. Excludes audio and USB headers/padding. Independent of preview, output FPS and recording bitrate. The requested encoder target is not a confirmed firmware readback; actual bitrate depends on the device and picture content."
        let signal=NSStackView(views:[format,bitrate]);signal.orientation = .vertical;signal.alignment = .leading;signal.spacing=5
        bitrate.widthAnchor.constraint(equalTo:signal.widthAnchor).isActive=true
        clock.font = .monospacedDigitSystemFont(ofSize:30,weight:.medium)
        detail.textColor = .secondaryLabelColor;detail.font = .systemFont(ofSize:12);detail.maximumNumberOfLines=2
        let timerColumn=NSStackView(views:[clock,detail]);timerColumn.orientation = .vertical;timerColumn.alignment = .leading;timerColumn.spacing=4
        meter.widthAnchor.constraint(equalToConstant:300).isActive=true;meter.heightAnchor.constraint(equalToConstant:54).isActive=true
        audioLabel.font = .systemFont(ofSize:12)
        let audioNote=NSTextField(labelWithString:"48 kHz stereo · preview volume does not affect recording");audioNote.font = .systemFont(ofSize:10);audioNote.textColor = .secondaryLabelColor
        let audioColumn=NSStackView(views:[audioLabel,meter,audioNote]);audioColumn.orientation = .vertical;audioColumn.alignment = .leading;audioColumn.spacing=5
        let info=NSStackView(views:[timerColumn,NSView(),audioColumn]);info.orientation = .horizontal;info.spacing=20
        connect.target=self;connect.action=#selector(toggleConnection)
        record.target=self;record.action=#selector(toggleRecording);record.bezelStyle = .rounded;record.controlSize = .large;record.keyEquivalent="r";record.keyEquivalentModifierMask=[.command]
        record.contentTintColor = .systemRed
        reveal.target=self;reveal.action=#selector(showFile);reveal.isEnabled=false
        let choose=NSButton(title:"Save Folder…",target:self,action:#selector(chooseFolder))
        folderLabel.stringValue=folder.path;folderLabel.lineBreakMode = .byTruncatingMiddle;folderLabel.textColor = .secondaryLabelColor;folderLabel.font = .systemFont(ofSize:11)
        settings.target=self;settings.action=#selector(showSettings)
        let controls=NSStackView(views:[record,connect,settings,NSView(),choose,reveal]);controls.orientation = .horizontal;controls.spacing=12
        stats.font = .monospacedSystemFont(ofSize:10,weight:.regular);stats.textColor = .tertiaryLabelColor
        videoToggle.state = .on
        for button in [videoToggle,audioToggle] { button.target=self;button.action=#selector(previewChanged) }
        volume.target=self;volume.action=#selector(previewChanged);volume.widthAnchor.constraint(equalToConstant:120).isActive=true
        volume.setAccessibilityLabel("Monitoring volume");volume.isEnabled=false
        let previewControls=NSStackView(views:[videoToggle,audioToggle,NSTextField(labelWithString:"Volume"),volume,NSView()]);previewControls.spacing=16
        durationToggle.target=self;durationToggle.action=#selector(durationChanged)
        durationField.widthAnchor.constraint(equalToConstant:90).isActive=true;durationField.isEnabled=false
        durationField.delegate=self;durationField.target=self;durationField.action=#selector(durationEdited)
        durationField.setAccessibilityLabel("Recording duration hours minutes seconds")
        durationField.toolTip="Hours:minutes:seconds from the actual recording start. Edit during recording and press Return to update the total limit; turning Stop after off removes it."
        countdown.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium)
        let durationControls=NSStackView(views:[durationToggle,durationField,NSTextField(labelWithString:"hh:mm:ss"),countdown,NSView()]);durationControls.spacing=10
        let stack=NSStackView(views:[top,signal,preview,previewControls,info,durationControls,controls,folderLabel,stats]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-18),preview.heightAnchor.constraint(greaterThanOrEqualToConstant:260)])
        for view in [top,signal,preview,info,controls,folderLabel,stats]{view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
        preview.setContentHuggingPriority(.defaultLow,for:.vertical)
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        // Drain the bounded preview queue up to 60 Hz. The renderer schedules each frame;
        // a 30 fps source or output therefore draws only 30 new video frames/s.
        timer=Timer(timeInterval:1.0/60,repeats:true){[weak self]_ in self?.refresh()}
        RunLoop.main.add(timer!,forMode:.common)
        engine.connect()
    }
    func setupMenu(){
        let main=NSMenu();let item=NSMenuItem();main.addItem(item);let appMenu=NSMenu();item.submenu=appMenu
        appMenu.addItem(withTitle:"About Elgato Recorder",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"Quit Elgato Recorder",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        NSApp.mainMenu=main
    }
    #if PREVIEW_DIAGNOSTICS
    var lastPreviewTrace=0.0
    #endif
    func refresh(){
        #if PREVIEW_DIAGNOSTICS
        PreviewTrace.shared.event(4)
        PreviewTrace.shared.event(10,window.isMiniaturized ? 1:0,window.occlusionState.contains(.visible) && !NSApp.isHidden ? 1:0)
        PreviewTrace.shared.event(11,current.peak,current.audioSignal ? 1:0)
        let traceNow=ProcessInfo.processInfo.systemUptime
        if traceNow-lastPreviewTrace>5 {
            lastPreviewTrace=traceNow
            preview.videoLayer.sampleBufferRenderer.loadVideoPerformanceMetrics{m in
                if let m{PreviewTrace.shared.event(6,Double(m.totalNumberOfFrames),Double(m.numberOfDroppedFrames));PreviewTrace.shared.event(7,m.totalAccumulatedFrameDelay)}
            }
            PreviewTrace.shared.save()
        }
        #endif
        updatePreviewVisibility()
        let(s,frames)=engine.snapshot();current=s;preview.show(frames)
        let usbUnsupported=s.usbSpeed>0 && s.usbSpeed<4
        let warning=usbUnsupported || s.monitoringError != nil || ["waiting","failed","error","retrying","disconnected","warning","unsupported"].contains{ s.status.localizedCaseInsensitiveContains($0) }
        status.stringValue=s.status;status.textColor=warning ? .systemOrange : (s.recording ? .systemRed : .labelColor)
        usbBadge.stringValue=s.usbSpeed>=4 ? (s.usbSpeed>=5 ? " USB 3.1+ · 10+ Gbps ":" USB 3.0 · 5 Gbps ") : (s.usbSpeed==3 ? " USB 2.0 · Unsupported ":usbUnsupported ? " USB · Unsupported ":" USB · not connected ")
        usbBadge.textColor=s.usbSpeed>=4 ? .white : .labelColor
        usbBadge.layer?.backgroundColor=(s.usbSpeed>=4 ? NSColor.systemBlue:NSColor.textBackgroundColor).cgColor
        usbBadge.layer?.borderColor=(s.usbSpeed>=4 ? NSColor.systemBlue:NSColor.separatorColor).cgColor
        usbBadge.toolTip=usbUnsupported ? "USB 2 is unsupported. Connect the 4K60 S+ directly using a USB 3 cable and port.":"USB 3 is required for capture; encoder bitrate is separate from USB link speed."
        detail.stringValue=s.monitoringError.map{"Audio monitoring: \($0)"} ?? (s.detail + (s.ndiStatus.map{" · " + $0} ?? ""));format.stringValue=s.format
        if s.connected,let target=s.requestedVideoMbps {
            let measured=s.incomingVideoMbps.map{String(format:"%.1f Mbps received",$0)} ?? "measuring…"
            bitrate.stringValue="Device video: \(measured) · requested: \(target) Mbps · 3 s average"
        }else{bitrate.stringValue="Device video bitrate · \(s.connecting ? "connecting…":"not connected")"}
        if usbUnsupported{detail.stringValue += " · USB 2 is unsupported; a USB 3 cable and port are required."}
        detail.textColor=warning ? .systemOrange : .secondaryLabelColor
        let seconds=Int(s.seconds);clock.stringValue=String(format:"%02d:%02d:%02d",seconds/3600,(seconds/60)%60,seconds%60)
        record.title=s.recording ? "Stop Recording" : "Record";record.isEnabled=s.connected && !s.saving
        connect.title=s.connected || s.connecting ? "Disconnect" : "Connect";connect.isEnabled = !s.saving && !s.connecting
        meter.update(left:s.peakLeft,right:s.peakRight)
        audioLabel.stringValue=s.audioFrames==0 ? "HDMI audio · awaiting packets" : (s.audioSignal ? "HDMI audio · signal detected" : "HDMI audio · silent")
        stats.stringValue="\(s.videoFrames) video frames  ·  \(s.audioFrames) audio samples  ·  \(s.writtenBytes/1_000_000) MB written  ·  \(s.discarded) discarded"
        reveal.isEnabled=s.lastFile != nil
        settings.isEnabled = !s.recording && !s.saving && !s.connecting
        durationToggle.isEnabled = !s.saving
        durationField.isEnabled = durationToggle.state == .on && !s.saving
        countdown.textColor=durationValidation == nil ? .secondaryLabelColor : .systemOrange
        if let validation=durationValidation{countdown.stringValue=validation}
        else if let remaining=s.remaining { let n=Int(ceil(remaining));countdown.stringValue=String(format:"%02d:%02d:%02d remaining",n/3600,(n/60)%60,n%60) } else { countdown.stringValue="" }
    }
    @objc func showSettings(){
        settingsController=RecordingSettings(profile:profile,usbSpeed:current.usbSpeed){ [weak self] value in
            guard let self else{return};self.profile=value
            if let data=try? JSONEncoder().encode(value){UserDefaults.standard.set(data,forKey:"recordingProfile")}
            self.engine.disconnect {DispatchQueue.main.async{
                self.engine.setProfile(value);self.preview.clear();self.engine.connect()
            }}
        }
        window.beginSheet(settingsController!.window)
    }
    private func updatePreviewVisibility(){
        guard let window else{return}
        preview.setPresentationActive(videoToggle.state == .on && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible) && !NSApp.isHidden)
    }
    func windowDidMiniaturize(_ notification:Notification){updatePreviewVisibility()}
    func windowDidDeminiaturize(_ notification:Notification){updatePreviewVisibility()}
    func windowDidChangeOcclusionState(_ notification:Notification){updatePreviewVisibility()}
    func applicationDidHide(_ notification:Notification){updatePreviewVisibility()}
    func applicationDidUnhide(_ notification:Notification){updatePreviewVisibility()}
    @objc func previewChanged(){
        let video=videoToggle.state == .on,audio=audioToggle.state == .on
        volume.isEnabled=audio
        engine.setPreview(video:video,audio:audio,volume:volume.floatValue)
        updatePreviewVisibility()
    }
    private func recordingLimit()throws->Double {
        guard durationToggle.state == .on else{return 0}
        let parts=durationField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).split(separator:":",omittingEmptySubsequences:false)
        guard parts.count==3,parts.allSatisfy({!$0.isEmpty && $0.allSatisfy({$0.isASCII && $0.isNumber})}),let h=Int(parts[0]),let m=Int(parts[1]),let s=Int(parts[2]),h<=999,m<60,s<60,h+m+s>0 else {throw RecorderError(message:"Enter hh:mm:ss, for example 00:30:00.")}
        return Double(h*3600+m*60+s)
    }
    @objc func durationChanged(){durationField.isEnabled=durationToggle.state == .on;durationEdited()}
    @objc func durationEdited(){
        do{
            let limit=try recordingLimit();durationValidation=nil;durationField.textColor = .labelColor
            // Return and editing-end can both fire. Apply each value only once;
            // the engine keeps the original recording start as its reference.
            if current.recording && appliedRecordingLimit != limit{engine.setRecordingLimit(limit);appliedRecordingLimit=limit}
        }catch{durationValidation="Use hh:mm:ss; current limit unchanged.";durationField.textColor = .systemOrange}
    }
    func controlTextDidEndEditing(_ notification:Notification){if let field=notification.object as? NSTextField,field === durationField{durationEdited()}}
    @objc func toggleConnection(){if current.connected{engine.disconnect()}else{preview.clear();engine.connect()}}
    @objc func toggleRecording(){
        refresh()
        if current.recording{engine.stopRecording();return}
        do{
            try profile.validateRecording()
            let limit=try recordingLimit();durationValidation=nil;durationField.textColor = .labelColor
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let attributes=try FileManager.default.attributesOfFileSystem(forPath:folder.path)
            if let free=attributes[.systemFreeSize] as? NSNumber,free.int64Value<500_000_000{throw RecorderError(message:"Less than 500 MB free in the recording destination.")}
            let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd_HH-mm-ss"
            let name="Elgato_\(formatter.string(from:Date()))_\(UUID().uuidString.prefix(4)).\(profile.fileExtension)"
            appliedRecordingLimit=limit
            engine.startRecording(folder.appendingPathComponent(name),limit:limit)
        }catch{let alert=NSAlert();alert.messageText="Cannot start recording";alert.informativeText=error.localizedDescription;alert.beginSheetModal(for:window)}
    }
    @objc func chooseFolder(){
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.canCreateDirectories=true;panel.prompt="Choose";panel.directoryURL=folder
        panel.beginSheetModal(for:window){response in if response == .OK,let url=panel.url{self.folder=url;self.folderLabel.stringValue=url.path;UserDefaults.standard.set(url.path,forKey:"recordingFolder")}}
    }
    @objc func showFile(){if let url=current.lastFile{NSWorkspace.shared.activateFileViewerSelecting([url])}}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply{
        engine.disconnect{DispatchQueue.main.async{sender.reply(toApplicationShouldTerminate:true)}};return .terminateLater
    }
}
@main struct ElgatoRecorderApp {
    static func main(){let app=NSApplication.shared;let delegate=AppDelegate();app.setActivationPolicy(.regular);app.delegate=delegate;app.run();withExtendedLifetime(delegate){}}
}
