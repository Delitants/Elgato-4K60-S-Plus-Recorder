import AppKit
final class RecordingSettings:NSObject {
 let window:NSWindow
 private var popups:[String:NSPopUpButton]=[:],fields:[String:NSTextField]=[:]
 private var original:RecordingProfile
 private let completion:(RecordingProfile)->Void
 private let explanation=NSTextField(wrappingLabelWithString:"")
 init(profile:RecordingProfile,completion:@escaping(RecordingProfile)->Void){
  original=profile;self.completion=completion
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:710,height:720),styleMask:[.titled],backing:.buffered,defer:false)
  super.init();window.title="Recording Settings"
  func popup(_ key:String,_ names:[String],_ index:Int)->NSView{let p=NSPopUpButton();p.addItems(withTitles:names);p.selectItem(at:min(max(0,index),names.count-1));p.target=self;p.action=#selector(update);popups[key]=p;return p}
  func field(_ key:String,_ value:String)->NSView{let f=NSTextField(string:value);fields[key]=f;return f}
  func integer(_ key:String,_ value:Int)->NSView{field(key,String(value))}
  let tabs=NSTabView()
  func tab(_ title:String,_ rows:[(String,NSView)]){
   let item=NSTabViewItem(identifier:title);item.label=title
   let grid=NSGridView(views:rows.map{[NSTextField(labelWithString:$0.0),$0.1]});grid.rowSpacing=10;grid.columnSpacing=16
   for(label,view)in rows{view.setAccessibilityLabel(label)}
   let view=NSView();grid.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(grid)
   NSLayoutConstraint.activate([grid.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:18),grid.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-18),grid.topAnchor.constraint(equalTo:view.topAnchor,constant:18)])
   item.view=view;tabs.addTabViewItem(item)
  }
  tab("Capture",[("Device encoder resolution",popup("capture4K",["1920 × 1080","3840 × 2160 (4K)"],profile.capture4K ? 1:0)),("Device video format",popup("captureHEVC",["H.264 · 8-bit","HEVC · 10-bit / HDR"],profile.captureHEVC ? 1:0)),("Device bitrate · Mbps",integer("deviceMbps",profile.deviceMbps)),("Video decoder",popup("decoder",["Automatic","Require hardware","Software"],profile.decoder))])
  tab("Video",[("Recorded video",popup("codec",["Original device stream","H.264","HEVC","ProRes 422","AV1 · software"],profile.codec)),("Mac encoder",popup("encoder",["Automatic","Require hardware","Software"],profile.encoder)),("Rate control",popup("rateControl",["ABR · average bitrate","CBR · constrained bitrate","CRF · constant quality"],RateControl.allCases.firstIndex(of:profile.rateControl)!)),("Video bitrate · Mbps",integer("videoMbps",profile.videoMbps)),("CRF quality",integer("quality",profile.quality)),("Compression preset",popup("preset",[profile.preset],0)),("Codec profile",popup("videoProfile",[profile.videoProfile],0)),("Keyframe seconds · 0 = Auto",integer("keyframeSeconds",profile.keyframeSeconds)),("Use B-frames",popup("bFrames",["Disabled","1","2","3","4"],profile.bFrames)),("Spatial AQ",popup("spatialAQ",["Auto","Enabled","Disabled"],AQMode.allCases.firstIndex(of:profile.spatialAQ)!)),("Rescale output",popup("scale",["Keep capture dimensions","1080p","720p"],profile.scale)),("Rescale sampling",popup("scalingFilter",["Disabled","Bilinear","Area","Bicubic","Lanczos"],ScalingFilter.allCases.firstIndex(of:profile.scalingFilter)!))])
  tab("Audio",[("Audio format",popup("audio",["PCM · lossless","AAC","Apple Lossless","Opus","FLAC"],profile.audio)),("Audio bitrate · kbps",integer("audioKbps",profile.audioKbps)),("Opus bitrate mode",popup("audioMode",["VBR","CBR","Constrained VBR"],["vbr","cbr","constrained"].firstIndex(of:profile.audioMode) ?? 0)),("Compression effort",integer("compressionLevel",profile.compressionLevel)),("HDMI audio",NSTextField(wrappingLabelWithString:"Stereo PCM · 48 kHz. This device cannot capture Dolby/DTS multichannel audio."))])
  tab("Output",[("Container",popup("container",["QuickTime MOV","MPEG-4 MP4","Matroska MKV","MPEG transport stream"],profile.container)),("File splitting",popup("splitMode",["Off","Split by time","Split by size"],profile.splitMode)),("Split interval · seconds",integer("splitSeconds",profile.splitSeconds)),("Target part size · MB",integer("splitMB",profile.splitMB)),("Split boundary",NSTextField(wrappingLabelWithString:"Parts start at source keyframes. Duration and size may exceed the target by a GOP plus container overhead. The recording timer applies to the whole session."))])
  tab("NDI",[("NDI® output",popup("ndiEnabled",["Off","On"],profile.ndiEnabled ? 1:0)),("Stream name",field("ndiName",profile.ndiName)),("NDI resolution",popup("ndiScale",["Capture resolution","1080p","720p"],profile.ndiScale)),("Receiver",NSTextField(wrappingLabelWithString:"Select this stream using DistroAV in OBS. Output includes video and stereo audio independently of local preview and recording. SDR output only.")),("About NDI",NSTextField(wrappingLabelWithString:"https://ndi.video\nNDI® is a registered trademark of Vizrt NDI AB."))])
  let cancel=NSButton(title:"Cancel",target:self,action:#selector(cancel));cancel.keyEquivalent="\u{1b}"
  let apply=NSButton(title:"Apply",target:self,action:#selector(apply));apply.keyEquivalent="\r"
  let buttons=NSStackView(views:[NSView(),cancel,apply]);buttons.spacing=12
  explanation.font = .systemFont(ofSize:12);explanation.textColor = .secondaryLabelColor
  let stack=NSStackView(views:[tabs,explanation,buttons]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-20),tabs.heightAnchor.constraint(equalToConstant:560)])
  for view in [tabs,explanation,buttons]{view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true};update()
 }
 private func index(_ key:String)->Int{popups[key]!.indexOfSelectedItem}
 private func number(_ key:String)->Int{Int(fields[key]!.stringValue) ?? -1}
 @objc private func update(){
  let c=index("codec"),sw=index("encoder")==2,transcode=c != 0
  func options(_ key:String,_ values:[String]){let p=popups[key]!;let selected=p.titleOfSelectedItem ?? "auto";if p.itemTitles != values{p.removeAllItems();p.addItems(withTitles:values);p.selectItem(withTitle:values.contains(selected) ? selected:"auto")}}
  options("preset",c==4 ? ["auto"]+(0...13).map(String.init):["auto","ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow"])
  options("videoProfile",c==1 ? ["auto","baseline","main","high"]:c==2 ? ["auto","main","main10"]:c==3 ? ["auto","proxy","lt","standard","hq"]:c==4 ? ["auto","main"]:["auto"])
  for key in ["encoder","rateControl","videoProfile","bFrames","spatialAQ","scale","scalingFilter"]{popups[key]!.isEnabled=transcode}
  popups["preset"]!.isEnabled=transcode && (sw || c==4)
  popups["spatialAQ"]!.isEnabled=c==1 || c==2;popups["bFrames"]!.isEnabled=c==1 || c==2
  fields["keyframeSeconds"]!.isEnabled=transcode && c != 3
  fields["videoMbps"]!.isEnabled=transcode && c != 3 && index("rateControl") != 2;fields["quality"]!.isEnabled=transcode && index("rateControl")==2
  fields["audioKbps"]!.isEnabled=index("audio")==1 || index("audio")==3;popups["audioMode"]!.isEnabled=index("audio")==3;fields["compressionLevel"]!.isEnabled=index("audio")>=3
  fields["splitSeconds"]!.isEnabled=index("splitMode")==1;fields["splitMB"]!.isEnabled=index("splitMode")==2
  if !transcode{popups["scale"]!.selectItem(at:0);popups["rateControl"]!.selectItem(at:0);popups["bFrames"]!.selectItem(at:0);popups["spatialAQ"]!.selectItem(at:0);fields["keyframeSeconds"]!.stringValue="0";popups["preset"]!.selectItem(at:0)}
  explanation.stringValue="Applying settings reconnects capture. HDR: choose HEVC capture and Original video. Use MKV for AV1, Opus, and FLAC. Unsupported combinations are checked before applying."
 }
 @objc private func cancel(){window.sheetParent?.endSheet(window)}
 @objc private func apply(){var p=original
  p.capture4K=index("capture4K")==1;p.captureHEVC=index("captureHEVC")==1;p.deviceMbps=number("deviceMbps");p.decoder=index("decoder")
  p.codec=index("codec");p.encoder=index("encoder");p.rateControl=RateControl.allCases[index("rateControl")];p.videoMbps=number("videoMbps");p.quality=number("quality");p.preset=popups["preset"]!.titleOfSelectedItem!;p.videoProfile=popups["videoProfile"]!.titleOfSelectedItem!;p.keyframeSeconds=number("keyframeSeconds");p.bFrames=index("bFrames");p.spatialAQ=AQMode.allCases[index("spatialAQ")];p.scale=index("scale");p.scalingFilter=ScalingFilter.allCases[index("scalingFilter")];if p.scalingFilter == .disabled{p.scale=0}
  p.audio=index("audio");p.audioKbps=number("audioKbps");p.audioMode=["vbr","cbr","constrained"][index("audioMode")];p.compressionLevel=number("compressionLevel")
  p.container=index("container");p.splitMode=index("splitMode");p.splitSeconds=number("splitSeconds");p.splitMB=number("splitMB");p.ndiEnabled=index("ndiEnabled")==1;p.ndiName=fields["ndiName"]!.stringValue;p.ndiScale=index("ndiScale")
  do{try p.validate();window.sheetParent?.endSheet(window);completion(p)}catch{let a=NSAlert();a.messageText="Check recording settings";a.informativeText=error.localizedDescription;a.beginSheetModal(for:window)}
 }
}
