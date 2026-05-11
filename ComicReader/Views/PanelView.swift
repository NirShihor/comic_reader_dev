import SwiftUI

struct PanelView: View {
    let comic: Comic
    let page: Page
    let panel: Panel
    let hotspots: [Hotspot]
    @Binding var navigateToPage: Int?
    var dismissToHome: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var whisperService = WhisperService.shared

    @State private var textRevealed = false
    @State private var translationRevealed: Set<String> = [] // Track by sentence ID
    @State private var highlightedWordIndex: Int?
    @State private var playingSentenceId: String?
    @State private var recordingSentenceId: String?
    @State private var processingSentenceId: String?
    @State private var practiceFeedback: PracticeFeedback?
    @State private var currentPanelId: String
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showEndOfEpisode = false
    @State private var selectedHotspot: Hotspot?

    init(comic: Comic, page: Page, panel: Panel, hotspots: [Hotspot] = [], navigateToPage: Binding<Int?>, dismissToHome: (() -> Void)? = nil) {
        self.comic = comic
        self.page = page
        self.panel = panel
        self.hotspots = hotspots
        self._navigateToPage = navigateToPage
        self.dismissToHome = dismissToHome
        _currentPanelId = State(initialValue: panel.id)
    }

    struct PracticeFeedback {
        let sentenceId: String
        let isCorrect: Bool
        let spokenText: String
        let expectedText: String
        let words: [Word]
    }

    // Panels sorted by panelOrder for consistent navigation.
    // Include all panels so users can navigate through every panel on the page.
    var sortedPanels: [Panel] {
        page.panels
            .sorted { $0.panelOrder < $1.panelOrder }
    }

    // Find current panel by ID - always returns the correct panel
    var currentPanel: Panel {
        sortedPanels.first(where: { $0.id == currentPanelId }) ?? panel
    }

    // Get current index for display purposes
    var currentPanelIndex: Int {
        sortedPanels.firstIndex(where: { $0.id == currentPanelId }) ?? 0
    }

    var isLastPanel: Bool {
        currentPanelIndex >= sortedPanels.count - 1
    }

    var isFirstPanel: Bool {
        currentPanelIndex == 0
    }

    var hasNextPage: Bool {
        guard let pageIndex = comic.pages.firstIndex(where: { $0.id == page.id }) else { return false }
        return pageIndex < comic.pages.count - 1
    }

    var hasPreviousPage: Bool {
        guard let pageIndex = comic.pages.firstIndex(where: { $0.id == page.id }) else { return false }
        return pageIndex > 0
    }

    /// Hotspots that overlap with the current panel, with coordinates mapped to panel-relative space (0-1)
    var panelHotspots: [(hotspot: Hotspot, relX: Double, relY: Double, relW: Double, relH: Double)] {
        let p = currentPanel
        let tx = p.tapZoneX, ty = p.tapZoneY, tw = p.tapZoneWidth, th = p.tapZoneHeight
        guard tw > 0, th > 0 else { return [] }

        return hotspots.compactMap { hotspot in
            // Check overlap between hotspot rect and panel tap zone
            let hRight = hotspot.x + hotspot.width
            let hBottom = hotspot.y + hotspot.height
            let pRight = tx + tw
            let pBottom = ty + th

            let overlapX = max(hotspot.x, tx)
            let overlapY = max(hotspot.y, ty)
            let overlapRight = min(hRight, pRight)
            let overlapBottom = min(hBottom, pBottom)

            guard overlapRight > overlapX, overlapBottom > overlapY else { return nil }

            // Map hotspot coordinates from page-space to panel-relative space (0-1)
            let relX = (hotspot.x - tx) / tw
            let relY = (hotspot.y - ty) / th
            let relW = hotspot.width / tw
            let relH = hotspot.height / th

            return (hotspot: hotspot, relX: relX, relY: relY, relW: relW, relH: relH)
        }
    }

