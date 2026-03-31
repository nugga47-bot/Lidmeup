import AVFoundation
import Foundation

/// Plays sound in response to lid movement.
/// Supports two modes:
/// - **Continuous**: loops an audio buffer, volume modulated by velocity
/// - **One-shot**: plays a short click on each degree change
final class CreakAudioEngine {
    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var clickPlayerNode = AVAudioPlayerNode()
    private var varispeed = AVAudioUnitVarispeed()
    private var audioBuffer: AVAudioPCMBuffer?
    private var clickBuffer: AVAudioPCMBuffer?
    private(set) var isRunning = false
    private(set) var isFileLoaded = false
    private(set) var loadedFileName: String = ""
    private(set) var currentPreset: SoundPreset = .customFile
    private var isOneShotMode = false

    // User-adjustable parameters
    var masterVolume: Float = 0.8
    var fadeSpeed: Double = 20.0
    var minRate: Float = 0.80
    var maxRate: Float = 1.20
    var velocityThreshold: Double = 0.3
    var velocityFullResponse: Double = 10.0

    // State
    private var latestVelocity: Double = 0
    private var latestAngle: Double = 0
    private var lastClickAngle: Double = 0
    private var currentVolume: Float = 0
    private var currentRate: Float = 1.0
    private var updateTimer: Timer?

