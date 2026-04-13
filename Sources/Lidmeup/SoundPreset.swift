import AVFoundation
import Foundation

enum SoundPreset: String, CaseIterable, Identifiable {
    case customFile1 = "Custom Sound 1"
    case customFile2 = "Custom Sound 2"
    case customFile3 = "Custom Sound 3"
    case metallicClick = "Metallic Knob Click"
    case iPodClick = "iPod Click Wheel"

    var id: String { rawValue }

    var isOneShot: Bool {
        switch self {
        case .metallicClick, .iPodClick: return true
        case .customFile1, .customFile2, .customFile3: return false
        }
    }

    var isCustom: Bool {
        switch self {
        case .customFile1, .customFile2, .customFile3: return true
        default: return false
        }
    }

    /// UserDefaults key for saving this slot's file bookmark
    var bookmarkKey: String {
        "lidmeup_audio_\(rawValue)"
    }
}

struct SoundGenerator {
    static let sampleRate: Double = 44100

    static func generateBuffer(for preset: SoundPreset) -> AVAudioPCMBuffer? {
        switch preset {
        case .customFile1, .customFile2, .customFile3: return nil
        case .metallicClick: return metallicClick()
        case .iPodClick: return iPodClick()
        }
    }

    // MARK: - Metallic Knob Click (~15ms)

    static func metallicClick() -> AVAudioPCMBuffer? {
        let duration = 0.018
        let frameCount = Int(sampleRate * duration)
        guard let buffer = createBuffer(frameCount: frameCount) else { return nil }
        let data = buffer.floatChannelData![0]

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let env = exp(-t * 400)
            let resonance1 = sin(2.0 * .pi * 3500.0 * t) * 0.6
            let resonance2 = sin(2.0 * .pi * 5200.0 * t) * 0.3
            let noise = Double.random(in: -1...1) * 0.4
            let attack = min(1.0, t / 0.0005)
            data[i] = Float((resonance1 + resonance2 + noise) * env * attack * 0.8)
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    // MARK: - iPod Click Wheel (~8ms)

    static func iPodClick() -> AVAudioPCMBuffer? {
        let duration = 0.010
        let frameCount = Int(sampleRate * duration)
        guard let buffer = createBuffer(frameCount: frameCount) else { return nil }
        let data = buffer.floatChannelData![0]

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let attack = min(1.0, t / 0.0002)
            let decay = exp(-t * 600)
            let click = sin(2.0 * .pi * 1800.0 * t) * 0.7
            let harmonic = sin(2.0 * .pi * 4400.0 * t) * 0.2
            let noise = Double.random(in: -1...1) * 0.15 * exp(-t * 1200)
            data[i] = Float((click + harmonic + noise) * attack * decay * 0.9)
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    // MARK: - Helpers

    private static func createBuffer(frameCount: Int) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
    }
}
