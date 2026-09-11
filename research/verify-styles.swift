import AppKit
import MetalKit

@main struct StyleCheck {
    static func main() throws {
        let renderer=try FoldRenderer()
        let folder=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var report=try renderer.verifyShader()
        // Actual artwork, blur textures and the same two-pass encoder as the app.
        let width=1440,height=900
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
        desc.storageMode = .shared;desc.usage=[.renderTarget,.shaderRead]
        let target=renderer.device.makeTexture(descriptor:desc)!
        let warm=renderer.queue.makeCommandBuffer()!
        renderer.prepareBlur(renderer.sample,command:warm)
        warm.commit();warm.waitUntilCompleted()
        var timings=[String:Any]()
        let names=["Silk","Shade","Frost","Ash"]
        for style in 0..<4 {
            var durations=[Double]()
            for (index,amount) in [Float(0),0.2,0.4,0.6,0.8,1].enumerated() {
                var p=EffectParameters();p.progress=amount;p.style=Float(style)
                switch style {
                case 1:p.perspective=0.9;p.blur=0.35;p.shadow=0.65
                case 2:p.perspective=0.85;p.blur=1;p.shadow=0.3
                case 3:p.perspective=0.6;p.blur=0.7;p.shadow=0.55
                default:p.blur=0.65;p.shadow=0.45
                }
                let command=renderer.queue.makeCommandBuffer()!
                let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target
                pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
                let encoder=command.makeRenderCommandEncoder(descriptor:pass)!
                renderer.encodeEffect(encoder,texture:renderer.sample,parameters:p)
                encoder.endEncoding();command.commit();command.waitUntilCompleted()
                guard command.status == .completed else {throw NSError(domain:"StyleCheck",code:1)}
                durations.append((command.gpuEndTime-command.gpuStartTime)*1000)
                var bytes=[UInt8](repeating:0,count:width*height*4)
                target.getBytes(&bytes,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)
                let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32)!
                for pixel in 0..<width*height {
                    let i=pixel*4
                    rep.bitmapData![i]=bytes[i+2];rep.bitmapData![i+1]=bytes[i+1];rep.bitmapData![i+2]=bytes[i];rep.bitmapData![i+3]=bytes[i+3]
                }
                try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("\(names[style])-\(index).png"))
            }
            timings[names[style]]=durations
        }
        report["artworkFrameGPUms"]=timings
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:folder.appendingPathComponent("checks.json"))
        print(String(data:data,encoding:.utf8)!)
        guard report["passed"] as? Bool == true else {exit(1)}
    }
}
