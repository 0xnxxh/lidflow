import MetalKit
import QuartzCore

/// The view stays on the UI thread. Its CAMetalLayer is rendered exclusively by
/// a CAMetalDisplayLink on a dedicated run loop, independent of SwiftUI work.
final class DisplayPacedView:MTKView {
    private var driver:MetalFrameDriver?
    func startDisplayUpdates(framesPerSecond:Int,renderer:FoldRenderer) {
        stopDisplayUpdates()
        isPaused=true;enableSetNeedsDisplay=false;delegate=nil
        guard let layer=layer as? CAMetalLayer else{return}
        layer.presentsWithTransaction=false
        layer.maximumDrawableCount=3
        let rate=min(framesPerSecond,window?.screen?.maximumFramesPerSecond ?? 60)
        let driver=MetalFrameDriver(layer:layer,renderer:renderer,rate:rate)
        self.driver=driver;driver.start()
    }
    func stopDisplayUpdates() {driver?.stop();driver=nil}
    deinit {driver?.stop()}
}

private final class MetalFrameDriver:NSObject,CAMetalDisplayLinkDelegate {
    private let metalLayer:CAMetalLayer
    private let renderer:FoldRenderer
    private let rate:Int
    private var runLoop:CFRunLoop?
    private var link:CAMetalDisplayLink?
    private var thread:Thread?
    private let ready=DispatchSemaphore(value:0)
    private let finished=DispatchSemaphore(value:0)
    init(layer:CAMetalLayer,renderer:FoldRenderer,rate:Int) {
        metalLayer=layer;self.renderer=renderer;self.rate=rate
    }
    func start() {
        let thread=Thread{[self] in
            autoreleasepool {
                runLoop=CFRunLoopGetCurrent()
                let link=CAMetalDisplayLink(metalLayer:metalLayer)
                link.delegate=self
                link.preferredFrameRateRange=CAFrameRateRange(minimum:Float(rate),maximum:Float(rate),preferred:Float(rate))
                link.preferredFrameLatency=2
                self.link=link
                link.add(to:.current,forMode:.default)
                ready.signal()
                CFRunLoopRun()
                link.invalidate();self.link=nil
                finished.signal()
            }
        }
        thread.name="LidFlow Metal display";thread.qualityOfService = .userInteractive
        self.thread=thread;thread.start();ready.wait()
    }
    func metalDisplayLink(_ link:CAMetalDisplayLink,needsUpdate update:CAMetalDisplayLink.Update) {
        autoreleasepool {
            renderer.drawFrame(drawable:update.drawable,presentationTime:update.targetPresentationTimestamp)
        }
    }
    func stop() {
        guard let runLoop,thread != nil else{return}
        CFRunLoopPerformBlock(runLoop,CFRunLoopMode.defaultMode.rawValue) {CFRunLoopStop(runLoop)}
        CFRunLoopWakeUp(runLoop)
        // The rendering loop never synchronously calls the main thread.
        finished.wait();thread=nil;self.runLoop=nil
    }
}
