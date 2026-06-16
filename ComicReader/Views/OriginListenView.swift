import SwiftUI
import AVFoundation
import MediaPlayer

// MARK: - Origin Listen State
enum OriginListenState: Equatable {
    case idle
    case playingSpanish
    case advancing          // 2s pause before next sentence
    indirect case paused(previous: OriginListenState)
    case completed

    static func == (lhs: OriginListenState, rhs: OriginListenState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.playingSpanish, .playingSpanish),
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

// MARK: - OriginListenView
struct OriginListenView: View {
    let comic: Comic
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var audioManager = AudioManager.shared
    @StateObject private var help = HelpModeController()

    @State private var sentences: [PracticeSentence] = []
    @State private var currentIndex = 0
    @State private var state: OriginListenState = .idle

    // Silent timer — plays near-silent audio for exact duration, fires delegate on completion
    @State private var silentPlayer: AVAudioPlayer?
    @State private var silentTimerDelegate = SilentTimerDelegate()

    // UI state
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
        .navigationTitle("Origin Listen")
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
            setupRemoteCommands()
            setupNowPlaying()
            audioManager.onPlaybackFinished = {
                handleAudioFinished()
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

            Image(systemName: "play.circle")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text(comic.title)
                .font(.title2)
                .fontWeight(.bold)

            Text("\(sentences.count) sentences")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Listen to the full story in Spanish, sentence by sentence.")
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
            .explains("Start Listening", "Play the whole story in Spanish, one sentence at a time.")
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
                .explains("Listen Again", "Play the whole story again from the beginning.")

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
                .explains("Done", "Finish and leave the listening session.")
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
            if currentIndex < sentences.count {
                Text(sentences[currentIndex].text)
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

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
                .explains("Back", "Go back to the previous sentence.")

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
                .explains("Pause / Resume", "Pause playback, or resume from where you left off.")

                // Skip button
                Button {
                    skipToNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
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

        case .advancing:
            VStack(spacing: 8) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .opacity(pulseAnimation ? 1.0 : 0.4)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: pulseAnimation)
            }
            .onAppear { pulseAnimation = true }
            .onDisappear { pulseAnimation = false }

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
                              !audioUrl.isEmpty else { continue }

                        result.append(PracticeSentence(
                            id: sentence.id,
                            text: sentence.text,
                            translation: sentence.translation ?? "",
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
        state = .idle
    }

    private func playCurrentSentence() {
        state = .playingSpanish
        resetAudioSessionForPlayback()
        let sentence = sentences[currentIndex]
        audioManager.play(sentence.audioUrl)
        updateNowPlaying()
    }

    private func handleAudioFinished() {
        switch state {
        case .playingSpanish:
            // Spanish finished → 2s pause → next sentence
            state = .advancing
            scheduleDelay(2.0) {
                guard self.state == .advancing else { return }
                self.advanceToNext()
            }

        default:
            break
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
        case .playingSpanish:
            playCurrentSentence()

        case .advancing:
            state = .advancing
            scheduleDelay(2.0) {
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
    }

    private func cleanup() {
        cancelAllActivity()
    }

    // MARK: - Helpers

    /// Plays a near-silent audio clip of exact duration to keep audio session alive in background.
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
        // Near-silent audio (amplitude 1 out of 32767)
        var samples = Data(count: dataSize)
        for i in stride(from: 0, to: dataSize, by: bytesPerSample) {
            samples[i] = 1
            samples[i + 1] = 0
        }
        wav.append(samples)

        do {
            let player = try AVAudioPlayer(data: wav)
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

    private func resetAudioSessionForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to reset audio session: \(error)")
        }
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
        info[MPMediaItemPropertyTitle] = "Origin Listen"
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
