import Foundation
import MetalKit

extension FoldRenderer {
    /// Exercise the actual bundled shader offscreen. No desktop is captured.
    func verifyShader() throws -> [String: Any] {
        let width=800, height=500
        var pixels=[UInt8](repeating:255,count:width*height*4)
        for y in 0..<height { for x in 0..<width {
            let i=(y*width+x)*4
            pixels[i]=UInt8(50+x*159/(width-1));pixels[i+1]=UInt8(70+y*99/(height-1));pixels[i+2]=150
        } }
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
        desc.storageMode = .shared; desc.usage = [.shaderRead,.renderTarget]
        guard let source=device.makeTexture(descriptor:desc),let target=device.makeTexture(descriptor:desc) else {
            throw NSError(domain:"LidFlowTests",code:1,userInfo:[NSLocalizedDescriptionKey:"texture allocation failed"])
        }
        source.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:pixels,bytesPerRow:width*4)
        func render(_ amount:Float,handoff:Bool = false,style:Float = 0)throws->[UInt8] {
            let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target
            pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
            let command=queue.makeCommandBuffer()!, encoder=command.makeRenderCommandEncoder(descriptor:pass)!
            var params=EffectParameters();params.progress=amount;params.blur=style>2.5 ? 0.7 : 0;params.shadow=style>2.5 ? 0.55 : 0;params.handoff=handoff ? 1 : 0;params.style=style
            encodeEffect(encoder,texture:source,parameters:params)
            encoder.endEncoding()
            command.commit();command.waitUntilCompleted()
            guard command.status == .completed else {throw command.error ?? NSError(domain:"LidFlowTests",code:2)}
            var output=[UInt8](repeating:0,count:pixels.count)
            target.getBytes(&output,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)
            return output
        }
        let clear=try render(0), folded=try render(0.8)
        let maxDelta=zip(clear,pixels).map {abs(Int($0)-Int($1))}.max() ?? 255
        func rgb(_ buffer:[UInt8],x:Int,y:Int)->[Int] {
            let i=(y*width+x)*4;return buffer[i..<i+3].map(Int.init)
        }
        let top=rgb(folded,x:width/2,y:2)
        let base=rgb(folded,x:width/2,y:height-2)
        let clearBase=rgb(clear,x:width/2,y:height-2)
        let baseDelta=zip(base,clearBase).map {abs($0-$1)}.max() ?? 255
        let restored=try render(0)
        let handoffClear=try render(0,handoff:true)
        let handoffMiddle=try render(0.006,handoff:true)
        let handoffFull=try render(0.012,handoff:true)
        let transparent=handoffClear.allSatisfy{$0==0}
        let center=(height/2*width+width/2)*4
        let midAlpha=Int(handoffMiddle[center+3])
        let fullAlpha=Int(handoffFull[center+3])
        // Style is a material choice, even with the optional blur/shadow controls at zero.
        let styles=try (0..<4).map { try render(0.5,style:Float($0)) }
        func meanRGBDifference(_ a:[UInt8],_ b:[UInt8])->Double {
            zip(a,b).enumerated().reduce(0.0) { result,item in
                result + (item.offset % 4 == 3 ? 0 : Double(abs(Int(item.element.0)-Int(item.element.1))))
            } / Double(width*height*3)
        }
        let differences=[meanRGBDifference(styles[0],styles[1]),meanRGBDifference(styles[0],styles[2]),meanRGBDifference(styles[1],styles[2])]
        let allStylesRestore=try (0..<4).allSatisfy { index in
            let restored=try render(0,style:Float(index)), transparent=try render(0,handoff:true,style:Float(index))
            return restored==clear && transparent.allSatisfy{$0==0}
        }
        let ashClosed=try render(1,style:3)
        let ashDisappears=ashClosed.enumerated().allSatisfy{$0.offset % 4 == 3 || $0.element==0}
        let ashReversible=try render(0.5,style:3)==styles[3]
        // At progress 0.5 the Ash desktop's projected top begins below y=60.
        // Visible material above it must come from independently drifting shards.
        let ashAirbornePixels=(0..<width*40).filter { pixel in
            let i=pixel*4;return styles[3][i]>10 || styles[3][i+1]>10 || styles[3][i+2]>10
        }.count
        let ashSmallStep=meanRGBDifference(styles[3],try render(0.50005,style:3))
        let passed=ashAirbornePixels>10 && ashSmallStep<1 && differences.allSatisfy{$0>8} && allStylesRestore && ashDisappears && ashReversible && maxDelta<=1 && top.allSatisfy{$0==0} && baseDelta<=4 && restored==clear && transparent && (126...129).contains(midAlpha) && fullAlpha==255
        let controls=try verifyControlsAndEdges()
        return ["passed":passed && (controls["passed"] as? Bool == true),"controlsAndEdges":controls,"materialMeanRGBDifferences":differences,"allStylesRestore":allStylesRestore,"ashFullyDisappears":ashDisappears,"ashReversible":ashReversible,"ashAirbornePixels":ashAirbornePixels,"ashSmallStepMeanRGBDifference":ashSmallStep,"identityMaxChannelError":maxDelta,"foldedTopRGB":top,
                "foldedBaseMaxChannelError":baseDelta,"clearAfterFoldEqualsInitial":restored==clear,
                "testInput":"synthetic color grid; no screen capture","shader":"bundled Shaders.metal","handoffAtClearFullyTransparent":transparent,
                "handoffMidAlpha":midAlpha,"handoffFullAlpha":fullAlpha]
    }
}


