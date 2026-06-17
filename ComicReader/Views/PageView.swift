import SwiftUI

struct PageView: View {
    let comic: Comic
    let page: Page
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

    init(comic: Comic, page: Page) {
        self.comic = comic
        self.page = page
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
            showEndOfEpisode = true
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            currentPageIndex += 1
            textRevealed = false
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
                // Page image
                let imageName = settingsManager.speakingPracticeMode && !textRevealed
                    ? (currentPage.noTextImage ?? currentPage.masterImage)
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
                                if settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode {
                                    // Practice modes keep the per-panel tap-to-reveal flow.
                                    ForEach(currentPage.panels.sorted { $0.panelOrder < $1.panelOrder }) { panel in
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(width: panel.tapZoneWidth * rect.width,
                                                   height: panel.tapZoneHeight * rect.height)
                                            .position(x: rect.minX + (panel.tapZoneX + panel.tapZoneWidth / 2) * rect.width,
                                                      y: rect.minY + (panel.tapZoneY + panel.tapZoneHeight / 2) * rect.height)
                                            .onTapGesture {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                withAnimation { selectedPanel = panel }
                                            }
                                    }
                                } else {
                                    // Normal reading: one tap target per text bubble, padded a
                                    // little so they're easy to hit.
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
                    }
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
            // Save progress when view appears
            progressManager.saveProgress(
                comicId: comic.id,
                pageNumber: currentPage.pageNumber,
                panelNumber: 0
            )
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
        .alert("End of Episode", isPresented: $showEndOfEpisode) {
            Button("Back to home page") {
                dismiss()
            }
            Button("Stay", role: .cancel) { }
        } message: {
            Text("You've reached the last page of this episode.")
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

/// A single bubble's reading content — tappable words, show/hide translation,
/// explain/close grammar, and audio playback with word highlighting. Mirrors the
/// normal-reading parts of PanelView's bubble card but is self-contained so it
/// can be shown in a bottom sheet anchored to one bubble. (If we keep this, the
/// next step is to have PanelView reuse it instead of duplicating.)
struct BubbleContentView: View {
    let comic: Comic
    let bubble: Bubble
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var audioManager = AudioManager.shared

    @State private var translationRevealed: Set<String> = []
    @State private var grammarRevealed: Set<String> = []
    @State private var playingSentenceId: String?
    @State private var highlightedWordIndex: Int?

    private var playingSentence: Sentence? {
        guard let id = playingSentenceId else { return nil }
        return bubble.sentences.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(bubble.sentences) { sentence in
                VStack(alignment: .leading, spacing: 8) {
                    sentenceText(sentence)
                    translationRow(sentence)
                    grammarRow(sentence)
                    audioRow(sentence)
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
        .onAppear { audioManager.setPlaybackRate(Float(settingsManager.playbackSpeed)) }
        .onDisappear { audioManager.stop() }
    }

    @ViewBuilder
    private func sentenceText(_ sentence: Sentence) -> some View {
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
                        isHighlighted: playingSentenceId == sentence.id && highlightedWordIndex == originalIndex,
                        fontSize: bubble.fontSize.map { CGFloat($0) }
                    )
                    // In help mode, highlight every word so it's clear they're
                    // tappable; a tap then explains (rather than opening) the word.
                    .explains("Tap a word",
                              "Tap any word to see its meaning and base form, hear it spoken, and save it to your vocabulary.",
                              id: "bubbleword.\(word.id)")
                }
            }
        }
    }

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

    @ViewBuilder
    private func audioRow(_ sentence: Sentence) -> some View {
        if let audioUrl = sentence.audioUrl, !audioUrl.isEmpty {
            HStack {
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
                Spacer()
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
        }
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
