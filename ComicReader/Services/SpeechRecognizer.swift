import Foundation
import Speech
import AVFoundation

@MainActor
class SpeechRecognizer: ObservableObject {
    static let shared = SpeechRecognizer()

    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcribedText = ""
    @Published var error: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))

    func requestPermissions() async -> Bool {
        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            error = "Speech recognition not authorized"
            return false
        }

        // Request microphone permission
        let micStatus = await AVAudioApplication.requestRecordPermission()
        guard micStatus else {
            error = "Microphone access not authorized"
            return false
        }

        return true
    }

    func startRecording(expectedText: String? = nil) async {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer not available"
            return
        }

        // Request permissions if needed
        guard await requestPermissions() else { return }

        // Reset state
        transcribedText = ""
        error = nil

        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Create audio engine and recognition request
            audioEngine = AVAudioEngine()
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

            guard let audioEngine = audioEngine,
                  let recognitionRequest = recognitionRequest else {
                error = "Failed to create audio components"
                return
            }

            recognitionRequest.shouldReportPartialResults = true

            // Add contextual hints to help recognition accuracy
            if let expected = expectedText {
                // Provide the expected phrase and its individual words as hints
                let words = expected.components(separatedBy: " ")
                recognitionRequest.contextualStrings = [expected] + words
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true

            // Start recognition task
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                Task { @MainActor in
                    if let result = result {
                        self?.transcribedText = result.bestTranscription.formattedString
                    }

                    if let error = error {
                        print("Speech recognition error: \(error.localizedDescription)")
                        // Check for simulator error (kAFAssistantErrorDomain error 216)
                        let nsError = error as NSError
                        if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                            self?.error = "Speech recognition is not available on the Simulator. Please test on a real device."
                        }
                        // Only show "no speech detected" if we actually got nothing
                        // Don't show error if we already have transcribed text
                    }
                }
            }

        } catch {
            self.error = "Recording failed: \(error.localizedDescription)"
            isRecording = false
        }
    }

    func stopRecording() -> String {
        // Stop audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        // End recognition request
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        // Reset
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        // Reset audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to reset audio session: \(error)")
        }

        return transcribedText
    }

    /// Compare spoken text with expected text
    /// Returns a score from 0 to 1
    func compareText(spoken: String, expected: String) -> (isCorrect: Bool, score: Double) {
        let spokenClean = normalizeText(spoken)
        let expectedClean = normalizeText(expected)

        // Calculate how many expected words were spoken
        let score = calculateCoverage(spoken: spokenClean, expected: expectedClean)

        // Consider correct if >= 50% of expected words were spoken (lenient)
        return (score >= 0.5, score)
    }

    private func normalizeText(_ text: String) -> String {
        // Remove accents by decomposing and removing diacritics
        let withoutAccents = text.folding(options: .diacriticInsensitive, locale: .current)

        return withoutAccents.lowercased()
            .replacingOccurrences(of: "¿", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "¡", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Calculate what percentage of expected words appear in spoken text
    /// Uses fuzzy matching for similar-sounding words
    private func calculateCoverage(spoken: String, expected: String) -> Double {
        let spokenWords = spoken.split(separator: " ").map { String($0) }
        let expectedWords = expected.split(separator: " ").map { String($0) }

        guard !expectedWords.isEmpty else { return spokenWords.isEmpty ? 1.0 : 0.0 }

        // Also check if words run together (e.g., "fue eso" -> "fueeso" matches "esfuerzo")
        let spokenJoined = spokenWords.joined()
        let expectedJoined = expectedWords.joined()

        // If the joined versions are similar, it's probably correct
        if stringSimilarity(spokenJoined, expectedJoined) > 0.6 {
            return 1.0
        }

        // Count how many expected words were spoken (with fuzzy matching)
        var matchedScore = 0.0
        for expectedWord in expectedWords {
            var bestMatch = 0.0
            for spokenWord in spokenWords {
                let similarity = stringSimilarity(spokenWord, expectedWord)
                bestMatch = max(bestMatch, similarity)
            }
            // Give full credit for exact match, partial for similar
            if bestMatch > 0.7 {
                matchedScore += 1.0
            } else if bestMatch > 0.5 {
                matchedScore += 0.5
            }
        }

        return matchedScore / Double(expectedWords.count)
    }

    /// Calculate similarity between two strings (0 to 1)
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        // Check if one contains the other
        if s1.contains(s2) || s2.contains(s1) {
            return 0.8
        }

        // Use Levenshtein-like comparison
        let longer = s1.count > s2.count ? s1 : s2
        let shorter = s1.count > s2.count ? s2 : s1
        let longerLength = longer.count

        let distance = levenshteinDistance(Array(longer), Array(shorter))
        return Double(longerLength - distance) / Double(longerLength)
    }

    /// Calculate Levenshtein distance between two character arrays
    private func levenshteinDistance(_ s1: [Character], _ s2: [Character]) -> Int {
        if s1.isEmpty { return s2.count }
        if s2.isEmpty { return s1.count }

        var prev = Array(0...s2.count)
        var curr = [Int](repeating: 0, count: s2.count + 1)

        for i in 1...s1.count {
            curr[0] = i
            for j in 1...s2.count {
                let cost = s1[i-1] == s2[j-1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,      // deletion
                    curr[j-1] + 1,    // insertion
                    prev[j-1] + cost  // substitution
                )
            }
            prev = curr
        }

        return prev[s2.count]
    }
}
