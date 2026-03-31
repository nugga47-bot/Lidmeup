import SwiftUI

struct ContentView: View {
    @StateObject private var sensor = LidSensor()

    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Lidmeup")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("MacBook Lid Detector")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            // Main gauge
            LidGaugeView(percentage: sensor.percentage)
                .frame(width: 220, height: 220)

            // Percentage text
            Text("\(Int(sensor.percentage.rounded()))%")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(colorForPercentage(sensor.percentage))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: Int(sensor.percentage.rounded()))

            // Status label
            Text(lidStatusLabel)
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            // Raw sensor value
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.yellow)
                Text("Light sensor: \(sensor.rawLightValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Status message
            Text(sensor.statusMessage)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            // Calibration controls
            VStack(spacing: 12) {
                Text("Calibration")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Set Fully Open") {
                        sensor.calibrateOpen()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Set Nearly Closed") {
                        sensor.calibrateClosed()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Reset") {
                        sensor.resetCalibration()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }

                if sensor.isCalibrated {
                    Text("Calibrated")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(30)
        .frame(width: 400, height: 520)
        .onAppear {
            sensor.startMonitoring()
        }
        .onDisappear {
            sensor.stopMonitoring()
        }
        .overlay {
            if !sensor.sensorAvailable {
                SensorUnavailableView()
            }
        }
    }

    private var lidStatusLabel: String {
        switch sensor.percentage {
        case 0..<5: return "Closed"
        case 5..<25: return "Barely Open"
        case 25..<50: return "Half Open"
        case 50..<75: return "Mostly Open"
        case 75..<95: return "Open"
        default: return "Fully Open"
        }
    }

    private func colorForPercentage(_ pct: Double) -> Color {
        if pct < 25 { return .red }
        if pct < 50 { return .orange }
        if pct < 75 { return .yellow }
        return .green
    }
}

// MARK: - Gauge View

struct LidGaugeView: View {
    let percentage: Double

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color.gray.opacity(0.2),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            // Filled arc
            Circle()
                .trim(from: 0, to: 0.75 * percentage / 100)
                .stroke(
                    gaugeGradient,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.easeInOut(duration: 0.2), value: percentage)

            // Laptop icon
            Image(systemName: laptopIcon)
                .font(.system(size: 40))
                .foregroundStyle(.primary)
        }
    }

    private var gaugeGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [.red, .orange, .yellow, .green]),
            center: .center,
            startAngle: .degrees(135),
            endAngle: .degrees(135 + 270)
        )
    }

    private var laptopIcon: String {
        if percentage < 5 {
            return "laptopcomputer.slash"
        } else {
            return "laptopcomputer"
        }
    }
}

// MARK: - Sensor Unavailable

struct SensorUnavailableView: View {
    var body: some View {
        ZStack {
            Color(.windowBackgroundColor).opacity(0.95)

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)

                Text("Sensor Not Available")
                    .font(.title2.bold())

                Text("Lidmeup requires a MacBook with an ambient light sensor.\n\nMake sure you're running this on a MacBook\nand that the sensor is accessible.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Text("Tip: On macOS, go to System Settings > Privacy & Security > Sensors\nand ensure this app has permission.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }
}

#Preview {
    ContentView()
}
