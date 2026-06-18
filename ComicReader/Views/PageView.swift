import SwiftUI

struct PageView: View {
    let comic: Comic
    let page: Page
    /// When true, this is a guided "On Screen" practice run: speaking practice
    /// through the whole comic, then listening practice through the whole comic.
    var guidedOnScreenPractice: Bool = false
    /// Called when the reader taps "Practice" at the end of the episode — the
    /// detail screen uses it to open the practice options once this view pops.
    var onRequestPractice: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var progressManager: ReadingProgressManager

    @State private var textRevealed = false
    @State private var selectedPanel: Panel?
    @State private var currentPageIndex: Int
    @State private var navigateToPage: Int?
    @State private var showingVocabulary = false
    @State private var showingSettings = false
    @State private var showEndOfEpisode = false
    @State private var showSpeakingDonePrompt = false   // guided: speaking → listening
    @State private var showOnScreenComplete = false     // guided: all done
    @State private var selectedBubbleIndex: Int?   // open bubble in the floating card
    @State private var pageImageAspect: CGFloat?   // width/height of the page artwork
    @StateObject private var help = HelpModeController()

    // Pages sorted by pageNumber for consistent navigation
    private var sortedPages: [Page] {
        comic.pages.sorted { $0.pageNumber < $1.pageNumber }
    }

    // Text-bearing bubbles on the current page, in reading order (panel order,
    // then the bubble order within each panel). These are the tap targets for the
    // per-bubble reading sheet; sound effects and image bubbles are excluded.
    private var pageTextBubbles: [Bubble] {
        currentPage.panels
            .sorted { $0.panelOrder < $1.panelOrder }
            .flatMap { $0.bubbles }
            .filter { $0.isSoundEffect != true && $0.type != .image && !$0.sentences.isEmpty }
    }

    private var isPracticeMode: Bool {
        settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
    }

    init(comic: Comic, page: Page, guidedOnScreenPractice: Bool = false, onRequestPractice: (() -> Void)? = nil) {
        self.comic = comic
        self.page = page
        self.guidedOnScreenPractice = guidedOnScreenPractice
        self.onRequestPractice = onRequestPractice
        // Initialize currentPageIndex to the correct page in sorted order
        let sorted = comic.pages.sorted { $0.pageNumber < $1.pageNumber }
        let index = sorted.firstIndex(where: { $0.id == page.id }) ?? 0
        _currentPageIndex = State(initialValue: index)
    }

    var currentPage: Page {
        sortedPages[currentPageIndex]
    }

