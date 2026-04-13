import AVFoundation
import Foundation

enum SoundPreset: String, CaseIterable, Identifiable {
    case customFile = "Custom File"
    case metallicClick = "Metallic Knob Click"
    case iPodClick = "iPod Click Wheel"
    case donkeyScream = "Donkey Scream"
    case fart = "Fart"

    var id: String { rawValue }

    /// Whether this preset plays one-shot clicks per degree change (vs. continuous loop)
    var isOneShot: Bool {
        switch self {
        case .metallicClick, .iPodClick: return true
        case .donkeyScream, .fart, .customFile: return false
        }
    }
}

/// Generates procedural audio buffers for built-in sound presets.
struct SoundGenerator {
    static let sampleRate: Double = 44100

    static func generateBuffer(for preset: SoundPreset) -> AVAudioPCMBuffer? {
        switch preset {
        case .customFile: return nil
        case .metallicClick: return metallicClick()
        case .iPodClick: return iPodClick()
        case .donkeyScream: return donkeyScream()
        case .fart: return fart()
        }
    }

    // MARK: - Metallic Knob Click (~15ms)
    // Short noise burst + resonant sine at ~3.5kHz with fast decay

    static func metallicClick() -> AVAudioPCMBuffer? {
        let duration = 0.018
        let frameCount = Int(sampleRate * duration)
        guard let buffer = createBuffer(frameCount: frameCount) else { return nil }
        let data = buffer.floatChannelData![0]

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let env = exp(-t * 400) // Very fast decay

            // Metallic resonance: two high-freq sines
            let resonance1 = sin(2.0 * .pi * 3500.0 * t) * 0.6
            let resonance2 = sin(2.0 * .pi * 5200.0 * t) * 0.3

            // Noise burst for the "click" attack
            let noise = Double.random(in: -1...1) * 0.4

            // Sharp attack envelope (peaks at ~0.5ms)
            let attack = min(1.0, t / 0.0005)

            data[i] = Float((resonance1 + resonance2 + noise) * env * attack * 0.8)
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    // MARK: - iPod Click Wheel (~8ms)
    // Ultra-short, crisp click — single filtered impulse

    static func iPodClick() -> AVAudioPCMBuffer? {
        let duration = 0.010
        let frameCount = Int(sampleRate * duration)
        guard let buffer = createBuffer(frameCount: frameCount) else { return nil }
        let data = buffer.floatChannelData![0]

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate

            // Sharp attack, fast decay
            let attack = min(1.0, t / 0.0002)
            let decay = exp(-t * 600)

            // Clean click: single mid-high frequency sine
            let click = sin(2.0 * .pi * 1800.0 * t) * 0.7

            // Tiny bit of upper harmonic for crispness
            let harmonic = sin(2.0 * .pi * 4400.0 * t) * 0.2

            // Micro noise for texture
            let noise = Double.random(in: -1...1) * 0.15 * exp(-t * 1200)

            data[i] = Float((click + harmonic + noise) * attack * decay * 0.9)
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    // MARK: - Donkey Scream (~2 seconds, loops)
    // "Hee-haw": alternating high-pitched inhale and low-pitched exhale
    // Nasal sawtooth with vibrato and amplitude modulation

    static func donkeyScream() -> AVAudioPCMBuffer? {
        let duration = 2.0
        let frameCount = Int(sampleRate * duration)
        guard let buffer = createBuffer(frameCount: frameCount) else { return nil }
        let data = buffer.floatChannelData![0]

        var phase: Double = 0

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let tNorm = t / duration  // 0..1

            // "Hee-haw" frequency pattern:
            // 0.0–0.4: "HEE" rising (350→700Hz)
            // 0.4–0.5: transition
            // 0.5–0.9: "HAW" falling (250→150Hz)
            // 0.9–1.0: fade out
            let baseFreq: Double
            let amplitude: Double

            if tNorm < 0.4 {
                // "HEE" - rising pitch, loud
                let heeT = tNorm / 0.4
                baseFreq = 350 + 350 * heeT
                let env = sin(heeT * .pi) // Swell in/out
                amplitude = env * 0.8
            } else if tNorm < 0.5 {
                // Brief gap
                let gapT = (tNorm - 0.4) / 0.1
                baseFreq = 700 - 450 * gapT
                amplitude = 0.1 * (1 - gapT)
            } else if tNorm < 0.9 {
                // "HAW" - falling pitch, loud
                let hawT = (tNorm - 0.5) / 0.4
                baseFreq = 250 - 100 * hawT
                let env = sin(hawT * .pi)
                amplitude = env * 0.9
            } else {
                // Fade out
                let fadeT = (tNorm - 0.9) / 0.1
                baseFreq = 150
                amplitude = 0.1 * (1 - fadeT)
            }

            // Strong vibrato for braying character
            let vibrato = sin(2.0 * .pi * 6.0 * t) * 0.08
            let freq = baseFreq * (1.0 + vibrato)

            // Advance phase
            phase += freq / sampleRate
            phase -= Double(Int(phase))

            // Nasal sawtooth (mix of saw + pulse for harsh nasal quality)
            let saw = 2.0 * phase - 1.0
            let pulse = phase < 0.35 ? 1.0 : -1.0
            let wave = saw * 0.5 + pulse * 0.35

            // Amplitude tremolo (fast wobble like a bray)
            let tremolo = 1.0 + sin(2.0 * .pi * 22.0 * t) * 0.3

            // Rough up the signal a bit
            var sample = wave * amplitude * tremolo
            sample = sample / (1.0 + abs(sample) * 0.5) // Soft clip

            data[i] = Float(sample * 0.7)
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    // MARK: - Fart (~1.5 seconds, loops)
    // Low-frequency rumble with noise bursts, pitch drops, and sputtering

    static func fart() -> AVAudioPCMBuffer? {
        let duration = 1.5
        let frameCount = Int(sampleRate * duration)
        guard let buffer = createBuffer(frameCount: frameCount) else { return nil }
        let data = buffer.floatChannelData![0]

        var phase: Double = 0
        var noiseState: Double = 0

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let tNorm = t / duration

            // Envelope: quick attack, sustained, sputtering end
            let envelope: Double
            if tNorm < 0.05 {
                envelope = tNorm / 0.05  // Attack
            } else if tNorm < 0.6 {
                envelope = 1.0  // Sustain
            } else {
                // Sputtering fade: multiply by a choppy pattern
                let fadeT = (tNorm - 0.6) / 0.4
                let chop = sin(tNorm * 80.0) > 0 ? 1.0 : 0.3
                envelope = (1.0 - fadeT) * chop
            }

            // Base frequency: starts ~80Hz, drops to ~40Hz
            let baseFreq = 80.0 - 40.0 * tNorm

            // Sub-oscillations for the "flapping" character
            let flap = sin(2.0 * .pi * 18.0 * t) * 0.5
            let freq = baseFreq * (1.0 + flap * 0.3)

            // Advance phase
            phase += freq / sampleRate
            phase -= Double(Int(phase))

            // Mix of: low square-ish wave + filtered noise
            let square = phase < 0.4 ? 0.8 : -0.8
            let saw = 2.0 * phase - 1.0
            let bass = square * 0.5 + saw * 0.3

            // Brown noise (random walk, low-pass)
            noiseState += Double.random(in: -0.15...0.15)
            noiseState *= 0.97  // Decay to keep bounded
            let noise = noiseState

            // Bubbling: amplitude modulated noise bursts
            let bubble = sin(2.0 * .pi * 25.0 * t)
            let bubbleEnv = max(0, bubble) // Only positive half
            let bubblyNoise = noise * bubbleEnv * 0.6

            var sample = (bass + bubblyNoise) * envelope

            // Soft clip
            sample = sample / (1.0 + abs(sample) * 0.3)

            data[i] = Float(sample * 0.75)
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