    /// The sentence currently playing audio (for word highlighting)
    var playingSentence: Sentence? {
        guard let id = playingSentenceId else { return nil }
        return currentPanel.bubbles.flatMap { $0.sentences }.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Panel artwork
                    panelImage

                    // All bubbles displayed vertically
                    ForEach(currentPanel.bubbles) { bubble in
                        if bubble.isSoundEffect == true {
                            // Sound effects are only shown in the panel artwork
                        } else {
                            bubbleCard(bubble)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            let horizontalDistance = value.translation.width
                            if horizontalDistance > 50 {
                                // Swiped right → previous panel/page
                                goToPrevious()
                            } else if horizontalDistance < -50 {
                                // Swiped left → next panel/page
                                goToNext()
                            }
                        }
                )
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 20) {
                        Button {
                            goToPrevious()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(isFirstPanel && !hasPreviousPage ? .gray : .blue)
                        }
                        .disabled(isFirstPanel && !hasPreviousPage)

                        Text("Panel \(currentPanelIndex + 1) of \(sortedPanels.count)")
                            .font(.headline)

                        Button {
                            goToNext()
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(isLastPanel && !hasNextPage ? .gray : .blue)
                        }
                        .disabled(isLastPanel && !hasNextPage)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if dismissToHome != nil {
                        Button {
                            dismiss()
                            dismissToHome?()
                        } label: {
                            Image(systemName: "house.fill")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .id(panel.id) // Force view recreation when panel changes
        .onChange(of: settingsManager.speakingPracticeMode) { _, _ in
            textRevealed = false
            practiceFeedback = nil
        }
        .onChange(of: settingsManager.listeningPracticeMode) { _, newValue in
            textRevealed = false
            practiceFeedback = nil
            // Auto-play first sentence audio when entering listening mode
            if newValue {
                autoPlayFirstSentence()
            }
        }
        .onChange(of: whisperService.error) { _, newError in
            // Only show error if we have no transcribed text (actual failure)
            if let error = newError, whisperService.transcribedText.isEmpty {
                recordingSentenceId = nil
                processingSentenceId = nil
                errorMessage = error
                showingError = true
                whisperService.error = nil
            }
        }
        .onChange(of: audioManager.currentTime) { _, _ in
            // Update word highlighting based on audio position (only for sentence playback)
            if audioManager.isSentencePlayback, let sentence = playingSentence {
                highlightedWordIndex = audioManager.currentWordIndex(for: sentence.words)
            }
        }
        .onChange(of: audioManager.isPlaying) { _, isPlaying in
            if !isPlaying {
                highlightedWordIndex = nil
                playingSentenceId = nil
            }
        }
        .onChange(of: settingsManager.playbackSpeed) { _, newSpeed in
            audioManager.setPlaybackRate(Float(newSpeed))
        }
        .onAppear {
            audioManager.setPlaybackRate(Float(settingsManager.playbackSpeed))
            if settingsManager.listeningPracticeMode {
                autoPlayFirstSentence()
            }
        }
        .onDisappear {
            audioManager.stop()
            whisperService.cancelRecording()
        }
        .alert("Speech Recognition Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(item: $selectedHotspot) { hotspot in
            HotspotView(hotspot: hotspot, comicId: comic.id)
                .environmentObject(settingsManager)
        }
        .alert("End of Episode", isPresented: $showEndOfEpisode) {
            Button("Back to home page") {
                dismiss()
                dismissToHome?()
            }
            Button("Stay", role: .cancel) { }
        } message: {
            Text("You've reached the last panel of this episode.")
        }
    }

    // MARK: - Navigation
    private var currentPageIndex: Int {
        comic.pages.firstIndex(where: { $0.id == page.id }) ?? 0
    }

    private func goToNext() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isLastPanel {
            // Navigate to next page then dismiss
            if hasNextPage {
                navigateToPage = currentPageIndex + 1
                dismiss()
            } else {
                showEndOfEpisode = true
            }
        } else {
            // Move to next panel by ID
            let nextIndex = currentPanelIndex + 1
            if nextIndex < sortedPanels.count {
                withAnimation {
                    currentPanelId = sortedPanels[nextIndex].id
                    resetPanelState()
                }
            }
        }
    }

    private func goToPrevious() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isFirstPanel {
            // Navigate to previous page then dismiss
            if hasPreviousPage {
                navigateToPage = currentPageIndex - 1
                dismiss()
            }
        } else {
            // Move to previous panel by ID
            let prevIndex = currentPanelIndex - 1
            if prevIndex >= 0 {
                withAnimation {
                    currentPanelId = sortedPanels[prevIndex].id
                    resetPanelState()
                }
            }
        }
    }

