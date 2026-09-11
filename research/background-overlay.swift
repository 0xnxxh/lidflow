import AppKit
import MetalKit

/// Developer-only test host. No capture permission, no sensor overrides, and
/// no production settings: exercises the real nonactivating overlay classes.
@main struct BackgroundOverlayCheck {
    static func main() {
        let application=NSApplication.shared
        let delegate=CheckDelegate()
        application.delegate=delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {application.run()}
    }
}
@MainActor final class CheckDelegate:NSObject,NSApplicationDelegate {
    private let overlay=OverlayController()
    private var timer:Timer?
    private var activeSamples=0,visibleSamples=0,keySamples=0,ready=0
    private var stopped=false
    private var frontBefore="",frontAfter=""
    private var ownFrontSamples=0
    func applicationDidFinishLaunching(_ notification:Notification) {
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {self.start()}
    }
    private func start() {
        guard let screen=NSScreen.main else {finish(error:"No screen");return}
        frontBefore=NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        do {
            overlay.parameters={time in
                var p=EffectParameters();p.style=0;p.progress=Float(0.3+0.15*sin(time));return p
            }
            overlay.onPresent={[weak self] in self?.ready+=1}
            overlay.onStop={[weak self] in self?.finish(escaped:true)}
            overlay.onFailure={[weak self] in self?.finish(error:$0)}
            try overlay.prepare(screen:screen,frames:nil);overlay.show()
            timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) {[weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else{return}
                    if NSApp.isActive {self.activeSamples+=1}
                    self.frontAfter=NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                    if self.frontAfter==Bundle.main.bundleIdentifier {self.ownFrontSamples+=1}
                    if self.overlay.isVisible {self.visibleSamples+=1}
                    if NSApp.keyWindow != nil {self.keySamples+=1}
                }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+8) {self.finish()}
        } catch {finish(error:error.localizedDescription)}
    }
    private func finish(escaped:Bool=false,error:String?=nil) {
        guard !stopped else{return};stopped=true;timer?.invalidate()
        let metrics=overlay.performanceSnapshot()
        overlay.hide()
        let passed=error==nil && ready>0 && visibleSamples>0 && ownFrontSamples==0 && !overlay.isVisible
        let report:[String:Any]=["passed":passed,"error":error as Any? ?? NSNull(),"escaped":escaped,
            "activeSamples":activeSamples,"ownFrontSamples":ownFrontSamples,"frontBefore":frontBefore,"frontAfter":frontAfter,"visibleSamples":visibleSamples,"keySamples":keySamples,"ready":ready,"render":metrics,
            "scope":"real overlay classes; sample artwork; no desktop capture or hardware input"]
        do {
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        } catch {fputs("Failed to write background overlay report: \(error)\n",stderr)}
        NSApp.terminate(nil)
    }
}
