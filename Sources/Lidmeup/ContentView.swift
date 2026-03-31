import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sensor = LidSensor()
    @State private var creakEngine = CreakAudioEngine()
    @State private var soundEnabled = false
    @State private var showFilePicker = false
    @State private var showSoundControls = false
    @State private var selectedPreset: SoundPreset = .customFile

    // Bound parameters
    @State private var volume: Double = 0.8
    @State private var fadeSpeed: Double = 20.0
    @State private var minRate: Double = 0.80
    @State private var maxRate: Double = 1.20
    @State private var sensitivity: Double = 10.0

    var body: some View {
        VStack(spacing: 20) {
            // Title
            VStack(spacing: 4) {
                Text("Lidmeup")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("MacBook Lid Detector")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Main gauge
            LidGaugeView(percentage: sensor.percentage)
                .frame(width: 200, height: 200)

            // Angle in degrees
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(sensor.angle.rounded()))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(colorForPercentage(sensor.percentage))
                    .contentTransition(.numericText())
                Text("\u{00B0}")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Percentage + status
            Text("\(Int(sensor.percentage.rounded()))% open  \u{2022}  \(sensor.status)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            // MARK: - Sound Section
            VStack(spacing: 12) {
                // Preset picker
                HStack {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(.orange)
                    Picker("Sound", selection: $selectedPreset) {
                        ForEach(SoundPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedPreset) {
                        if selectedPreset == .customFile {
                            // Restore custom file if available
                            if !creakEngine.isFileLoaded || creakEngine.loadedFileName == creakEngine.currentPreset.rawValue {
                                creakEngine.selectPreset(.customFile)
                            }
                        } else {
                            creakEngine.selectPreset(selectedPreset)
                        }
                    }
                }

                // Custom file row (only for custom file preset)
                if selectedPreset == .customFile {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)
                        if creakEngine.isFileLoaded && creakEngine.currentPreset == .customFile {
                            Text(creakEngine.loadedFileName)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No sound file loaded")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Choose File...") {
                            showFilePicker = true
                        }
                        .controlSize(.small)
                    }
                }

                // Play + Controls row
                HStack(spacing: 10) {
                    Button {
                        soundEnabled.toggle()
                        if soundEnabled {
                            creakEngine.start()
                        } else {
                            creakEngine.stop()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            Text(soundEnabled ? "Sound On" : "Sound Off")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(soundEnabled ? .orange : .gray)
                    .disabled(!creakEngine.isFileLoaded)
                    .keyboardShortcut(.space, modifiers: [])

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSoundControls.toggle()
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.bordered)
                }

                // Expandable controls
                if showSoundControls {
                    SoundControlsView(
                        volume: $volume,
                        fadeSpeed: $fadeSpeed,
                        minRate: $minRate,
                        maxRate: $maxRate,
                        sensitivity: $sensitivity
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Status bar
            HStack {
                Circle()
                    .fill(sensor.isAvailable ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(sensor.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if sensor.velocity > 0.5 {
                    Text(String(format: "%.1f\u{00B0}/s", sensor.velocity))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 400, idealWidth: 400, minHeight: 500, idealHeight: 700)
        .onAppear {
            sensor.start()
        }
        .onDisappear {
            sensor.stop()
            creakEngine.stop()
        }
        .onChange(of: sensor.angle) {
            if soundEnabled {
                creakEngine.feed(angle: sensor.angle, velocity: sensor.velocity)
            }
        }
        .onChange(of: sensor.velocity) {
            if soundEnabled {
                creakEngine.feed(angle: sensor.angle, velocity: sensor.velocity)
            }
        }
        .onChange(of: volume) { creakEngine.masterVolume = Float(volume) }
        .onChange(of: fadeSpeed) { creakEngine.fadeSpeed = fadeSpeed }
        .onChange(of: minRate) { creakEngine.minRate = Float(minRate) }
        .onChange(of: maxRate) { creakEngine.maxRate = Float(maxRate) }
        .onChange(of: sensitivity) { creakEngine.velocityFullResponse = sensitivity }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    creakEngine.loadFile(url: url)
                }
            }
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

// MARK: - Sound Controls

struct SoundControlsView: View {
    @Binding var volume: Double
    @Binding var fadeSpeed: Double
    @Binding var minRate: Double
    @Binding var maxRate: Double
    @Binding var sensitivity: Double

    var body: some View {
        VStack(spacing: 10) {
            ParamSlider(label: "Volume", value: $volume, range: 0...1, displayFormat: "%.0f%%") { $0 * 100 }
            ParamSlider(label: "Fade Speed", value: $fadeSpeed, range: 10...500, unit: "ms")
            ParamSlider(label: "Min Pitch", value: $minRate, range: 0.3...1.5, displayFormat: "%.2fx")
            ParamSlider(label: "Max Pitch", value: $maxRate, range: 0.5...3.0, displayFormat: "%.2fx")
            ParamSlider(label: "Sensitivity", value: $sensitivity, range: 1...50, unit: "\u{00B0}/s")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ParamSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""
    var displayFormat: String? = nil
    var displayTransform: ((Double) -> Double)? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 75, alignment: .leading)
            Slider(value: $value, in: range)
                .controlSize(.small)
            Text(formattedValue)
                .font(.caption.monospacedDigit())
                .frame(width: 55, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }

    private var formattedValue: String {
        let displayVal = displayTransform?(value) ?? value
        if let fmt = displayFormat {
            return String(format: fmt, displayVal)
        }
        return String(format: "%.1f", displayVal) + unit
    }
}

// MARK: - Gauge View

struct LidGaugeView: View {
    let percentage: Double

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color.gray.opacity(0.2),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * percentage / 100)
                .stroke(
                    gaugeGradient,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.linear(duration: 0.03), value: percentage)

            Image(systemName: percentage < 5 ? "laptopcomputer.slash" : "laptopcomputer")
                .font(.system(size: 36))
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
                    Text("Supported: MacBook Pro 14\"/16\" (2021+), MacBook Air (M2+, 2022+)")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            }
        }
    }
}
