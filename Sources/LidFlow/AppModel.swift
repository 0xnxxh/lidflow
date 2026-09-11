import AppKit
import SwiftUI
import FoldCore
import OSLog
import ScreenCaptureKit

@MainActor final class AppModel: ObservableObject {
    var windowVisible:Bool {
        NSApp.windows.contains {$0.title=="LidFlow" && $0.isVisible && !$0.isMiniaturized}
    }
    @Published var angle: Double?
    @Published var sensorStatus = "正在连接传感器…"
    @Published var status = "自动跟随已开启 · 等待盖子读数"
    @Published private(set) var enabled = true
    @Published var previewAngle = 70.0
    @Published var followPreview = false
    @Published var demoPlaying = false
    @Published var clearAngle: Double { didSet { defaults.set(clearAngle, forKey: "clearAngle") } }
    @Published var perspective: Double { didSet { saveEffectSettings() } }
    @Published var blur: Double { didSet { saveEffectSettings() } }
    @Published var shadow: Double { didSet { saveEffectSettings() } }
    @Published private(set) var style: Int
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound") } }
    @Published var polling: Bool { didSet { defaults.set(polling, forKey: "polling"); reconnectSensor() } }
    @Published var displayFPS:Int {
        didSet {
            defaults.set(displayFPS,forKey:"displayFPS")
            endCapture();gate.reset();overlay.framesPerSecond=displayFPS
            status="刷新率已更新 · 自动跟随已开启"
        }
    }
    @Published var rendererError: String?
    @Published var framesReceived: UInt64 = 0
    private var presentedFrames: UInt64 = 0
    @Published var screenAccess = ScreenAccessState.unverified
    @Published var checkingPermission = false
    var hasCapturePermission: Bool { screenAccess.isAllowed }
    var permissionLabel: String {
        if checkingPermission { return "正在验证屏幕访问…" }
        switch screenAccess {
        case .verified: return "屏幕访问已验证"
        case .preflightAllowed: return "屏幕录制已允许"
        case .denied: return "当前版本未获系统授权"
        case .unverified: return "屏幕访问待验证"
        }
    }
    let capture = DesktopCapture()
    let sensor = LidSensor()
    let overlay = OverlayController()
    private let renderInput=RenderInput()
    private let defaults = UserDefaults.standard
    private let settings:EffectSettingsStore
    private var loadingSettings=false
    private var follow=AutomaticFollow()
    private var timer:DispatchSourceTimer?
    private var activity:NSObjectProtocol?
    private var isShuttingDown=false
    private var gate = FoldGate()
    private var targetProgress = 0.0
    private var previewMotion=LidMotion()
    private var previewStart: CFTimeInterval?
    private var clearStart: CFTimeInterval?
    private var preparing = false
    private var prepared = false
    private var attemptID = UUID()
    private var preparingSince = 0.0
    private var lastDiagnostics = 0.0
    private var diagnosticsURL: URL?
    private var observers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: "app.lidflow.local", category: "lifecycle")

    init() {
        let d = UserDefaults.standard
        let store=EffectSettingsStore(defaults:d);settings=store
        d.register(defaults: ["clearAngle":110.0,"sound":false,"polling":true,"displayFPS":120])
        clearAngle=d.double(forKey:"clearAngle");style=store.selectedStyle
        let saved=store.settings(for:store.selectedStyle)
        perspective=saved.perspective;blur=saved.blur;shadow=saved.shadow
        displayFPS=d.integer(forKey:"displayFPS")==60 ? 60 : 120
        sound=d.bool(forKey:"sound");polling=d.bool(forKey:"polling")
        overlay.framesPerSecond=displayFPS
        screenAccess.observePreflight(CGPreflightScreenCaptureAccess())
        if let i = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.count > i+1 {
            diagnosticsURL=URL(fileURLWithPath:CommandLine.arguments[i+1])
        }
        capture.onFailure = { [weak self] in self?.failFollowing($0) }
        capture.onFrame = { [weak self] in
            guard let self, self.prepared, self.enabled else { return }
            if !self.overlay.isVisible { self.overlay.show(); self.status = "正在跟随盖子 · Esc 恢复本次画面" }
        }
        overlay.parameters = { [renderInput,sensor] time in renderInput.parameters(at:time,sensor:sensor) }
        overlay.onStop = { [weak self] in self?.dismissCurrentFold() }
        overlay.onFailure = { [weak self] in self?.failFollowing($0) }
        overlay.onPresent = { [weak self] in self?.presentedFrames &+= 1 }
        sensor.start(polling: polling)
        // This service outlives the settings window. Activity prevents App Nap
        // from suspending lid work without preventing display or system sleep.
        updateActivity()
        let timer=DispatchSource.makeTimerSource(queue:.main)
        timer.schedule(deadline:.now(),repeating:.milliseconds(50),leeway:.milliseconds(3))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated {self?.tick()} }
        self.timer=timer;timer.resume()
        let center=NSWorkspace.shared.notificationCenter
        let events:[(Notification.Name,AutomaticFollow.Suspension,Bool)]=[
            (NSWorkspace.willSleepNotification,.systemSleep,true),
            (NSWorkspace.didWakeNotification,.systemSleep,false),
            (NSWorkspace.screensDidSleepNotification,.displaySleep,true),
            (NSWorkspace.screensDidWakeNotification,.displaySleep,false),
            (NSWorkspace.sessionDidResignActiveNotification,.inactiveSession,true),
            (NSWorkspace.sessionDidBecomeActiveNotification,.inactiveSession,false)]
        for (name,reason,suspend) in events {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated {self?.handleSession(reason,suspend:suspend)}
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else{return}
                self.endCapture();self.gate.reset();self.follow.retry();self.updateActivity()
                self.status="显示器已更新 · 自动跟随已开启"
            }
        })
        if let i=CommandLine.arguments.firstIndex(of:"--render-check"),CommandLine.arguments.count>i+1 {
            do {
                let result=try FoldRenderer().verifyShader()
                let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
                try data.write(to:URL(fileURLWithPath:CommandLine.arguments[i+1]),options:.atomic)
            } catch { rendererError="GPU 检查失败：\(error.localizedDescription)" }
        }
        log.info("app started; automatic following enabled independently of settings window")
    }
    func effect(progress: Double) -> EffectParameters {
        var p=EffectParameters();p.progress=Float(progress);p.perspective=Float(perspective)
        p.blur=Float(blur);p.shadow=Float(shadow);p.style=Float(style);return p
    }
    func previewParameters() -> EffectParameters {
        let selected:Double
        if followPreview {selected=previewMotion.update(angle:sensor.snapshot().angle ?? clearAngle,at:CACurrentMediaTime())}
        else if demoPlaying,let start=previewStart {selected=animatedPreviewAngle(at:CACurrentMediaTime(),start:start)}
        else {selected=previewAngle}
        var parameters=effect(progress:FoldDynamics.progress(angle:selected,clearAngle:clearAngle))
        if followPreview {parameters.prefiltered=1} else {previewMotion.reset()}
        return parameters
    }
    private func animatedPreviewAngle(at now:Double,start:Double)->Double {
        10+(clearAngle-10)*(0.5+0.5*cos((now-start)*1.2))
    }
    private func updateRenderInput() {
        var input=RenderInput.State()
        input.effect=effect(progress:0);input.enabled=enabled
        input.clearAngle=clearAngle
        renderInput.update(input)
    }
    private func saveEffectSettings() {
        guard !loadingSettings else{return}
        settings.save(EffectSettings(perspective:perspective,blur:blur,shadow:shadow),for:style)
    }
    private func loadEffectSettings() {
        loadingSettings=true
        let value=settings.settings(for:style)
        perspective=value.perspective;blur=value.blur;shadow=value.shadow
        loadingSettings=false;updateRenderInput()
    }
    func selectStyle(_ index:Int) {
        guard (0...3).contains(index) else{return}
        style=index;settings.selectedStyle=index;loadEffectSettings()
    }
    func resetCurrentEffect() {settings.reset(style);loadEffectSettings()}
    func reconnectSensor() {
        endCapture();gate.reset();follow.retry()
        if !follow.isSuspended {sensor.start(polling:polling)}
        status="正在重新连接 · 连接后自动跟随";updateActivity()
    }
    private func updateActivity() {
        if !isShuttingDown && !follow.isSuspended && !follow.failureBlocked {
            if activity==nil {activity=ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Track lid angle while LidFlow runs in the background")}
        } else if let activity {ProcessInfo.processInfo.endActivity(activity);self.activity=nil}
    }
    private func handleSession(_ reason:AutomaticFollow.Suspension,suspend:Bool) {
        if suspend {
            follow.suspend(reason);endCapture();gate.reset();sensor.stop()
            status="等待屏幕与会话恢复"
        } else {
            follow.resume(reason)
            if !follow.isSuspended {follow.retry();sensor.start(polling:polling);status="自动跟随已恢复"}
        }
        enabled=follow.isReady;updateRenderInput();updateActivity()
    }
    func requestPermission() {
        guard !checkingPermission else { return }
        checkingPermission=true
        Task {
            defer { checkingPermission=false }
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                screenAccess.captureSucceeded()
                follow.retry();updateActivity();status="屏幕访问已验证 · 自动跟随已开启"
                log.info("ScreenCaptureKit permission probe succeeded")
            } catch {
                handleCaptureError(error)
            }
        }
    }
    func openPermissionSettings() {
        if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    private func handleCaptureError(_ error: Error) {
        let nsError=error as NSError
        if nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userDeclined.rawValue {
            screenAccess.captureDenied()
            failFollowing("系统未授权当前版本。若开关已开启，请移除旧 LidFlow 项，重新添加当前 App 后重启。")
        } else {
            failFollowing("屏幕连接失败：\(error.localizedDescription)")
        }
        log.error("capture error domain=\(nsError.domain,privacy:.public) code=\(nsError.code) message=\(nsError.localizedDescription,privacy:.public)")
    }
    func toggleDemo() {
        demoPlaying.toggle();followPreview=false
        previewStart=demoPlaying ? CACurrentMediaTime() : nil
    }
    private func dismissCurrentFold() {
        follow.dismissCurrentFold();enabled=false;gate.reset();targetProgress=0
        updateRenderInput();endCapture();status="本次画面已恢复 · 打开盖子后自动继续"
        writeDiagnostics()
    }
    private func failFollowing(_ reason:String) {
        follow.failed();enabled=false;gate.reset();targetProgress=0
        updateRenderInput();endCapture();status=reason;updateActivity()
        log.error("automatic following blocked: \(reason,privacy:.public)");writeDiagnostics()
    }
    private func endCapture() {
        attemptID=UUID();preparing=false;prepared=false;clearStart=nil
        overlay.hide();capture.stop()
    }
    private func beginCapture() {
        guard !preparing && !prepared else { return }
        preparing=true;preparingSince=CACurrentMediaTime();status="正在连接内置屏…"
        let id=UUID();attemptID=id
        Task { [weak self] in
            guard let self else { return }
            do {
                let screen=try await self.capture.start()
                guard self.attemptID==id, self.enabled else { return }
                try self.overlay.prepare(screen:screen,frames:self.capture.frames)
                self.preparing=false;self.prepared=true
                self.updateRenderInput()
                self.status="正在跟随盖子 · Esc 恢复本次画面"
                self.screenAccess.captureSucceeded()
                if self.capture.frames.snapshot().0 != nil { self.overlay.show() }
            } catch {
                guard self.attemptID==id else { return }
                self.handleCaptureError(error)
            }
        }
    }
    private func tick() {
        guard !isShuttingDown else{return}
        let now=CACurrentMediaTime()
        let latest=sensor.snapshot()
        if angle != latest.angle {angle=latest.angle}
        if sensorStatus != latest.status {sensorStatus=latest.status}
        follow.observe(angle:latest.angle,clearAngle:clearAngle)
        let ready=follow.isReady && latest.angle != nil
        if enabled != ready {enabled=ready}
        updateRenderInput()
        if latest.angle == nil && (prepared || preparing) {endCapture();gate.reset()}
        if latest.angle == nil && !follow.failureBlocked && !follow.isSuspended {status=latest.status}
        if follow.waitingForOpen {status="本次画面已恢复 · 打开盖子后自动继续"}
        if demoPlaying && windowVisible, let start=previewStart {
            previewAngle=animatedPreviewAngle(at:now,start:start)
        }
        if enabled {
            let active=gate.update(angle:angle,clearAngle:clearAngle)
            targetProgress=active ? FoldDynamics.progress(angle:angle ?? clearAngle,clearAngle:clearAngle) : 0
            let atClearAngle=(angle ?? clearAngle)>=clearAngle
            if active && !atClearAngle {
                clearStart=nil
                if !prepared && !preparing { beginCapture() }
            } else if prepared || preparing {
                if clearStart==nil { clearStart=now }
                if now-(clearStart ?? now)>0.12 && (!overlay.isVisible || overlay.hasPresentedClearFrame) {
                    endCapture();gate.reset();status="自动跟随已开启 · 等待下次合盖"
                    if sound { NSSound(named:"Pop")?.play() }
                }
            } else if status != "自动跟随已开启 · 设置窗口可关闭" {status="自动跟随已开启 · 设置窗口可关闭"}
        }
        if (preparing || (prepared && capture.frames.snapshot().0 == nil)) && now-preparingSince>10 { failFollowing("等待屏幕捕获超时，请检查屏幕录制权限后重试") }
        if now-lastDiagnostics>1 {
            lastDiagnostics=now;framesReceived=capture.frames.snapshot().2
            screenAccess.observePreflight(CGPreflightScreenCaptureAccess());writeDiagnostics()
        }
    }
    private func writeDiagnostics() {
        guard let diagnosticsURL else { return }
        let value:[String:Any]=["time":Date().description,"angle":angle as Any? ?? NSNull(),"sensor":sensorStatus,
            "events":sensor.eventCount,"reads":sensor.readCount,"changedReadings":sensor.changedReadings,
            "minimumAngle":sensor.minimumAngle as Any? ?? NSNull(),"maximumAngle":sensor.maximumAngle as Any? ?? NSNull(),"enabled":enabled,"waitingForOpen":follow.waitingForOpen,"suspended":follow.isSuspended,"failureBlocked":follow.failureBlocked,
            "overlayVisible":overlay.isVisible,"status":status,"captureFrames":framesReceived,
            "firstFramesPresented":presentedFrames,"permission":hasCapturePermission,"previewAngle":previewAngle,
            "progress":targetProgress,"polling":polling,"sensorReadMs":sensor.snapshot().readMilliseconds,
            "render":overlay.performanceSnapshot(),"appActive":NSApp.isActive,"settingsWindowVisible":windowVisible,
            "backgroundActivity":activity != nil,"style":style,"effectSettings":["perspective":perspective,"blur":blur,"shadow":shadow]]
        do { let data=try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]);try data.write(to:diagnosticsURL,options:.atomic) }
        catch { log.error("diagnostics write failed: \(error.localizedDescription)") }
    }
    func shutdown() {
        isShuttingDown=true;enabled=false;updateRenderInput();endCapture();sensor.stop();timer?.cancel();timer=nil;updateActivity()
    }
}
