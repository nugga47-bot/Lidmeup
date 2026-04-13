import AVFoundation
import Foundation

/// Plays sound in response to lid movement.
/// Fully rebuilds the audio engine graph when switching between modes
/// to avoid Core Audio graph initialization errors.
final class CreakAudioEngine {
    private var engine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var clickPlayerNode: AVAudioPlayerNode!
    private var varispeed: AVAudioUnitVarispeed!
    private var audioBuffer: AVAudioPCMBuffer?
    private var clickBuffer: AVAudioPCMBuffer?
    private var customFileBuffer: AVAudioPCMBuffer?
    private var customFileFormat: AVAudioFormat?
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
        // Restore last used custom file
        if let bookmark = UserDefaults.standard.data(forKey: savedFileKey) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
               url.startAccessingSecurityScopedResource() {
                loadFileIntoBuffer(url: url)
            }
        }
    }

    // MARK: - Build a fresh engine for the current mode

    private func buildEngine() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        clickPlayerNode = AVAudioPlayerNode()
        varispeed = AVAudioUnitVarispeed()

        if isOneShotMode {
            // One-shot: clickPlayerNode → mixer
            engine.attach(clickPlayerNode)
            engine.connect(clickPlayerNode, to: engine.mainMixerNode, format: monoFormat)
            clickPlayerNode.volume = masterVolume
        } else {
            // Continuous: playerNode → varispeed → mixer
            let format: AVAudioFormat
            if currentPreset == .customFile, let cf = customFileFormat {
                format = cf
            } else {
                format = monoFormat
            }
            engine.attach(playerNode)
            engine.attach(varispeed)
            engine.connect(playerNode, to: varispeed, format: format)
            engine.connect(varispeed, to: engine.mainMixerNode, format: nil)
            playerNode.volume = 0
            varispeed.rate = 1.0
        }
    }

    // MARK: - Preset Selection

    func selectPreset(_ preset: SoundPreset) {
        let wasRunning = isRunning
        if wasRunning { stop() }

        currentPreset = preset
        isOneShotMode = preset.isOneShot

        if preset == .customFile {
            audioBuffer = customFileBuffer
            clickBuffer = nil
            isFileLoaded = customFileBuffer != nil
            loadedFileName = isFileLoaded ? (loadedFileName.isEmpty ? "Custom" : loadedFileName) : ""
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

    private func loadFileIntoBuffer(url: URL) {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return }
            try file.read(into: buffer)

            customFileBuffer = buffer
            customFileFormat = format
            audioBuffer = buffer
            loadedFileName = url.lastPathComponent
            isFileLoaded = true

            print("[CreakAudioEngine] Loaded: \(loadedFileName) (\(file.length) frames, \(format.sampleRate)Hz)")
        } catch {
            print("[CreakAudioEngine] Failed to load: \(error)")
        }
    }

    func loadFile(url: URL, saveBookmark: Bool = true) {
        let wasRunning = isRunning
        if wasRunning { stop() }

        loadFileIntoBuffer(url: url)

        currentPreset = .customFile
        isOneShotMode = false
        clickBuffer = nil

        if saveBookmark {
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: savedFileKey)
            }
        }

        if wasRunning && isFileLoaded { start() }
    }

    // MARK: - Playback

    func start() {
        guard isFileLoaded else {
            print("[CreakAudioEngine] No audio loaded")
            return
        }
        guard !isRunning else { return }

        // Build a fresh engine every time to avoid graph corruption
        buildEngine()

        do {
            try engine.start()

            if isOneShotMode {
                clickPlayerNode.play()
            } else if let buffer = audioBuffer {
                playerNode.volume = 0
                playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
                playerNode.play()
            }

            currentVolume = 0
            currentRate = 1.0
            lastClickAngle = latestAngle
            isRunning = true

            updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.updateAudio()
            }
            RunLoop.current.add(updateTimer!, forMode: .common)

            print("[CreakAudioEngine] Started (\(isOneShotMode ? "one-shot" : "continuous") mode)")
        } catch {
            print("[CreakAudioEngine] Failed to start: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        updateTimer?.invalidate()
        updateTimer = nil

        playerNode?.stop()
        clickPlayerNode?.stop()
        engine?.stop()

        isRunning = false
        latestVelocity = 0
        currentVolume = 0
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
