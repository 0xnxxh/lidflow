import XCTest
@testable import FoldCore

final class FoldDynamicsTests: XCTestCase {
    func testClearAndClosedEndpointsAndMonotonicMotion() {
        XCTAssertEqual(FoldDynamics.progress(angle: 120, clearAngle: 110), 0)
        XCTAssertEqual(FoldDynamics.progress(angle: 110, clearAngle: 110), 0)
        XCTAssertEqual(FoldDynamics.progress(angle: 0, clearAngle: 110), 1)
        XCTAssertEqual(FoldDynamics.progress(angle: 10, clearAngle: 110), 1)
        let values = stride(from: 110.0, through: 10.0, by: -5).map {
            FoldDynamics.progress(angle: $0, clearAngle: 110)
        }
        XCTAssertEqual(values, values.sorted())
    }

    func testInvalidSamplesFailOpenInsteadOfCoveringDesktop() {
        for angle in [Double.nan, .infinity, -.infinity, -1, 361] {
            XCTAssertNil(FoldDynamics.validAngle(angle))
        }
        XCTAssertEqual(FoldDynamics.progress(angle: .nan, clearAngle: 110), 0)
    }

    func testSmoothingIsIndependentOfRefreshRate() {
        func advance(_ hz: Double) -> Double {
            var value = 0.0
            for _ in 0..<Int(hz) { value = FoldDynamics.smooth(value, toward: 1, dt: 1 / hz) }
            return value
        }
        XCTAssertEqual(advance(60), advance(120), accuracy: 0.00001)
    }

    func testHysteresisAvoidsFlappingAtClearAngle() {
        var gate = FoldGate()
        XCTAssertFalse(gate.update(angle: 109.5, clearAngle: 110))
        XCTAssertTrue(gate.update(angle: 105, clearAngle: 110))
        XCTAssertTrue(gate.update(angle: 110, clearAngle: 110))
        XCTAssertFalse(gate.update(angle: 112, clearAngle: 110))
        XCTAssertFalse(gate.update(angle: 109.5, clearAngle: 110))
        XCTAssertTrue(gate.update(angle: 80, clearAngle: 110))
        XCTAssertFalse(gate.update(angle: nil, clearAngle: 110))
    }

    func testFollowSettlesWithin60MillisecondsWithoutOvershoot() {
        var value=0.0
        for _ in 0..<7 {value=FoldDynamics.smooth(value,toward:1,dt:1/120)}
        XCTAssertGreaterThan(value,0.9,"Angle smoothing must not add a visible long tail")
        XCTAssertLessThanOrEqual(value,1)
        for _ in 0..<7 {value=FoldDynamics.smooth(value,toward:0,dt:1/120)}
        XCTAssertLessThan(value,0.1)
    }

}
