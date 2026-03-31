import Foundation
import IOKit
import IOKit.hid

/// Reads the MacBook's lid angle sensor via IOKit HID.
/// Based on https://github.com/samhenrigold/LidAngleSensor
///
/// Accesses the HID device with usage page 0x0020, usage 0x008A
/// and reads the raw angle from bytes 1-2 of the feature report.
@Observable
final class LidSensor {
    private(set) var angle: Double = 0.0
    private(set) var velocity: Double = 0.0
    private(set) var isAvailable: Bool = false
    private(set) var statusMessage: String = "Starting..."
    private(set) var debugLog: String = ""

    /// Angle as a percentage (0% = closed at 0 deg, 100% = fully open at ~130 deg)
    var percentage: Double {
        min(100, max(0, angle / 130.0 * 100.0))
    }

    var status: String {
        switch angle {
        case ..<5:     return "Closed"
        case 5..<45:   return "Slightly Open"
        case 45..<90:  return "Half Open"
        case 90..<120: return "Mostly Open"
        default:       return "Fully Open"
        }
    }

    // No smoothing — use raw values for instant response

    private var timer: Timer?
    private var hidDevice: IOHIDDevice?
    private var reportID: CFIndex = 0
    private var reportLength: CFIndex = 0
    private var lastAngle: Double = 0.0
    private var lastTimestamp: TimeInterval = 0
    private var hasFirstReading: Bool = false

    init() {}

    deinit {
        stop()
    }

    private func log(_ msg: String) {
        debugLog = msg
        print("[LidSensor] \(msg)")
    }

    // MARK: - Lifecycle

    func start() {
        guard hidDevice == nil else { return }
        findSensor()
        guard hidDevice != nil else {
            statusMessage = "Lid angle sensor not found. Is this a supported MacBook?"
            isAvailable = false
            return
        }

        // Open the device for reading
        let openResult = IOHIDDeviceOpen(hidDevice!, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            log("Failed to open HID device: \(String(format: "0x%x", openResult))")
            statusMessage = "Could not open sensor (error: \(String(format: "0x%x", openResult)))"
            isAvailable = false
            hidDevice = nil
            return
        }

        isAvailable = true
        statusMessage = "Sensor connected"
        lastTimestamp = ProcessInfo.processInfo.systemUptime
        log("Sensor opened, starting polling (reportID=\(reportID), reportLength=\(reportLength))")

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let device = hidDevice {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidDevice = nil
    }

    // MARK: - HID Sensor Discovery

    private func findSensor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)

