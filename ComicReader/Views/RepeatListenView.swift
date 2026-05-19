import SwiftUI
import AVFoundation
import MediaPlayer

// MARK: - Listen State
enum ListenState: Equatable {
    case idle
    case playingSpanish
    case pauseBeforeEnglish   // 1s pause after Spanish
    case playingEnglish       // playing English translation audio
    case pauseBeforeRepeat    // 1s pause after English
    case playingSpanishAgain  // replay Spanish
    case advancing            // 3s pause before next sentence
    indirect case paused(previous: ListenState)
    case completed

    static func == (lhs: ListenState, rhs: ListenState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.playingSpanish, .playingSpanish),
             (.pauseBeforeEnglish, .pauseBeforeEnglish),
             (.playingEnglish, .playingEnglish),
             (.pauseBeforeRepeat, .pauseBeforeRepeat),
             (.playingSpanishAgain, .playingSpanishAgain),
             (.advancing, .advancing),
             (.completed, .completed):
            return true
        case (.paused(let a), .paused(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - TTS Delegate for Listen Mode
class ListenTTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?()
        }
    }
}

// MARK: - Silent Timer Delegate
/// Plays a near-silent audio clip of a specific duration and fires a callback when done.
/// This keeps the audio session active in the background so iOS doesn't suspend the app.
class SilentTimerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?()
        }
    }
}

// MARK: - RepeatListenView
struct RepeatListenView: View {
    let comic: Comic
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var audioManager = AudioManager.shared

    @State private var sentences: [PracticeSentence] = []
    @State private var currentIndex = 0
    @State private var state: ListenState = .idle

    // TTS fallback for English
    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var ttsDelegate = ListenTTSDelegate()
    @State private var usingTTSFallback = false

    // Silent timer — plays near-silent audio for exact duration, fires delegate on completion
    @State private var silentPlayer: AVAudioPlayer?
    @State private var silentTimerDelegate = SilentTimerDelegate()

    // UI state
    @State private var showSpanishText = false
    @State private var showTranslation = false
    @State private var pulseAnimation = false

