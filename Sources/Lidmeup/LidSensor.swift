import Foundation
import IOKit

/// Reads the MacBook's ambient light sensor (ALS) via IOKit to estimate lid openness.
/// As the lid closes, less ambient light reaches the sensor, so the reading decreases.
/// We map this to a percentage: 0% = closed, 100% = fully open.
final class LidSensor: ObservableObject {
    @Published var percentage: Double = 100.0
    @Published var rawLightValue: UInt64 = 0
    @Published var isCalibrated: Bool = false
    @Published var sensorAvailable: Bool = true
    @Published var statusMessage: String = "Starting..."

    private var timer: Timer?
    private var connection: io_connect_t = 0
    private var serviceOpen: Bool = false

    // Calibration values
    private var minLight: UInt64 = 0       // Light reading when lid is closed
    private var maxLight: UInt64 = 500_000 // Light reading when lid is fully open (default)

    private let calibrationKey = "lidmeup_calibration"

    init() {
        loadCalibration()
        openSensor()
    }

    deinit {
        stopMonitoring()
        closeSensor()
    }

    // MARK: - IOKit Sensor Access

    private func openSensor() {
        let serviceDict = IOServiceMatching("AppleLMUController")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, serviceDict)

        guard service != IO_OBJECT_NULL else {
            DispatchQueue.main.async {
                self.sensorAvailable = false
                self.statusMessage = "No ambient light sensor found. Is this a MacBook?"
            }
            return
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        if result == KERN_SUCCESS {
            serviceOpen = true
            DispatchQueue.main.async {
                self.statusMessage = "Sensor connected"
            }
        } else {
            DispatchQueue.main.async {
                self.sensorAvailable = false
                self.statusMessage = "Could not open light sensor (error: \(result))"
            }
        }
    }

    private func closeSensor() {
        if serviceOpen {
            IOServiceClose(connection)
            serviceOpen = false
        }
    }

    private func readLightSensor() -> UInt64? {
        guard serviceOpen else { return nil }

        var outputCount: UInt32 = 2
        var values = [UInt64](repeating: 0, count: 2)

        let result = IOConnectCallMethod(
            connection,
            0,           // selector for getLightSensorReading
            nil, 0,      // no scalar input
            nil, 0,      // no struct input
            &values, &outputCount,  // scalar output
            nil, nil     // no struct output
        )

        guard result == KERN_SUCCESS else { return nil }

        // values[0] is the left sensor, values[1] is the right sensor
        // Average both sensors for a more stable reading
        return (values[0] + values[1]) / 2
    }

    // MARK: - Monitoring

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateReading()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateReading() {
        guard let lightValue = readLightSensor() else {
            return
        }

        DispatchQueue.main.async { [self] in
            self.rawLightValue = lightValue

            // Dynamically update maxLight if we see a higher value
            if lightValue > self.maxLight && self.isCalibrated {
                self.maxLight = lightValue
                self.saveCalibration()
            }

            // Calculate percentage
            let range = Double(self.maxLight) - Double(self.minLight)
            if range > 0 {
                let normalized = (Double(lightValue) - Double(self.minLight)) / range
                self.percentage = min(100, max(0, normalized * 100))
            } else {
                self.percentage = lightValue > 0 ? 100 : 0
            }

            self.statusMessage = "Monitoring lid position..."
        }
    }

    // MARK: - Calibration

    func calibrateOpen() {
        guard let value = readLightSensor() else { return }
        DispatchQueue.main.async {
            self.maxLight = max(value, 1) // Avoid zero
            self.isCalibrated = true
            self.saveCalibration()
            self.statusMessage = "Open position calibrated (\(value))"
        }
    }

    func calibrateClosed() {
        guard let value = readLightSensor() else { return }
        DispatchQueue.main.async {
            self.minLight = value
            self.isCalibrated = true
            self.saveCalibration()
            self.statusMessage = "Closed position calibrated (\(value))"
        }
    }

    func resetCalibration() {
        DispatchQueue.main.async {
            self.minLight = 0
            self.maxLight = 500_000
            self.isCalibrated = false
            UserDefaults.standard.removeObject(forKey: self.calibrationKey)
            self.statusMessage = "Calibration reset"
        }
    }

    private func saveCalibration() {
        let data: [String: UInt64] = ["min": minLight, "max": maxLight]
        UserDefaults.standard.set(data, forKey: calibrationKey)
    }

    private func loadCalibration() {
        guard let data = UserDefaults.standard.dictionary(forKey: calibrationKey),
              let min = data["min"] as? UInt64,
              let max = data["max"] as? UInt64 else { return }
        minLight = min
        maxLight = max
        isCalibrated = true
    }
}
