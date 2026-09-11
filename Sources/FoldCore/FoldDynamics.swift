import Foundation

public struct FoldDynamics {
    public static func validAngle(_ angle: Double) -> Double? {
        angle.isFinite && (0...360).contains(angle) ? angle : nil
    }

    public static func progress(angle: Double, clearAngle: Double, closedAngle: Double = 10) -> Double {
        guard validAngle(angle) != nil, clearAngle.isFinite, clearAngle > closedAngle else { return 0 }
        let q = min(1, max(0, (clearAngle - angle) / (clearAngle - closedAngle)))
        return q * q * (3 - 2 * q)
    }

    public static func smooth(_ value: Double, toward target: Double, dt: Double) -> Double {
        let delta = max(0, min(dt, 0.1))
        return value + (target - value) * (1 - exp(-delta / 0.022))
    }


}

public struct FoldGate {
    public private(set) var isActive = false
    public init() {}
    public mutating func update(angle: Double?, clearAngle: Double) -> Bool {
        guard let angle, FoldDynamics.validAngle(angle) != nil else {
            isActive = false
            return false
        }
        if isActive { isActive = angle < clearAngle + 2 }
        else { isActive = angle < clearAngle - 2 }
        return isActive
    }
    public mutating func reset() { isActive = false }
}