extension FoldRenderer {
    /// Exercise slider endpoints against actual filtered textures, plus the
    /// silhouette on a flat white source (isolates coverage from image detail).
    func verifyControlsAndEdges() throws -> [String:Any] {
        let width=800,height=500
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
        desc.storageMode = .shared;desc.usage=[.shaderRead,.renderTarget]
        let source=device.makeTexture(descriptor:desc)!,target=device.makeTexture(descriptor:desc)!
        var pixels=[UInt8](repeating:255,count:width*height*4)
        for y in 0..<height {for x in 0..<width {
            let value:UInt8=(x/8+y/8)%2 == 0 ? 230 : 30
            let i=(y*width+x)*4;pixels[i]=value;pixels[i+1]=value;pixels[i+2]=value
        }}
        func upload(_ bytes:[UInt8]) throws {
            source.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:bytes,bytesPerRow:width*4)
            let command=queue.makeCommandBuffer()!;prepareBlur(source,command:command)
            command.commit();command.waitUntilCompleted()
            guard command.status == .completed else {throw command.error ?? NSError(domain:"LidFlowTests",code:3)}
        }
        func render(_ p:EffectParameters)throws->[UInt8] {
            let command=queue.makeCommandBuffer()!,pass=MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
            let encoder=command.makeRenderCommandEncoder(descriptor:pass)!
            encodeEffect(encoder,texture:source,parameters:p);encoder.endEncoding()
            command.commit();command.waitUntilCompleted()
            guard command.status == .completed else {throw command.error ?? NSError(domain:"LidFlowTests",code:4)}
            var bytes=[UInt8](repeating:0,count:pixels.count)
            target.getBytes(&bytes,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)
            return bytes
        }
        func difference(_ a:[UInt8],_ b:[UInt8])->Double {
            var total=0.0
            for i in stride(from:0,to:a.count,by:4) {total+=Double(abs(Int(a[i])-Int(b[i])))}
            return total/Double(width*height)
        }
        func detail(_ bytes:[UInt8])->Double {
            var total=0.0,count=0
            for y in 140..<300 {for x in 240..<560 {
                let i=(y*width+x)*4;total+=Double(abs(Int(bytes[i])-Int(bytes[i+4])));count+=1
            }}
            return total/Double(count)
        }
        try upload(pixels)
        let names=["Silk","Shade","Frost","Ash"]
        var controls=[String:Any](),edges=[String:Any](),passed=true
        for style in 0..<4 {
            var p=EffectParameters();p.progress=0.55;p.style=Float(style);p.blur=0;p.shadow=0
            let base=try render(p)
            p.perspective=0;let flat=try render(p);p.perspective=1
            p.blur=1;let blur=try render(p);p.blur=0
            p.shadow=1;let shadow=try render(p);p.shadow=0
            let perspectiveDelta=difference(base,flat),blurDelta=difference(base,blur),shadowDelta=difference(base,shadow)
            let detailRatio=detail(blur)/max(detail(base),0.001)
            let controlsPass=perspectiveDelta>5 && blurDelta>3 && shadowDelta>5 && (style==3 || detailRatio<0.8)
            controls[names[style]]=["perspectiveMeanDelta":perspectiveDelta,"blurOrDriftMeanDelta":blurDelta,
                                   "shadowOrSizeMeanDelta":shadowDelta,"fullBlurDetailRatio":detailRatio,"passed":controlsPass]
            passed = passed && controlsPass
        }
        try upload([UInt8](repeating:255,count:pixels.count))
        for style in 0..<3 {
            var p=EffectParameters();p.progress=0.55;p.style=Float(style);p.blur=1;p.shadow=0
            let soft=try render(p);p.blur=0;let crisp=try render(p)
            // A white horizontal section halfway up the projected plane should
            // cross black -> soft silhouette -> white over several pixels.
            let row=height/2
            func transitionWidth(_ bytes:[UInt8])->Int {
                let interior=Double(bytes[(row*width+width/2)*4])
                return (0..<width/3).filter {let value=Double(bytes[(row*width+$0)*4]);return value>interior*0.05 && value<interior*0.95}.count
            }
            let phi=Double(p.progress*p.perspective)*1.25663706
            let r=1-(Double(row)+0.5)/Double(height),v=r*1.8/(1.8*cos(phi)-r*sin(phi))
            let k=1.8/(1.8+v*sin(phi)),left=(1-k)*0.5*Double(width)
            let outsideX=max(0,Int(floor(left))-2)
            let outside=Int(soft[(row*width+outsideX)*4])
            let softWidth=transitionWidth(soft),crispWidth=transitionWidth(crisp)
            let edgesPass=softWidth>=6 && softWidth>=crispWidth+4 && outside>5
            edges[names[style]]=["softTransitionPixels":softWidth,"zeroBlurTransitionPixels":crispWidth,"outsideOriginalEdge":outside,"passed":edgesPass]
            passed = passed && edgesPass
        }
        return ["passed":passed,"controls":controls,"edges":edges,"input":"800x500 checkerboard and flat white; actual blur textures"]
    }
}
