import Foundation
import IOKit.hid
import CoreGraphics

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let match: [String: Any] = [kIOHIDVendorIDKey: 0x05ac, kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 0x8a]
IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print("managerOpen=\(status)")
guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
    print("No matching lid sensor")
    exit(2)
}
for device in devices {
    let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    print("deviceOpen=\(result)")
    if result != kIOReturnSuccess { continue }
    var report = [UInt8](repeating: 0, count: 8)
    var length = report.count
    let read = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
    print("featureRead=\(read), length=\(length)")
    if read == kIOReturnSuccess && length >= 3 {
        print("angleDegrees=\(UInt16(report[1]) | (UInt16(report[2]) << 8))")
    }
    if let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] {
        for e in elements {
            print("element type=\(IOHIDElementGetType(e).rawValue) usagePage=\(IOHIDElementGetUsagePage(e)) usage=\(IOHIDElementGetUsage(e)) reportID=\(IOHIDElementGetReportID(e)) size=\(IOHIDElementGetReportSize(e)) min=\(IOHIDElementGetLogicalMin(e)) max=\(IOHIDElementGetLogicalMax(e))")
        }
    }
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
}
IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print("screenCaptureAlreadyAuthorized=\(CGPreflightScreenCaptureAccess())")
