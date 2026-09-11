import XCTest
@testable import FoldCore

final class AutomaticFollowTests:XCTestCase {
    func testReadyAtLaunchWithoutAWindowOrStartAction() {
        let follow=AutomaticFollow();XCTAssertTrue(follow.isReady)
    }
    func testEscapeRestoresCurrentFoldAndRearmsAfterOpening() {
        var follow=AutomaticFollow();follow.dismissCurrentFold()
        follow.observe(angle:80,clearAngle:110);XCTAssertFalse(follow.isReady)
        follow.observe(angle:nil,clearAngle:110);XCTAssertFalse(follow.isReady)
        follow.observe(angle:110,clearAngle:110);XCTAssertTrue(follow.isReady)
        follow.observe(angle:90,clearAngle:110);XCTAssertTrue(follow.isReady)
    }
    func testOverlappingSleepAndSessionEventsResumeOnlyWhenAllClear() {
        var follow=AutomaticFollow();follow.suspend(.systemSleep);follow.suspend(.displaySleep)
        follow.suspend(.inactiveSession);follow.resume(.systemSleep);XCTAssertFalse(follow.isReady)
        follow.resume(.displaySleep);XCTAssertFalse(follow.isReady)
        follow.resume(.inactiveSession);XCTAssertTrue(follow.isReady)
    }
    func testPermissionFailureDoesNotRepeatedlyStartCaptureUntilRetry() {
        var follow=AutomaticFollow();follow.failed();follow.observe(angle:120,clearAngle:110)
        XCTAssertFalse(follow.isReady);follow.retry();XCTAssertTrue(follow.isReady)
    }
}
