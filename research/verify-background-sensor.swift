import Foundation
@main struct Verify {
    static func main() {
        let sensor=LidSensor()
        sensor.start(polling:true)
        // Intentionally do not service the main run loop: I/O must still progress.
        Thread.sleep(forTimeInterval:2)
        let first=sensor.snapshot()
        Thread.sleep(forTimeInterval:2)
        let second=sensor.snapshot()
        sensor.start(polling:true)
        Thread.sleep(forTimeInterval:1)
        let restarted=sensor.snapshot()
        sensor.stop()
        Thread.sleep(forTimeInterval:0.1)
        let passed=second.readCount-first.readCount>=200 && restarted.readCount>=90 && restarted.angle != nil
        print("passed=\(passed), readsPerSecond=\(Double(second.readCount-first.readCount)/2), restartReads=\(restarted.readCount), status=\(restarted.status)")
        if !passed {exit(1)}
    }
}
