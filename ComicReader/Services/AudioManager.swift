import Foundation
import AVFoundation
import UIKit

@MainActor
class AudioManager: ObservableObject {
    static let shared = AudioManager()

    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var isSentencePlayback = false  // True when playing full sentence (enables word highlighting)

    private var player: AVAudioPlayer?
    private var timer: Timer?

    // AVAudioEngine for boosted playback
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    /// Play audio from bundle by filename (without extension)
    /// - Parameters:
    ///   - filename: Audio filename without extension
    ///   - volume: Volume level (1.0 = normal, 2.0 = double volume for dictionary words)
    ///   - enableHighlighting: Set to true for sentence playback to enable word highlighting
    func play(_ filename: String, volume: Float = 1.0, enableHighlighting: Bool = false) {
        stop()
        isSentencePlayback = enableHighlighting

        // Try to find the file in multiple locations
        var url: URL?

        // 1. Try BundledComics folder first (sentence audio - comic specific)
        if let bundledComicsURL = Bundle.main.url(forResource: "BundledComics", withExtension: nil) {
            url = findAudioFile(named: filename, in: bundledComicsURL)
        }

        // 2. Try Documents/Comics folder (downloaded comics)
        if url == nil {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let comicsDir = documents.appendingPathComponent("Comics")
            url = findAudioFile(named: filename, in: comicsDir)
        }

        // 3. Try Dictionary folder (word pronunciations - shared across comics)
        if url == nil, let dictionaryURL = Bundle.main.url(forResource: "Dictionary", withExtension: nil) {
            url = findAudioFile(named: filename, in: dictionaryURL)
        }

        // 4. Fall back to root bundle (old architecture / direct bundle resources)
        if url == nil {
            url = Bundle.main.url(forResource: filename, withExtension: "mp3")
        }

        guard let audioUrl = url else {
            print("❌ Audio file not found: \(filename).mp3")
            print("   Searched in BundledComics, Dictionary, and root bundle")
            return
        }

        print("✅ Playing audio: \(audioUrl.lastPathComponent) at volume \(volume)")

        // Ensure audio session is active
        setupAudioSession()

        // Use standard playback (AVAudioEngine has issues on devices)
        playWithPlayer(url: audioUrl, volume: min(volume, 1.0))
    }

    /// Standard playback with AVAudioPlayer (volume capped at 1.0)
    private func playWithPlayer(url: URL, volume: Float) {
        do {
            isLoading = true
            player = try AVAudioPlayer(contentsOf: url)
            player?.enableRate = true
            player?.rate = playbackRate
            player?.volume = min(volume, 1.0)
            player?.prepareToPlay()

            let success = player?.play() ?? false
            print("🔊 AVAudioPlayer.play() returned: \(success), duration: \(player?.duration ?? 0), volume: \(player?.volume ?? 0)")

            isPlaying = true
            isLoading = false
            duration = player?.duration ?? 0

            // Start timer to track progress
            startTimer()

            // Haptic feedback
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        } catch {
            print("❌ Failed to play audio: \(error)")
            isLoading = false
        }
    }

    /// Boosted playback with AVAudioEngine (allows volume > 1.0)
    private func playWithEngine(url: URL, volume: Float) {
        do {
            isLoading = true

            // Stop any existing engine
            audioEngine?.stop()
            playerNode?.stop()

            audioEngine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()

            guard let engine = audioEngine, let node = playerNode else { return }

            engine.attach(node)

            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat

            // Connect with volume boost
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = volume

            try engine.start()

            node.scheduleFile(audioFile, at: nil) { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.audioEngine?.stop()
                }
            }

            node.play()

            isPlaying = true
            isLoading = false
            duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

            // Haptic feedback
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        } catch {
            print("Failed to play boosted audio: \(error)")
            isLoading = false
        }
    }

    func stop() {
        player?.stop()
        player = nil

        // Stop audio engine if running
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil

        isPlaying = false
        isSentencePlayback = false
        currentTime = 0
        stopTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func resume() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    /// Get the current word index based on timing data
    func currentWordIndex(for words: [Word]) -> Int? {
        let currentMs = Int(currentTime * 1000)

        for (index, word) in words.enumerated() {
            guard let startMs = word.startTimeMs else { continue }
            let endMs = word.endTimeMs ?? (words.indices.contains(index + 1) ? words[index + 1].startTimeMs : nil) ?? Int.max

            if currentMs >= startMs && currentMs < endMs {
                return index
            }
        }

        // If past all words, return last word
        if let lastWord = words.last, let lastStart = lastWord.startTimeMs, currentMs >= lastStart {
            return words.count - 1
        }

        return nil
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.player else { return }
                self.currentTime = player.currentTime

                // Check if playback finished
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.currentTime = 0
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Recursively search for an audio file in a directory
    private func findAudioFile(named filename: String, in directory: URL) -> URL? {
        let fm = FileManager.default

        // If filename contains path components (e.g. "words/el"), try direct path first
        let directPath = directory.appendingPathComponent("\(filename).mp3")
        if fm.fileExists(atPath: directPath.path) {
            return directPath
        }

        // Fall back to recursive search by last path component
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }

        // Use just the final component for matching (e.g. "words/el" -> "el.mp3")
        let baseName = (filename as NSString).lastPathComponent
        let targetFilename = "\(baseName).mp3"

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == targetFilename {
                return fileURL
            }
        }

        return nil
    }
}
