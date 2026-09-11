import AppKit
import ScreenCaptureKit
import CoreMedia
import OSLog

final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let frames = FrameStore()
    var onFrame: (() -> Void)?
    var onFailure: ((String) -> Void)?
    private var stream: SCStream?
    private let streamLock = NSLock()
    private let captureQueue = DispatchQueue(label: "app.lidflow.capture", qos: .userInteractive)
    private let log = Logger(subsystem: "app.lidflow.local", category: "capture")
    private var runID = UUID()
    private var firstDelivered = false

    @MainActor func start() async throws -> NSScreen {
        let id = UUID(); runID = id
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard runID == id else { throw CancellationError() }
        guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }) else {
            throw NSError(domain: "LidFlow", code: 2, userInfo: [NSLocalizedDescriptionKey: "内置屏当前不可用。请打开 MacBook 显示器后重试。"])
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        guard !ownApps.isEmpty else {
            throw NSError(domain: "LidFlow", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法建立覆盖窗口排除规则，请重新打开 App。"])
        }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let pixelWidth = Int(screen.frame.width * screen.backingScaleFactor)
        let scale = min(1, 2560.0 / Double(pixelWidth))
        config.width = Int(Double(pixelWidth) * scale)
        config.height = Int(screen.frame.height * screen.backingScaleFactor * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
        config.colorSpaceName = CGColorSpace.sRGB
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        setStream(stream)
        try await stream.startCapture()
        guard runID == id else { try? await stream.stopCapture(); throw CancellationError() }
        log.info("capture started \(config.width)x\(config.height), self excluded")
        return screen
    }
    @MainActor func stop() {
        runID = UUID()
        let previous = clearStream()
        if let previous { Task { do { try await previous.stopCapture() } catch { log.info("capture stop: \(error.localizedDescription)") } } }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return }
        if raw == SCFrameStatus.blank.rawValue || raw == SCFrameStatus.suspended.rawValue {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.matches(stream) else { return }
                self.onFailure?("显示器暂停，桌面效果已停止。")
            }; return
        }
        guard raw == SCFrameStatus.complete.rawValue, let image = sampleBuffer.imageBuffer else { return }
        streamLock.lock()
        guard self.stream === stream else { streamLock.unlock(); return }
        frames.put(image)
        let first = !firstDelivered
        firstDelivered = true
        streamLock.unlock()
        // One readiness notification; frame delivery never queues a closure per frame.
        if first {
            log.info("first complete desktop frame")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.matches(stream) else { return }
                self.onFrame?()
            }
        }
    }
    private func matches(_ candidate: SCStream) -> Bool {
        streamLock.lock(); defer { streamLock.unlock() }
        return stream === candidate
    }
    private func setStream(_ value: SCStream) {
        streamLock.lock(); defer { streamLock.unlock() }
        stream = value; firstDelivered = false
    }
    private func clearStream() -> SCStream? {
        streamLock.lock(); defer { streamLock.unlock() }
        let previous = stream; stream = nil; frames.clear()
        return previous
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.matches(stream) else { return }
            self.onFailure?("屏幕捕获停止：\(error.localizedDescription)")
        }
    }
}
