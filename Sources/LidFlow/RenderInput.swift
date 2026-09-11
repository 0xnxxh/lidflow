import Foundation
import FoldCore

/// UI settings are snapshotted at UI rate. The render thread samples hardware
/// directly and evaluates animated time at the intended presentation timestamp.
final class RenderInput {
    struct State {
        var effect=EffectParameters()
        var enabled=false
        var clearAngle=110.0
    }
    private let lock=NSLock()
    private var state=State()
    private var motion=LidMotion()
    private var wasFollowing=false
    func update(_ state:State) {lock.lock();self.state=state;lock.unlock()}
    func parameters(at time:Double,sensor:LidSensor)->EffectParameters {
        lock.lock();let state=state;lock.unlock()
        var effect=state.effect
        if state.enabled {
            if !wasFollowing {motion.reset();wasFollowing=true}
            let raw=sensor.snapshot().angle ?? state.clearAngle
            let continuous=motion.update(angle:raw,at:time)
            effect.progress=Float(FoldDynamics.progress(angle:continuous,clearAngle:state.clearAngle))
            effect.handoff=1;effect.prefiltered=1
        } else {effect.progress=0;motion.reset();wasFollowing=false}
        return effect
    }
}
