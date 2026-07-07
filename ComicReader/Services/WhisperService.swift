import Foundation
import AVFoundation

@MainActor
class WhisperService: ObservableObject {
    static let shared = WhisperService()

    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcribedText = ""
    @Published var error: String?
    /// Set when the last attempt captured no audio at all (engine stalled),
    /// as opposed to capturing audio that contained no speech.
    @Published var captureDiagnostic: String?

    // Continuous capture: one AVAudioEngine runs for the whole practice
    // session. iOS forbids STARTING a microphone capture while the app is
    // backgrounded (screen locked) — a fresh per-attempt AVAudioRecorder
    // there records pure silence, so speech detection never fires and only
    // the fallback timer ends attempts. An engine started in the foreground
    // keeps capturing across lock/unlock; each attempt just carves a segment
    // out of the running stream.
    private let engine = AVAudioEngine()
    private var engineRunning = false
    private var configObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var watchdogTimer: Timer?
    private var attemptStartBufferCount = 0
    private let capture = CaptureBox()
    private var recordingURL: URL?
    private var recordingFormatSampleRate: Double = 0
    private var restartTask: Task<Void, Never>?
    private var peakPower: Float = -160
    private var speechDetected = false
    private var silenceStart: Date?
    var onSilenceDetected: (() -> Void)?
    // dB below which input counts as "silence". Locked iPhones apply lower
    // mic gain than unlocked ones (readings drop several dB), so this must
    // leave headroom or speech goes undetected when the phone is locked.
    private let silenceThreshold: Float = -44
    private let silenceDuration: TimeInterval = 1.5  // seconds of silence after speech to auto-stop

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

        // Setup audio session for recording. Skip when already configured —
        // redundant setCategory calls reconfigure the running capture engine,
        // which can silence the mic while the phone is locked.
        do {
            let audioSession = AVAudioSession.sharedInstance()
            if audioSession.category != .playAndRecord {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
                try audioSession.setActive(true)
            }
        } catch {
            self.error = "Failed to setup audio session: \(error.localizedDescription)"
            return
        }

        // Engine start can be refused while the phone is locked (StartIO
        // error). Don't abort the attempt — the watchdog below retries every
        // second and capture kicks in as soon as iOS allows it.
        do {
            try startEngineIfNeeded()
        } catch {
            print("[Whisper] Engine start refused (will retry via watchdog): \(error)")
        }

