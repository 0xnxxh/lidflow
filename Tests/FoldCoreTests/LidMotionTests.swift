import XCTest
@testable import FoldCore

final class LidMotionTests:XCTestCase {
    func testSlowIntegerOpeningNearClearDoesNotMoveInOneDegreeSteps() {
        var motion=LidMotion(),previous=100.0
        var maxStep=0.0,maxLag=0.0
        for i in 0...240 {
            let t=Double(i)/120,truth=100+6*t,raw=truth.rounded(.down)
            let value=motion.update(angle:raw,at:t)
            if i>0 {maxStep=max(maxStep,abs(value-previous))}
            maxLag=max(maxLag,truth-value);previous=value
        }
        XCTAssertLessThan(maxStep,0.13,"Slow opening must not jump a whole degree on a display frame")
        XCTAssertLessThan(maxLag,1.5,"Smoothing cannot hide stutter behind a long delay")
        XCTAssertGreaterThan(previous,110.8)
    }
    func testQuickOpeningAndReversalStayResponsive() {
        var motion=LidMotion()
        _=motion.update(angle:35,at:0)
        var value=35.0
        for i in 1...12 {value=motion.update(angle:120,at:Double(i)/120)}
        XCTAssertGreaterThan(value,116)
        for i in 13...30 {value=motion.update(angle:70,at:Double(i)/120)}
        XCTAssertEqual(value,70,accuracy:0.5)
    }
    func testStopSettlesAndResetDoesNotReplayOldVelocity() {
        var motion=LidMotion()
        for i in 0...120 {_=motion.update(angle:100+Double(i/10),at:Double(i)/120)}
        var result=0.0
        for i in 121...240 {result=motion.update(angle:112,at:Double(i)/120)}
        XCTAssertEqual(result,112,accuracy:0.001)
        motion.reset()
        XCTAssertEqual(motion.update(angle:40,at:3),40)
    }
    func testSameTimelineIsStableAt60And120Hz() {
        func run(_ hz:Int)->Double {
            var m=LidMotion();_=m.update(angle:100,at:0)
            var value=100.0
            for i in 1...hz {value=m.update(angle:101,at:Double(i)/Double(hz))}
            return value
        }
        XCTAssertEqual(run(60),run(120),accuracy:0.00001)
    }
}