    // The rectangle the aspect-fit page image actually occupies inside `size`
    // (centered, with letterbox bars excluded). Used to place tap targets so they
    // line up with the artwork rather than the full container.
    private func fittedImageRect(in size: CGSize) -> CGRect {
        guard let aspect = pageImageAspect, aspect > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        if size.width / size.height > aspect {
            let h = size.height, w = h * aspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: h)
        } else {
            let w = size.width, h = w / aspect
            return CGRect(x: 0, y: (size.height - h) / 2, width: w, height: h)
        }
    }

    private func loadPageAspect() {
        let name = currentPage.masterImage
        let comicId = comic.id
        Task.detached {
            let size = ComicImageLoader.shared.loadImage(named: name, forComic: comicId)?.size
            if let size, size.height > 0 {
                let aspect = size.width / size.height
                await MainActor.run { pageImageAspect = aspect }
            }
        }
    }

    private func goToNextPage() {
        guard currentPageIndex < sortedPages.count - 1 else {
            if guidedOnScreenPractice {
                handleGuidedEnd()
            } else {
                showEndOfEpisode = true
            }
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            currentPageIndex += 1
            textRevealed = false
        }
    }

    // MARK: - Guided "On Screen" practice (speaking → listening)

    /// Reached the end of the comic during a guided run. After speaking practice,
    /// offer to start listening practice; after listening, the run is complete.
    private func handleGuidedEnd() {
        if settingsManager.speakingPracticeMode {
            showSpeakingDonePrompt = true
        } else {
            showOnScreenComplete = true
        }
    }

    private func startListeningPhase() {
        settingsManager.speakingPracticeMode = false
        settingsManager.listeningPracticeMode = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation {
            currentPageIndex = 0
            textRevealed = false
        }
    }

    private func finishGuidedPractice() {
        settingsManager.speakingPracticeMode = false
        settingsManager.listeningPracticeMode = false
        dismiss()
    }

    // End-of-episode prompt: nudges toward practice, but with an ✕ (and tap-outside)
    // to dismiss and stay on the last page. Kept out of `body` to keep it compiling.
    @ViewBuilder
    private var endOfEpisodeOverlay: some View {
        if showEndOfEpisode {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showEndOfEpisode = false } }

                VStack(spacing: 16) {
                    Text("End of Episode")
                        .font(.headline)
                    Text("You've reached the end. Ready to practice?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showEndOfEpisode = false
                        onRequestPractice?()
                        dismiss()
                    } label: {
                        Text("Practice")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
                .frame(maxWidth: 300)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation { showEndOfEpisode = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                    .accessibilityLabel("Close")
                }
                .shadow(radius: 20)
                .padding(.horizontal, 40)
            }
            .transition(.opacity)
            .zIndex(3)
        }
    }

    private func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            currentPageIndex -= 1
            textRevealed = false
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                // Page image. In practice modes show the empty-bubbles art (bubbles
                // visible, text blank) so they're tappable; fall back to the no-text
                // art, then the full page, for comics baked before that existed.
                let imageName = isPracticeMode
                    ? (currentPage.emptyBubblesImage ?? currentPage.noTextImage ?? currentPage.masterImage)
                    : currentPage.masterImage

                ComicImage(imageName: imageName, comicId: comic.id)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay {
                        // Tap targets, mapped into the actual aspect-fit image rect
                        // (so they line up with the artwork, not the letterbox bars).
                        GeometryReader { imageGeometry in
                            let rect = fittedImageRect(in: imageGeometry.size)
                            ZStack {
                                // One tap target per text bubble. Opens the floating
                                // card — the same interaction for normal reading and
                                // for practice (the card shows practice controls when
                                // a practice mode is on).
                                ForEach(Array(pageTextBubbles.enumerated()), id: \.element.id) { i, b in
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .frame(width: b.width * rect.width + 16,
                                               height: b.height * rect.height + 16)
                                        .position(x: rect.minX + (b.positionX + b.width / 2) * rect.width,
                                                  y: rect.minY + (b.positionY + b.height / 2) * rect.height)
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            selectedBubbleIndex = i
                                        }
                                }
                            }
                        }
                    }
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            let horizontalDistance = value.translation.width
                            if horizontalDistance > 50 {
                                // Swiped right → previous page
                                goToPreviousPage()
                            } else if horizontalDistance < -50 {
                                // Swiped left → next page
                                goToNextPage()
                            }
                        }
                )
            }

            // Help hints over the page (help mode only, while nothing is open)
            if selectedPanel == nil && selectedBubbleIndex == nil {
                VStack(spacing: 10) {
                    Spacer()
                    HelpHint(icon: "hand.tap.fill", label: "Tap a bubble",
                             title: "Open a speech bubble",
                             text: "Tap any speech or narration bubble to open its text, translation, grammar and audio — the page stays visible above.")
                    HelpHint(icon: "arrow.left.and.right", label: "Swipe",
                             title: "Turn the page",
                             text: "Swipe left or right anywhere on the page — or use the arrows at the top — to move between pages.",
                             animatedSwipe: true)
                }
                .padding(.bottom, 60)
            }

            // Panel view overlay — presented on top of the page instead of as a sheet
            // to avoid iOS sheet presentation scaling the underlying page view
            if let panel = selectedPanel {
                PanelView(
                    comic: comic,
                    page: currentPage,
                    panel: panel,
                    hotspots: currentPage.hotspots ?? [],
                    navigateToPage: $navigateToPage,
                    dismissPanel: {
                        // Remove the overlay without animation — an interrupted
                        // removal transition can leave the page layout stuck
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            selectedPanel = nil
                        }
                    },
                    dismissToHome: {
                        dismiss()
                    },
                    guidedOnScreenPractice: guidedOnScreenPractice,
                    onGuidedEnd: { handleGuidedEnd() }
                )
                .environmentObject(settingsManager)
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }

            // Floating, draggable card showing one bubble's content (normal reading).
            // Lives over the page so the artwork stays visible; drag its header to
            // move it out of the way.
            if let idx = selectedBubbleIndex, pageTextBubbles.indices.contains(idx) {
                FloatingBubbleCard(
                    comic: comic,
                    bubbles: pageTextBubbles,
                    index: Binding(
                        get: { selectedBubbleIndex ?? 0 },
                        set: { selectedBubbleIndex = $0 }
                    ),
                    onClose: { selectedBubbleIndex = nil }
                )
                .environmentObject(settingsManager)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(2)
            }

            endOfEpisodeOverlay
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Only show the page controls while the panel overlay is closed —
            // the panel's own toolbar items (home/Done/panel nav) render into
            // the same bar, so showing both sets duplicates the buttons
            if selectedPanel == nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "house.fill")
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 20) {
                        Button {
                            goToPreviousPage()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(currentPageIndex > 0 ? .white : .gray)
                        }
                        .disabled(currentPageIndex == 0)

                        Text("\(currentPage.pageNumber) / \(sortedPages.count)")
                            .foregroundStyle(.white)

                        Button {
                            goToNextPage()
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(currentPageIndex < sortedPages.count - 1 ? .white : .gray)
                        }
                        .disabled(currentPageIndex >= sortedPages.count - 1)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
                        } label: {
                            Image(systemName: help.isActive ? "questionmark.circle.fill" : "questionmark.circle")
                                .foregroundStyle(.white)
                        }
                        Button {
                            showingVocabulary = true
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(.white)
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .helpTooltipLayer()
        .environmentObject(help)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .onAppear {
            loadPageAspect()
            // Guided run starts in speaking practice (safety net if not already set).
            if guidedOnScreenPractice && !settingsManager.speakingPracticeMode && !settingsManager.listeningPracticeMode {
                settingsManager.speakingPracticeMode = true
            }
            // Save progress when view appears
            progressManager.saveProgress(
                comicId: comic.id,
                pageNumber: currentPage.pageNumber,
                panelNumber: 0
            )
        }
        .onDisappear {
            // Leaving a guided run (finished or backed out) returns the comic to
            // normal reading — don't leave a practice mode stuck on.
            if guidedOnScreenPractice {
                settingsManager.speakingPracticeMode = false
                settingsManager.listeningPracticeMode = false
            }
        }
        .onChange(of: currentPageIndex) { _, _ in
            // Close the bubble card and refresh the artwork aspect for the new page
            selectedBubbleIndex = nil
            loadPageAspect()
            // Save progress when page changes
            progressManager.saveProgress(
                comicId: comic.id,
                pageNumber: currentPage.pageNumber,
                panelNumber: 0
            )
        }
        .onChange(of: navigateToPage) { _, newPageIndex in
            guard let newPageIndex = newPageIndex else { return }
            // Cross-page navigation from the panel view: close the overlay and
            // swap the page in a single transaction with animations disabled.
            // Running the overlay's removal transition and the page change as
            // concurrent animations can wedge the layout mid-flight, leaving
            // the page rendered small and unresponsive.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedPanel = nil
                currentPageIndex = newPageIndex
                textRevealed = false
            }
            navigateToPage = nil
        }
        .sheet(isPresented: $showingVocabulary) {
            NavigationStack {
                VocabularyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showingVocabulary = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .environmentObject(settingsManager)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
        .alert("Speaking practice complete", isPresented: $showSpeakingDonePrompt) {
            Button("Start listening practice") { startListeningPhase() }
            Button("Finish", role: .cancel) { finishGuidedPractice() }
        } message: {
            Text("Now go through the comic again — listen to each sentence and recall its meaning.")
        }
        .alert("Practice complete", isPresented: $showOnScreenComplete) {
            Button("Done") { finishGuidedPractice() }
        } message: {
            Text("You've finished speaking and listening practice for this comic. ¡Bien hecho!")
        }
        .background(DisableInteractivePopGesture())
    }
}

