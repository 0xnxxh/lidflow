import Foundation

/// Bounded measurements, queried once per second by diagnostics. No pixels.
final class RenderMetrics {
    private let lock=NSLock()
    private var draws=0,completions=0,skipped=0,mainThreadDraws=0,over12ms=0,over20ms=0
    private var cpu:[Double]=[],gpu:[Double]=[],intervals:[Double]=[]
    private var waits:[Double]=[],imports:[Double]=[],filters:[Double]=[]
    private var lastPresentation=0.0
    private var lastProgress=1.0
    private var lastHandoff=false
    func submitted(cpuMilliseconds:Double,onMainThread:Bool) {
        lock.lock();defer{lock.unlock()};draws += 1;if onMainThread {mainThreadDraws += 1}
        append(cpuMilliseconds,to:&cpu)
    }
    func stages(drawableWait:Double,textureImport:Double,filterEncode:Double) {
        lock.lock();defer{lock.unlock()}
        append(drawableWait,to:&waits);append(textureImport,to:&imports);append(filterEncode,to:&filters)
    }
    func completed(gpuMilliseconds:Double) {
        lock.lock();defer{lock.unlock()};completions += 1
        append(gpuMilliseconds,to:&gpu)
    }
    func presented(at time:Double,progress:Double,handoff:Bool) {
        lock.lock();defer{lock.unlock()}
        if lastPresentation>0,time>lastPresentation {
            let delta=(time-lastPresentation)*1000
            append(delta,to:&intervals)
            if delta>12 {over12ms += 1};if delta>20 {over20ms += 1}
        }
        lastPresentation=time;lastProgress=progress;lastHandoff=handoff
    }
    var hasPresentedClearFrame:Bool {
        lock.lock();defer{lock.unlock()}
        return lastHandoff && lastProgress<0.00005 && lastPresentation>0
    }
    func dropped() {lock.lock();skipped += 1;lock.unlock()}
    func reset() {
        lock.lock();defer{lock.unlock()}
        draws=0;completions=0;skipped=0;mainThreadDraws=0;over12ms=0;over20ms=0;cpu=[];gpu=[];intervals=[];waits=[];imports=[];filters=[];lastPresentation=0;lastProgress=1;lastHandoff=false
    }
    private func append(_ value:Double,to values:inout [Double]) {
        values.append(value);if values.count>240 {values.removeFirst(values.count-240)}
    }
    func snapshot()->[String:Any] {
        lock.lock();defer{lock.unlock()}
        func stats(_ values:[Double])->[String:Double] {
            guard !values.isEmpty else{return [:]};let v=values.sorted()
            return ["medianMs":v[v.count/2],"p95Ms":v[min(v.count-1,Int(Double(v.count)*0.95))],"maxMs":v.last!]
        }
        return ["presentedProgress":lastProgress,"handoff":lastHandoff,"submitted":draws,"completed":completions,"mainThreadDraws":mainThreadDraws,"intervalsOver12ms":over12ms,"intervalsOver20ms":over20ms,"inFlightSkipped":skipped,
                "cpuEncode":stats(cpu),"gpu":stats(gpu),"presentationInterval":stats(intervals),
                "drawableWait":stats(waits),"textureImport":stats(imports),"filterEncode":stats(filters)]
    }
}
