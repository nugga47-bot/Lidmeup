import AVFoundation
import Foundation

final class CreakAudioEngine {
    private var engine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var clickPlayerNode: AVAudioPlayerNode!
    private var varispeed: AVAudioUnitVarispeed!
    private var audioBuffer: AVAudioPCMBuffer?
    private var clickBuffer: AVAudioPCMBuffer?
    private(set) var isRunning = false
    private(set) var isFileLoaded = false
    private(set) var loadedFileName: String = ""
    private(set) var currentPreset: SoundPreset = .customFile1
    private var isOneShotMode = false

    // Per-slot storage
    private var slotBuffers: [SoundPreset: AVAudioPCMBuffer] = [:]
    private var slotFormats: [SoundPreset: AVAudioFormat] = [:]
    private var slotFileNames: [SoundPreset: String] = [:]
    private var currentCustomFormat: AVAudioFormat?

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

    private let monoFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let savedPresetKey = "lidmeup_selected_preset"

    init() {
        // Restore saved files for all custom slots
        for preset in SoundPreset.allCases where preset.isCustom {
            restoreFile(for: preset)
        }

        // Restore last selected preset
        if let savedPreset = UserDefaults.standard.string(forKey: savedPresetKey),
           let preset = SoundPreset.allCases.first(where: { $0.rawValue == savedPreset }) {
            currentPreset = preset
            selectPreset(preset)
        }
    }

    // MARK: - File persistence per slot

    private func restoreFile(for preset: SoundPreset) {
        guard let bookmark = UserDefaults.standard.data(forKey: preset.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else { return }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return }
            try file.read(into: buffer)

            slotBuffers[preset] = buffer
            slotFormats[preset] = format
            slotFileNames[preset] = url.lastPathComponent
            print("[CreakAudioEngine] Restored \(preset.rawValue): \(url.lastPathComponent)")
        } catch {
            print("[CreakAudioEngine] Failed to restore \(preset.rawValue): \(error)")
        }
    }

    // MARK: - Build engine

    private func buildEngine() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        clickPlayerNode = AVAudioPlayerNode()
        varispeed = AVAudioUnitVarispeed()

        if isOneShotMode {
            engine.attach(clickPlayerNode)
            engine.connect(clickPlayerNode, to: engine.mainMixerNode, format: monoFormat)
            clickPlayerNode.volume = masterVolume
        } else if currentPreset.isCustom, let cf = currentCustomFormat {
            engine.attach(playerNode)
            engine.attach(varispeed)
            engine.connect(playerNode, to: varispeed, format: cf)
            engine.connect(varispeed, to: engine.mainMixerNode, format: cf)
            playerNode.volume = 0
            varispeed.rate = 1.0
        } else {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: monoFormat)
            playerNode.volume = 0
        }
    }

    // MARK: - Preset Selection

    func selectPreset(_ preset: SoundPreset) {
        let wasRunning = isRunning
        if wasRunning { stop() }

        currentPreset = preset
        isOneShotMode = preset.isOneShot

        // Save selection
        UserDefaults.standard.set(preset.rawValue, forKey: savedPresetKey)

        if preset.isCustom {
            audioBuffer = slotBuffers[preset]
            currentCustomFormat = slotFormats[preset]
            loadedFileName = slotFileNames[preset] ?? ""
            isFileLoaded = audioBuffer != nil
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
            }
            currentCustomFormat = nil
        }

        if wasRunning && isFileLoaded { start() }
    }

    // MARK: - File Loading (into current custom slot)

    func loadFile(url: URL) {
        guard currentPreset.isCustom else { return }

        let wasRunning = isRunning
        if wasRunning { stop() }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return }
            try file.read(into: buffer)

            slotBuffers[currentPreset] = buffer
            slotFormats[currentPreset] = format
            slotFileNames[currentPreset] = url.lastPathComponent

            audioBuffer = buffer
            currentCustomFormat = format
            loadedFileName = url.lastPathComponent
            isFileLoaded = true
            isOneShotMode = false
            clickBuffer = nil

            // Save bookmark for this slot
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: currentPreset.bookmarkKey)
            }

            print("[CreakAudioEngine] Loaded \(currentPreset.rawValue): \(loadedFileName) (\(file.length) frames, \(format.sampleRate)Hz)")
        } catch {
            print("[CreakAudioEngine] Failed to load: \(error)")
            isFileLoaded = false
        }

        if wasRunning && isFileLoaded { start() }
    }

    /// Returns the saved filename for a custom slot (for UI display)
    func fileName(for preset: SoundPreset) -> String? {
        slotFileNames[preset]
    }

    // MARK: - Playback

    func start() {
        guard isFileLoaded else { return }
        guard !isRunning else { return }

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
        if targetVolume == 0 && currentVolume < 0.01 { currentVolume = 0 }
        playerNode.volume = currentVolume

        if currentPreset.isCustom {
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
}