// Disables the enclosing UINavigationController's interactive pop (edge swipe-back)
// gesture while this view is on screen, restoring it when the view goes away.
// A rightward swipe (e.g. "previous panel/page") can otherwise be captured by the
// swipe-back recognizer, starting an interactive pop that gets cancelled mid-flight
// and leaves the view stuck small and unresponsive.
struct DisableInteractivePopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        private weak var navController: UINavigationController?
        private var previousState = true

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Walk the responder chain to find the enclosing navigation controller
            var responder: UIResponder? = view
            while let current = responder {
                if let nav = current as? UINavigationController {
                    navController = nav
                    break
                }
                if let vc = current as? UIViewController, let nav = vc.navigationController {
                    navController = nav
                    break
                }
                responder = current.next
            }
            if let gesture = navController?.interactivePopGestureRecognizer {
                previousState = gesture.isEnabled
                gesture.isEnabled = false
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navController?.interactivePopGestureRecognizer?.isEnabled = previousState
        }
    }
}

// MARK: - Per-bubble content + sheet (on-page reading, one bubble at a time)

private struct BubblePracticeFeedback {
    let sentenceId: String
    let isCorrect: Bool
    let spokenText: String
    let expectedText: String
    let words: [Word]
}

/// A single bubble's content for the floating card. Handles normal reading
/// (tappable words, translation, grammar, audio) AND practice modes (speaking:
/// say the Spanish from the English prompt; listening: recall the meaning) — so
/// the floating card is the single surface for both, mirroring PanelView's bubble
/// card. (If kept, the cleanup is to have PanelView reuse this.)
struct BubbleContentView: View {
    let comic: Comic
    let bubble: Bubble
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var whisperService = WhisperService.shared

