import AppKit
import MetalKit
import MetalPerformanceShaders
import CoreVideo
import FoldCore

struct EffectParameters {
    var progress: Float = 0
    var perspective: Float = 1
    var blur: Float = 0.85
    var shadow: Float = 0.7
    var style: Float = 0
    var aspect: Float = 1.6
    var handoff:Float = 0
    var prefiltered:Float = 0
}

final class FrameStore {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var generation: UInt64 = 0
    private var frameCount: UInt64 = 0
    func put(_ frame: CVPixelBuffer) {
        lock.lock(); defer { lock.unlock() }
        buffer = frame; generation &+= 1; frameCount &+= 1
    }
    func clear() { lock.lock(); buffer = nil; generation &+= 1; lock.unlock() }
    func snapshot() -> (CVPixelBuffer?, UInt64, UInt64) {
        lock.lock(); defer { lock.unlock() }
        return (buffer, generation, frameCount)
    }
}

final class FoldRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let ashPipeline: MTLRenderPipelineState
    let sample: MTLTexture
    let metrics=RenderMetrics()
    private let scaler:MPSImageBilinearScale
    private var blurKernels:[MPSImageGaussianBlur]=[]
    var parameters: () -> EffectParameters = { EffectParameters() }
    var timedParameters: ((Double)->EffectParameters)?
    private var announcedFirstFrame=false
    var frameStore: FrameStore?
    var onPresent: (() -> Void)?
    var isEnabled: () -> Bool = { true }
    private var cache: CVMetalTextureCache?
    private var blurred: [MTLTexture] = []
    private var smallSource: MTLTexture?
    private var source: MTLTexture?
    private var retainedCVTexture: CVMetalTexture?
    private var retainedBuffer: CVPixelBuffer?
    private var generation: UInt64 = .max
    private var smoothed = 0.0
    private var lastTime: CFTimeInterval = 0
    private let inFlight = DispatchSemaphore(value: 2)
    private var sampleBlurred = false
    private var previousParameters: EffectParameters?
    private var resized = true
    var onFailure: ((String) -> Void)?

    init(rendering: Void = ()) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "LidFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: "这台 Mac 无法创建 Metal 设备。"])
        }
        self.device = device; self.queue = queue
        scaler=MPSImageBilinearScale(device:device)
        let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal")!
        let library = try device.makeLibrary(source: String(contentsOf: shaderURL,encoding:.utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.vertexFunction = library.makeFunction(name: "ashVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "ashFragment")
        let attachment = descriptor.colorAttachments[0]!
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        ashPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        sample = try Self.makeArtwork(device: device)
        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    }

    func attach(_ view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0,0,0,1)
        view.preferredFramesPerSecond = min(120,view.window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = self
    }
    func reset() { smoothed = 0; lastTime = 0; previousParameters = nil; resized = true;metrics.reset();announcedFirstFrame=false }
    func releaseFrames() {retainedBuffer=nil;retainedCVTexture=nil;source=nil;generation = .max;sampleBlurred=false}
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { resized = true }
    func draw(in view: MTKView) {
        guard isEnabled(),view.window?.isVisible == true,view.window?.isMiniaturized == false else{return}
        drawFrame(drawable:nil,presentationTime:CACurrentMediaTime(),previewView:view)
    }
    func drawFrame(drawable suppliedDrawable:CAMetalDrawable?,presentationTime:Double,previewView:MTKView? = nil) {
        let now=CACurrentMediaTime()
        let frameTime=presentationTime>0 ? presentationTime : now
        var p=timedParameters?(frameTime) ?? parameters()
        let frames = frameStore?.snapshot()
        let sourceChanged = frames.map { $0.1 != generation } ?? false
        let settling = abs(smoothed - Double(p.progress)) > 0.0001
        if suppliedDrawable == nil && !resized && !sourceChanged && !settling, let previousParameters,
           previousParameters.progress == p.progress && previousParameters.perspective == p.perspective &&
           previousParameters.blur == p.blur && previousParameters.shadow == p.shadow && previousParameters.style == p.style {
            lastTime = now
            return
        }
        guard inFlight.wait(timeout: .now()) == .success else { metrics.dropped();return }
        guard let command = queue.makeCommandBuffer() else {inFlight.signal();return}
        let importStart=CACurrentMediaTime()
        previousParameters = p; resized = false
        smoothed = p.prefiltered>0.5 ? Double(p.progress) : FoldDynamics.smooth(smoothed, toward: Double(p.progress), dt: lastTime == 0 ? 1/120 : frameTime-lastTime)
        if abs(smoothed-Double(p.progress)) < 0.0001 { smoothed = Double(p.progress) }
        lastTime = frameTime; p.progress = Float(smoothed)
        var dirty = !sampleBlurred
        var texture = sample
        if let frames {
            let (buffer, id, _) = frames
            if id != generation {
                generation = id
                retainedBuffer = buffer; retainedCVTexture = nil; source = nil
                if let buffer, let cache {
                    var cv: CVMetalTexture?
                    let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil,
                        .bgra8Unorm, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &cv)
                    if result == kCVReturnSuccess, let cv { retainedCVTexture = cv; source = CVMetalTextureGetTexture(cv) }
                }
                dirty = true
            }
            guard let source else { inFlight.signal(); return }
            texture = source
        }
        p.aspect=Float(texture.width)/Float(texture.height)
        let importEnd=CACurrentMediaTime()
        if blurred.isEmpty || dirty {
            prepareBlur(texture, command: command)
            sampleBlurred = true
        }
        let filterEnd=CACurrentMediaTime()
        // Acquire the drawable late: expensive work must not consume its deadline.
        let drawable:CAMetalDrawable
        let pass:MTLRenderPassDescriptor
        if let suppliedDrawable {
            drawable=suppliedDrawable
            pass=MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1)
        } else {
            guard let existingPass=previewView?.currentRenderPassDescriptor,let existingDrawable=previewView?.currentDrawable else {inFlight.signal();return}
            drawable=existingDrawable;pass=existingPass
        }
        let drawableReady=CACurrentMediaTime()
        metrics.stages(drawableWait:(drawableReady-filterEnd)*1000,textureImport:(importEnd-importStart)*1000,
                       filterEncode:(filterEnd-importEnd)*1000)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { inFlight.signal(); return }
        encodeEffect(encoder, texture:texture, parameters:p)
        encoder.endEncoding()
        let buffer = retainedBuffer, cvTexture = retainedCVTexture
        let semaphore = inFlight
        let callback = announcedFirstFrame ? nil : onPresent
        announcedFirstFrame=true
        let failure = onFailure
        let metrics=metrics
        metrics.submitted(cpuMilliseconds:(CACurrentMediaTime()-now)*1000,onMainThread:Thread.isMainThread)
        let presentedProgress=p.progress
        let handoff=p.handoff>0.5
        drawable.addPresentedHandler {metrics.presented(at:$0.presentedTime,progress:Double(presentedProgress),handoff:handoff)}
        command.addCompletedHandler { result in
            withExtendedLifetime((buffer, cvTexture)) {}
            semaphore.signal()
            metrics.completed(gpuMilliseconds:(result.gpuEndTime-result.gpuStartTime)*1000)
            if result.status == .completed { DispatchQueue.main.async { callback?() } }
            else { DispatchQueue.main.async { failure?("Metal 渲染中断，已恢复桌面") } }
        }
        command.present(drawable)
        command.commit()
    }

    /// Shared by the live view and offscreen verification, including the particle pass.
    func encodeEffect(_ encoder:MTLRenderCommandEncoder,texture:MTLTexture,parameters:EffectParameters) {
        var p=parameters
        p.aspect=Float(texture.width)/Float(texture.height)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&p,length:MemoryLayout<EffectParameters>.stride,index:0)
        encoder.setFragmentTexture(texture,index:0)
        for i in 0..<3 {encoder.setFragmentTexture(blurred.indices.contains(i) ? blurred[i] : texture,index:i+1)}
        encoder.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4)
        if p.style>2.5 && p.progress>0.00005 {
            let columns=Int(floor(144-68*p.shadow))
            let rows=Int(ceil(Float(columns)/max(p.aspect,0.5)))
            encoder.setRenderPipelineState(ashPipeline)
            encoder.setVertexBytes(&p,length:MemoryLayout<EffectParameters>.stride,index:0)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3,instanceCount:columns*rows*2)
        }
    }

    func prepareBlur(_ texture: MTLTexture, command: MTLCommandBuffer) {
        let width = min(960, texture.width)
        let height = max(1, Int(Double(width)*Double(texture.height)/Double(texture.width)))
        if smallSource?.width != width || smallSource?.height != height {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]; desc.storageMode = .private
            smallSource = device.makeTexture(descriptor: desc)
            blurred = (0..<3).compactMap { _ in device.makeTexture(descriptor: desc) }
            blurKernels=[4.0,11.0,25.0].map {sigma in
                let kernel=MPSImageGaussianBlur(device:device,sigma:Float(sigma)*Float(width)/960)
                kernel.edgeMode = .clamp;return kernel
            }
        }
        guard let smallSource, blurred.count == 3 else { return }
        scaler.encode(commandBuffer: command, sourceTexture: texture, destinationTexture: smallSource)
        for (i,kernel) in blurKernels.enumerated() {
            kernel.encode(commandBuffer: command, sourceTexture: smallSource, destinationTexture: blurred[i])
        }
    }

    private static func makeArtwork(device: MTLDevice) throws -> MTLTexture {
        let w=1440, h=900
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        NSGradient(colors:[NSColor(red:0.11,green:0.20,blue:0.28,alpha:1),NSColor(red:0.49,green:0.65,blue:0.68,alpha:1)])!.draw(in:NSRect(x:0,y:0,width:w,height:h),angle:90)
        for (index,color) in [NSColor(red:0.15,green:0.34,blue:0.39,alpha:1), NSColor(red:0.28,green:0.48,blue:0.50,alpha:1),NSColor(red:0.58,green:0.71,blue:0.69,alpha:1)].enumerated() {
            let y=Double(330-index*110)
            let path=NSBezierPath(); path.move(to:NSPoint(x:0,y:0));path.line(to:NSPoint(x:0,y:y))
            path.curve(to:NSPoint(x:1440,y:y+90),controlPoint1:NSPoint(x:500,y:y+260),controlPoint2:NSPoint(x:950,y:y-250))
            path.line(to:NSPoint(x:1440,y:0));path.close();color.setFill();path.fill()
        }
        func centered(_ text:String,y:Double,font:NSFont,color:NSColor) {
            let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:color]
            let size=(text as NSString).size(withAttributes:attrs)
            (text as NSString).draw(at:NSPoint(x:(1440-size.width)/2,y:y),withAttributes:attrs)
        }
        centered("THURSDAY · LIDFLOW",y:690,font:.systemFont(ofSize:23,weight:.medium),color:.white.withAlphaComponent(0.72))
        centered("09:41",y:520,font:.systemFont(ofSize:142,weight:.ultraLight),color:.white.withAlphaComponent(0.94))
        centered("让桌面，随角度流动。",y:450,font:.systemFont(ofSize:25,weight:.regular),color:.white.withAlphaComponent(0.72))
        NSColor.white.withAlphaComponent(0.25).setFill(); NSBezierPath(roundedRect:NSRect(x:490,y:24,width:460,height:66),xRadius:22,yRadius:22).fill()
        for i in 0..<7 {
            let x=Double(509+i*63)
            NSColor(calibratedHue:CGFloat(i)/9,saturation:0.37,brightness:0.95,alpha:0.95).setFill()
            NSBezierPath(roundedRect:NSRect(x:x,y:35,width:44,height:44),xRadius:11,yRadius:11).fill()
            let symbol=NSImage(systemSymbolName:["safari","folder.fill","calendar","music.note","photo","gearshape.fill","terminal"][i],accessibilityDescription:nil)!
            symbol.draw(in:NSRect(x:x+10,y:45,width:24,height:24))
        }
        NSGraphicsContext.restoreGraphicsState()
        return try MTKTextureLoader(device:device).newTexture(cgImage:rep.cgImage!,options:[.SRGB:false])
    }
}