    private func resetPanelState() {
        translationRevealed = []
        textRevealed = false
        practiceFeedback = nil
        playingSentenceId = nil
        recordingSentenceId = nil
        processingSentenceId = nil
        audioManager.stop()
        whisperService.cancelRecording()

        // Auto-play first sentence when navigating panels in listening mode
        if settingsManager.listeningPracticeMode {
            autoPlayFirstSentence()
        }
    }

    private var panelClipShape: AnyShape {
        if let corners = currentPanel.corners, corners.count >= 3 {
            return AnyShape(PanelClipShape(corners: corners))
        }
        return AnyShape(RoundedRectangle(cornerRadius: 12))
    }

    private var isPracticeMode: Bool {
        settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
    }

    // MARK: - Panel Image
    private var panelImage: some View {
        let imageName = isPracticeMode && !textRevealed
            ? (currentPanel.noTextImage ?? currentPanel.artworkImage)
            : currentPanel.artworkImage

        // Cap image height so bubble cards and controls stay visible without scrolling
        let maxImageHeight: CGFloat = UIScreen.main.bounds.height * 0.4

        return ZStack {
            ComicImage(imageName: imageName, comicId: comic.id)
                .aspectRatio(contentMode: .fit)
                .clipShape(panelClipShape)
                .frame(maxWidth: .infinity, maxHeight: maxImageHeight)
                .shadow(radius: 4)
                .overlay {
                    // Hotspot glowing indicators (on top, so their taps take priority)
                    GeometryReader { geo in
                        ForEach(panelHotspots, id: \.hotspot.id) { item in
                            hotspotIndicator(item: item, in: geo)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    let hasTextContent = currentPanel.bubbles.contains { !$0.sentences.isEmpty }
                    if isPracticeMode && hasTextContent {
                        withAnimation {
                            textRevealed.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

            // Only show "Tap to reveal" if panel has text content (bubbles with sentences)
            let hasTextContent = currentPanel.bubbles.contains { !$0.sentences.isEmpty }
            if isPracticeMode && !textRevealed && hasTextContent {
                VStack {
                    Spacer()
                    Label("Tap to reveal", systemImage: "eye")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
        .id(currentPanel.id) // Force recreation when panel changes
    }

    // MARK: - Hotspot Indicator
    @ViewBuilder
    private func hotspotIndicator(item: (hotspot: Hotspot, relX: Double, relY: Double, relW: Double, relH: Double), in geo: GeometryProxy) -> some View {
        let w = item.relW * geo.size.width
        let h = item.relH * geo.size.height
        let centerX = (item.relX + item.relW / 2) * geo.size.width
        let centerY = (item.relY + item.relH / 2) * geo.size.height

        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let pulse = (sin(seconds * 2.5) + 1.0) / 2.0 // 0...1 oscillation

            ZStack {
                // Pulsing border
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.yellow, lineWidth: 1.5 + pulse * 1.5)
                    .shadow(color: .yellow.opacity(pulse * 0.8), radius: 4 + pulse * 6)
                    .opacity(0.3 + pulse * 0.7)

                // Invisible tap target
                Color.clear
                    .contentShape(Rectangle())
            }
        }
        .frame(width: w, height: h)
        .position(x: centerX, y: centerY)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            selectedHotspot = item.hotspot
        }
    }

    // MARK: - Bubble Card (normal speech/thought/narration)
    private func bubbleCard(_ bubble: Bubble) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(bubble.sentences) { sentence in
                VStack(alignment: .leading, spacing: 8) {
                    // Main text
                    if settingsManager.speakingPracticeMode {
                        Text(sentence.translation ?? "")
                            .font(.title3)
                            .fontWeight(.medium)
                    } else if settingsManager.listeningPracticeMode {
                        Text("What is the English meaning?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        // Hide manually added phrases (quiz-only)
                        let displayWords = sentence.words.filter { word in
                            if word.manual == true { return false }
                            // Backward compat: multi-word phrases without timing are manual entries
                            if word.startTimeMs == nil && word.text.contains(" ") { return false }
                            return true
                        }
                        if displayWords.isEmpty {
                            Text(sentence.text)
                                .font(.title3)
                                .fontWeight(.medium)
                        } else {
                            FlowLayout(spacing: 2) {
                                ForEach(displayWords) { word in
                                    let originalIndex = sentence.words.firstIndex(where: { $0.id == word.id })
                                    WordButton(
                                        word: word,
                                        isHighlighted: playingSentenceId == sentence.id && highlightedWordIndex == originalIndex
                                    )
                                }
                            }
                        }
                    }

                    // Translation (only for sentences with audio - skip for sound effects)
                    if !isPracticeMode,
                       let translation = sentence.translation,
                       let audioUrl = sentence.audioUrl, !audioUrl.isEmpty {
                        if translationRevealed.contains(sentence.id) {
                            Text(translation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                withAnimation {
                                    translationRevealed.insert(sentence.id)
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label("Show translation", systemImage: "eye")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    // Audio controls per sentence (only if audio exists)
                    if let audioUrl = sentence.audioUrl, !audioUrl.isEmpty {
                        HStack {
                            if settingsManager.speakingPracticeMode {
                                speakingPracticeControls(for: sentence)
                            } else if settingsManager.listeningPracticeMode {
                                listeningPracticeControls(for: sentence)
                            } else {
                                normalPlaybackControls(for: sentence)
                            }

                            Spacer()

                            Menu {
                                Button("0.5x") { settingsManager.playbackSpeed = 0.5 }
                                Button("0.75x") { settingsManager.playbackSpeed = 0.75 }
                                Button("1x") { settingsManager.playbackSpeed = 1.0 }
                                Button("1.25x") { settingsManager.playbackSpeed = 1.25 }
                            } label: {
                                Text("\(settingsManager.playbackSpeed, specifier: "%.2g")x")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Show Spanish text when revealed in practice mode (with tappable words)
                    if isPracticeMode && textRevealed {
                        let revealedWords = sentence.words.filter { word in
                            if word.manual == true { return false }
                            if word.startTimeMs == nil && word.text.contains(" ") { return false }
                            return true
                        }
                        if revealedWords.isEmpty {
                            Text(sentence.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            FlowLayout(spacing: 2) {
                                ForEach(revealedWords) { word in
                                    WordButton(word: word, isHighlighted: false)
                                }
                            }
                        }
                    }

                    // Show translation when revealed in listening practice mode
                    if settingsManager.listeningPracticeMode && textRevealed {
                        if let translation = sentence.translation {
                            Text(translation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }

                    // Inline practice feedback for this sentence
                    if let feedback = practiceFeedback, feedback.sentenceId == sentence.id {
                        feedbackCard(feedback)
                    }

                    if sentence.id != bubble.sentences.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Speaking Practice Controls
    @ViewBuilder
    private func speakingPracticeControls(for sentence: Sentence) -> some View {
        let isThisRecording = recordingSentenceId == sentence.id
        Button {
            if isThisRecording {
                stopRecording(for: sentence)
            } else {
                startRecording(for: sentence)
            }
        } label: {
            Label(
                isThisRecording ? "Stop" : "Speak",
                systemImage: isThisRecording ? "stop.fill" : "mic.fill"
            )
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isThisRecording ? Color.red : Color.blue)
            .clipShape(Capsule())
        }
        .disabled(processingSentenceId != nil || (recordingSentenceId != nil && !isThisRecording))

        // Listen button to hear the sentence before speaking
        Button {
            if audioManager.isPlaying && playingSentenceId == sentence.id {
                audioManager.stop()
            } else {
                playingSentenceId = sentence.id
                playAudio(sentence.audioUrl)
            }
        } label: {
            Group {
                if audioManager.isLoading && playingSentenceId == sentence.id {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else {
                    Image(systemName: audioManager.isPlaying && playingSentenceId == sentence.id ? "stop.fill" : "speaker.wave.2.fill")
                }
            }
            .frame(width: 40, height: 40)
            .background(audioManager.isPlaying && playingSentenceId == sentence.id ? Color.red : Color.green)
            .clipShape(Circle())
            .foregroundStyle(.white)
        }
        .disabled(isThisRecording || processingSentenceId != nil)

        if processingSentenceId == sentence.id {
            ProgressView()
                .padding(.leading, 8)
        }
    }

    // MARK: - Listening Practice Controls
    @ViewBuilder
    private func listeningPracticeControls(for sentence: Sentence) -> some View {
        // Speak English meaning button
        let isThisRecording = recordingSentenceId == sentence.id
        Button {
            if isThisRecording {
                stopListeningRecording(for: sentence)
            } else {
                startRecording(for: sentence)
            }
        } label: {
            Label(
                isThisRecording ? "Stop" : "Speak",
                systemImage: isThisRecording ? "stop.fill" : "mic.fill"
            )
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isThisRecording ? Color.red : Color.blue)
            .clipShape(Capsule())
        }
        .disabled(processingSentenceId != nil || (recordingSentenceId != nil && !isThisRecording))

        // Play Spanish audio button
        Button {
            if audioManager.isPlaying && playingSentenceId == sentence.id {
                audioManager.stop()
            } else {
                playingSentenceId = sentence.id
                playAudio(sentence.audioUrl)
            }
        } label: {
            Group {
                if audioManager.isLoading && playingSentenceId == sentence.id {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else {
                    Image(systemName: audioManager.isPlaying && playingSentenceId == sentence.id ? "stop.fill" : "speaker.wave.2.fill")
                }
            }
            .frame(width: 40, height: 40)
            .background(audioManager.isPlaying && playingSentenceId == sentence.id ? Color.red : Color.green)
            .clipShape(Circle())
            .foregroundStyle(.white)
        }
        .disabled(isThisRecording || processingSentenceId != nil)

        if processingSentenceId == sentence.id {
            ProgressView()
                .padding(.leading, 8)
        }
    }

    // MARK: - Normal Playback Controls
    @ViewBuilder
    private func normalPlaybackControls(for sentence: Sentence) -> some View {
        Button {
            if audioManager.isPlaying && playingSentenceId == sentence.id {
                audioManager.stop()
            } else {
                playingSentenceId = sentence.id
                playAudio(sentence.audioUrl)
            }
        } label: {
            if audioManager.isLoading && playingSentenceId == sentence.id {
                ProgressView()
                    .tint(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.6))
                    .clipShape(Capsule())
            } else {
                Label(
                    audioManager.isPlaying && playingSentenceId == sentence.id ? "Stop" : "Play",
                    systemImage: audioManager.isPlaying && playingSentenceId == sentence.id ? "stop.fill" : "play.fill"
                )
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(audioManager.isPlaying && playingSentenceId == sentence.id ? Color.red : Color.blue)
                .clipShape(Capsule())
            }
        }
        .disabled(audioManager.isLoading && playingSentenceId == sentence.id)
    }

    // MARK: - Sound Effect Card (text only, no audio)
    private func soundEffectCard(_ bubble: Bubble) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(bubble.sentences) { sentence in
                Text(sentence.text)
                    .font(.title3)
                    .fontWeight(.bold)
                    .italic()
                    .foregroundStyle(.secondary)

                if let translation = sentence.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Feedback Card
    private func feedbackCard(_ feedback: PracticeFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(feedback.isCorrect ? .green : .red)
                Text(feedback.isCorrect ? "Correct!" : "Not quite")
                    .fontWeight(.semibold)
            }
            .font(.headline)

            if settingsManager.listeningPracticeMode {
                // Listening mode feedback: show English expected + Spanish text
                VStack(alignment: .leading, spacing: 4) {
                    if !feedback.isCorrect {
                        Text("You said: \"\(feedback.spokenText)\"")
                            .font(.subheadline)
                    }

                    HStack {
                        Text("English:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(feedback.expectedText)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    // Show the Spanish sentence with tappable words
                    Text("Spanish:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    let feedbackWords = feedback.words.filter { word in
                        if word.manual == true { return false }
                        if word.startTimeMs == nil && word.text.contains(" ") { return false }
                        return true
                    }
                    if !feedbackWords.isEmpty {
                        FlowLayout(spacing: 2) {
                            ForEach(feedbackWords) { word in
                                WordButton(word: word, isHighlighted: false)
                            }
                        }
                    }
                }
            } else if !feedback.isCorrect {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You said: \"\(feedback.spokenText)\"")
                        .font(.subheadline)

                    Text("Expected:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    let feedbackWords = feedback.words.filter { word in
                        if word.manual == true { return false }
                        if word.startTimeMs == nil && word.text.contains(" ") { return false }
                        return true
                    }
                    if feedbackWords.isEmpty {
                        Text(feedback.expectedText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 2) {
                            ForEach(feedbackWords) { word in
                                WordButton(word: word, isHighlighted: false)
                            }
                        }
                    }
                }
            } else {
                let feedbackWords = feedback.words.filter { word in
                    if word.manual == true { return false }
                    if word.startTimeMs == nil && word.text.contains(" ") { return false }
                    return true
                }
                if feedbackWords.isEmpty {
                    Text(feedback.expectedText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 2) {
                        ForEach(feedbackWords) { word in
                            WordButton(word: word, isHighlighted: false)
                        }
                    }
                }
            }

            HStack {
                Button {
                    playAudio(practiceSentence?.audioUrl)
                } label: {
                    if audioManager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("Loading...")
                            .font(.subheadline)
                    } else {
                        Label("Listen", systemImage: "speaker.wave.2.fill")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(audioManager.isLoading)

                Button {
                    practiceFeedback = nil
                } label: {
                    Label("Try Again", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(feedback.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions
    private func playAudio(_ url: String?) {
        guard let url = url else { return }
        audioManager.play(url, enableHighlighting: true)
    }

    @State private var practiceSentence: Sentence?

    private func startRecording(for sentence: Sentence) {
        practiceSentence = sentence
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await whisperService.startRecording()
            if whisperService.isRecording {
                recordingSentenceId = sentence.id
            }
        }
    }

    private func stopRecording(for sentence: Sentence) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recordingSentenceId = nil
        processingSentenceId = sentence.id

        Task {
            let expectedText = sentence.text
            let spokenText = await whisperService.stopRecording(expectedText: expectedText)

            if let error = whisperService.error, spokenText.isEmpty {
                processingSentenceId = nil
                errorMessage = error
                showingError = true
                whisperService.error = nil
                return
            }
            whisperService.error = nil

            var isCorrect = false
            var matchedText = expectedText
            var matchedAudio = sentence.audioUrl

            let (mainCorrect, _) = whisperService.compareText(spoken: spokenText, expected: expectedText)
            if mainCorrect {
                isCorrect = true
            } else if let alternatives = sentence.alternativeTexts {
                for (i, alt) in alternatives.enumerated() {
                    if whisperService.compareText(spoken: spokenText, expected: alt).isCorrect {
                        isCorrect = true
                        matchedText = alt
                        if let altAudios = sentence.alternativeAudioUrls, i < altAudios.count {
                            matchedAudio = altAudios[i]
                        }
                        break
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 300_000_000)

            processingSentenceId = nil
            practiceFeedback = PracticeFeedback(
                sentenceId: sentence.id,
                isCorrect: isCorrect,
                spokenText: spokenText.isEmpty ? "(no speech detected)" : spokenText,
                expectedText: matchedText,
                words: sentence.words
            )
            playingSentenceId = sentence.id
            playAudio(matchedAudio)
        }
    }

    // MARK: - Listening Practice Recording
    private func stopListeningRecording(for sentence: Sentence) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recordingSentenceId = nil
        processingSentenceId = sentence.id

        Task {
            let expectedTranslation = sentence.translation ?? ""
            let spokenText = await whisperService.stopRecording(
                expectedText: expectedTranslation,
                language: "en"
            )

            if let error = whisperService.error, spokenText.isEmpty {
                processingSentenceId = nil
                errorMessage = error
                showingError = true
                whisperService.error = nil
                return
            }
            whisperService.error = nil

            let isCorrect = compareEnglishMeaning(
                spoken: spokenText,
                expected: expectedTranslation
            )

            try? await Task.sleep(nanoseconds: 300_000_000)

            processingSentenceId = nil
            practiceFeedback = PracticeFeedback(
                sentenceId: sentence.id,
                isCorrect: isCorrect,
                spokenText: spokenText.isEmpty ? "(no speech detected)" : spokenText,
                expectedText: expectedTranslation,
                words: sentence.words
            )
            // Play the Spanish audio so they can hear it again
            playingSentenceId = sentence.id
            playAudio(sentence.audioUrl)
        }
    }

    // MARK: - English Meaning Comparison (lenient)
    private func compareEnglishMeaning(spoken: String, expected: String) -> Bool {
        let spokenNorm = normalizeEnglish(spoken)
        let expectedNorm = normalizeEnglish(expected)

        if spokenNorm.isEmpty { return false }
        if spokenNorm == expectedNorm { return true }

        // Contains check (handles "the house" matching "house")
        if spokenNorm.contains(expectedNorm) || expectedNorm.contains(spokenNorm) {
            return true
        }

        // Fuzzy match with relaxed threshold
        let (isMatch, matchScore) = whisperService.compareText(spoken: spokenNorm, expected: expectedNorm)
        if isMatch || matchScore >= 0.7 { return true }

        return false
    }

    private func normalizeEnglish(_ text: String) -> String {
        var result = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "'", with: "'")

        // Strip leading articles
        let articlePrefixes = ["the ", "a ", "an "]
        for prefix in articlePrefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Auto-play First Sentence
    private func autoPlayFirstSentence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let firstBubble = currentPanel.bubbles.first(where: { $0.isSoundEffect != true }),
               let firstSentence = firstBubble.sentences.first,
               let audioUrl = firstSentence.audioUrl, !audioUrl.isEmpty {
                playingSentenceId = firstSentence.id
                playAudio(firstSentence.audioUrl)
            }
        }
    }
}

// MARK: - Word Button
struct WordButton: View {
    let word: Word
    let isHighlighted: Bool
    @State private var showingDefinition = false
    @State private var isSaved = false
    @StateObject private var vocabularyManager = VocabularyManager()
    @StateObject private var audioManager = AudioManager.shared

    var body: some View {
        Button {
            showingDefinition = true
            // Check if word is already saved
            isSaved = vocabularyManager.savedWords.contains { $0.word.id == word.id }
        } label: {
            Text(word.text)
                .font(.body)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(isHighlighted ? Color.yellow.opacity(0.3) : Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDefinition) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(word.text)
                        .font(.headline)

                    Spacer()

                    // Play word audio (exact word as spoken in sentence)
                    Button {
                        if let wordAudio = word.wordAudioUrl {
                            // Use narrator's word audio
                            audioManager.play(wordAudio, volume: 1.0)
                        } else if let audioUrl = word.audioUrl {
                            // Fallback to legacy audioUrl
                            audioManager.play(audioUrl, volume: 1.0)
                        } else {
                            // Fallback to dictionary lookup by cleaned word text
                            let cleanedText = word.text
                                .lowercased()
                                .replacingOccurrences(of: "¿", with: "")
                                .replacingOccurrences(of: "?", with: "")
                                .replacingOccurrences(of: "¡", with: "")
                                .replacingOccurrences(of: "!", with: "")
                                .replacingOccurrences(of: ".", with: "")
                                .replacingOccurrences(of: ",", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let audioFile = cleanedText.folding(options: .diacriticInsensitive, locale: .current)
                            audioManager.play(audioFile, volume: 1.0)
                        }
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Text(word.meaning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let baseForm = word.baseForm, baseForm.lowercased() != word.text.lowercased() {
                    HStack {
                        Text("Base form: \(baseForm)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        // Play base form audio
                        Button {
                            if let baseFormAudio = word.baseFormAudioUrl {
                                // Use narrator's base form audio
                                audioManager.play(baseFormAudio, volume: 1.0)
                            } else {
                                // Fallback to dictionary lookup
                                let audioFile = baseForm.lowercased().folding(options: .diacriticInsensitive, locale: .current)
                                audioManager.play(audioFile, volume: 1.0)
                            }
                        } label: {
                            Image(systemName: "speaker.wave.1.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                Button {
                    if isSaved {
                        vocabularyManager.removeWord(word.id)
                        isSaved = false
                    } else {
                        vocabularyManager.saveWord(word)
                        isSaved = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Label(
                        isSaved ? "Remove from Vocabulary" : "Add to Vocabulary",
                        systemImage: isSaved ? "bookmark.slash.fill" : "bookmark.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(isSaved ? .red : .blue)
                }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .init(frame.size))
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

// MARK: - Panel Clip Shape
/// Clips an image to the panel's actual quadrilateral shape using its corner points.
/// Corners are in page-normalized coordinates (0-1); the image is the bounding-box crop,
/// so corners are remapped to local image coordinates.
struct PanelClipShape: Shape {
    let corners: [CornerPoint]

    func path(in rect: CGRect) -> Path {
        guard corners.count >= 3 else {
            return RoundedRectangle(cornerRadius: 12).path(in: rect)
        }

        // Compute the bounding box of the corners in normalized page space
        let xs = corners.map { $0.x }
        let ys = corners.map { $0.y }
        let minX = xs.min()!
        let minY = ys.min()!
        let maxX = xs.max()!
        let maxY = ys.max()!
        let bboxW = maxX - minX
        let bboxH = maxY - minY

        guard bboxW > 0, bboxH > 0 else {
            return RoundedRectangle(cornerRadius: 12).path(in: rect)
        }

        // Map each corner from page-normalized coords to local rect coords
        let localPoints = corners.map { corner in
            CGPoint(
                x: rect.minX + ((corner.x - minX) / bboxW) * rect.width,
                y: rect.minY + ((corner.y - minY) / bboxH) * rect.height
            )
        }

        var path = Path()
        path.move(to: localPoints[0])
        for i in 1..<localPoints.count {
            path.addLine(to: localPoints[i])
        }
        path.closeSubpath()
        return path
    }
}

/// A slightly irregular rectangle that mimics hand-drawn comic panel edges.
/// Uses a seeded random wobble on each edge so the shape is deterministic per panel.
struct HandDrawnRectShape: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        // Inset slightly to trim composite border pixels at edges
        let inset: CGFloat = 4
        let r = rect.insetBy(dx: inset, dy: inset)
        let wobble: CGFloat = 3  // max wobble in points

        // Simple seeded pseudo-random: hash-based, deterministic per seed + index
        func wobbleOffset(_ index: Int) -> CGFloat {
            var h = seed &* 2654435761 &+ index &* 2246822519
            h = (h ^ (h >> 13)) &* 1274126177
            h = h ^ (h >> 16)
            let normalized = CGFloat(abs(h) % 1000) / 1000.0  // 0..1
            return (normalized - 0.5) * 2 * wobble  // -wobble..+wobble
        }

        var path = Path()

        // 4 corners with slight wobble
        let tl = CGPoint(x: r.minX + wobbleOffset(0), y: r.minY + wobbleOffset(1))
        let tr = CGPoint(x: r.maxX + wobbleOffset(2), y: r.minY + wobbleOffset(3))
        let br = CGPoint(x: r.maxX + wobbleOffset(4), y: r.maxY + wobbleOffset(5))
        let bl = CGPoint(x: r.minX + wobbleOffset(6), y: r.maxY + wobbleOffset(7))

        // Draw edges with slight midpoint wobble for organic feel
        path.move(to: tl)

        // Top edge
        let topMid = CGPoint(
            x: (tl.x + tr.x) / 2 + wobbleOffset(8),
            y: (tl.y + tr.y) / 2 + wobbleOffset(9)
        )
        path.addQuadCurve(to: tr, control: topMid)

        // Right edge
        let rightMid = CGPoint(
            x: (tr.x + br.x) / 2 + wobbleOffset(10),
            y: (tr.y + br.y) / 2 + wobbleOffset(11)
        )
        path.addQuadCurve(to: br, control: rightMid)

        // Bottom edge
        let bottomMid = CGPoint(
            x: (br.x + bl.x) / 2 + wobbleOffset(12),
            y: (br.y + bl.y) / 2 + wobbleOffset(13)
        )
        path.addQuadCurve(to: bl, control: bottomMid)

        // Left edge
        let leftMid = CGPoint(
            x: (bl.x + tl.x) / 2 + wobbleOffset(14),
            y: (bl.y + tl.y) / 2 + wobbleOffset(15)
        )
        path.addQuadCurve(to: tl, control: leftMid)

        path.closeSubpath()
        return path
    }
}

#Preview {
    PanelView(
        comic: ComicData.allComics[0],
        page: ComicData.allComics[0].pages[0],
        panel: ComicData.allComics[0].pages[0].panels[0],
        hotspots: ComicData.allComics[0].pages[0].hotspots ?? [],
        navigateToPage: .constant(nil)
    )
    .environmentObject(SettingsManager())
}
