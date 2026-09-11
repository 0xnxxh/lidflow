import Foundation
import IOKit.hid

final class EventState {
    var count = 0
    var firstTime: Double?
    var lastTime: Double?
    var minimum = Int.max
    var maximum = Int.min
}
let state = EventState()
let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x05ac,
    kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 0x8a] as CFDictionary)
let openResult = IOHIDManagerOpen(manager, 0)
guard openResult == kIOReturnSuccess else { print("managerOpen=\(openResult)"); exit(2) }
guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first else {
    print("No sensor"); exit(2)
}
let deviceOpen = IOHIDDeviceOpen(device, 0)
guard deviceOpen == kIOReturnSuccess else { print("deviceOpen=\(deviceOpen)"); exit(2) }
IOHIDDeviceSetInputValueMatching(device, [kIOHIDElementUsagePageKey: 0x20,
    kIOHIDElementUsageKey: 0x47f] as CFDictionary)
let pointer = Unmanaged.passUnretained(state).toOpaque()
IOHIDDeviceRegisterInputValueCallback(device, { context, result, _, value in
    guard result == kIOReturnSuccess, let context else { return }
    let state = Unmanaged<EventState>.fromOpaque(context).takeUnretainedValue()
    let angle = IOHIDValueGetIntegerValue(value)
    let time = CFAbsoluteTimeGetCurrent()
    state.count += 1
    if state.firstTime == nil { state.firstTime = time }
    state.lastTime = time
    state.minimum = min(state.minimum, angle)
    state.maximum = max(state.maximum, angle)
    if state.count <= 5 { print("callback \(state.count): angleDegrees=\(angle)") }
}, pointer)
IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
print("Listening for 4 seconds. No timer reads and no feature report polling.")
CFRunLoopRunInMode(.defaultMode, 4.0, false)
IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
IOHIDDeviceClose(device, 0)
IOHIDManagerClose(manager, 0)
print("callbacks=\(state.count)")
if state.count > 0 {
    print("angleRange=\(state.minimum)...\(state.maximum)")
    if let first = state.firstTime, let last = state.lastTime, last > first {
        print(String(format: "observedCallbackRate=%.1f/s", Double(state.count - 1) / (last - first)))
    }
}
