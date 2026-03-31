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
    private(set) var angle: Double = 120.0
    private(set) var velocity: Double = 0.0
    private(set) var isAvailable: Bool = false
    private(set) var statusMessage: String = "Starting..."

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
    private var reportID: UInt32 = 0
    private var reportLength: Int = 0
    private var lastAngle: Double = 120.0
    private var lastTimestamp: TimeInterval = 0

    init() {}

    deinit {
        stop()
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

        isAvailable = true
        statusMessage = "Sensor connected"
        lastTimestamp = ProcessInfo.processInfo.systemUptime

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hidDevice = nil
    }

    // MARK: - HID Sensor Discovery

    private func findSensor() {
        // Try standard sensor first (usage page 0x0020, usage 0x008A)
        if let device = findStandardSensor() {
            hidDevice = device
            return
        }
        // Fallback: vendor-specific device 0x8104
        if let device = findVendorSpecificSensor() {
            hidDevice = device
            return
        }
    }

    private func findStandardSensor() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }

        for device in deviceSet {
            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
                continue
            }

            for element in elements {
                let usagePage = IOHIDElementGetUsagePage(element)
                let usage = IOHIDElementGetUsage(element)

                if usagePage == 0x0020 && usage == 0x008A {
                    let rid = IOHIDElementGetReportID(element)
                    self.reportID = UInt32(rid)
                    // Determine report length from device
                    self.reportLength = 64 // Default; will be overridden if needed
                    statusMessage = "Found standard lid angle sensor"
                    return device
                }
            }
        }

        return nil
    }

    private func findVendorSpecificSensor() -> IOHIDDevice? {
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: 0xFF00,
            kIOHIDDeviceUsageKey: 0x0001,
        ]
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }

        for device in deviceSet {
            let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
            if productID == 0x8104 {
                self.reportID = 0
                self.reportLength = 64
                statusMessage = "Found vendor-specific lid angle sensor"
                return device
            }
        }

        return nil
    }

    // MARK: - Polling

    private func poll() {
        guard let device = hidDevice else { return }

        var report = [UInt8](repeating: 0, count: reportLength)
        var length = CFIndex(reportLength)

        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            CFIndex(reportID),
            &report,
            &length
        )

        guard result == kIOReturnSuccess, length >= 3 else { return }

        // Raw angle from bytes 1-2 (little-endian 16-bit)
        let rawAngle = Double(UInt16(report[1]) | (UInt16(report[2]) << 8))

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
    }
}
