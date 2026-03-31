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
    var fadeSpeed: Double = 5.0         // Fade time in ms (lower = snappier)
    var minRate: Float = 0.80           // Playback rate when slow
    var maxRate: Float = 1.20           // Playback rate when fast
    var velocityThreshold: Double = 0.5 // Min velocity to trigger sound (deg/s)
    var velocityFullResponse: Double = 10.0 // Velocity for max volume (deg/s)

    // Current state from sensor (written by main thread via feed())
    private var lastVelocity: Double = 0
    private var lastAngle: Double = 0

    private var updateTimer: Timer?
    private let savedFileKey = "lidmeup_audio_file"

    init() {
        engine.attach(playerNode)
        engine.attach(varispeed)
        engine.connect(playerNode, to: varispeed, format: nil)
        engine.connect(varispeed, to: engine.mainMixerNode, format: nil)
        playerNode.volume = 0

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
            isRunning = true

            // Own update loop at 60Hz to continuously apply volume from latest velocity
            updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.updateVolume()
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
        lastVelocity = 0
        playerNode.volume = 0
    }

    // MARK: - Feed from sensor (called every sensor poll)

    func feed(angle: Double, velocity: Double) {
        lastAngle = angle
        lastVelocity = velocity
    }

    // MARK: - Volume update (runs at 60Hz independently)

    private func updateVolume() {
        // Compute target gain from current velocity
        let targetGain: Float
        if lastVelocity <= velocityThreshold {
            targetGain = 0
        } else if lastVelocity >= velocityFullResponse {
            targetGain = masterVolume
        } else {
            let t = Float((lastVelocity - velocityThreshold) / (velocityFullResponse - velocityThreshold))
            let smooth = t * t * (3 - 2 * t)
            targetGain = smooth * masterVolume
        }

        // Apply fade
        let alpha = Float(min(1.0, (1.0 / 60.0) / (fadeSpeed / 1000.0)))
        var newGain = playerNode.volume + (targetGain - playerNode.volume) * alpha

        // Snap to zero when fading out and nearly silent
        if targetGain == 0 && newGain < 0.01 {
            newGain = 0
        }

        playerNode.volume = newGain

        // Playback rate from velocity
        let rateFraction = Float(min(1.0, max(0.0, lastVelocity / velocityFullResponse)))
        varispeed.rate = minRate + (maxRate - minRate) * rateFraction
    }
}