    var body: some View {
        Group {
            if state == .idle {
                startView
            } else if state == .completed {
                completedView
            } else {
                listenView
            }
        }
        .navigationTitle("Repeat Listen")
        .navigationBarTitleDisplayMode(.inline)
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
            cleanup()
            teardownRemoteCommands()
            audioManager.onPlaybackFinished = nil
        }
    }

    // MARK: - Start View
    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "headphones")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text(comic.title)
                .font(.title2)
                .fontWeight(.bold)

            Text("\(sentences.count) sentences")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Listen to each sentence, mentally repeat it, then think of the English meaning. The answer will be revealed automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                startListening()
            } label: {
                Text("Start Listening")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .disabled(sentences.isEmpty)
        }
    }

    // MARK: - Completed View
    private var completedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Listening Complete!")
                .font(.title2)
                .fontWeight(.bold)

            Text("Listened to \(sentences.count) sentences")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    resetListening()
                } label: {
                    Text("Listen Again")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .cornerRadius(16)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Listen View
    private var listenView: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 4)
                    Rectangle()
                        .fill(.blue)
                        .frame(width: geometry.size.width * CGFloat(currentIndex) / CGFloat(max(sentences.count, 1)), height: 4)
                }
            }
            .frame(height: 4)

            Text("Sentence \(currentIndex + 1) of \(sentences.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()

            // State indicator
            stateIndicator

            Spacer()

            // Sentence display
            VStack(spacing: 16) {
                if showSpanishText && currentIndex < sentences.count {
                    Text(sentences[currentIndex].text)
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }

                if showTranslation && currentIndex < sentences.count {
                    Text(sentences[currentIndex].translation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSpanishText)
            .animation(.easeInOut(duration: 0.3), value: showTranslation)

            Spacer()

            // Controls
            HStack(spacing: 40) {
                // Back button
                Button {
                    goBack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundStyle(currentIndex > 0 ? .blue : .gray)
                }
                .disabled(currentIndex <= 0)

                // Pause/Resume
                Button {
                    if isPausedState {
                        resumeFromPause()
                    } else {
                        pauseCurrent()
                    }
                } label: {
                    Image(systemName: isPausedState ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(isPausedState ? .blue : .orange)
                }

                // Skip button
                Button {
                    skipToNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - State Indicator
    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .playingSpanish:
            VStack(spacing: 8) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative)
                Text("Listening...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .pauseBeforeEnglish, .pauseBeforeRepeat:
            VStack(spacing: 8) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .opacity(pulseAnimation ? 1.0 : 0.4)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: pulseAnimation)
            }
            .onAppear { pulseAnimation = true }
            .onDisappear { pulseAnimation = false }

        case .playingEnglish:
            VStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative)
                Text("English meaning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .playingSpanishAgain:
            VStack(spacing: 8) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative)
                Text("Listen again...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .advancing:
            VStack(spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Next...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .paused:
            VStack(spacing: 8) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        default:
            EmptyView()
        }
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

    private func startListening() {
        guard !sentences.isEmpty else { return }
        currentIndex = 0
        playCurrentSentence()
    }

    private func resetListening() {
        currentIndex = 0
        showSpanishText = false
        showTranslation = false
        state = .idle
    }

    private func playCurrentSentence() {
        showSpanishText = false
        showTranslation = false
        state = .playingSpanish

        resetAudioSessionForPlayback()

        let sentence = sentences[currentIndex]
        audioManager.play(sentence.audioUrl)
        updateNowPlaying()
    }

    // Called when AudioManager finishes playing
    private func handleAudioFinished() {
        switch state {
        case .playingSpanish:
            // Spanish finished → 1s pause → play English
            showSpanishText = true
            state = .pauseBeforeEnglish

            scheduleDelay(1.0) {
                guard self.state == .pauseBeforeEnglish else { return }
                self.playEnglishTranslation()
            }

        case .playingEnglish:
            // English finished → 1s pause → play Spanish again
            showTranslation = true
            state = .pauseBeforeRepeat

            scheduleDelay(1.0) {
                guard self.state == .pauseBeforeRepeat else { return }
                self.replaySpanish()
            }

        case .playingSpanishAgain:
            // Second Spanish finished → 3s pause → next sentence
            state = .advancing

            scheduleDelay(3.0) {
                guard self.state == .advancing else { return }
                self.advanceToNext()
            }

        default:
            break
        }
    }

    private func replaySpanish() {
        state = .playingSpanishAgain
        resetAudioSessionForPlayback()
        let sentence = sentences[currentIndex]
        audioManager.play(sentence.audioUrl)
    }

    // MARK: - English Translation Playback

    private func playEnglishTranslation() {
        let sentence = sentences[currentIndex]
        print("🔊 English audio for sentence \(currentIndex): translationAudioUrl=\(sentence.translationAudioUrl ?? "NIL"), audioUrl=\(sentence.audioUrl)")
        if let translationUrl = sentence.translationAudioUrl, !translationUrl.isEmpty {
            print("🔊 Playing pre-recorded English: \(translationUrl)")
            state = .playingEnglish
            audioManager.play(translationUrl)
        } else {
            // TTS fallback
            print("🔊 No pre-recorded English, using TTS fallback")
            state = .playingEnglish
            usingTTSFallback = true
            speakTTS(sentence.translation) {
                self.usingTTSFallback = false
                self.handleAudioFinished()
            }
        }
    }

    // MARK: - Navigation

    private func advanceToNext() {
        currentIndex += 1
        if currentIndex >= sentences.count {
            state = .completed
            updateNowPlaying()
        } else {
            playCurrentSentence()
        }
    }

    private func skipToNext() {
        cancelAllActivity()
        currentIndex += 1
        if currentIndex >= sentences.count {
            state = .completed
            updateNowPlaying()
        } else {
            playCurrentSentence()
        }
    }

    private func goBack() {
        cancelAllActivity()
        guard currentIndex > 0 else {
            playCurrentSentence()
            return
        }
        currentIndex -= 1
        playCurrentSentence()
    }

    // MARK: - Pause/Resume

    private func pauseCurrent() {
        guard !isPausedState else { return }
        let previousState = state
        cancelAllActivity()
        state = .paused(previous: previousState)
        updateNowPlaying()
    }

    private func resumeFromPause() {
        guard case .paused(let previous) = state else { return }

        switch previous {
        case .playingSpanish, .playingEnglish, .playingSpanishAgain:
            // Restart from the current sentence
            playCurrentSentence()

        case .pauseBeforeEnglish:
            state = .pauseBeforeEnglish
            scheduleDelay(1.0) {
                guard self.state == .pauseBeforeEnglish else { return }
                self.playEnglishTranslation()
            }

        case .pauseBeforeRepeat:
            state = .pauseBeforeRepeat
            scheduleDelay(1.0) {
                guard self.state == .pauseBeforeRepeat else { return }
                self.replaySpanish()
            }

        case .advancing:
            state = .advancing
            scheduleDelay(3.0) {
                guard self.state == .advancing else { return }
                self.advanceToNext()
            }

        default:
            playCurrentSentence()
        }
        updateNowPlaying()
    }

    private func togglePause() {
        if isPausedState {
            resumeFromPause()
        } else {
            pauseCurrent()
        }
    }

    // MARK: - Cleanup

    private func cancelAllActivity() {
        silentPlayer?.stop()
        silentPlayer = nil
        silentTimerDelegate.onFinish = nil
        audioManager.stop()
        synthesizer.stopSpeaking(at: .immediate)
        usingTTSFallback = false
    }

    private func cleanup() {
        cancelAllActivity()
    }

    // MARK: - Helpers

    /// Plays a near-silent audio clip of exact duration. When it finishes,
    /// the SilentTimerDelegate fires the action. This keeps the audio session
    /// active in the background so iOS doesn't suspend the app.
    private func scheduleDelay(_ interval: TimeInterval, action: @escaping () -> Void) {
        silentPlayer?.stop()
        silentPlayer = nil

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

        do {
            let player = try AVAudioPlayer(data: wav)
            player.numberOfLoops = 0  // play once — exact duration
            player.volume = 0.01      // near-silent but not zero
            player.delegate = silentTimerDelegate
            silentTimerDelegate.onFinish = action
            player.play()
            silentPlayer = player
        } catch {
            print("Failed to create silent timer: \(error)")
            // Fallback: just call action after delay on main queue
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { action() }
        }
    }

    private func resetAudioSessionForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to reset audio session: \(error)")
        }
    }

    // MARK: - TTS Fallback

    private func speakTTS(_ text: String, completion: @escaping () -> Void) {
        resetAudioSessionForPlayback()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.5

        ttsDelegate.onFinish = completion
        synthesizer.speak(utterance)
    }

    // MARK: - Remote Commands (AirPod Controls)

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
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
        info[MPMediaItemPropertyTitle] = "Repeat Listen"
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
