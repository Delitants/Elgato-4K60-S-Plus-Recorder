import AppKit

final class TerminationTestApplication:NSApplication {
    var replies=[Bool]()
    override func reply(toApplicationShouldTerminate value:Bool){replies.append(value)}
}
@main struct WindowLifecycleTests {
    static func main(){
        let app=TerminationTestApplication.shared as! TerminationTestApplication
        app.setActivationPolicy(.prohibited)
        func controller()->AppDelegate {
            let delegate=AppDelegate()
            delegate.window=NSWindow(contentRect:.zero,styleMask:.titled,backing:.buffered,defer:true)
            delegate.window.isReleasedWhenClosed=false
            delegate.timer=Timer(timeInterval:3600,repeats:true){_ in}
            return delegate
        }
        // A window-close notification must stop refresh before asynchronous quit
        // finishes. A callback already queued by the run loop must be harmless.
        let closed=controller();let closeTimer=closed.timer!
        let observer:NSWindowDelegate=closed
        observer.windowWillClose?(Notification(name:NSWindow.willCloseNotification,object:closed.window))
        guard !closeTimer.isValid else{print("FAIL window close left the refresh timer active");exit(1)}
        closed.status.stringValue="closed sentinel";closed.refresh()
        guard closed.status.stringValue=="closed sentinel" else{print("FAIL queued refresh touched closed-window UI");exit(1)}
        // Closing a different window must not suspend the main recorder.
        let active=controller();let activeTimer=active.timer!
        let other=NSWindow(contentRect:.zero,styleMask:.titled,backing:.buffered,defer:true)
        other.isReleasedWhenClosed=false
        (active as NSWindowDelegate).windowWillClose?(Notification(name:NSWindow.willCloseNotification,object:other))
        guard activeTimer.isValid else{print("FAIL another window stopped the recorder UI");exit(1)}
        activeTimer.invalidate()
        // Menu/Dock quit must stop refresh too. Repeated quit requests must not
        // replace the pending completion or produce duplicate termination replies.
        let quitting=controller();let quitTimer=quitting.timer!
        guard quitting.applicationShouldTerminate(app) == .terminateLater else{exit(1)}
        guard !quitTimer.isValid else{print("FAIL quit left the refresh timer active");exit(1)}
        _=quitting.applicationShouldTerminate(app)
        quitting.status.stringValue="quit sentinel";quitting.refresh()
        guard quitting.status.stringValue=="quit sentinel" else{print("FAIL refresh ran during deferred termination");exit(1)}
        let limit=Date().addingTimeInterval(1)
        while Date()<limit{RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
        guard app.replies==[true] else{print("FAIL deferred termination replies: \(app.replies)");exit(1)}
        print("PASS window-close and quit stop UI refresh; unrelated windows remain active; one deferred termination reply")
    }
}