        // Create temp WAV file for this segment, in the live input format (from
        // the session, not the node — the node's format goes stale across route
        // changes, which would make every captured buffer get dropped as a
        // mismatch and the recording come out empty).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).wav")
        guard let format = currentCaptureFormat() else {
            self.error = "Audio input not ready"
            return
        }

        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            recordingURL = url
            recordingFormatSampleRate = format.sampleRate
            peakPower = -160
            speechDetected = false
            silenceStart = nil
            captureDiagnostic = nil
            attemptStartBufferCount = capture.stats().count
            capture.setFile(file)
            isRecording = true
            startWatchdog()
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    /// While recording, verify the engine is actually delivering audio
    /// buffers; restart it if it stalls (locking the phone can stop the
    /// engine via an interruption without any notification we handle).
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                let stats = self.capture.stats()
                let stale = stats.last.map { Date().timeIntervalSince($0) > 1.2 } ?? true
                if stale || !self.engine.isRunning {
                    print("[Whisper] Capture stalled (engineRunning=\(self.engine.isRunning)), restarting")
                    if self.engineRunning {
                        self.restartEngine()
                    } else {
                        try? self.startEngineIfNeeded()
                    }
                }
            }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    /// Start the shared capture engine (idempotent). Must first be called in
    /// the foreground; once running it survives screen lock.
    /// Capture format derived from the audio session's current hardware (mono
    /// float at the live sample rate). Used instead of the input node's format,
    /// which goes stale across route changes while the engine is stopped.
    private func currentCaptureFormat() -> AVAudioFormat? {
        let session = AVAudioSession.sharedInstance()
        let rate = session.sampleRate
        guard rate > 0 else { return nil }
        let channels = AVAudioChannelCount(max(1, session.inputNumberOfChannels))
        return AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)
    }

    private func startEngineIfNeeded() throws {
        guard !engineRunning else { return }
        let input = engine.inputNode
        // The input node's reported format is stale while the engine is stopped —
        // it lags route changes (e.g. stuck at the old AirPods 24 kHz after they're
        // unplugged, even though the hardware is back to 48 kHz). Gating on it
        // deadlocks; building a tap from it crashes. The audio SESSION's sample
        // rate is the live hardware truth, so build the tap from that — the node
        // reconfigures to match when the engine starts, so the formats line up at
        // render time (no mismatch crash, no deadlock).
        guard let format = currentCaptureFormat() else {
            print("[Whisper] Session input not ready — deferring start")
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.capture.write(buffer)
            let db = Self.levelDb(of: buffer)
            Task { @MainActor in self.processLevel(db) }
        }
        engine.prepare()
        try engine.start()
        engineRunning = true
        print("[Whisper] Capture engine started (\(format.sampleRate) Hz)")

        // If the engine restarted onto a different route mid-attempt, the
        // recording file is in the old format and every new buffer would be
        // dropped as a mismatch (silent recording). Swap it to the new format
        // so the attempt keeps capturing.
        if isRecording, recordingFormatSampleRate > 0, format.sampleRate != recordingFormatSampleRate {
            recreateRecordingFile(format: format)
        }

        if configObserver == nil {
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    print("[Whisper] Audio configuration changed")
                    self?.scheduleEngineRestart()
                }
            }
        }
        if routeChangeObserver == nil {
            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.engineRunning else { return }
                    // A route change (AirPods in/out) changes the input format.
                    // Tear the tap down now and rebuild on the new route — this
                    // fires before the engine's own configuration-change in some
                    // cases, narrowing the window for a format-mismatch crash.
                    print("[Whisper] Audio route changed, rebuilding capture")
                    self.scheduleEngineRestart()
                }
            }
        }
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                Task { @MainActor in
                    guard let self else { return }
                    if typeValue == AVAudioSession.InterruptionType.ended.rawValue {
                        print("[Whisper] Audio interruption ended, restoring capture")
                        try? AVAudioSession.sharedInstance().setActive(true)
                        self.restartEngine()
                    } else {
                        print("[Whisper] Audio interruption began")
                    }
                }
            }
        }
    }

    /// Rebuild the tap and restart the engine (route change, interruption,
    /// or watchdog-detected stall).
    private func restartEngine() {
        guard engineRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engineRunning = false
        do {
            try startEngineIfNeeded()
        } catch {
            print("[Whisper] Engine restart failed: \(error)")
        }
    }

    /// Debounced engine restart. A single route change (e.g. AirPods connecting)
    /// fires a burst of configuration notifications and the new input format
    /// isn't valid immediately, so coalesce them and wait briefly for the route
    /// to settle before rebuilding the tap.
    private func scheduleEngineRestart() {
        // The input hardware format just changed (e.g. phone mic 48 kHz ->
        // AirPods 24 kHz). The installed tap is now stale, and the moment the
        // engine renders a buffer against it CoreAudio throws "Input HW format
        // and tap format not matching" and crashes. So detach the tap IMMEDIATELY
        // (cheap, non-blocking) — but do NOT call engine.stop() here: during a
        // live Bluetooth route switch stop() blocks the main thread until the
        // route finishes renegotiating, which can hang the app indefinitely.
        if engineRunning {
            engine.inputNode.removeTap(onBus: 0)
            engineRunning = false
        }
        // Rebuild once the new route has settled. The engine stops itself on a
        // configuration change, so by now stop() is usually a quick no-op rather
        // than a blocking call. The fresh format is briefly invalid mid-switch,
        // which the guard in startEngineIfNeeded handles (it defers and the next
        // record attempt retries).
        restartTask?.cancel()
        restartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            if self.engine.isRunning { self.engine.stop() }
            self.engineRunning = false   // keep flag in sync so startEngineIfNeeded rebuilds
            do {
                try self.startEngineIfNeeded()
            } catch {
                print("[Whisper] Engine restart after route change failed: \(error)")
            }
        }
    }

    /// Swap the in-flight recording to a file matching the current input format.
    /// Used when the route changes mid-attempt so the live buffers (now a
    /// different sample rate) still get written instead of dropped.
    private func recreateRecordingFile(format: AVAudioFormat) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).wav")
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            capture.setFile(file)
            recordingURL = url
            recordingFormatSampleRate = format.sampleRate
            print("[Whisper] Recording file switched to new format (\(format.sampleRate) Hz)")
        } catch {
            print("[Whisper] Failed to recreate recording file: \(error)")
        }
    }

    /// Start the capture engine ahead of time, while the app is certainly in
    /// the foreground (call when a practice session begins). iOS refuses to
    /// START capture while locked, but lets running capture continue.
    func warmUpCapture() {
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
                try session.setActive(true)
            }
            try startEngineIfNeeded()
        } catch {
            print("[Whisper] warmUpCapture failed: \(error)")
        }
    }

    /// Fully stop the capture engine. Call when leaving a practice screen.
    /// No-op while a recording is in flight — another view disappearing
    /// mid-practice must not kill the shared engine (friendly fire).
    func endCaptureSession() {
        guard !isRecording else { return }
        capture.setFile(nil)
        stopWatchdog()
        restartTask?.cancel()
        restartTask = nil
        recordingFormatSampleRate = 0
        if engineRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engineRunning = false
            print("[Whisper] Capture engine stopped")
        }
        isRecording = false
        onSilenceDetected = nil
    }

    /// RMS level of a buffer in dBFS
    private nonisolated static func levelDb(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return -160 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return -160 }
        var sum: Float = 0
        for i in 0..<n {
            let v = data[i]
            sum += v * v
        }
        let rms = sqrt(sum / Float(n))
        return rms > 0 ? 20 * log10(rms) : -160
    }

    /// Speech/silence state machine, fed from the capture tap (~10x/sec)
    private func processLevel(_ power: Float) {
        guard isRecording else { return }
        if power > peakPower {
            peakPower = power
        }
        if power > silenceThreshold {
            speechDetected = true
            silenceStart = nil
        } else if speechDetected {
            if silenceStart == nil {
                silenceStart = Date()
            } else if Date().timeIntervalSince(silenceStart!) >= silenceDuration {
                onSilenceDetected?()
                onSilenceDetected = nil  // fire only once
            }
        }
    }

    /// Stop recording and transcribe with Whisper
    func stopRecording(expectedText: String? = nil, language: String = "es") async -> String {
        guard isRecording else {
            return ""
        }

        capture.setFile(nil)  // stop writing; engine keeps running for the next attempt
        isRecording = false
        stopWatchdog()
        onSilenceDetected = nil
        isProcessing = true

        // Distinguish "engine delivered no audio at all" from "audio was silent"
        let buffersThisAttempt = capture.stats().count - attemptStartBufferCount
        if buffersThisAttempt == 0 {
            captureDiagnostic = "mic stalled — no audio captured"
            print("[Whisper] ZERO buffers captured this attempt — engine was dead")
            isProcessing = false
            return ""
        }
        print("[Whisper] Attempt captured \(buffersThisAttempt) buffers, peak \(peakPower) dB")

        // Skip transcription if no speech detected (peak power below threshold).
        // Generous on purpose: locked iPhones meter speech several dB lower
        // than unlocked ones; a too-high gate silently fails every attempt.
        if peakPower < -55 {
            print("[Whisper] No speech detected (peak power: \(peakPower) dB), skipping transcription")
            isProcessing = false
            return ""
        }
        print("[Whisper] Recording finished: peak \(peakPower) dB")

        defer {
            // Cleanup
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            recordingURL = nil

            // Don't reset audio session category here — the calling view
            // (RepeatPracticeView, SpeakingTestView) manages the session for
            // the entire practice flow. Flipping to .playback after each
            // recording causes Bluetooth HFP/A2DP profile switches that
            // create pauses and audio drops on car hands-free systems.
        }

        // Transcribe with Whisper
        guard let url = recordingURL else {
            isProcessing = false
            return ""
        }

        do {
            // Quiet recordings make gpt-4o-transcribe hallucinate a plausible but
            // wrong sentence; boost faint-but-real speech to a healthy level first.
            // Only boost when something actually crossed the speech threshold —
            // otherwise we'd amplify near-silent noise into a hallucination and
            // rob the "I didn't hear anything" path of its empty transcription.
            if peakPower > silenceThreshold {
                boostRecordingGain(at: url)
            }
            // Never pass the EXPECTED sentence as the prompt: it biases the model
            // into echoing the answer back for mumbled/low-confidence audio, so
            // wrong attempts "pass". But gpt-4o-transcribe often ignores the
            // `language` field on short clips and auto-detects the wrong language
            // (e.g. Spanish decoded as Esperanto), so we pass a GENERIC prompt in
            // the target language to anchor it — it contains no answer words, so it
            // can't cause an echo/false-pass.
            let transcription = try await transcribeWithWhisper(audioURL: url, prompt: languageAnchorPrompt(language), language: language)
            print("[Whisper] Transcribed: \"\(transcription)\" (expected: \"\(expectedText ?? "-")\", speechDetected: \(speechDetected))")
            // On silence/non-speech the model often just echoes our generic anchor
            // prompt back. That isn't real speech — treat it as empty so callers run
            // their "I didn't hear anything" path instead of scoring it wrong.
            if isAnchorEcho(transcription, language: language) {
                print("[Whisper] Anchor prompt echoed — treating as no speech")
                transcribedText = ""
                isProcessing = false
                return ""
            }
            transcribedText = transcription
            isProcessing = false
            return transcription
        } catch {
            self.error = "Transcription failed: \(error.localizedDescription)"
            isProcessing = false
            return ""
        }
    }

    /// Cancel recording without transcribing (capture engine keeps running)
    func cancelRecording() {
        capture.setFile(nil)
        isRecording = false
        stopWatchdog()
        onSilenceDetected = nil

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    /// Peak-normalize a quiet recording before transcription. Faint audio (e.g.
    /// the phone held a little far, or metered low while locked) makes the model
    /// invent text; boosting toward ~-3 dBFS — capped so we never crank near-
    /// silence into noise — keeps real speech intelligible. Any failure is
    /// swallowed and the original file is left untouched.
    private func boostRecordingGain(at url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData else { return }

        let channelCount = Int(format.channelCount)
        let n = Int(buffer.frameLength)
        var peak: Float = 0
        for c in 0..<channelCount {
            let s = channels[c]
            for i in 0..<n { let a = abs(s[i]); if a > peak { peak = a } }
        }
        guard peak > 0.0005 else { return }            // basically silence — leave it
        let gain = min(0.7 / peak, 16.0)               // target ~-3 dBFS, cap ~+24 dB
        guard gain > 1.2 else { return }               // already loud enough
        for c in 0..<channelCount {
            let s = channels[c]
            for i in 0..<n { s[i] *= gain }
        }

        // Write boosted audio to a temp file, then atomically replace the original
        // so a failure can never leave us without a recording.
        let tmp = url.deletingLastPathComponent().appendingPathComponent("boost_\(UUID().uuidString).wav")
        do {
            let out = try AVAudioFile(forWriting: tmp, settings: file.fileFormat.settings)
            try out.write(from: buffer)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    /// A generic prompt in the target language, used only to pin the transcription
    /// to that language (gpt-4o-transcribe otherwise auto-detects and can drift to
    /// a similar-sounding language). Deliberately contains no comic/answer words.
    private func languageAnchorPrompt(_ language: String) -> String? {
        switch language {
        case "es": return "Lo que sigue es una frase corta en español."
        case "en": return "The following is a short phrase in English."
        default: return nil
        }
    }

    /// True when the transcription is just the anchor prompt echoed back (which the
    /// model does on silence/non-speech) — so we can treat it as "nothing heard".
    private func isAnchorEcho(_ text: String, language: String) -> Bool {
        guard let anchor = languageAnchorPrompt(language) else { return false }
        let t = wordsOnly(text), a = wordsOnly(anchor)
        guard !a.isEmpty, !t.isEmpty else { return false }
        // Full echo: the model handed our whole anchor prompt back.
        if t == a || t.contains(a) { return true }
        // Partial echo: a long run of the anchor. Require several anchor words so a
        // legitimate SHORT answer that merely happens to be an anchor word (e.g.
        // "the", "is", "a" — all in the English anchor) isn't discarded as an echo.
        // Real answers in the meaning/word drills are only 1–3 words.
        if a.contains(t) {
            return t.split(separator: " ").count >= 4
        }
        return false
    }

    /// Lowercased, letters-only, single-spaced — for loose text comparison.
    private func wordsOnly(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Send audio to Whisper API for transcription
    private func transcribeWithWhisper(audioURL: URL, prompt: String? = nil, language: String = "es") async throws -> String {
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

        // Add model field. gpt-4o-transcribe is more accurate and noise-robust
        // than whisper-1; same endpoint, same default JSON response ({ "text" }).
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("gpt-4o-transcribe\r\n".data(using: .utf8)!)

        // Add language field. An empty language means auto-detect (used by Flow
        // Practice, where the learner may speak the target language OR English
        // to ask for help).
        if !language.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }

        // Add prompt hint to reduce hallucination on short audio
        if let prompt = prompt, !prompt.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(prompt)\r\n".data(using: .utf8)!)
        }

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
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

    /// Compare spoken text with expected text. `passThreshold` is the
    /// fraction of expected words that must match (default 0.85).
    func compareText(spoken: String, expected: String, passThreshold: Double = 0.85) -> (isCorrect: Bool, score: Double) {
        let spokenClean = normalizeText(spoken)
        let expectedClean = normalizeText(expected)

        let spokenWords = spokenClean.split(separator: " ").map { String($0) }
        let expectedWords = expectedClean.split(separator: " ").map { String($0) }

        // Identify proper nouns from the original text (capitalized, not first word)
        let originalWords = expected
            .replacingOccurrences(of: "¿", with: "").replacingOccurrences(of: "¡", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").map { String($0) }
        let properNounIndices: Set<Int> = Set(originalWords.indices.filter { idx in
            guard idx > 0, let first = originalWords[idx].first else { return false }
            return first.isUppercase
        })

        guard !expectedWords.isEmpty else { return (true, 1.0) }

        // A lone word gives Whisper no context, so it mis-spells or mis-scripts
        // it far more often than words in a sentence. Be much more forgiving when
        // the target is a single word.
        let singleWord = expectedWords.count == 1

        var matchedCount = 0
        var usedSpokenIndices = Set<Int>()

        for (wordIdx, expectedWord) in expectedWords.enumerated() {
            // Try exact match first
            if let idx = spokenWords.indices.first(where: { !usedSpokenIndices.contains($0) && spokenWords[$0] == expectedWord }) {
                matchedCount += 1
                usedSpokenIndices.insert(idx)
            } else {
                let isProperNoun = properNounIndices.contains(wordIdx)
                // Fuzzy match: lenient for names, moderate for regular words
                for (idx, spokenWord) in spokenWords.enumerated() where !usedSpokenIndices.contains(idx) {
                    let distance = levenshteinDistance(expectedWord, spokenWord)
                    let maxLen = max(expectedWord.count, spokenWord.count)
                    let matches: Bool
                    if isProperNoun {
                        // Names: allow up to 50% difference (handles "Zik"/"Zeke", "Mía"/"Mia")
                        matches = maxLen > 0 && Double(distance) / Double(maxLen) <= 0.5
                    } else if singleWord {
                        // Single-word target: allow ~40% difference (handles
                        // mis-spellings and transliterated hallucinations).
                        matches = maxLen > 0 && Double(distance) / Double(maxLen) <= 0.4
                    } else if maxLen <= 3 {
                        // Short words (1-3 chars): allow 1 edit of any kind
                        matches = distance <= 1
                    } else {
                        // Regular words: allow 1 edit of any kind, or 2 edits for longer words (8+)
                        matches = distance <= 1 || (maxLen >= 8 && distance <= 2)
                    }
                    if matches {
                        matchedCount += 1
                        usedSpokenIndices.insert(idx)
                        break
                    }
                }
            }
        }

        let score = Double(matchedCount) / Double(expectedWords.count)

        // Allow small word count differences (Whisper may add/drop small words)
        let wordCountDiff = abs(spokenWords.count - expectedWords.count)
        if wordCountDiff > 2 {
            return (false, score * 0.5)
        }

        return (score >= passThreshold, score)
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
        // Transliterate any non-Latin script to Latin first: Whisper sometimes
        // renders a lone Spanish word in another alphabet (e.g. "Nadie" as
        // Cyrillic "Надія"), and this makes the two comparable.
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        return latin.folding(options: .diacriticInsensitive, locale: .current)
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

// MARK: - Capture file box
/// Thread-safe holder for the segment file being written by the audio tap
/// (the tap runs on a realtime audio thread, not the main actor).
final class CaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var bufferCount: Int = 0
    private var lastBufferAt: Date?

    func setFile(_ newFile: AVAudioFile?) {
        lock.lock()
        file = newFile
        lock.unlock()
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        bufferCount += 1
        lastBufferAt = Date()
        guard let file else { return }
        // CRITICAL: AVAudioFile.write(from:) raises an uncatchable Objective-C
        // exception (NOT a Swift error) when the buffer's format doesn't match
        // the file's. This happens during an audio route change (e.g. AirPods
        // connecting) when buffers arrive in the new hardware format before the
        // file has been swapped — the do/catch below does NOT save us, so we
        // must reject mismatched buffers up front to avoid crashing the app.
        let bf = buffer.format, ff = file.processingFormat
        guard bf.sampleRate == ff.sampleRate, bf.channelCount == ff.channelCount else {
            return
        }
        do {
            try file.write(from: buffer)
        } catch {
            // Genuine write error — drop the buffer.
        }
    }

    /// (total buffers seen, time of the most recent one)
    func stats() -> (count: Int, last: Date?) {
        lock.lock()
        defer { lock.unlock() }
        return (bufferCount, lastBufferAt)
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
