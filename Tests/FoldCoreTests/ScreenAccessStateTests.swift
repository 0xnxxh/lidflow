import XCTest
@testable import FoldCore

final class ScreenAccessStateTests: XCTestCase {
    func testActualSuccessIsNotOverwrittenByCachedNegativePreflight() {
        var state=ScreenAccessState.unverified
        state.captureSucceeded()
        state.observePreflight(false)
        XCTAssertTrue(state.isAllowed)
        XCTAssertEqual(state,.verified)
    }
    func testDenialIsNotOverwrittenByStalePositivePreflight() {
        var state=ScreenAccessState.verified
        state.captureDenied()
        state.observePreflight(true)
        XCTAssertFalse(state.isAllowed)
        XCTAssertEqual(state,.denied)
    }
    func testRetryCanRecoverAfterDenial() {
        var state=ScreenAccessState.denied
        state.captureSucceeded()
        XCTAssertTrue(state.isAllowed)
    }
}