    @State private var translationRevealed: Set<String> = []
    @State private var grammarRevealed: Set<String> = []
    @State private var textRevealed = false
    @State private var playingSentenceId: String?
    @State private var highlightedWordIndex: Int?
    @State private var recordingSentenceId: String?
    @State private var processingSentenceId: String?
    @State private var practiceFeedback: BubblePracticeFeedback?
    @State private var practiceSentence: Sentence?
    @State private var showingError = false
    @State private var errorMessage = ""

    private var isPracticeMode: Bool {
        settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
    }

    private var playingSentence: Sentence? {
        guard let id = playingSentenceId else { return nil }
        return bubble.sentences.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(bubble.sentences) { sentence in
                VStack(alignment: .leading, spacing: 8) {
                    mainText(sentence)
                    if !isPracticeMode {
                        translationRow(sentence)
                        grammarRow(sentence)
                    }
                    audioRow(sentence)
                    revealedContent(sentence)
                    if let fb = practiceFeedback, fb.sentenceId == sentence.id {
                        feedbackCard(fb)
                    }
                    if sentence.id != bubble.sentences.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: audioManager.currentTime) { _, _ in
            if audioManager.isSentencePlayback, let s = playingSentence {
                highlightedWordIndex = audioManager.currentWordIndex(for: s.words)
            }
        }
        .onChange(of: audioManager.isPlaying) { _, isPlaying in
            if !isPlaying { highlightedWordIndex = nil; playingSentenceId = nil }
        }
        .onChange(of: settingsManager.playbackSpeed) { _, s in
            audioManager.setPlaybackRate(Float(s))
        }
        .onChange(of: whisperService.error) { _, newError in
            if let error = newError, whisperService.transcribedText.isEmpty {
                recordingSentenceId = nil
                processingSentenceId = nil
                errorMessage = error
                showingError = true
                whisperService.error = nil
            }
        }
        .onAppear {
            audioManager.setPlaybackRate(Float(settingsManager.playbackSpeed))
            // In listening mode, auto-play the first sentence so the learner has
            // something to recall the meaning of.
            if settingsManager.listeningPracticeMode,
               let first = bubble.sentences.first, let url = first.audioUrl, !url.isEmpty {
                playingSentenceId = first.id
                audioManager.play(url, enableHighlighting: true)
            }
        }
        .onDisappear {
            audioManager.stop()
            whisperService.cancelRecording()
        }
        .alert("Speech Recognition Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
    }

    // MARK: Main line (prompt differs per mode)

    @ViewBuilder
    private func mainText(_ sentence: Sentence) -> some View {
        if settingsManager.speakingPracticeMode {
            Text(sentence.translation ?? "")
                .font(.title3).fontWeight(.medium)
        } else if settingsManager.listeningPracticeMode {
            Text("What is the English meaning?")
                .font(.subheadline).foregroundStyle(.secondary).italic()
        } else {
            wordsLine(sentence, highlight: true)
        }
    }

    @ViewBuilder
    private func wordsLine(_ sentence: Sentence, highlight: Bool) -> some View {
        let displayWords = sentence.words.filter { word in
            if word.manual == true { return false }
            if word.startTimeMs == nil && word.text.contains(" ") { return false }
            return true
        }
        let textFont: Font = bubble.fontSize.map { .system(size: CGFloat($0)) } ?? .title3
        if displayWords.isEmpty {
            Text(sentence.text).font(textFont).fontWeight(.medium)
        } else {
            FlowLayout(spacing: 2) {
                ForEach(displayWords) { word in
                    let originalIndex = sentence.words.firstIndex(where: { $0.id == word.id })
                    WordButton(
                        word: word,
                        isHighlighted: highlight && playingSentenceId == sentence.id && highlightedWordIndex == originalIndex,
                        fontSize: bubble.fontSize.map { CGFloat($0) }
                    )
                    .explains("Tap a word",
                              "Tap any word to see its meaning and base form, hear it spoken, and save it to your vocabulary.",
                              id: "bubbleword.\(word.id)")
                }
            }
        }
    }

    // MARK: Normal-mode rows

    @ViewBuilder
    private func translationRow(_ sentence: Sentence) -> some View {
        if let translation = sentence.translation,
           let audioUrl = sentence.audioUrl, !audioUrl.isEmpty {
            if translationRevealed.contains(sentence.id) {
                Text(translation).font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button {
                    withAnimation { translationRevealed.insert(sentence.id) }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Show translation", systemImage: "eye").font(.subheadline).foregroundStyle(.blue)
                }
            }
        }
    }

    @ViewBuilder
    private func grammarRow(_ sentence: Sentence) -> some View {
        if let note = sentence.grammarNote, !note.isEmpty {
            if grammarRevealed.contains(sentence.id) {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation { grammarRevealed.remove(sentence.id) }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.purple.opacity(0.6))
                                .padding(6)
                        }
                        .accessibilityLabel("Close grammar note")
                    }
            } else {
                Button {
                    withAnimation { grammarRevealed.insert(sentence.id) }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Explain grammar", systemImage: "text.book.closed").font(.subheadline).foregroundStyle(.purple)
                }
            }
        }
    }

    // MARK: Audio / practice controls

    @ViewBuilder
    private func audioRow(_ sentence: Sentence) -> some View {
        if let audioUrl = sentence.audioUrl, !audioUrl.isEmpty {
            HStack(spacing: 10) {
                if settingsManager.speakingPracticeMode {
                    micButton(sentence, listening: false)
                    listenButton(sentence)
                } else if settingsManager.listeningPracticeMode {
                    micButton(sentence, listening: true)
                    listenButton(sentence)
                } else {
                    playButton(sentence, audioUrl: audioUrl)
                }
                if processingSentenceId == sentence.id { ProgressView() }
                Spacer()
                speedMenu
            }
        }
    }

    private var speedMenu: some View {
        Menu {
            Button("0.5x") { settingsManager.playbackSpeed = 0.5 }
            Button("0.75x") { settingsManager.playbackSpeed = 0.75 }
            Button("1x") { settingsManager.playbackSpeed = 1.0 }
            Button("1.25x") { settingsManager.playbackSpeed = 1.25 }
        } label: {
            Text("\(settingsManager.playbackSpeed, specifier: "%.2g")x")
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.systemGray5)).clipShape(Capsule())
        }
    }

    private func playButton(_ sentence: Sentence, audioUrl: String) -> some View {
        Button {
            if audioManager.isPlaying && playingSentenceId == sentence.id {
                audioManager.stop()
            } else {
                playingSentenceId = sentence.id
                audioManager.play(audioUrl, enableHighlighting: true)
            }
        } label: {
            let isThis = audioManager.isPlaying && playingSentenceId == sentence.id
            Label(isThis ? "Stop" : "Play", systemImage: isThis ? "stop.fill" : "play.fill")
                .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(isThis ? Color.red : Color.blue)
                .clipShape(Capsule())
        }
    }

    private func micButton(_ sentence: Sentence, listening: Bool) -> some View {
        let isThisRecording = recordingSentenceId == sentence.id
        return Button {
            if isThisRecording {
                if listening { stopListeningRecording(for: sentence) } else { stopRecording(for: sentence) }
            } else {
                startRecording(for: sentence)
            }
        } label: {
            Label(isThisRecording ? "Stop" : "Speak", systemImage: isThisRecording ? "stop.fill" : "mic.fill")
                .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(isThisRecording ? Color.red : Color.blue)
                .clipShape(Capsule())
        }
        .disabled(processingSentenceId != nil || (recordingSentenceId != nil && !isThisRecording))
    }

    private func listenButton(_ sentence: Sentence) -> some View {
        let isThis = audioManager.isPlaying && playingSentenceId == sentence.id
        return Button {
            if isThis {
                audioManager.stop()
            } else {
                playingSentenceId = sentence.id
                playAudio(sentence.audioUrl)
            }
        } label: {
            Image(systemName: isThis ? "stop.fill" : "speaker.wave.2.fill")
                .frame(width: 40, height: 40)
                .background(isThis ? Color.red : Color.green)
                .clipShape(Circle())
                .foregroundStyle(.white)
        }
        .disabled(recordingSentenceId == sentence.id || processingSentenceId != nil)
    }

    // MARK: Revealed text (practice modes)

    @ViewBuilder
    private func revealedContent(_ sentence: Sentence) -> some View {
        if isPracticeMode {
            if textRevealed {
                if settingsManager.listeningPracticeMode, let translation = sentence.translation {
                    Text(translation).font(.subheadline).foregroundStyle(.secondary).italic()
                }
                wordsLine(sentence, highlight: false)
                Button {
                    withAnimation { textRevealed = false }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Hide", systemImage: "eye.slash").font(.subheadline).foregroundStyle(.blue)
                }
            } else {
                Button {
                    withAnimation { textRevealed = true }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Reveal", systemImage: "eye").font(.subheadline).foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: Feedback

    private func feedbackCard(_ feedback: BubblePracticeFeedback) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(feedback.isCorrect ? .green : .red)
                Text(feedback.isCorrect ? "Correct!" : "Not quite").fontWeight(.semibold)
            }
            .font(.headline)

            if !feedback.isCorrect {
                Text("You said: \"\(feedback.spokenText)\"").font(.subheadline)
            }
            Text(settingsManager.listeningPracticeMode ? "Meaning: \(feedback.expectedText)" : "Expected: \(feedback.expectedText)")
                .font(.subheadline).foregroundStyle(.secondary)

            HStack {
                Button { playAudio(practiceSentence?.audioUrl) } label: {
                    Label("Listen", systemImage: "speaker.wave.2.fill").font(.subheadline)
                }
                .buttonStyle(.bordered)
                Button { practiceFeedback = nil } label: {
                    Label("Try Again", systemImage: "arrow.counterclockwise").font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(feedback.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Actions

    private func playAudio(_ url: String?) {
        guard let url else { return }
        audioManager.play(url, enableHighlighting: true)
    }

    private func startRecording(for sentence: Sentence) {
        practiceSentence = sentence
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await whisperService.startRecording()
            if whisperService.isRecording { recordingSentenceId = sentence.id }
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
                errorMessage = error; showingError = true; whisperService.error = nil
                return
            }
            whisperService.error = nil
            let (isCorrect, _) = whisperService.compareText(spoken: spokenText, expected: expectedText)
            try? await Task.sleep(nanoseconds: 300_000_000)
            processingSentenceId = nil
            practiceFeedback = BubblePracticeFeedback(
                sentenceId: sentence.id, isCorrect: isCorrect,
                spokenText: spokenText.isEmpty ? "(no speech detected)" : spokenText,
                expectedText: expectedText, words: sentence.words)
            playingSentenceId = sentence.id
            playAudio(sentence.audioUrl)
        }
    }

    private func stopListeningRecording(for sentence: Sentence) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recordingSentenceId = nil
        processingSentenceId = sentence.id
        Task {
            let expected = sentence.translation ?? ""
            let spokenText = await whisperService.stopRecording(expectedText: expected, language: "en")
            if let error = whisperService.error, spokenText.isEmpty {
                processingSentenceId = nil
                errorMessage = error; showingError = true; whisperService.error = nil
                return
            }
            whisperService.error = nil
            let isCorrect = compareEnglishMeaning(spoken: spokenText, expected: expected)
            try? await Task.sleep(nanoseconds: 300_000_000)
            processingSentenceId = nil
            practiceFeedback = BubblePracticeFeedback(
                sentenceId: sentence.id, isCorrect: isCorrect,
                spokenText: spokenText.isEmpty ? "(no speech detected)" : spokenText,
                expectedText: expected, words: sentence.words)
            playingSentenceId = sentence.id
            playAudio(sentence.audioUrl)
        }
    }

    private func compareEnglishMeaning(spoken: String, expected: String) -> Bool {
        let s = normalizeEnglish(spoken), e = normalizeEnglish(expected)
        if s.isEmpty { return false }
        if s == e || s.contains(e) || e.contains(s) { return true }
        let (isMatch, score) = whisperService.compareText(spoken: s, expected: e)
        return isMatch || score >= 0.7
    }

    private func normalizeEnglish(_ text: String) -> String {
        var result = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
        for prefix in ["the ", "a ", "an "] where result.hasPrefix(prefix) {
            result = String(result.dropFirst(prefix.count))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A floating, draggable card showing one bubble's content at a time, with a
/// stepper to move through the page's bubbles. Drag the header to reposition it
/// anywhere over the page; sits near the bottom by default so the artwork above
/// stays visible.
struct FloatingBubbleCard: View {
    let comic: Comic
    let bubbles: [Bubble]
    @Binding var index: Int
    var onClose: () -> Void
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var offset: CGSize = .zero
    @State private var accumulated: CGSize = .zero

    var body: some View {
        card
            .frame(maxWidth: 380)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 12)
            .padding(.bottom, 30)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                if bubbles.indices.contains(index) {
                    BubbleContentView(comic: comic, bubble: bubbles[index])
                        .id(bubbles[index].id)   // reset per-bubble state when stepping
                        .padding(14)
                }
            }
            .frame(maxHeight: 340)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }

    // Drag this bar to move the whole card around the page.
    private var header: some View {
        HStack(spacing: 12) {
            Button { if index > 0 { withAnimation { index -= 1 } } } label: {
                Image(systemName: "chevron.left.circle.fill").font(.title3)
            }
            .disabled(index <= 0)

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("\(index + 1) of \(bubbles.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button { if index < bubbles.count - 1 { withAnimation { index += 1 } } } label: {
                Image(systemName: "chevron.right.circle.fill").font(.title3)
            }
            .disabled(index >= bubbles.count - 1)

            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { v in
                    offset = CGSize(width: accumulated.width + v.translation.width,
                                    height: accumulated.height + v.translation.height)
                }
                .onEnded { _ in accumulated = offset }
        )
    }
}

#Preview {
    NavigationStack {
        PageView(comic: ComicData.allComics[0], page: ComicData.allComics[0].pages[0])
            .environmentObject(SettingsManager())
            .environmentObject(ReadingProgressManager())
    }
}
