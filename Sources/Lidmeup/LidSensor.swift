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

    // Smoothing factors
    private let angleSmoothingFactor = 0.05
    private let velocitySmoothingFactor = 0.30

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
                    // Get report size from the element, add 1 byte for report ID prefix
                    let reportSize = IOHIDElementGetReportSize(element)
                    self.reportLength = CFIndex((reportSize / 8) + 1)
                    if self.reportLength < 3 {
                        self.reportLength = 64 // Fallback
                    }

                    let deviceName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
                    log("Found standard sensor on '\(deviceName)' (reportID=\(reportID), reportLength=\(reportLength))")
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

    private func poll() {
        guard let device = hidDevice else { return }

        var report = [UInt8](repeating: 0, count: Int(reportLength))
        var length = reportLength

        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            reportID,
            &report,
            &length
        )

        guard result == kIOReturnSuccess else {
            if !hasFirstReading {
                log("GetReport failed: \(String(format: "0x%x", result)), length=\(length)")
            }
            return
        }

        guard length >= 3 else {
            if !hasFirstReading {
                log("Report too short: \(length) bytes")
            }
            return
        }

        // Raw angle from bytes 1-2 (little-endian 16-bit)
        let rawAngle = Double(UInt16(report[1]) | (UInt16(report[2]) << 8))

        if !hasFirstReading {
            log("First reading: raw=\(rawAngle)° (bytes: \(report.prefix(Int(length)).map { String(format: "%02x", $0) }.joined(separator: " ")))")
            lastAngle = rawAngle
            hasFirstReading = true
        }

        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTimestamp
        lastTimestamp = now

        // Exponential smoothing on angle
        let smoothedAngle = lastAngle + angleSmoothingFactor * (rawAngle - lastAngle)

        // Velocity calculation
        if dt > 0 {
            let rawVelocity = abs(smoothedAngle - lastAngle) / dt
            velocity = velocity + velocitySmoothingFactor * (rawVelocity - velocity)
        }

        // Decay velocity when not moving
        if abs(rawAngle - lastAngle) < 0.5 {
            velocity *= 0.5
        }

        lastAngle = smoothedAngle
        angle = smoothedAngle
        statusMessage = "Monitoring lid position..."
    }
}
