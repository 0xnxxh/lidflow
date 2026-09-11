import Foundation

/// Critically damped reconstruction of quantized hinge positions. Position and
/// velocity stay continuous across integer reports; no prediction beyond input.
public struct LidMotion {
    private var position:Double?
    private var velocity=0.0
    private var lastTime:Double?
    public init() {}
    public mutating func reset() {position=nil;velocity=0;lastTime=nil}
    public mutating func update(angle:Double,at time:Double)->Double {
        guard angle.isFinite,time.isFinite else {return position ?? 0}
        guard let current=position,let lastTime,time>=lastTime,time-lastTime<0.25 else {
            position=angle;velocity=0;self.lastTime=time;return angle
        }
        let dt=time-lastTime
        // Large, fast folds must still catch up promptly; slow one-degree
        // changes use enough damping to avoid a new acceleration kick per tick.
        let omega=abs(current-angle)>3 ? 65.0 : 36.0
        let error=current-angle,coefficient=velocity+omega*error,decay=exp(-omega*dt)
        var next=angle+(error+coefficient*dt)*decay
        velocity=(velocity-omega*coefficient*dt)*decay
        if abs(next-angle)<0.00001 && abs(velocity)<0.001 {next=angle;velocity=0}
        position=next;self.lastTime=time;return next
    }
}
