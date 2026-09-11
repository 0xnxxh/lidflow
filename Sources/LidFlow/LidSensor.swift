import Foundation
import IOKit.hid
import QuartzCore
import FoldCore

/// HID I/O and callbacks are serialized off the UI thread. Renderers take a
/// bounded latest-value snapshot; slow frames never accumulate sensor callbacks.
final class LidSensor {
    struct Snapshot {
        var angle: Double?
        var status = "正在连接传感器…"
        var eventCount = 0
        var readCount = 0
        var changedReadings = 0
        var minimumAngle: Double?
        var maximumAngle: Double?
        var timestamp = 0.0
        var readMilliseconds = 0.0
    }
    private let ioQueue = DispatchQueue(label:"app.lidflow.sensor",qos:.userInteractive)
    private let lock = NSLock()
    private var state = Snapshot()
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var errors = 0
    private var cancelling=false
    private var afterDisconnect:(()->Void)?
    private var polling = true
    private var restartGeneration=0

    func snapshot() -> Snapshot { lock.lock();defer{lock.unlock()};return state }
    var eventCount:Int {snapshot().eventCount}
    var readCount:Int {snapshot().readCount}
    var changedReadings:Int {snapshot().changedReadings}
    var minimumAngle:Double? {snapshot().minimumAngle}
    var maximumAngle:Double? {snapshot().maximumAngle}

    // The callback context survives until IOKit finishes cancelling the device.
    private final class Context {
        weak var sensor:LidSensor?
        init(_ sensor:LidSensor) {self.sensor=sensor}
    }
    func start(polling:Bool) {
        ioQueue.async { [weak self] in
            guard let self else{return}
            self.restartGeneration += 1
            let generation=self.restartGeneration
            self.disconnect { [weak self] in
                guard let self,self.restartGeneration==generation else{return}
                self.connect(polling:polling)
            }
        }
    }
    private func connect(polling:Bool) {
        self.polling=polling;errors=0
        lock.lock();state=Snapshot();lock.unlock()
        let manager=IOHIDManagerCreate(kCFAllocatorDefault,0)
        self.manager=manager
        IOHIDManagerSetDeviceMatching(manager,[kIOHIDVendorIDKey:0x05ac,
            kIOHIDPrimaryUsagePageKey:0x20,kIOHIDPrimaryUsageKey:0x8a] as CFDictionary)
        guard IOHIDManagerOpen(manager,0)==kIOReturnSuccess,
              let devices=IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,let device=devices.first else {
            fail("未找到铰链传感器 · 可使用手动预览");return
        }
        guard IOHIDDeviceOpen(device,0)==kIOReturnSuccess else {fail("无法打开铰链传感器");return}
        self.device=device
        IOHIDDeviceSetInputValueMatching(device,[kIOHIDElementUsagePageKey:0x20,kIOHIDElementUsageKey:0x47f] as CFDictionary)
        let context=Unmanaged.passRetained(Context(self)).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(device,{ context,result,sender,value in
            guard result==kIOReturnSuccess,let context else{return}
            let owner=Unmanaged<Context>.fromOpaque(context).takeUnretainedValue()
            guard let sensor=owner.sensor,let current=sensor.device,
                  sender==Unmanaged.passUnretained(current).toOpaque(),
                  let angle=FoldDynamics.validAngle(Double(IOHIDValueGetIntegerValue(value))) else{return}
            sensor.record(angle,event:true,readMilliseconds:0)
        },context)
        IOHIDDeviceSetDispatchQueue(device,ioQueue)
        IOHIDDeviceSetCancelHandler(device) {
            IOHIDDeviceClose(device,0)
            IOHIDManagerClose(manager,0)
            let owner=Unmanaged<Context>.fromOpaque(context).takeRetainedValue()
            if let sensor=owner.sensor {
                let completion=sensor.afterDisconnect;sensor.afterDisconnect=nil;sensor.cancelling=false
                completion?()
            }
        }
        IOHIDDeviceActivate(device)
        readAngle()
        if polling {
            let timer=DispatchSource.makeTimerSource(queue:ioQueue)
            timer.schedule(deadline:.now(),repeating:.nanoseconds(8_333_333),leeway:.microseconds(500))
            timer.setEventHandler{[weak self] in self?.readAngle()}
            self.timer=timer;timer.resume()
        }
    }
    private func record(_ angle:Double,event:Bool,readMilliseconds:Double) {
        lock.lock();defer{lock.unlock()}
        if let previous=state.angle,previous != angle {state.changedReadings += 1}
        state.angle=angle;state.timestamp=CACurrentMediaTime()
        state.minimumAngle=min(state.minimumAngle ?? angle,angle)
        state.maximumAngle=max(state.maximumAngle ?? angle,angle)
        if event {state.eventCount += 1} else {state.readCount += 1;state.readMilliseconds=readMilliseconds}
        state.status=polling ? "流畅读取 · 后台 120 Hz" : "HID 事件 · \(state.eventCount) 次"
    }
    private func fail(_ message:String) {
        lock.lock();state.angle=nil;state.status=message;lock.unlock()
    }
    private func readAngle() {
        guard let device else{return}
        var bytes=[UInt8](repeating:0,count:8),length=8
        let start=CACurrentMediaTime()
        let result=IOHIDDeviceGetReport(device,kIOHIDReportTypeFeature,1,&bytes,&length)
        guard result==kIOReturnSuccess,length>=3,
              let angle=FoldDynamics.validAngle(Double(UInt16(bytes[1]) | UInt16(bytes[2])<<8)) else {
            errors += 1
            if errors>=3 {fail("角度读取中断，请重新连接传感器")}
            return
        }
        errors=0;record(angle,event:false,readMilliseconds:(CACurrentMediaTime()-start)*1000)
    }
    func stop() {
        ioQueue.async{[weak self] in
            guard let self else{return}
            self.restartGeneration += 1;self.disconnect()
        }
    }
    private func disconnect(completion:(()->Void)? = nil) {
        timer?.cancel();timer=nil
        let oldDevice=device,oldManager=manager
        device=nil;manager=nil
        if let device=oldDevice {
            cancelling=true
            afterDisconnect=completion
            IOHIDDeviceCancel(device)
        } else if cancelling {
            // Cancellation is already in flight; latest start/stop owns completion.
            afterDisconnect=completion
        } else {
            if let oldManager {IOHIDManagerClose(oldManager,0)}
            completion?()
        }
    }
    deinit {
        timer?.cancel()
        if let device {IOHIDDeviceCancel(device)}
        else if let manager {IOHIDManagerClose(manager,0)}
    }
}
