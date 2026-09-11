import AppKit
import MetalKit

final class EffectPanel: NSPanel {
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { escape?() } }
}

final class OverlayController {
    private var panel: EffectPanel?
    private var view: DisplayPacedView?
    private var renderer: FoldRenderer?
    private var localKeys: Any?
    var framesPerSecond=120
    var hasPresentedClearFrame:Bool {renderer?.metrics.hasPresentedClearFrame ?? false}
    var isVisible: Bool { panel?.isVisible == true }
    var onStop: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var parameters: (Double) -> EffectParameters = {_ in EffectParameters() }
    var onPresent: (() -> Void)?

    func warmRenderer() throws {
        if renderer == nil {renderer=try FoldRenderer()}
    }
    func performanceSnapshot()->[String:Any] {
        var result=renderer?.metrics.snapshot() ?? [:];result["requestedFPS"]=framesPerSecond;return result
    }
    func prepare(screen: NSScreen, frames: FrameStore?) throws {
        hide()
        try warmRenderer()
        let renderer=renderer!
        renderer.frameStore = frames
        renderer.timedParameters = parameters
        renderer.onPresent = { [weak self] in
            if let panel=self?.panel, panel.isVisible, panel.alphaValue != 1 {panel.alphaValue=1}
            self?.onPresent?()
        }
        renderer.onFailure = { [weak self] message in self?.onFailure?(message) }
        self.renderer = renderer
        let panel = EffectPanel(contentRect: screen.frame, styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.isReleasedWhenClosed = false
        panel.alphaValue=0
        panel.escape = { [weak self] in self?.onStop?() }
        let view = DisplayPacedView(frame: NSRect(origin: .zero, size: screen.frame.size))
        renderer.attach(view); view.autoresizingMask = [.width, .height]
        panel.contentView = view
        (view.layer as? CAMetalLayer)?.isOpaque=false
        view.clearColor=MTLClearColorMake(0,0,0,0)
        view.preferredFramesPerSecond=min(120,screen.maximumFramesPerSecond)
        self.panel = panel; self.view = view
        view.isPaused = true
    }
    func show() {
        guard let panel, !panel.isVisible else { return }
        renderer?.reset()
        localKeys=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard self?.isVisible == true else {return event}
            if event.keyCode==53 { self?.onStop?() }
            return nil
        }
        panel.makeKeyAndOrderFront(nil)
        if let renderer {view?.startDisplayUpdates(framesPerSecond:framesPerSecond,renderer:renderer)}
    }
    func hide() {
        if let localKeys {NSEvent.removeMonitor(localKeys)}
        localKeys=nil
        view?.stopDisplayUpdates()
        view?.isPaused = true
        panel?.orderOut(nil)
        panel?.close(); panel = nil; view = nil; renderer?.releaseFrames();renderer?.frameStore=nil

    }
}
