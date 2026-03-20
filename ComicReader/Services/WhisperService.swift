import Foundation
import AVFoundation

@MainActor
class WhisperService: ObservableObject {
    static let shared = WhisperService()

    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcribedText = ""
    @Published var error: String?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    private let apiURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    /// Start recording audio
    func startRecording() async {
        // Request microphone permission
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            error = "Microphone permission denied"
            return
        }

        // Reset state
        transcribedText = ""
        error = nil

        // Setup audio session for recording
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            self.error = "Failed to setup audio session: \(error.localizedDescription)"
            return
        }

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("recording_\(UUID().uuidString).m4a")

        guard let url = recordingURL else {
            error = "Failed to create recording file"
            return
        }

        // Audio settings for Whisper (m4a works well)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    /// Stop recording and transcribe with Whisper
    func stopRecording() async -> String {
        guard let recorder = audioRecorder, recorder.isRecording else {
            return ""
        }

        recorder.stop()
        isRecording = false
        isProcessing = true

        defer {
            // Cleanup
            audioRecorder = nil
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            recordingURL = nil

            // Reset audio session for playback
            Task {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.playback, mode: .default)
                    try audioSession.setActive(true)
                } catch {
                    print("Failed to reset audio session: \(error)")
                }
            }
        }

        // Transcribe with Whisper
        guard let url = recordingURL else {
            isProcessing = false
            return ""
        }

        do {
            let transcription = try await transcribeWithWhisper(audioURL: url)
            transcribedText = transcription
            isProcessing = false
            return transcription
        } catch {
            self.error = "Transcription failed: \(error.localizedDescription)"
            isProcessing = false
            return ""
        }
    }

    /// Cancel recording without transcribing
    func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    /// Send audio to Whisper API for transcription
    private func transcribeWithWhisper(audioURL: URL) async throws -> String {
        let apiKey = Secrets.openAIAPIKey

        guard apiKey != "YOUR_OPENAI_API_KEY_HERE" else {
            throw WhisperError.missingAPIKey
        }

        // Read audio file
        let audioData = try Data(contentsOf: audioURL)

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Add language field (Spanish)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("es\r\n".data(using: .utf8)!)

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response
        let json = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return json.text
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Compare spoken text with expected text
    func compareText(spoken: String, expected: String) -> (isCorrect: Bool, score: Double) {
        let spokenClean = normalizeText(spoken)
        let expectedClean = normalizeText(expected)

        let spokenWords = spokenClean.split(separator: " ").map { String($0) }
        let expectedWords = expectedClean.split(separator: " ").map { String($0) }

        guard !expectedWords.isEmpty else { return (true, 1.0) }

        var matchedCount = 0
        var usedSpokenIndices = Set<Int>()

        for expectedWord in expectedWords {
            // Try exact match first
            if let idx = spokenWords.indices.first(where: { !usedSpokenIndices.contains($0) && spokenWords[$0] == expectedWord }) {
                matchedCount += 1
                usedSpokenIndices.insert(idx)
            } else {
                // Fuzzy match: accept if edit distance is small relative to word length
                // This handles Whisper transcribing names/sounds differently (e.g. "zik" vs "zeke")
                for (idx, spokenWord) in spokenWords.enumerated() where !usedSpokenIndices.contains(idx) {
                    let maxLen = max(expectedWord.count, spokenWord.count)
                    let distance = levenshteinDistance(expectedWord, spokenWord)
                    // Allow up to ~50% character difference (handles name variations like "zik"/"zeke")
                    if maxLen > 0 && Double(distance) / Double(maxLen) <= 0.5 {
                        matchedCount += 1
                        usedSpokenIndices.insert(idx)
                        break
                    }
                }
            }
        }

        let score = Double(matchedCount) / Double(expectedWords.count)

        // Pass if 70% of words match
        return (score >= 0.7, score)
    }

    /// Levenshtein edit distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = curr
        }
        return prev[n]
    }

    private func normalizeText(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "¿", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "¡", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Models
struct WhisperResponse: Codable {
    let text: String
}

enum WhisperError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key not configured. Please add your key to Secrets.swift"
        case .invalidResponse:
            return "Invalid response from Whisper API"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        }
    }
}
