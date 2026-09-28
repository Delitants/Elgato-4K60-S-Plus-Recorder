import AppKit
import AVFoundation

final class PreviewView:NSView {
    let videoLayer=AVSampleBufferDisplayLayer()
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=NSColor.black.cgColor;videoLayer.videoGravity = .resizeAspect;layer?.addSublayer(videoLayer)}
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();CATransaction.begin();CATransaction.setDisableActions(true);videoLayer.frame=bounds;CATransaction.commit()}
    func show(_ sample:CMSampleBuffer){
        if videoLayer.status == .failed {videoLayer.flush()}
        guard videoLayer.isReadyForMoreMediaData else{return}
        if let a=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:true){
            let d=unsafeBitCast(CFArrayGetValueAtIndex(a,0),to:CFMutableDictionary.self)
            CFDictionarySetValue(d,Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        };videoLayer.enqueue(sample)
    }
}
final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let engine=CaptureEngine()
    var window:NSWindow!,timer:Timer?
    let preview=PreviewView(frame:.zero)
    let status=NSTextField(labelWithString:"Connecting…")
    let detail=NSTextField(wrappingLabelWithString:"Opening your Elgato 4K60 S+.")
    let format=NSTextField(labelWithString:"Waiting for video")
    let clock=NSTextField(labelWithString:"00:00")
    let stats=NSTextField(labelWithString:"")
    let audioLabel=NSTextField(labelWithString:"HDMI audio · awaiting packets")
    let meter=NSLevelIndicator()
    let folderLabel=NSTextField(labelWithString:"")
    let connect=NSButton(title:"Disconnect",target:nil,action:nil)
    let record=NSButton(title:"Record",target:nil,action:nil)
    let reveal=NSButton(title:"Show Last Recording",target:nil,action:nil)
    let videoToggle=NSButton(checkboxWithTitle:"Video preview",target:nil,action:nil)
    let audioToggle=NSButton(checkboxWithTitle:"Listen to HDMI audio",target:nil,action:nil)
    let volume=NSSlider(value:0.7,minValue:0,maxValue:1,target:nil,action:nil)
    let durationToggle=NSButton(checkboxWithTitle:"Stop after",target:nil,action:nil)
    let durationField=NSTextField(string:"00:30:00")
    let countdown=NSTextField(labelWithString:"")
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
        let top=NSStackView(views:[identity,NSView(),status]);top.orientation = .horizontal;top.distribution = .fill
        format.font = .monospacedSystemFont(ofSize:12,weight:.regular);format.textColor = .secondaryLabelColor
        clock.font = .monospacedDigitSystemFont(ofSize:30,weight:.medium)
        detail.textColor = .secondaryLabelColor;detail.font = .systemFont(ofSize:12);detail.maximumNumberOfLines=2
        let timerColumn=NSStackView(views:[clock,detail]);timerColumn.orientation = .vertical;timerColumn.alignment = .leading;timerColumn.spacing=4
        meter.levelIndicatorStyle = .continuousCapacity;meter.minValue=0;meter.maxValue=1;meter.warningValue=0.8;meter.criticalValue=0.95
        meter.widthAnchor.constraint(equalToConstant:220).isActive=true
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
        durationField.setAccessibilityLabel("Recording duration hours minutes seconds")
        durationField.toolTip="Hours:minutes:seconds. The timer starts when you press Record."
        countdown.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium)
        let durationControls=NSStackView(views:[durationToggle,durationField,NSTextField(labelWithString:"hh:mm:ss"),countdown,NSView()]);durationControls.spacing=10
        let stack=NSStackView(views:[top,format,preview,previewControls,info,durationControls,controls,folderLabel,stats]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-18),preview.heightAnchor.constraint(greaterThanOrEqualToConstant:260)])
        for view in [top,preview,info,controls,folderLabel,stats]{view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
        preview.setContentHuggingPriority(.defaultLow,for:.vertical)
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        // Poll for newly selected frames up to 60 Hz. snapshot consumes each frame once;
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
    func refresh(){
        let(s,frame)=engine.snapshot();current=s;if videoToggle.state == .on,let frame{preview.show(frame)}
        status.stringValue=s.status;status.textColor=s.recording ? .systemRed : .labelColor
        detail.stringValue=s.monitoringError.map{"Audio monitoring: \($0)"} ?? (s.detail + (s.ndiStatus.map{" · " + $0} ?? ""));format.stringValue=s.format
        let seconds=Int(s.seconds);clock.stringValue=String(format:"%02d:%02d:%02d",seconds/3600,(seconds/60)%60,seconds%60)
        record.title=s.recording ? "Stop Recording" : "Record";record.isEnabled=s.connected && !s.saving
        connect.title=s.connected || s.connecting ? "Disconnect" : "Connect";connect.isEnabled = !s.saving && !s.connecting
        meter.doubleValue=s.peak
        audioLabel.stringValue=s.audioFrames==0 ? "HDMI audio · awaiting packets" : (s.peak<0.0001 ? "HDMI audio · silent" : "HDMI audio · signal detected")
        stats.stringValue="\(s.videoFrames) video frames  ·  \(s.audioFrames) audio samples  ·  \(s.bytes/1_000_000) MB received  ·  \(s.discarded) discarded"
        reveal.isEnabled=s.lastFile != nil
        settings.isEnabled = !s.recording && !s.saving && !s.connecting
        durationToggle.isEnabled = !s.recording && !s.saving
        durationField.isEnabled = durationToggle.state == .on && !s.recording && !s.saving
        if let remaining=s.remaining { let n=Int(ceil(remaining));countdown.stringValue=String(format:"%02d:%02d:%02d remaining",n/3600,(n/60)%60,n%60) } else { countdown.stringValue="" }
    }
    @objc func showSettings(){
        settingsController=RecordingSettings(profile:profile){ [weak self] value in
            guard let self else{return};self.profile=value
            if let data=try? JSONEncoder().encode(value){UserDefaults.standard.set(data,forKey:"recordingProfile")}
            self.engine.disconnect {DispatchQueue.main.async{
                self.engine.setProfile(value);self.preview.videoLayer.flushAndRemoveImage();self.engine.connect()
            }}
        }
        window.beginSheet(settingsController!.window)
    }
    @objc func previewChanged(){
        let video=videoToggle.state == .on,audio=audioToggle.state == .on
        volume.isEnabled=audio
        engine.setPreview(video:video,audio:audio,volume:volume.floatValue)
        if !video { preview.videoLayer.flushAndRemoveImage() }
    }
    @objc func durationChanged(){durationField.isEnabled=durationToggle.state == .on}
    @objc func toggleConnection(){if current.connected{engine.disconnect()}else{preview.videoLayer.flushAndRemoveImage();engine.connect()}}
    @objc func toggleRecording(){
        refresh()
        if current.recording{engine.stopRecording();return}
        do{
            try profile.validateRecording()
            var limit:Double=0
            if durationToggle.state == .on {
                let parts=durationField.stringValue.split(separator:":",omittingEmptySubsequences:false)
                guard parts.count==3,let h=Int(parts[0]),let m=Int(parts[1]),let s=Int(parts[2]),h>=0,h<=999,m>=0,m<60,s>=0,s<60,h+m+s>0 else { throw RecorderError(message:"Enter a duration as hh:mm:ss, for example 00:30:00.") }
                limit=Double(h*3600+m*60+s)
            }
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let attributes=try FileManager.default.attributesOfFileSystem(forPath:folder.path)
            if let free=attributes[.systemFreeSize] as? NSNumber,free.int64Value<500_000_000{throw RecorderError(message:"Less than 500 MB free in the recording destination.")}
            let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd_HH-mm-ss"
            let name="Elgato_\(formatter.string(from:Date()))_\(UUID().uuidString.prefix(4)).\(profile.fileExtension)"
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
