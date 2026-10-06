import AppKit
final class RecordingSettings:NSObject {
 let window:NSWindow
 private let tabs=NSTabView()
 private var popups:[String:NSPopUpButton]=[:],fields:[String:NSTextField]=[:]
 private var original:RecordingProfile
 private let completion:(RecordingProfile)->Void
 private let explanation=NSTextField(wrappingLabelWithString:"")
 private let compressionNote=NSTextField(wrappingLabelWithString:"")
 private let usbSpeed:Int
 init(profile:RecordingProfile,usbSpeed:Int=0,completion:@escaping(RecordingProfile)->Void){
  original=profile;self.usbSpeed=usbSpeed;self.completion=completion
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:710,height:720),styleMask:[.titled],backing:.buffered,defer:false)
  super.init();window.title="Recording Settings"
  func popup(_ key:String,_ names:[String],_ index:Int)->NSView{let p=NSPopUpButton();p.addItems(withTitles:names);p.selectItem(at:min(max(0,index),names.count-1));p.target=self;p.action=#selector(update);popups[key]=p;return p}
  func field(_ key:String,_ value:String)->NSView{let f=NSTextField(string:value);fields[key]=f;return f}
  func integer(_ key:String,_ value:Int)->NSView{field(key,String(value))}
  tabs.tabViewType = .noTabsNoBorder
  let navigation=NSSegmentedControl(labels:["Capture","Video","Audio","Output","NDI"],trackingMode:.selectOne,target:self,action:#selector(selectTab(_:)))
  navigation.segmentStyle = .rounded;navigation.font = .systemFont(ofSize:13);navigation.selectedSegment=0
  navigation.setAccessibilityLabel("Recording settings pages")
  let navigationRow=NSView();navigation.translatesAutoresizingMaskIntoConstraints=false;navigationRow.addSubview(navigation)
  NSLayoutConstraint.activate([navigation.centerXAnchor.constraint(equalTo:navigationRow.centerXAnchor),navigation.topAnchor.constraint(equalTo:navigationRow.topAnchor),navigation.bottomAnchor.constraint(equalTo:navigationRow.bottomAnchor)])
  func tab(_ title:String,_ rows:[(String,NSView)]){
   let item=NSTabViewItem(identifier:title);item.label=title
   let grid=NSGridView(views:rows.map{[NSTextField(labelWithString:$0.0),$0.1]});grid.rowSpacing=title=="Video" ? 7:10;grid.columnSpacing=16
   for(label,view)in rows{view.setAccessibilityLabel(label)}
   let view=NSView();grid.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(grid)
   NSLayoutConstraint.activate([grid.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:18),grid.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-18),grid.topAnchor.constraint(equalTo:view.topAnchor,constant:18)])
   item.view=view;tabs.addTabViewItem(item)
  }
  tab("Capture",[("Device encoder resolution",popup("capture4K",["1920 × 1080","3840 × 2160 (4K)"],profile.capture4K ? 1:0)),("Device video format",popup("captureHEVC",["H.264 · 8-bit","HEVC · 10-bit / HDR"],profile.captureHEVC ? 1:0)),("Encoder target bitrate",popup("deviceMbps",["\(profile.deviceMbps) Mbps"],0)),("Capture connection",NSTextField(wrappingLabelWithString:usbSpeed>0 && usbSpeed<4 ? "USB 2 is unsupported. Connect a USB 3 cable and port before capture.":"USB 3 is required. Bitrate is the device encoder target, not USB throughput.")),("Source content cadence / cap",popup("sourceFPS",["Automatic · incoming stream"]+FrameRateChoice.allCases.dropFirst().map{$0.title},FrameRateChoice.allCases.firstIndex(of:profile.sourceFPS)!)),("Video decoder",popup("decoder",["Automatic","Require hardware","Software"],profile.decoder))])
  tab("Video",[("Recorded video",popup("codec",["Original device stream","H.264 / AVC","HEVC","ProRes 422","AV1 · software"],profile.codec)),("Output FPS · preview / record / NDI",popup("outputFPS",FrameRateChoice.allCases.map{$0.title},FrameRateChoice.allCases.firstIndex(of:profile.outputFPS)!)),("Mac encoder",popup("encoder",["Automatic","Require hardware","Software"],profile.encoder)),("Rate control",popup("rateControl",["ABR · average bitrate","CBR · constrained bitrate","CRF · software constant quality",RecordingProfile.hardwareCQBuildSupported ? "CQ · hardware constant quality":"CQ · requires Apple Silicon"],RateControl.allCases.firstIndex(of:profile.rateControl)!)),("Video bitrate · Mbps",integer("videoMbps",profile.videoMbps)),("CRF quality",integer("quality",profile.quality)),("Hardware CQ · 0–100",integer("hardwareQuality",profile.hardwareQuality)),("Software compression effort",popup("preset",[profile.preset],0)),("Codec profile",popup("videoProfile",[profile.videoProfile],0)),("Keyframe seconds · 0 = Auto",integer("keyframeSeconds",profile.keyframeSeconds)),("Use B-frames",popup("bFrames",["Disabled","1","2","3","4"],profile.bFrames)),("Spatial AQ",popup("spatialAQ",["Auto","Enabled","Disabled"],AQMode.allCases.firstIndex(of:profile.spatialAQ)!)),("Rescale output",popup("scale",["Keep capture dimensions","1080p","720p"],profile.scale)),("Rescale sampling",popup("scalingFilter",["Disabled","Bilinear","Area","Bicubic","Lanczos"],ScalingFilter.allCases.firstIndex(of:profile.scalingFilter)!))])
  popups["rateControl"]!.autoenablesItems=false
  popups["rateControl"]!.toolTip="Hardware CQ is available for H.264/HEVC in the native Apple Silicon app. Intel builds support ABR/CBR and software CRF. CQ never falls back to software or bitrate control."
  fields["hardwareQuality"]!.toolTip="Hardware constant quality: 0–100; higher means better quality and larger files. Start at 65 and compare representative motion and gradients. 100 is not lossless. File size and bitrate vary with the scene; no bitrate cap applies. Available in the native Apple Silicon app for H.264/HEVC."
  popups["sourceFPS"]!.toolTip="Choose 23.976 or 24 fps for film repeated inside a 59.94/60 fps stream. At native output cadence, recording recovers the original picture sequence. Other choices cap processing. This does not change HDMI or device FPS; Incoming remains measured."
  popups["preset"]!.toolTip="Select Software under Mac encoder to choose x264/x265 speed and compression effort. Hardware encoding does not expose these presets."
  compressionNote.font = .systemFont(ofSize:11);compressionNote.textColor = .secondaryLabelColor
  if let video=tabs.tabViewItems.first(where:{$0.label=="Video"})?.view {
   compressionNote.translatesAutoresizingMaskIntoConstraints=false;video.addSubview(compressionNote)
   NSLayoutConstraint.activate([compressionNote.leadingAnchor.constraint(equalTo:video.leadingAnchor,constant:18),compressionNote.trailingAnchor.constraint(equalTo:video.trailingAnchor,constant:-18),compressionNote.topAnchor.constraint(equalTo:video.subviews[0].bottomAnchor,constant:12)])
  }
  tab("Audio",[("Audio format",popup("audio",["PCM · lossless","AAC","Apple Lossless","Opus","FLAC"],profile.audio)),("Audio bitrate · kbps",integer("audioKbps",profile.audioKbps)),("Opus bitrate mode",popup("audioMode",["VBR","CBR","Constrained VBR"],["vbr","cbr","constrained"].firstIndex(of:profile.audioMode) ?? 0)),("Compression effort",integer("compressionLevel",profile.compressionLevel)),("HDMI audio",NSTextField(wrappingLabelWithString:"Stereo PCM · 48 kHz. This device cannot capture Dolby/DTS multichannel audio."))])
  tab("Output",[("Container",popup("container",["QuickTime MOV","MPEG-4 MP4","Matroska MKV","MPEG transport stream"],profile.container)),("MKV network playback",popup("mkvNetworkPlayback",["Default layout","Prefer seek index at front"],profile.mkvNetworkPlayback ? 1:0)),("Network playback",NSTextField(wrappingLabelWithString:"For completed MKV files served over DLNA/HTTP. Preserves encoded quality; reserves 1 MiB per file. Falls back to an end index with a warning if full. TV/server seeking support is still required.")),("File splitting",popup("splitMode",["Off","Split by time","Split by size"],profile.splitMode)),("Split interval · seconds",integer("splitSeconds",profile.splitSeconds)),("Target part size · MB",integer("splitMB",profile.splitMB)),("Split boundary",NSTextField(wrappingLabelWithString:"Splits wait for a source keyframe, then the next selected output frame. Targets may be exceeded by a GOP, one output interval, and buffering. The recording timer applies to the whole session."))])
  tab("NDI",[("NDI® output",popup("ndiEnabled",["Off","On"],profile.ndiEnabled ? 1:0)),("Stream name",field("ndiName",profile.ndiName)),("NDI resolution",popup("ndiScale",["Capture resolution","1080p","720p"],profile.ndiScale)),("Receiver",NSTextField(wrappingLabelWithString:"Select this stream using DistroAV in OBS. Output includes video and stereo audio independently of local preview and recording. SDR output only.")),("About NDI",NSTextField(wrappingLabelWithString:"https://ndi.video\nNDI® is a registered trademark of Vizrt NDI AB."))])
  let cancel=NSButton(title:"Cancel",target:self,action:#selector(cancel));cancel.keyEquivalent="\u{1b}"
  let apply=NSButton(title:"Apply",target:self,action:#selector(apply));apply.keyEquivalent="\r"
  let buttons=NSStackView(views:[NSView(),cancel,apply]);buttons.spacing=12
  explanation.font = .systemFont(ofSize:12);explanation.textColor = .secondaryLabelColor
  let stack=NSStackView(views:[navigationRow,tabs,explanation,buttons]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-20),tabs.heightAnchor.constraint(equalToConstant:520)])
  for view in [navigationRow,tabs,explanation,buttons]{view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true};update()
 }
 @objc private func selectTab(_ sender:NSSegmentedControl){tabs.selectTabViewItem(at:sender.selectedSegment)}
 private func index(_ key:String)->Int{popups[key]!.indexOfSelectedItem}
 private func number(_ key:String)->Int{Int(fields[key]!.stringValue) ?? -1}
 private func updateDeviceBitrates(){
  let popup=popups["deviceMbps"]!,maximum=index("captureHEVC")==1 ? 140:200
  let selected=Int((popup.titleOfSelectedItem ?? "").split(separator:" ").first ?? "") ?? original.deviceMbps
  var values=[10,20,40,60,80,100,140,200].filter{$0<=maximum}
  if (1...maximum).contains(original.deviceMbps) && !values.contains(original.deviceMbps){values.append(original.deviceMbps)}
  if (1...maximum).contains(selected) && !values.contains(selected){values.append(selected)}
  values.sort()
  let titles=values.map{value in "\(value) Mbps" + (value==40 ? " · recommended default":![10,20,40,60,80,100,140,200].contains(value) ? " · saved custom":"")}
  if popup.itemTitles != titles{popup.removeAllItems();popup.addItems(withTitles:titles)}
  popup.selectItem(at:values.firstIndex(of:min(maximum,max(1,selected))) ?? values.firstIndex(of:40)!)
  popup.toolTip="Device encoder target bitrate, not USB throughput. 40 Mbps is the default starting point; increase for more detail. Maximum: \(maximum) Mbps. USB 3 is required."
 }
 @objc private func update(){
  updateDeviceBitrates()
  let c=index("codec"),sw=index("encoder")==2,transcode=c != 0
  func options(_ key:String,_ values:[String]){let p=popups[key]!;let selected=p.titleOfSelectedItem ?? "auto";if p.itemTitles != values{p.removeAllItems();p.addItems(withTitles:values);p.selectItem(withTitle:values.contains(selected) ? selected:"auto")}}
  options("preset",c==4 ? ["auto"]+(0...13).map(String.init):["auto","ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow"])
  options("videoProfile",c==1 ? ["auto","baseline","main","high"]:c==2 ? ["auto","main","main10"]:c==3 ? ["auto","proxy","lt","standard","hq"]:c==4 ? ["auto","main"]:["auto"])
  for key in ["encoder","rateControl","videoProfile","bFrames","spatialAQ","scale","scalingFilter"]{popups[key]!.isEnabled=transcode}
  popups["preset"]!.isEnabled=(c==1 || c==2) && sw || c==4
  if !popups["preset"]!.isEnabled{popups["preset"]!.selectItem(withTitle:"auto")}
  compressionNote.stringValue=c==4 ? "AV1 software effort: lower numbers compress more efficiently but encode more slowly.":"For x264/x265 effort presets, choose H.264 or HEVC and Mac encoder → Software. Slower presets trade more CPU time for compression efficiency. Hardware encoding does not expose x264/x265 effort presets."
  popups["spatialAQ"]!.isEnabled=c==1 || c==2;popups["bFrames"]!.isEnabled=c==1 || c==2
  fields["keyframeSeconds"]!.isEnabled=transcode && c != 3
  let rc=RateControl.allCases[index("rateControl")],cq=rc == .cq
  popups["rateControl"]!.item(at:3)?.isEnabled=RecordingProfile.hardwareCQBuildSupported && (c==1 || c==2) && !sw
  fields["videoMbps"]!.isEnabled=transcode && c != 3 && (rc == .abr || rc == .cbr)
  fields["quality"]!.isEnabled=transcode && rc == .crf
  fields["hardwareQuality"]!.isEnabled=(c==1 || c==2) && !sw && cq && RecordingProfile.hardwareCQBuildSupported
  if cq{compressionNote.stringValue="Hardware CQ: higher quality means larger files. Bitrate varies with the scene; there is no size or bitrate cap. Start at 65. Quality 100 is not lossless. CQ requires the native Apple Silicon app and hardware H.264/HEVC."}
  fields["audioKbps"]!.isEnabled=index("audio")==1 || index("audio")==3;popups["audioMode"]!.isEnabled=index("audio")==3;fields["compressionLevel"]!.isEnabled=index("audio")>=3
  popups["mkvNetworkPlayback"]!.isEnabled=index("container")==2
  fields["splitSeconds"]!.isEnabled=index("splitMode")==1;fields["splitMB"]!.isEnabled=index("splitMode")==2
  if !transcode{popups["scale"]!.selectItem(at:0);popups["rateControl"]!.selectItem(at:0);popups["bFrames"]!.selectItem(at:0);popups["spatialAQ"]!.selectItem(at:0);fields["keyframeSeconds"]!.stringValue="0";popups["preset"]!.selectItem(at:0)}
  var pending=original;pending.codec=c;pending.encoder=index("encoder");pending.bFrames=index("bFrames");pending.rateControl=RateControl.allCases[index("rateControl")]
  if usbSpeed>0 && usbSpeed<4{explanation.stringValue="USB 2 is unsupported. Use a USB 3 cable and port; changing encoder bitrate cannot make USB 2 capture supported.";explanation.textColor = .systemOrange;return}
  if let warning=pending.recordingWarning{explanation.stringValue=warning;explanation.textColor = .systemOrange;return}
  explanation.textColor = .secondaryLabelColor
  explanation.stringValue="Applying settings reconnects capture. HDR: choose HEVC capture and Original video. FPS follows incoming timestamps; physical HDMI timing is unverified. Source cadence cap limits processing; Incoming FPS still measures the device stream. Lower output FPS requires a video encoder for recording."
 }
 @objc private func cancel(){window.sheetParent?.endSheet(window)}
 @objc private func apply(){update();var p=original
  p.sourceFPS=FrameRateChoice.allCases[index("sourceFPS")];p.outputFPS=FrameRateChoice.allCases[index("outputFPS")]
  p.capture4K=index("capture4K")==1;p.captureHEVC=index("captureHEVC")==1;p.deviceMbps=Int(popups["deviceMbps"]!.titleOfSelectedItem!.split(separator:" ")[0]) ?? original.deviceMbps;p.decoder=index("decoder")
  p.codec=index("codec");p.encoder=index("encoder");p.rateControl=RateControl.allCases[index("rateControl")];p.videoMbps=number("videoMbps");p.quality=number("quality");p.hardwareQuality=number("hardwareQuality");p.preset=popups["preset"]!.titleOfSelectedItem!;p.videoProfile=popups["videoProfile"]!.titleOfSelectedItem!;p.keyframeSeconds=number("keyframeSeconds");p.bFrames=index("bFrames");p.spatialAQ=AQMode.allCases[index("spatialAQ")];p.scale=index("scale");p.scalingFilter=ScalingFilter.allCases[index("scalingFilter")];if p.scalingFilter == .disabled{p.scale=0}
  p.audio=index("audio");p.audioKbps=number("audioKbps");p.audioMode=["vbr","cbr","constrained"][index("audioMode")];p.compressionLevel=number("compressionLevel")
  p.container=index("container");p.mkvNetworkPlayback=index("mkvNetworkPlayback")==1;p.splitMode=index("splitMode");p.splitSeconds=number("splitSeconds");p.splitMB=number("splitMB");p.ndiEnabled=index("ndiEnabled")==1;p.ndiName=fields["ndiName"]!.stringValue;p.ndiScale=index("ndiScale")
  do{try p.validateRecording();window.sheetParent?.endSheet(window);completion(p)}catch{let a=NSAlert();a.messageText="Check recording settings";a.informativeText=error.localizedDescription;a.beginSheetModal(for:window)}
 }
}
