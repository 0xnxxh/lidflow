import Foundation
import IOKit.hid
let m=IOHIDManagerCreate(kCFAllocatorDefault,0)
IOHIDManagerSetDeviceMatching(m,[kIOHIDVendorIDKey:0x05ac,kIOHIDPrimaryUsagePageKey:0x20,kIOHIDPrimaryUsageKey:0x8a] as CFDictionary)
guard IOHIDManagerOpen(m,0)==0,let devices=IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>,let d=devices.first,IOHIDDeviceOpen(d,0)==0 else {exit(1)}
if let elements=IOHIDDeviceCopyMatchingElements(d,nil,0) as? [IOHIDElement] {
 for e in elements where IOHIDElementGetUsagePage(e)==0x20 && IOHIDElementGetReportSize(e)>0 {
  print("usage=\(IOHIDElementGetUsage(e)) report=\(IOHIDElementGetReportID(e)) bits=\(IOHIDElementGetReportSize(e)) physical=\(IOHIDElementGetPhysicalMin(e))...\(IOHIDElementGetPhysicalMax(e)) exponent=\(IOHIDElementGetUnitExponent(e)) unit=\(IOHIDElementGetUnit(e))")
 }
}
IOHIDDeviceClose(d,0);IOHIDManagerClose(m,0)