    private let savedFileKey = "lidmeup_audio_file"
    private let monoFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    init() {
        setupEngine()

        // Restore last used custom file
        if let bookmark = UserDefaults.standard.data(forKey: savedFileKey) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
               url.startAccessingSecurityScopedResource() {
                loadFile(url: url, saveBookmark: false)
            }
        }
    }

    private func setupEngine() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        clickPlayerNode = AVAudioPlayerNode()
        varispeed = AVAudioUnitVarispeed()

        engine.attach(playerNode)
        engine.attach(clickPlayerNode)
        engine.attach(varispeed)

        // Continuous path: playerNode → varispeed → mixer
        engine.connect(playerNode, to: varispeed, format: nil)
        engine.connect(varispeed, to: engine.mainMixerNode, format: nil)

        // One-shot path: clickPlayerNode → mixer
        engine.connect(clickPlayerNode, to: engine.mainMixerNode, format: monoFormat)

        playerNode.volume = 0
        clickPlayerNode.volume = 1.0
        varispeed.rate = 1.0
    }

    // MARK: - Preset Selection

    func selectPreset(_ preset: SoundPreset) {
        let wasRunning = isRunning
        if wasRunning { stop() }

        currentPreset = preset
        isOneShotMode = preset.isOneShot

        if preset == .customFile {
            // Keep whatever custom file was loaded
            clickBuffer = nil
        } else {
            if let buffer = SoundGenerator.generateBuffer(for: preset) {
                if preset.isOneShot {
                    clickBuffer = buffer
                    audioBuffer = nil
                } else {
                    audioBuffer = buffer
                    clickBuffer = nil
                }
                loadedFileName = preset.rawValue
                isFileLoaded = true
                print("[CreakAudioEngine] Generated \(preset.rawValue): \(buffer.frameLength) frames")
            }
        }

        if wasRunning && isFileLoaded { start() }
    }

    // MARK: - File Loading

    private var customFileBuffer: AVAudioPCMBuffer?

    func loadFile(url: URL, saveBookmark: Bool = true) {
        do {
            let file = try AVAudioFile(forReading: url)

            guard let format = AVAudioFormat(
                commonFormat: file.processingFormat.commonFormat,
                sampleRate: file.processingFormat.sampleRate,
                channels: file.processingFormat.channelCount,
                interleaved: file.processingFormat.isInterleaved
            ) else { return }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return }
            try file.read(into: buffer)

            customFileBuffer = buffer
            audioBuffer = buffer
            clickBuffer = nil

            currentPreset = .customFile
            isOneShotMode = false
            loadedFileName = url.lastPathComponent
            isFileLoaded = true

            if saveBookmark {
                if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(bookmark, forKey: savedFileKey)
                }
            }

            // Reconnect playerNode with the file's format
            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(varispeed)
            engine.connect(playerNode, to: varispeed, format: format)
            engine.connect(varispeed, to: engine.mainMixerNode, format: nil)

            print("[CreakAudioEngine] Loaded: \(loadedFileName) (\(file.length) frames, \(format.sampleRate)Hz)")
        } catch {
            print("[CreakAudioEngine] Failed to load file: \(error)")
            isFileLoaded = false
        }
    }

    // MARK: - Playback

    func start() {
        guard isFileLoaded else {
            print("[CreakAudioEngine] No audio loaded")
            return
        }
        guard !isRunning else { return }

        // For procedural presets, reconnect playerNode with monoFormat
        if currentPreset != .customFile && !isOneShotMode {
            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(varispeed)
            engine.connect(playerNode, to: varispeed, format: monoFormat)
            engine.connect(varispeed, to: engine.mainMixerNode, format: nil)
        }

        do {
            try engine.start()

            if isOneShotMode {
                clickPlayerNode.volume = masterVolume
                // Pre-play so it's ready to schedule buffers
                clickPlayerNode.play()
            } else if let buffer = audioBuffer {
                playerNode.volume = 0
                playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
                playerNode.play()
            }

            currentVolume = 0
            currentRate = 1.0
            varispeed.rate = 1.0
            lastClickAngle = latestAngle
            isRunning = true

            updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.updateAudio()
            }
            RunLoop.current.add(updateTimer!, forMode: .common)

            print("[CreakAudioEngine] Started (\(isOneShotMode ? "one-shot" : "continuous") mode)")
        } catch {
            print("[CreakAudioEngine] Failed to start engine: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        updateTimer?.invalidate()
        updateTimer = nil
        playerNode.stop()
        clickPlayerNode.stop()
        engine.stop()
        isRunning = false
        latestVelocity = 0
        currentVolume = 0
        playerNode.volume = 0
    }

    // MARK: - Feed from sensor

    func feed(angle: Double, velocity: Double) {
        latestAngle = angle
        latestVelocity = velocity
    }

    // MARK: - Audio update (60Hz)

    private func updateAudio() {
        if isOneShotMode {
            updateOneShot()
        } else {
            updateContinuous()
        }
    }

    private func updateOneShot() {
        guard let buffer = clickBuffer else { return }

        let angleDelta = abs(latestAngle - lastClickAngle)
        if angleDelta >= 1.0 && latestVelocity > velocityThreshold {
            clickPlayerNode.scheduleBuffer(buffer, at: nil, options: [])
            lastClickAngle = latestAngle
        }
    }

    private func updateContinuous() {
        let targetVolume: Float
        if latestVelocity <= velocityThreshold {
            targetVolume = 0
        } else if latestVelocity >= velocityFullResponse {
            targetVolume = masterVolume
        } else {
            let t = Float((latestVelocity - velocityThreshold) / (velocityFullResponse - velocityThreshold))
            targetVolume = t * masterVolume
        }

        let dt: Float = 1.0 / 60.0
        let tau = Float(fadeSpeed / 1000.0)
        let alpha = min(1.0, dt / max(tau, 0.001))

        currentVolume += (targetVolume - currentVolume) * alpha
        if targetVolume == 0 && currentVolume < 0.01 {
            currentVolume = 0
        }

        playerNode.volume = currentVolume

        let targetRate: Float
        if latestVelocity <= velocityThreshold {
            targetRate = minRate
        } else {
            let rateFraction = Float(min(1.0, latestVelocity / velocityFullResponse))
            targetRate = minRate + (maxRate - minRate) * rateFraction
        }
        let rateAlpha = min(1.0, dt / 0.1)
        currentRate += (targetRate - currentRate) * rateAlpha
        varispeed.rate = currentRate
    }
}
