/// A CoreGraphics preflight is a hint. Actual ScreenCaptureKit success/denial
/// remains authoritative for this process and must not be overwritten by a cached hint.
public enum ScreenAccessState: Equatable {
    case unverified, preflightAllowed, verified, denied

    public var isAllowed: Bool { self == .preflightAllowed || self == .verified }

    public mutating func observePreflight(_ allowed: Bool) {
        if self == .verified || self == .denied { return }
        self = allowed ? .preflightAllowed : .unverified
    }
    public mutating func captureSucceeded() { self = .verified }
    public mutating func captureDenied() { self = .denied }
}
