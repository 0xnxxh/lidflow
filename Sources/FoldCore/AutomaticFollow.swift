/// Following belongs to the process, independent of any settings window.
public struct AutomaticFollow {
    public enum Suspension:Hashable,Sendable {case systemSleep,displaySleep,inactiveSession}
    private var suspensions:Set<Suspension>=[]
    public private(set) var waitingForOpen=false
    public private(set) var failureBlocked=false
    public var isReady:Bool {suspensions.isEmpty && !waitingForOpen && !failureBlocked}
    public var isSuspended:Bool {!suspensions.isEmpty}
    public init() {}
    public mutating func suspend(_ reason:Suspension) {suspensions.insert(reason)}
    public mutating func resume(_ reason:Suspension) {suspensions.remove(reason)}
    public mutating func dismissCurrentFold() {waitingForOpen=true}
    public mutating func observe(angle:Double?,clearAngle:Double) {
        if let angle,FoldDynamics.validAngle(angle) != nil,angle>=clearAngle {waitingForOpen=false}
    }
    public mutating func failed() {failureBlocked=true}
    public mutating func retry() {failureBlocked=false}
}
