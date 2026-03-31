import SwiftUI

struct ContentView: View {
    @State private var sensor = LidSensor()

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

            // Angle in degrees
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(sensor.angle.rounded()))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(colorForPercentage(sensor.percentage))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: Int(sensor.angle.rounded()))
                Text("\u{00B0}")
                    .font(.system(size: 32, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Percentage
            Text("\(Int(sensor.percentage.rounded()))% open")
                .font(.title2)
                .foregroundStyle(.secondary)

            // Status label
            Text(sensor.status)
                .font(.title3)
                .foregroundStyle(.tertiary)

            // Velocity
            if sensor.velocity > 0.5 {
                Text(String(format: "%.1f\u{00B0}/s", sensor.velocity))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Spacer()

            // Status message
            HStack {
                Circle()
                    .fill(sensor.isAvailable ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(sensor.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(30)
        .frame(width: 400, height: 520)
        .onAppear {
            sensor.start()
        }
        .onDisappear {
            sensor.stop()
        }
        .overlay {
            if !sensor.isAvailable && sensor.statusMessage.contains("not found") {
                SensorUnavailableView()
            }
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

                VStack(spacing: 8) {
                    Text("Lidmeup requires a MacBook with a lid angle sensor.")
                        .font(.body)

                    Text("Supported models:")
                        .font(.subheadline.bold())
                        .padding(.top, 4)

                    Text("MacBook Pro 14\"/16\" (2021-2024, M1 Pro/Max+)\nMacBook Air (M2+, 2022+)")
                        .font(.caption)
                        .multilineTextAlignment(.center)

                    Text("Note: M1/M2 MacBook Air/Pro with Touch Bar\nare NOT supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            }
        }
    }
}

#Preview {
    ContentView()
}