        // Schedule on run loop so device enumeration works
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            log("Failed to open HID manager: \(String(format: "0x%x", openResult))")
            return
        }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            log("No HID devices found at all")
            return
        }

        log("Found \(deviceSet.count) HID devices, scanning for lid sensor...")

        // Try standard sensor (usage page 0x0020, usage 0x008A)
        for device in deviceSet {
            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
                continue
            }

            for element in elements {
                let usagePage = IOHIDElementGetUsagePage(element)
                let usage = IOHIDElementGetUsage(element)

                if usagePage == 0x0020 && usage == 0x008A {
                    self.reportID = CFIndex(IOHIDElementGetReportID(element))

                    // Get max feature report size from device property
                    let maxSize = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
                    let elementReportSize = IOHIDElementGetReportSize(element)
                    let elementReportCount = IOHIDElementGetReportCount(element)

                    // Use device's max feature report size if available, otherwise calculate from element
                    if maxSize > 0 {
                        self.reportLength = CFIndex(maxSize)
                    } else {
                        self.reportLength = CFIndex((elementReportSize * elementReportCount / 8) + 1)
                    }
                    if self.reportLength < 3 {
                        self.reportLength = 3
                    }

                    let deviceName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
                    log("Found standard sensor on '\(deviceName)' (reportID=\(reportID), maxFeatureSize=\(maxSize), elementSize=\(elementReportSize), elementCount=\(elementReportCount), reportLength=\(reportLength))")
                    statusMessage = "Found lid angle sensor"
                    hidDevice = device
                    return
                }
            }
        }

        // Fallback: vendor-specific device (product ID 0x8104)
        for device in deviceSet {
            let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
            if productID == 0x8104 {
                self.reportID = 0
                self.reportLength = 64
                let deviceName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
                log("Found vendor-specific sensor on '\(deviceName)' (productID=0x8104)")
                statusMessage = "Found vendor-specific lid sensor"
                hidDevice = device
                return
            }
        }

        log("No lid angle sensor found among \(deviceSet.count) HID devices")
    }

    // MARK: - Polling

    private var retryCount = 0

    private func tryGetReport(device: IOHIDDevice, type: IOHIDReportType, id: CFIndex, length: CFIndex) -> (kern_return_t, [UInt8], CFIndex) {
        var report = [UInt8](repeating: 0, count: Int(length))
        var outLength = length
        let result = IOHIDDeviceGetReport(device, type, id, &report, &outLength)
        return (result, report, outLength)
    }

    private func poll() {
        guard let device = hidDevice else { return }

        // On first few failures, try different report configurations
        if !hasFirstReading && retryCount < 5 {
            // Try configured values first
            let (result, report, length) = tryGetReport(device: device, type: kIOHIDReportTypeFeature, id: reportID, length: reportLength)

            if result == kIOReturnSuccess && length >= 2 {
                processReport(report: report, length: length)
                return
            }

            retryCount += 1
            log("Attempt \(retryCount): reportType=Feature reportID=\(reportID) len=\(reportLength) -> \(String(format: "0x%x", result))")

            // Try alternative configurations
            let attempts: [(IOHIDReportType, CFIndex, CFIndex)] = [
                (kIOHIDReportTypeFeature, reportID, 3),
                (kIOHIDReportTypeFeature, reportID, 4),
                (kIOHIDReportTypeFeature, reportID, 8),
                (kIOHIDReportTypeFeature, reportID, 16),
                (kIOHIDReportTypeInput, reportID, reportLength),
                (kIOHIDReportTypeInput, reportID, 3),
                (kIOHIDReportTypeInput, reportID, 4),
                (kIOHIDReportTypeFeature, 1, 3),
                (kIOHIDReportTypeFeature, 1, 4),
                (kIOHIDReportTypeFeature, 1, reportLength),
            ]

            for (type, id, len) in attempts {
                let typeName = type == kIOHIDReportTypeFeature ? "Feature" : "Input"
                let (r, rep, l) = tryGetReport(device: device, type: type, id: id, length: len)
                if r == kIOReturnSuccess && l >= 2 {
                    log("SUCCESS with reportType=\(typeName) reportID=\(id) len=\(len) -> got \(l) bytes")
                    reportID = id
                    reportLength = len
                    processReport(report: rep, length: l)
                    return
                } else {
                    log("  tried reportType=\(typeName) reportID=\(id) len=\(len) -> \(String(format: "0x%x", r))")
                }
            }
            return
        }

        // Normal path after first successful read
        let (result, report, length) = tryGetReport(device: device, type: kIOHIDReportTypeFeature, id: reportID, length: reportLength)
        if result == kIOReturnSuccess && length >= 2 {
            processReport(report: report, length: length)
        }
    }

    private func processReport(report: [UInt8], length: CFIndex) {
        // Try bytes 1-2 first (common when report ID prefix present), fall back to 0-1
        let rawAngle: Double
        if length >= 3 {
            rawAngle = Double(UInt16(report[1]) | (UInt16(report[2]) << 8))
        } else {
            rawAngle = Double(UInt16(report[0]) | (UInt16(report[1]) << 8))
        }

        if !hasFirstReading {
            let bytes = report.prefix(Int(length)).map { String(format: "%02x", $0) }.joined(separator: " ")
            log("First reading: raw=\(rawAngle)° (bytes: \(bytes))")
            lastAngle = rawAngle
            hasFirstReading = true
        }

        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTimestamp
        lastTimestamp = now

        // Direct velocity from raw angle delta — no smoothing
        if dt > 0 {
            velocity = abs(rawAngle - lastAngle) / dt
        }

        lastAngle = rawAngle
        angle = rawAngle
        statusMessage = "Monitoring lid position..."
    }
}
