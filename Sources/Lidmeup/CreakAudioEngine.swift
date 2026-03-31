import AVFoundation
import Foundation

/// Plays a user-provided audio file, looped and modulated by lid velocity/angle.
/// Volume fades in when the lid moves and fades out when it stops.
final class CreakAudioEngine {
    private let engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var varispeed = AVAudioUnitVarispeed()
    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?
    private(set) var isRunning = false
    private(set) var isFileLoaded = false
    private(set) var loadedFileName: String = ""

    // User-adjustable parameters
    var masterVolume: Float = 0.8       // 0.0 - 1.0
    var fadeSpeed: Double = 20.0        // Fade time in ms (balance between responsive and smooth)
    var minRate: Float = 0.80           // Playback rate when slow
    var maxRate: Float = 1.20           // Playback rate when fast
    var velocityThreshold: Double = 0.3 // Min velocity to trigger sound (deg/s)
    var velocityFullResponse: Double = 10.0 // Velocity for max volume (deg/s)

    // Current state from sensor
    private var latestVelocity: Double = 0
    private var latestAngle: Double = 0
    private var currentVolume: Float = 0
    private var currentRate: Float = 1.0

    private var updateTimer: Timer?
    private let savedFileKey = "lidmeup_audio_file"

    init() {
        engine.attach(playerNode)
        engine.attach(varispeed)
        engine.connect(playerNode, to: varispeed, format: nil)
        engine.connect(varispeed, to: engine.mainMixerNode, format: nil)
        playerNode.volume = 0
        varispeed.rate = 1.0

        // Restore last used file
        if let bookmark = UserDefaults.standard.data(forKey: savedFileKey) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
               url.startAccessingSecurityScopedResource() {
                loadFile(url: url, saveBookmark: false)
            }
        }
    }

    // MARK: - File Loading

    func loadFile(url: URL, saveBookmark: Bool = true) {
        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file

            guard let format = AVAudioFormat(
                commonFormat: file.processingFormat.commonFormat,
                sampleRate: file.processingFormat.sampleRate,
                channels: file.processingFormat.channelCount,
                interleaved: file.processingFormat.isInterleaved
            ) else { return }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return }
            try file.read(into: buffer)
            audioBuffer = buffer

            loadedFileName = url.lastPathComponent
            isFileLoaded = true

            if saveBookmark {
                if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(bookmark, forKey: savedFileKey)
                }
            }

            print("[CreakAudioEngine] Loaded: \(loadedFileName) (\(file.length) frames, \(format.sampleRate)Hz)")
        } catch {
            print("[CreakAudioEngine] Failed to load file: \(error)")
            isFileLoaded = false
        }
    }

    // MARK: - Playback

    func start() {
        guard isFileLoaded, let buffer = audioBuffer else {
            print("[CreakAudioEngine] No audio file loaded")
            return
        }
        guard !isRunning else { return }

        do {
            try engine.start()
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            playerNode.play()
            playerNode.volume = 0
            currentVolume = 0
            currentRate = 1.0
            varispeed.rate = 1.0
            isRunning = true

            // 60Hz update loop for smooth volume/rate changes
            updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.updateAudio()
            }
            RunLoop.current.add(updateTimer!, forMode: .common)

            print("[CreakAudioEngine] Started playback")
        } catch {
            print("[CreakAudioEngine] Failed to start: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        updateTimer?.invalidate()
        updateTimer = nil
        playerNode.stop()
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

    // MARK: - Smooth audio update (60Hz)

    private func updateAudio() {
        // Target volume from velocity
        let targetVolume: Float
        if latestVelocity <= velocityThreshold {
            targetVolume = 0
        } else if latestVelocity >= velocityFullResponse {
            targetVolume = masterVolume
        } else {
            let t = Float((latestVelocity - velocityThreshold) / (velocityFullResponse - velocityThreshold))
            targetVolume = t * masterVolume
        }

        // Smooth volume ramp (avoids clicks/jitter)
        let dt: Float = 1.0 / 60.0
        let tau = Float(fadeSpeed / 1000.0)
        let alpha = min(1.0, dt / max(tau, 0.001))

        currentVolume += (targetVolume - currentVolume) * alpha

        // Snap to zero when nearly silent and fading out
        if targetVolume == 0 && currentVolume < 0.01 {
            currentVolume = 0
        }

        playerNode.volume = currentVolume

        // Smooth rate changes (avoids pitch distortion from jerky updates)
        let targetRate: Float
        if latestVelocity <= velocityThreshold {
            targetRate = minRate
        } else {
            let rateFraction = Float(min(1.0, latestVelocity / velocityFullResponse))
            targetRate = minRate + (maxRate - minRate) * rateFraction
        }
        let rateAlpha = min(1.0, dt / 0.1) // 100ms time constant for smooth pitch
        currentRate += (targetRate - currentRate) * rateAlpha
        varispeed.rate = currentRate
    }
}
