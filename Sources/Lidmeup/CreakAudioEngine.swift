import AVFoundation
import Foundation

/// Synthesizes a door-creak sound in real-time, driven by lid velocity.
/// Uses multiple detuned oscillators with frequency modulation for a creaky character.
final class CreakAudioEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private(set) var isRunning = false

    // Parameters (tweakable)
    var baseFrequency: Double = 180.0     // Base creak pitch (Hz)
    var frequencyRange: Double = 120.0    // How much pitch varies with angle
    var vibratoRate: Double = 12.0        // Wobble speed for creaky character (Hz)
    var vibratoDepth: Double = 0.35       // How much wobble
    var velocityFullGain: Double = 8.0    // Velocity for maximum volume (deg/s)
    var velocityQuietGain: Double = 0.5   // Velocity below which sound fades out
    var maxVolume: Double = 0.7           // Peak output volume

    // Ramping (milliseconds)
    var gainRampMs: Double = 40.0
    var frequencyRampMs: Double = 60.0

    // State (accessed from audio thread)
    nonisolated(unsafe) private var phase1: Double = 0
    nonisolated(unsafe) private var phase2: Double = 0
    nonisolated(unsafe) private var phase3: Double = 0
    nonisolated(unsafe) private var vibratoPhase: Double = 0
    nonisolated(unsafe) private var noisePhase: Double = 0
    nonisolated(unsafe) private var currentGain: Double = 0
    nonisolated(unsafe) private var currentFreq: Double = 180.0

    // Targets (set from main thread, read from audio thread)
    nonisolated(unsafe) private var targetGain: Double = 0
    nonisolated(unsafe) private var targetFreq: Double = 180.0

    func start() {
        guard !isRunning else { return }

        let sampleRate = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        sourceNode = AVAudioSourceNode(format: format) { [self] _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let buffer = ablPointer[0]
            let frames = Int(frameCount)
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let dt = 1.0 / sampleRate
            let gainAlpha = min(1.0, dt / (self.gainRampMs / 1000.0))
            let freqAlpha = min(1.0, dt / (self.frequencyRampMs / 1000.0))

            for i in 0..<frames {
                // Ramp gain and frequency toward targets
                self.currentGain += (self.targetGain - self.currentGain) * gainAlpha
                self.currentFreq += (self.targetFreq - self.currentFreq) * freqAlpha

                // Vibrato (creates the "creaky" wobble)
                self.vibratoPhase += self.vibratoRate * dt
                let vibrato = sin(self.vibratoPhase * 2.0 * .pi) * self.vibratoDepth

                let freq = self.currentFreq * (1.0 + vibrato)

                // Oscillator 1: Main tone (slightly harsh sawtooth-like)
                self.phase1 += freq * dt
                self.phase1 -= Double(Int(self.phase1))
                let saw1 = 2.0 * self.phase1 - 1.0

                // Oscillator 2: Detuned slightly up (adds thickness)
                self.phase2 += (freq * 1.007) * dt
                self.phase2 -= Double(Int(self.phase2))
                let saw2 = 2.0 * self.phase2 - 1.0

                // Oscillator 3: Sub-harmonic (adds body)
                self.phase3 += (freq * 0.501) * dt
                self.phase3 -= Double(Int(self.phase3))
                let sub = sin(self.phase3 * 2.0 * .pi) * 0.3

                // Mix oscillators and apply soft clipping for warmth
                var mix = (saw1 * 0.5 + saw2 * 0.3 + sub) * self.currentGain

                // Soft clip (tanh-like)
                mix = mix / (1.0 + abs(mix))

                data[i] = Float(mix)
            }

            return noErr
        }

        guard let sourceNode else { return }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            isRunning = true
        } catch {
            print("[CreakAudioEngine] Failed to start: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        sourceNode.map { engine.detach($0) }
        sourceNode = nil
        isRunning = false
        currentGain = 0
        targetGain = 0
    }

    /// Called every frame with the current lid angle and velocity.
    func feed(angle: Double, velocity: Double) {
        // Map velocity to gain using smoothstep
        let t: Double
        if velocity <= velocityQuietGain {
            t = 0
        } else if velocity >= velocityFullGain {
            t = 1
        } else {
            let normalized = (velocity - velocityQuietGain) / (velocityFullGain - velocityQuietGain)
            t = normalized * normalized * (3 - 2 * normalized) // smoothstep
        }
        targetGain = t * maxVolume

        // Map angle to frequency (lower angle = lower pitch, like a heavy door)
        let angleFraction = min(1.0, max(0.0, angle / 130.0))
        targetFreq = baseFrequency + frequencyRange * angleFraction
    }

    func resetToDefaults() {
        baseFrequency = 180.0
        frequencyRange = 120.0
        vibratoRate = 12.0
        vibratoDepth = 0.35
        velocityFullGain = 8.0
        velocityQuietGain = 0.5
        maxVolume = 0.7
        gainRampMs = 40.0
        frequencyRampMs = 60.0
    }
}
