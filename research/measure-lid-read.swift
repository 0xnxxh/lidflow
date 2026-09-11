import Foundation
import IOKit.hid
import QuartzCore
let manager=IOHIDManagerCreate(kCFAllocatorDefault,0)
IOHIDManagerSetDeviceMatching(manager,[kIOHIDVendorIDKey:0x05ac,kIOHIDPrimaryUsagePageKey:0x20,kIOHIDPrimaryUsageKey:0x8a] as CFDictionary)
guard IOHIDManagerOpen(manager,0)==kIOReturnSuccess,
      let devices=IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,let device=devices.first,
      IOHIDDeviceOpen(device,0)==kIOReturnSuccess else {fatalError("Sensor unavailable")}
var durations=[Double](), successes=0
for _ in 0..<180 {
    var bytes=[UInt8](repeating:0,count:8),length=8
    let start=CACurrentMediaTime()
    let result=IOHIDDeviceGetReport(device,kIOHIDReportTypeFeature,1,&bytes,&length)
    durations.append((CACurrentMediaTime()-start)*1000)
    if result==kIOReturnSuccess {successes += 1}
    Thread.sleep(forTimeInterval:1/120)
}
durations.sort()
print("reads=\(durations.count), successes=\(successes), medianMs=\(durations[90]), p95Ms=\(durations[171]), maxMs=\(durations.last!)")
IOHIDDeviceClose(device,0);IOHIDManagerClose(manager,0)
