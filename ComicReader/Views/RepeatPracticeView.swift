import SwiftUI
import AVFoundation
import MediaPlayer

// MARK: - Practice Sentence Model
struct PracticeSentence: Identifiable {
    let id: String
    let text: String
    let translation: String
    let audioUrl: String
    let translationAudioUrl: String?
    let alternativeTexts: [String]
    let pageNumber: Int
    let panelOrder: Int
}

// MARK: - Practice State
enum PracticeState: Equatable {
    case idle
    case playingSpanish
    case waitingForRepeat
    case recordingRepeat
    case processingRepeat
    case feedbackRepeat(correct: Bool)    // playing feedback clip
    case replayingCorrect                 // replaying Spanish after incorrect pronunciation
    case askingMeaning                    // playing "What does it mean?" clip
    case waitingForMeaning
    case recordingMeaning
    case processingMeaning
    case feedbackMeaning(correct: Bool)   // playing feedback clip
    case playingEnglish                   // playing English translation audio (incorrect meaning)
    case replayingBeforeAdvance           // playing Spanish before advancing (correct meaning)
    case replayingBeforeRetry             // playing Spanish before retrying meaning
    case repromptNoAudioRepeat            // "I didn't hear anything" → then replay Spanish
    case repromptNoAudioMeaning           // "I didn't hear anything" → then re-ask the meaning
    case advancing
    indirect case paused(previous: PracticeState)
    case completed

    static func == (lhs: PracticeState, rhs: PracticeState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.playingSpanish, .playingSpanish),
             (.waitingForRepeat, .waitingForRepeat),
             (.recordingRepeat, .recordingRepeat),
             (.processingRepeat, .processingRepeat),
             (.replayingCorrect, .replayingCorrect),
             (.askingMeaning, .askingMeaning),
             (.waitingForMeaning, .waitingForMeaning),
             (.recordingMeaning, .recordingMeaning),
             (.processingMeaning, .processingMeaning),
             (.playingEnglish, .playingEnglish),
             (.replayingBeforeAdvance, .replayingBeforeAdvance),
             (.replayingBeforeRetry, .replayingBeforeRetry),
             (.repromptNoAudioRepeat, .repromptNoAudioRepeat),
             (.repromptNoAudioMeaning, .repromptNoAudioMeaning),
             (.advancing, .advancing),
             (.completed, .completed):
            return true
        case (.feedbackRepeat(let a), .feedbackRepeat(let b)):
            return a == b
        case (.feedbackMeaning(let a), .feedbackMeaning(let b)):
            return a == b
        case (.paused(let a), .paused(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - TTS Delegate (fallback for English when no pre-recorded audio)
class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?()
        }
    }
}

// MARK: - RepeatPracticeView
struct RepeatPracticeView: View {
    let comic: Comic
    @EnvironmentObject private var progressManager: ReadingProgressManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var audioManager = AudioManager.shared
    @ObservedObject private var whisperService = WhisperService.shared
    @StateObject private var help = HelpModeController()

    @State private var sentences: [PracticeSentence] = []
    @State private var currentIndex = 0
    @State private var state: PracticeState = .idle
    @State private var autoStopTimer: Timer?

    // Silent timer — plays near-silent audio for exact duration, fires delegate on completion
    // This keeps the audio session active in the background so iOS doesn't suspend the app
    @State private var silentPlayer: AVAudioPlayer?
    @State private var silentTimerDelegate = SilentTimerDelegate()
    // Loops near-silent audio for the whole session so iOS never suspends the
    // app while the screen is dark — without it the silent gaps (especially
    // waiting for Whisper transcription, when neither mic nor audio is live)
    // freeze the practice loop.
    @State private var keepAlivePlayer: AVAudioPlayer?

    // TTS fallback for English
    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var ttsDelegate = TTSDelegate()
    @State private var usingTTSFallback = false

    // Scores (first attempt only)
    @State private var pronunciationCorrect = 0
    @State private var meaningCorrect = 0
    @State private var totalAttempted = 0
    @State private var isFirstRepeatAttempt = true
    @State private var isFirstMeaningAttempt = true

    // UI state
    @State private var showSpanishText = false
    @State private var showTranslation = false
    @State private var pulseAnimation = false

