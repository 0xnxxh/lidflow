import AppKit
import MetalKit

@main struct Benchmark {
    static func main() throws {
        let renderer=try FoldRenderer()
        let device=renderer.device
        let width=2560,height=1662
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
        desc.storageMode = .shared;desc.usage=[.shaderRead,.renderTarget]
        let source=device.makeTexture(descriptor:desc)!,target=device.makeTexture(descriptor:desc)!
        let bytes=[UInt8](repeating:127,count:width*height*4)
        source.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:bytes,bytesPerRow:width*4)
        var results=[String:Any]()
        for style in 0..<4 {
        var cpu=[Double](),gpu=[Double]()
        for i in 0..<100 {
            let begin=CACurrentMediaTime()
            let command=renderer.queue.makeCommandBuffer()!
            renderer.prepareBlur(source,command:command)
            let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target
            pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
            let encoder=command.makeRenderCommandEncoder(descriptor:pass)!
            var p=EffectParameters();p.progress=Float(i%50)/50
            p.style=Float(style)
            renderer.encodeEffect(encoder,texture:source,parameters:p)
            encoder.endEncoding()
            let encoded=CACurrentMediaTime()
            command.commit();command.waitUntilCompleted()
            guard command.status == .completed else {fatalError("GPU failed")}
            if i>=10 {cpu.append((encoded-begin)*1000);gpu.append((command.gpuEndTime-command.gpuStartTime)*1000)}
        }
        func stats(_ array:[Double])->[String:Double] {let v=array.sorted();return ["medianMs":v[v.count/2],"p95Ms":v[Int(Double(v.count)*0.95)],"maxMs":v.last!]}
        results[["Silk","Shade","Frost","Ash"][style]]=["width":width,"height":height,"frames":cpu.count,"cpuEncode":stats(cpu),"gpu":stats(gpu),"scope":"synthetic offscreen; 3 blur passes plus full-size material and particle rendering; excludes capture, display pacing and sensor"]
        }
        let data=try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        print(String(data:data,encoding:.utf8)!)
    }
}