    // Pre-recorded feedback audio filenames (without extension)
    private let correctClip = "correct"
    private let notQuiteClip = "not_quite_listen_again"
    private let whatDoesItMeanClip = "what_does_it_mean"
    private let noAudioClip = "no_audio"   // "I didn't hear anything. Please try again."

    var body: some View {
        Group {
            if state == .idle {
                startView
            } else if state == .completed {
                completedView
            } else {
                practiceView
            }
        }
        .navigationTitle("Repeat Practice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
                } label: {
                    Image(systemName: help.isActive ? "questionmark.circle.fill" : "questionmark.circle")
                }
            }
        }
        .helpTooltipLayer()
        .environmentObject(help)
        .onAppear {
            buildSentences()
            synthesizer.delegate = ttsDelegate
            setupRemoteCommands()
            setupNowPlaying()
            // Direct callback for background playback — bypasses SwiftUI .onChange which doesn't fire in background
            audioManager.onPlaybackFinished = { [self] in
                if !usingTTSFallback {
                    handleAudioFinished()
                }
            }
        }
        .onDisappear {
            // Remember the spot if they left mid-session (not finished / not on start).
            if state != .completed && state != .idle && !sentences.isEmpty {
                savePracticeSpot()
            }
            cleanup()
            teardownRemoteCommands()
            audioManager.onPlaybackFinished = nil
        }
    }

    // MARK: - Start View
    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mouth.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text(comic.title)
                .font(.title2)
                .fontWeight(.bold)

            Text("\(sentences.count) sentences")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Listen to each sentence, repeat it back, then say what it means in English.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                startPractice()
            } label: {
                Label(isResumingPractice ? "Continue" : "Start", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .explains("Start", "Begin the practice. You'll hear each sentence, repeat it aloud, then say what it means.")
        }
    }

    // MARK: - Practice View
    private var practiceView: some View {
        VStack(spacing: 0) {
            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: Double(currentIndex), total: Double(max(sentences.count, 1)))
                    .tint(.green)

                Text("Sentence \(currentIndex + 1) of \(sentences.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // State indicator
            stateIndicator
                .frame(height: 120)

            // Text display
            VStack(spacing: 12) {
                if showSpanishText, currentIndex < sentences.count {
                    Text(sentences[currentIndex].text)
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }

                if showTranslation, currentIndex < sentences.count {
                    Text(sentences[currentIndex].translation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 80)
            .animation(.easeInOut(duration: 0.3), value: showSpanishText)
            .animation(.easeInOut(duration: 0.3), value: showTranslation)

            Spacer()

            // Bottom controls
            HStack(spacing: 40) {
                Button {
                    skipToPrevious()
                } label: {
                    Image(systemName: "backward.end.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(currentIndex > 0 ? .secondary : Color.secondary.opacity(0.3))
                }
                .disabled(currentIndex == 0)
                .explains("Back", "Go back to the previous sentence.")

                Button {
                    togglePause()
                } label: {
                    let isPaused = isPausedState
                    Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(isPaused ? .green : .secondary)
                }
                .explains("Pause / Play", "Pause the practice, or resume from where you left off.")

                Button {
                    skipToNext()
                } label: {
                    Image(systemName: "forward.end.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
                .explains("Skip", "Jump ahead to the next sentence.")
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - State Indicator
    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .playingSpanish, .replayingCorrect, .replayingBeforeAdvance, .replayingBeforeRetry:
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
                .symbolEffect(.variableColor.iterative)

        case .playingEnglish:
            VStack(spacing: 8) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.purple)
                    .symbolEffect(.variableColor.iterative)
                Text("EN")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.purple)
            }

        case .waitingForRepeat, .waitingForMeaning:
            Image(systemName: "mic.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .opacity(pulseAnimation ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulseAnimation)
                .onAppear { pulseAnimation = true }
                .onDisappear { pulseAnimation = false }

        case .recordingRepeat, .recordingMeaning:
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)

        case .processingRepeat, .processingMeaning:
            ProgressView()
                .scaleEffect(2)

        case .feedbackRepeat(let correct), .feedbackMeaning(let correct):
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(correct ? .green : .red)

        case .askingMeaning:
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.purple)

        case .repromptNoAudioRepeat, .repromptNoAudioMeaning:
            // Neutral "didn't catch that" — not a wrong-answer ✗.
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

        case .advancing:
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

        default:
            EmptyView()
        }
    }

    // MARK: - Completed View
    private var completedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "trophy.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)

            Text("Practice Complete!")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 16) {
                scoreRow(label: "Pronunciation", correct: pronunciationCorrect, total: totalAttempted, icon: "mic.fill")
                scoreRow(label: "Comprehension", correct: meaningCorrect, total: totalAttempted, icon: "brain.head.profile")
            }
            .padding(.horizontal, 32)

            if totalAttempted > 0 {
                let overallPercent = Int(Double(pronunciationCorrect + meaningCorrect) / Double(totalAttempted * 2) * 100)
                Text("\(overallPercent)% overall")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(overallPercent >= 70 ? .green : .orange)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    resetPractice()
                } label: {
                    Label("Try Again", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .explains("Try Again", "Restart the practice from the first sentence.")

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .explains("Done", "Finish and leave the practice.")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private func scoreRow(label: String, correct: Int, total: Int, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.body)
            Spacer()
            Text("\(correct)/\(total)")
                .font(.body)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Build Sentences
    private func buildSentences() {
        var result: [PracticeSentence] = []
        let sortedPages = comic.pages.sorted { $0.pageNumber < $1.pageNumber }

        for page in sortedPages {
            let sortedPanels = page.panels.sorted { $0.panelOrder < $1.panelOrder }
            for panel in sortedPanels {
                for bubble in panel.bubbles {
                    if bubble.isSoundEffect == true { continue }
                    for sentence in bubble.sentences {
                        guard let audioUrl = sentence.audioUrl,
                              !audioUrl.isEmpty,
                              let translation = sentence.translation,
                              !translation.isEmpty else { continue }

                        result.append(PracticeSentence(
                            id: sentence.id,
                            text: sentence.text,
                            translation: translation,
                            audioUrl: audioUrl,
                            translationAudioUrl: sentence.translationAudioUrl,
                            alternativeTexts: sentence.alternativeTexts ?? [],
                            pageNumber: page.pageNumber,
                            panelOrder: panel.panelOrder
                        ))
                    }
                }
            }
        }

        sentences = result
    }

    // MARK: - State Machine

    private var isPausedState: Bool {
        if case .paused = state { return true }
        return false
    }

    // True when there's a saved spot partway through, so the start button reads
    // "Continue" rather than "Start".
    private var isResumingPractice: Bool {
        let idx = progressManager.practiceStartIndex(for: comic.id)
        return idx > 0 && idx < sentences.count
    }

    private func startPractice() {
        guard !sentences.isEmpty else { return }
        // Resume where the last practice run left off (0 if none / already finished).
        let saved = progressManager.practiceStartIndex(for: comic.id)
        currentIndex = saved < sentences.count ? saved : 0
        pronunciationCorrect = 0
        meaningCorrect = 0
        totalAttempted = 0
        startKeepAlive()
        // Start the capture engine now, while we're certainly foreground —
        // iOS refuses to start (but not continue) capture once locked.
        whisperService.warmUpCapture()
        playCurrentSentence()
    }

    private func resetPractice() {
        currentIndex = 0
        pronunciationCorrect = 0
        meaningCorrect = 0
        totalAttempted = 0
        showSpanishText = false
        showTranslation = false
        state = .idle
    }

    private func playCurrentSentence() {
        guard currentIndex < sentences.count else {
            state = .completed
            stopKeepAlive()
            updateNowPlaying()
            return
        }

        resetAudioSessionForPlayback()
        showSpanishText = false
        showTranslation = false
        isFirstRepeatAttempt = true
        isFirstMeaningAttempt = true
        state = .playingSpanish
        updateNowPlaying()

        let sentence = sentences[currentIndex]
        audioManager.play(sentence.audioUrl)
    }

    // MARK: - Audio Completion Handler
    private func handleAudioFinished() {
        switch state {
        case .playingSpanish:
            // Spanish sentence finished → wait then record repeat
            state = .waitingForRepeat
            scheduleDelay(0.8) {
                guard self.state == .waitingForRepeat else { return }
                self.startRecordingRepeat()
            }

        case .feedbackRepeat(let correct):
            resetAudioSessionForPlayback()
            if correct {
                // Correct pronunciation → ask meaning
                state = .askingMeaning
                audioManager.play(whatDoesItMeanClip)
            } else {
                // Incorrect → replay Spanish for retry
                state = .replayingCorrect
                audioManager.play(sentences[currentIndex].audioUrl)
            }

        case .replayingCorrect:
            // Spanish replayed after incorrect → record retry
            state = .waitingForRepeat
            scheduleDelay(0.8) {
                guard self.state == .waitingForRepeat else { return }
                self.startRecordingRepeat()
            }

        case .askingMeaning:
            // "What does it mean?" finished → record meaning
            state = .waitingForMeaning
            scheduleDelay(0.8) {
                guard self.state == .waitingForMeaning else { return }
                self.startRecordingMeaning()
            }

        case .feedbackMeaning(let correct):
            resetAudioSessionForPlayback()
            if correct {
                // Correct meaning → replay Spanish then advance
                state = .replayingBeforeAdvance
                audioManager.play(sentences[currentIndex].audioUrl)
            } else {
                // Incorrect meaning → play English translation
                playEnglishTranslation()
            }

        case .playingEnglish:
            // English finished → replay Spanish before retry
            showTranslation = true
            state = .replayingBeforeRetry
            resetAudioSessionForPlayback()
            audioManager.play(sentences[currentIndex].audioUrl)

        case .replayingBeforeAdvance:
            // Spanish replayed after correct meaning → advance
            advanceToNext()

        case .replayingBeforeRetry:
            // Spanish replayed after incorrect meaning → ask again
            scheduleDelay(0.5) {
                self.resetAudioSessionForPlayback()
                self.state = .askingMeaning
                self.audioManager.play(self.whatDoesItMeanClip)
            }

        case .repromptNoAudioRepeat:
            // "I didn't hear anything" finished → replay the phrase, then re-record
            // (same as the incorrect-pronunciation path, but unscored).
            resetAudioSessionForPlayback()
            state = .replayingCorrect
            audioManager.play(sentences[currentIndex].audioUrl)

        case .repromptNoAudioMeaning:
            // "I didn't hear anything" finished → re-ask "what does it mean?"
            resetAudioSessionForPlayback()
            state = .askingMeaning
            audioManager.play(whatDoesItMeanClip)

        default:
            break
        }
    }

    // MARK: - Recording: Repeat

    private func startRecordingRepeat() {
        state = .recordingRepeat

        Task {
            // Auto-stop on silence after speech
            whisperService.onSilenceDetected = {
                guard self.state == .recordingRepeat else { return }
                self.stopRecordingRepeat()
            }

            await whisperService.startRecording()

            // Fallback max timer (in case silence detection doesn't trigger)
            let sentence = sentences[currentIndex]
            let wordCount = sentence.text.split(separator: " ").count
            let timeout = max(4.0, Double(wordCount) * 1.0 + 2.0)
            autoStopTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                Task { @MainActor in
                    guard self.state == .recordingRepeat else { return }
                    self.stopRecordingRepeat()
                }
            }
        }
    }

    private func stopRecordingRepeat() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        state = .processingRepeat

        let sentence = sentences[currentIndex]

        Task {
            let transcription = await whisperService.stopRecording(expectedText: sentence.text, language: "es")

            resetAudioSessionForPlayback()

            // No speech captured → say so and re-record, rather than scoring a
            // silent attempt as wrong.
            if transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handleNoAudio(repeatStep: true)
                return
            }

            // Reject if user spoke the English translation instead of Spanish
            if !sentence.translation.isEmpty && detectSpokenEnglish(spoken: transcription, expected: sentence.translation) {
                // Spoke the meaning, not the Spanish — mark incorrect
                if isFirstRepeatAttempt {
                    isFirstRepeatAttempt = false
                }
                showSpanishText = true
                state = .feedbackRepeat(correct: false)
                audioManager.play(notQuiteClip)
                return
            }

            // Compare with expected text (85%)
            let result = whisperService.compareText(spoken: transcription, expected: sentence.text, passThreshold: 0.85)
            var isCorrect = result.isCorrect

            // Check alternative texts
            if !isCorrect {
                for alt in sentence.alternativeTexts {
                    let altResult = whisperService.compareText(spoken: transcription, expected: alt, passThreshold: 0.85)
                    if altResult.isCorrect {
                        isCorrect = true
                        break
                    }
                }
            }

            // Score only first attempt
            if isFirstRepeatAttempt {
                if isCorrect { pronunciationCorrect += 1 }
                isFirstRepeatAttempt = false
            }

            showSpanishText = true
            state = .feedbackRepeat(correct: isCorrect)

            // Play feedback clip
            audioManager.play(isCorrect ? correctClip : notQuiteClip)
        }
    }

    // MARK: - Recording: Meaning

    private func startRecordingMeaning() {
        state = .recordingMeaning

        Task {
            // Auto-stop on silence after speech
            whisperService.onSilenceDetected = {
                guard self.state == .recordingMeaning else { return }
                self.stopRecordingMeaning()
            }

            await whisperService.startRecording()

            // Fallback max timer (in case silence detection doesn't trigger)
            let sentence = sentences[currentIndex]
            let wordCount = sentence.translation.split(separator: " ").count
            let timeout = max(5.0, Double(wordCount) * 1.0 + 3.0)
            autoStopTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                Task { @MainActor in
                    guard self.state == .recordingMeaning else { return }
                    self.stopRecordingMeaning()
                }
            }
        }
    }

    private func stopRecordingMeaning() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        state = .processingMeaning

        let sentence = sentences[currentIndex]

        Task {
            let transcription = await whisperService.stopRecording(expectedText: sentence.translation, language: "en")

            resetAudioSessionForPlayback()

            // No speech captured → say so and re-record, rather than scoring it wrong.
            if transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handleNoAudio(repeatStep: false)
                return
            }

            let isCorrect = compareEnglish(spoken: transcription, expected: sentence.translation)

            // Score only first attempt
            if isFirstMeaningAttempt {
                if isCorrect { meaningCorrect += 1 }
                isFirstMeaningAttempt = false
            }

            if isCorrect { showTranslation = true }

            state = .feedbackMeaning(correct: isCorrect)

            // Play feedback clip
            audioManager.play(isCorrect ? correctClip : notQuiteClip)
        }
    }

    // MARK: - English Translation Playback

    private func playEnglishTranslation() {
        let sentence = sentences[currentIndex]
        resetAudioSessionForPlayback()

        if let translationUrl = sentence.translationAudioUrl, !translationUrl.isEmpty {
            // Pre-recorded English audio available
            state = .playingEnglish
            audioManager.play(translationUrl)
        } else {
            // Fallback: iOS TTS
            state = .playingEnglish
            usingTTSFallback = true
            speakTTS(sentence.translation) {
                self.usingTTSFallback = false
                self.handleAudioFinished()
            }
        }
    }

    // MARK: - Advance

    private func advanceToNext() {
        // Count this sentence as attempted (once per sentence)
        totalAttempted += 1

        state = .advancing
        scheduleDelay(1.0) {
            self.currentIndex += 1
            if self.currentIndex >= self.sentences.count {
                self.state = .completed
                self.clearPracticeSpot()
                self.stopKeepAlive()
                self.updateNowPlaying()
            } else {
                self.savePracticeSpot()
                self.playCurrentSentence()
            }
        }
    }

    // MARK: - Pause / Resume / Skip

    private func togglePause() {
        if case .paused(let previous) = state {
            resumeFrom(previous)
        } else {
            pauseCurrent()
        }
    }

    private func pauseCurrent() {
        let previousState = state
        cancelAllActivity()
        state = .paused(previous: previousState)
        updateNowPlaying()
    }

    private func resumeFrom(_ previousState: PracticeState) {
        resetAudioSessionForPlayback()
        switch previousState {
        case .playingSpanish, .waitingForRepeat:
            playCurrentSentence()
        case .recordingRepeat:
            state = .waitingForRepeat
            scheduleDelay(0.5) {
                guard self.state == .waitingForRepeat else { return }
                self.startRecordingRepeat()
            }
        case .processingRepeat, .feedbackRepeat, .replayingCorrect:
            // Restart from Spanish replay
            state = .replayingCorrect
            audioManager.play(sentences[currentIndex].audioUrl)
        case .askingMeaning, .waitingForMeaning:
            state = .askingMeaning
            audioManager.play(whatDoesItMeanClip)
        case .recordingMeaning:
            state = .waitingForMeaning
            scheduleDelay(0.5) {
                guard self.state == .waitingForMeaning else { return }
                self.startRecordingMeaning()
            }
        case .processingMeaning, .feedbackMeaning, .playingEnglish, .replayingBeforeRetry:
            state = .askingMeaning
            audioManager.play(whatDoesItMeanClip)
        case .replayingBeforeAdvance, .advancing:
            advanceToNext()
        default:
            playCurrentSentence()
        }
        updateNowPlaying()
    }

    private func skipToNext() {
        cancelAllActivity()

        // Count as attempted if we haven't already
        if state != .idle && state != .completed && state != .advancing {
            totalAttempted += 1
        }

        currentIndex += 1
        if currentIndex >= sentences.count {
            state = .completed
            clearPracticeSpot()
            updateNowPlaying()
        } else {
            savePracticeSpot()
            playCurrentSentence()
        }
    }

    private func skipToPrevious() {
        cancelAllActivity()
        guard currentIndex > 0 else {
            // Already at the first sentence — just replay it.
            playCurrentSentence()
            return
        }
        currentIndex -= 1
        savePracticeSpot()
        playCurrentSentence()
    }

    private func savePracticeSpot() {
        progressManager.savePracticePosition(comicId: comic.id, index: currentIndex, total: sentences.count)
    }

    private func clearPracticeSpot() {
        progressManager.clearPracticePosition(for: comic.id)
    }

    private func goBack() {
        cancelAllActivity()

        guard currentIndex > 0 else {
            // Already at first sentence, just replay it
            playCurrentSentence()
            return
        }

        currentIndex -= 1
        isFirstRepeatAttempt = true
        isFirstMeaningAttempt = true
        showSpanishText = false
        showTranslation = false
        playCurrentSentence()
    }

    private func cancelAllActivity() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        silentPlayer?.stop()
        silentPlayer = nil
        audioManager.stop()
        synthesizer.stopSpeaking(at: .immediate)
        usingTTSFallback = false
        whisperService.cancelRecording()
    }

    private func cleanup() {
        cancelAllActivity()
        stopKeepAlive()
        whisperService.endCaptureSession()
    }

    // MARK: - Helpers

    /// Start a looping near-silent player that runs for the whole practice
    /// session. iOS keeps backgrounded apps alive only while audio is
    /// actually playing; this covers every silent gap in the practice loop
    /// (most importantly the Whisper transcription wait, when neither the
    /// mic nor any audio is active).
    private func startKeepAlive() {
        guard keepAlivePlayer == nil else { return }
        do {
            let player = try AVAudioPlayer(data: makeSilentWav(duration: 10))
            player.numberOfLoops = -1
            player.volume = 0.01
            player.play()
            keepAlivePlayer = player
        } catch {
            print("Failed to start keep-alive player: \(error)")
        }
    }

    private func stopKeepAlive() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
    }

    /// Plays a near-silent audio clip of exact duration. When it finishes,
    /// the SilentTimerDelegate fires the action. This keeps the audio session
    /// active in the background so iOS doesn't suspend the app.
    private func scheduleDelay(_ interval: TimeInterval, action: @escaping () -> Void) {
        silentPlayer?.stop()
        silentPlayer = nil

        do {
            let player = try AVAudioPlayer(data: makeSilentWav(duration: interval))
            player.numberOfLoops = 0
            player.volume = 0.01
            player.delegate = silentTimerDelegate
            silentTimerDelegate.onFinish = action
            player.play()
            silentPlayer = player
        } catch {
            print("Failed to create silent timer: \(error)")
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { action() }
        }
    }

    /// Build a mono 16-bit PCM WAV of near-silence (amplitude 1/32767 — not
    /// true zero so iOS keeps the audio session alive).
    private func makeSilentWav(duration interval: TimeInterval) -> Data {
        let sampleRate: Double = 44100
        let numSamples = Int(sampleRate * interval)
        let bytesPerSample = 2
        let dataSize = numSamples * bytesPerSample

        var wav = Data()
        // RIFF header
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var fileSize = UInt32(36 + dataSize)
        wav.append(Data(bytes: &fileSize, count: 4))
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        // fmt chunk
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var chunkSize: UInt32 = 16
        wav.append(Data(bytes: &chunkSize, count: 4))
        var audioFormat: UInt16 = 1 // PCM
        wav.append(Data(bytes: &audioFormat, count: 2))
        var channels: UInt16 = 1
        wav.append(Data(bytes: &channels, count: 2))
        var sr = UInt32(sampleRate)
        wav.append(Data(bytes: &sr, count: 4))
        var byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bytesPerSample)
        wav.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(bytesPerSample) * channels
        wav.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample: UInt16 = 16
        wav.append(Data(bytes: &bitsPerSample, count: 2))
        // data chunk
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var ds = UInt32(dataSize)
        wav.append(Data(bytes: &ds, count: 4))
        // Near-silent audio (amplitude 1 out of 32767) — not true zero so iOS keeps session alive
        var samples = Data(count: dataSize)
        for i in stride(from: 0, to: dataSize, by: bytesPerSample) {
            samples[i] = 1      // low byte = 1
            samples[i + 1] = 0  // high byte = 0 → amplitude of 1/32767
        }
        wav.append(samples)
        return wav
    }

    private func resetAudioSessionForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use .playAndRecord throughout practice so mic stays available in
            // background. Only touch the session when something actually
            // changed — redundant setCategory calls force the capture engine
            // to reconfigure, which can kill the mic while the phone is locked.
            if audioSession.category != .playAndRecord {
                // .allowBluetoothA2DP keeps AirPods on the high-quality music
                // profile (input falls back to the iPhone mic) instead of HFP
                // call mode — in call mode the stem press is treated as call
                // control and never reaches our remote-command handlers.
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
                try audioSession.setActive(true)
            }
        } catch {
            print("Failed to reset audio session: \(error)")
        }
    }

    // MARK: - TTS Fallback

    /// No speech captured: tell the user and re-record the same step (never
    /// scored as wrong). Prefers the recorded clip (plays even when the phone is
    /// locked, via the audio engine); falls back to the system voice until the
    /// clip is added to the app bundle/target.
    private func handleNoAudio(repeatStep: Bool) {
        // After the prompt, replay the phrase and try again (like the "Not quite"
        // flow): repromptNoAudioRepeat → replay Spanish → record; repromptNoAudio-
        // Meaning → re-ask "what does it mean?" → record. handleAudioFinished
        // drives those transitions when the prompt clip/TTS finishes.
        state = repeatStep ? .repromptNoAudioRepeat : .repromptNoAudioMeaning
        if Bundle.main.url(forResource: noAudioClip, withExtension: "mp3") != nil {
            audioManager.play(noAudioClip)
        } else {
            speakTTS("I didn't hear anything. Please try again.") {
                self.handleAudioFinished()
            }
        }
    }

    private func speakTTS(_ text: String, completion: @escaping () -> Void) {
        resetAudioSessionForPlayback()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.pitchMultiplier = 1.0

        ttsDelegate.onFinish = completion
        synthesizer.speak(utterance)
    }

    // MARK: - English Comparison (Lenient)

    private func compareEnglish(spoken: String, expected: String) -> Bool {
        let spokenClean = normalizeEnglish(spoken)
        let expectedClean = normalizeEnglish(expected)

        if spokenClean == expectedClean { return true }
        if spokenClean.contains(expectedClean) || expectedClean.contains(spokenClean) { return true }

        let spokenWords = spokenClean.split(separator: " ").map(String.init)
        let expectedWords = expectedClean.split(separator: " ").map(String.init)

        guard !expectedWords.isEmpty else { return true }

        // Allow word count differences (Whisper may add/drop small words like "it", "is")
        let wordCountDiff = abs(spokenWords.count - expectedWords.count)
        if wordCountDiff > 3 { return false }

        var matchCount = 0
        var usedIndices = Set<Int>()

        for expectedWord in expectedWords {
            for (i, spokenWord) in spokenWords.enumerated() where !usedIndices.contains(i) {
                let maxLen = max(expectedWord.count, spokenWord.count)
                let distance = levenshteinDistance(spokenWord, expectedWord)
                let matches: Bool
                if spokenWord == expectedWord {
                    matches = true
                } else if maxLen <= 3 {
                    // Short words: allow 1 edit
                    matches = distance <= 1
                } else if maxLen >= 6 {
                    // Longer words: allow 2 edits
                    matches = distance <= 2
                } else {
                    // Medium words: allow 1 edit
                    matches = distance <= 1
                }
                if matches {
                    matchCount += 1
                    usedIndices.insert(i)
                    break
                }
            }
        }

        let score = Double(matchCount) / Double(expectedWords.count)
        return score >= 0.65
    }

    /// Stricter check used only to reject English during Spanish repeat phase.
    /// Requires high confidence that the user actually spoke English (not Spanish that happens to share some words).
    private func detectSpokenEnglish(spoken: String, expected: String) -> Bool {
        let spokenClean = normalizeEnglish(spoken)
        let expectedClean = normalizeEnglish(expected)

        // Exact or substring match is a clear signal
        if spokenClean == expectedClean { return true }
        if spokenClean.contains(expectedClean) || expectedClean.contains(spokenClean) { return true }

        let spokenWords = spokenClean.split(separator: " ").map(String.init)
        let expectedWords = expectedClean.split(separator: " ").map(String.init)

        guard expectedWords.count >= 2 else {
            // Single-word translations can easily false-match Spanish — only reject on exact match
            return spokenClean == expectedClean
        }

        var matchCount = 0
        var usedIndices = Set<Int>()

        for expectedWord in expectedWords {
            for (i, spokenWord) in spokenWords.enumerated() where !usedIndices.contains(i) {
                // Strict: exact match only (no fuzzy)
                if spokenWord == expectedWord {
                    matchCount += 1
                    usedIndices.insert(i)
                    break
                }
            }
        }

        let score = Double(matchCount) / Double(expectedWords.count)
        // Require 71%+ exact word match for English (lower than Spanish —
        // Whisper is less accurate with English in noisy/mobile conditions,
        // and the meaning check shouldn't punish loose-but-correct phrasing)
        return score >= 0.71
    }

    private func normalizeEnglish(_ text: String) -> String {
        var result = text.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "'", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "it's", with: "it is")
            .replacingOccurrences(of: "don't", with: "do not")
            .replacingOccurrences(of: "doesn't", with: "does not")
            .replacingOccurrences(of: "didn't", with: "did not")
            .replacingOccurrences(of: "can't", with: "cannot")
            .replacingOccurrences(of: "won't", with: "will not")
            .replacingOccurrences(of: "isn't", with: "is not")
            .replacingOccurrences(of: "aren't", with: "are not")
            .replacingOccurrences(of: "wasn't", with: "was not")
            .replacingOccurrences(of: "weren't", with: "were not")
            .replacingOccurrences(of: "i'm", with: "i am")
            .replacingOccurrences(of: "we're", with: "we are")
            .replacingOccurrences(of: "they're", with: "they are")
            .replacingOccurrences(of: "you're", with: "you are")
            .replacingOccurrences(of: "he's", with: "he is")
            .replacingOccurrences(of: "she's", with: "she is")
            .replacingOccurrences(of: "let's", with: "let us")
            .replacingOccurrences(of: "that's", with: "that is")
            .replacingOccurrences(of: "there's", with: "there is")
            .replacingOccurrences(of: "what's", with: "what is")
            .replacingOccurrences(of: "i've", with: "i have")
            .replacingOccurrences(of: "we've", with: "we have")
            .replacingOccurrences(of: "they've", with: "they have")
            .replacingOccurrences(of: "you've", with: "you have")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading articles
        let articles = ["the ", "a ", "an "]
        for article in articles {
            if result.hasPrefix(article) {
                result = String(result.dropFirst(article.count))
            }
        }
        return result
    }

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

    // MARK: - Remote Commands (AirPod Controls)

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        do {
            // .allowBluetoothA2DP: see resetAudioSessionForPlayback — without it
            // AirPods run in HFP call mode and stem presses never reach the app.
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session for remote commands: \(error)")
        }

        UIApplication.shared.beginReceivingRemoteControlEvents()

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            Task { @MainActor in self.skipToNext() }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            Task { @MainActor in self.goBack() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in self.togglePause() }
            return .success
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in
                if case .paused = self.state { self.togglePause() }
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in
                if case .paused = self.state { } else { self.pauseCurrent() }
            }
            return .success
        }
    }

    private func setupNowPlaying() {
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = "Repeat Practice"
        info[MPMediaItemPropertyArtist] = comic.title
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentIndex)
        info[MPMediaItemPropertyPlaybackDuration] = Double(sentences.count)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPausedState ? 0.0 : 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func teardownRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
