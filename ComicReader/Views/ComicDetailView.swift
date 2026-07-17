import SwiftUI

enum PracticeDestination: Hashable {
    case quiz
    case speaking
    case listening
    case repeatPractice
    case translateSpeak   // reverse Listen & speak: hear English, answer in Spanish
    case repeatListen
    case originListen
    case flowPractice

    // Stable string used to persist/restore the last-used practice mode.
    var modeKey: String {
        switch self {
        case .quiz: return "quiz"
        case .speaking: return "speaking"
        case .listening: return "listening"
        case .repeatPractice: return "repeatPractice"
        case .translateSpeak: return "translateSpeak"
        case .repeatListen: return "repeatListen"
        case .originListen: return "originListen"
        case .flowPractice: return "flowPractice"
        }
    }

    init?(modeKey: String) {
        switch modeKey {
        case "quiz": self = .quiz
        case "speaking": self = .speaking
        case "listening": self = .listening
        case "repeatPractice": self = .repeatPractice
        case "translateSpeak": self = .translateSpeak
        case "repeatListen": self = .repeatListen
        case "originListen": self = .originListen
        case "flowPractice": self = .flowPractice
        default: return nil
        }
    }
}

struct ComicDetailView: View {
    let comic: Comic
    /// When true (e.g. opened from the Library "Continue" card), immediately
    /// resume reading/practice exactly like tapping the primary button here.
    var autoResume: Bool = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var progressManager: ReadingProgressManager
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var localStorage = LocalComicStorage.shared

    @State private var didAutoResume = false
    @State private var practiceDestination: PracticeDestination?
    @State private var selectedPage: Page?
    @State private var showingDeleteConfirmation = false
    @State private var showingPracticeHelp = false
    @State private var showPracticeOptions = false
    @State private var showingDrillChooser = false
    @State private var showingListenSpeakChooser = false   // Listen & speak: direction picker
    @State private var guidedOnScreen = false   // next PageView push is a guided practice run
    @State private var pendingBubbleId: String? = nil   // bubble to resume the guided run at
    @State private var openPracticeAfterReading = false  // end-of-episode "Practice" tapped
    @State private var practiceFromEnd = false  // popup came from the episode end → modes start from the beginning
    @State private var scrollTopToken = 0                 // bump to scroll the page to the top
    @StateObject private var help = HelpModeController()

    // First-visit onboarding callouts for this "comic cockpit" screen. `cockpitStep`
    // walks a short sequence (0 = none). Gated once-only by `seenCockpitTips`, unless
    // HelpDebug.forceShowTooltips is on.
    @AppStorage("help.seen.comic-cockpit") private var seenCockpitTips = false
    @State private var cockpitStep = 0
    // True while "?" is replaying the sequence — bypasses the "seen" flag.
    @State private var helpReplay = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    // body is split in two (navigation/practice plumbing here, dialogs + callouts
    // in `body`) — as ONE modifier chain the type-checker gives up on it.
    private var coreContent: some View {
        scrollContent
            .overlay { practiceOptionsOverlay }
            .navigationTitle("")   // shown in the header instead — avoid duplicate
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    navBarCollectionTitle
                }
                ToolbarItem(placement: .topBarTrailing) {
                    trailingToolbar
                }
            }
            .alert("Delete Comic", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    localStorage.deleteComic(comic.id)
                    progressManager.clearProgress(for: comic.id)
                    dismiss()
                }
            } message: {
                Text("Delete \"\(comic.title)\"? This will remove it from your device. You can re-download it later.")
            }
            .navigationDestination(item: $practiceDestination) { destinationView($0) }
            .onChange(of: practiceDestination) { _, newValue in
                if let dest = newValue {
                    // Coming from the episode-end "Practice" button: they just finished
                    // reading, so the mode starts from the beginning, not the saved spot.
                    if practiceFromEnd {
                        progressManager.clearPracticePosition(for: comic.id)
                        progressManager.clearWordPosition(for: comic.id)
                        progressManager.clearPracticeBubble(for: comic.id)
                    }
                    // Launching practice counts as interacting → Library "Continue";
                    // remember the mode (for Restart/Continue) and close the popup.
                    progressManager.touchProgress(comicId: comic.id)
                    progressManager.setPracticeMode(comic.id, mode: dest.modeKey)
                    showPracticeOptions = false
                }
            }
            .onChange(of: showPracticeOptions) { _, open in
                // Popup gone (mode chosen or dismissed) → back to normal resume behaviour.
                if !open { practiceFromEnd = false }
            }
            .navigationDestination(item: $selectedPage) { page in
                PageView(comic: comic, page: page, guidedOnScreenPractice: guidedOnScreen,
                         onRequestPractice: { openPracticeAfterReading = true },
                         initialBubbleId: pendingBubbleId)
                    .id(page.id)  // Force new view instance for each page
            }
            .onChange(of: selectedPage) { _, newValue in
                // Once the page view is dismissed, the next open is a normal read again.
                if newValue == nil {
                    guidedOnScreen = false
                    // If they tapped "Practice" at the end of the episode, open the
                    // practice popup once the page view has finished popping.
                    if openPracticeAfterReading {
                        openPracticeAfterReading = false
                        practiceFromEnd = true   // whatever mode they pick starts from the beginning
                        scrollTopToken += 1   // jump the home page back to the top
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.2)) { showPracticeOptions = true }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPracticeHelp) {
                PracticeModesHelpView()
            }
    }

    var body: some View {
        coreContent
            .confirmationDialog("Drill the key words", isPresented: $showingDrillChooser, titleVisibility: .visible) {
                drillChooserButtons
            }
            .confirmationDialog("Listen & speak", isPresented: $showingListenSpeakChooser, titleVisibility: .visible) {
                listenSpeakChooserButtons
            } message: {
                Text("Hear the Spanish, repeat it and give the meaning — or hear the English and answer in Spanish.")
            }
            .helpTooltipLayer()
            .environmentObject(help)
            .anchoredCallout(
                targetID: cockpitTarget,
                text: cockpitText,
                icon: nil,
                showArrow: cockpitStep >= 2,     // step 1 floats under the cover, no arrow
                placeBelow: cockpitStep == 1,
                arrowTrailing: cockpitStep == 2,  // point at the toggle switch on the right
                isPresented: cockpitStep != 0
            ) {
                // Tap-closing the Speaking-toggle tip (step 2, scrolled down to the
                // practice section) brings "Start reading" back on screen — the tip
                // itself suggests scrolling up to it. Flipping the toggle instead
                // dismisses via onChange below without yanking the scroll position.
                if cockpitStep == 2 { scrollTopToken += 1 }
                advanceCockpitTips()
            }
            .onChange(of: help.isActive) { _, active in
                // "?" replays the cockpit sequence from step 1; off dismisses it.
                if active {
                    helpReplay = true
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { cockpitStep = 1 }
                } else {
                    helpReplay = false
                    if cockpitStep != 0 { withAnimation { cockpitStep = 0 } }
                }
            }
            .onChange(of: settingsManager.speakingEnabled) { _, _ in
                // Its callout's action was taken — retire it.
                if cockpitStep == 2 { advanceCockpitTips() }
            }
            .onAppear {
                startCockpitTips()
                // Opened via the Library "Continue" card: pick up exactly where the
                // user left off (same spot and mode as the primary button here).
                guard autoResume, !didAutoResume else { return }
                didAutoResume = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if lastWasPractice {
                        launchPractice(restart: false)
                    } else {
                        startNormalReading(startingPage)
                    }
                }
            }
    }

    // MARK: - Cockpit onboarding sequence
    private var cockpitTarget: String {
        switch cockpitStep {
        case 1: return "comic.cockpit"
        case 2: return "comic.speaking"
        default: return ""
        }
    }

    private var cockpitText: String {
        switch cockpitStep {
        case 1: return "This is the language-learning cockpit. Decide if you want to simply read and listen, or practice with any of the different practice modes. It is recommended to read and listen to the comic at least once before starting to practice."
        case 2: return "Prefer not to speak at this time? Change to silent exercises. You can close me to see the different exercise modes or scroll up and click the Start reading button."
        default: return ""
        }
    }

    private func startCockpitTips() {
        // Skip when auto-resuming straight into the reader — the screen is leaving.
        guard !autoResume, cockpitStep == 0 else { return }
        if !HelpDebug.forceShowTooltips { guard !seenCockpitTips else { return } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard cockpitStep == 0 else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { cockpitStep = 1 }
        }
    }

    private func advanceCockpitTips() {
        // Step through the sequence; end (and mark seen) after the last callout.
        // Additional steps get chained here as they're added.
        withAnimation(.easeInOut(duration: 0.2)) {
            if cockpitStep < 2 {
                cockpitStep += 1
            } else {
                cockpitStep = 0
                seenCockpitTips = true
                // End of a "?" replay — close help mode too.
                if helpReplay {
                    helpReplay = false
                    help.isActive = false
                }
            }
        }
    }

    // Extracted so the `body` modifier chain stays short enough for the Swift
    // type-checker (a long chain + the destination switch was timing out).
    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    coverBanner
                        .calloutAnchor("comic.cockpit")
                        .padding(.horizontal, 16)
                        .id("top")

                    bannerCaption
                        .padding(.horizontal, 16)

                    actionButtons
                        .padding(.horizontal, 16)

                    descriptionParagraph
                        .padding(.horizontal, 16)

                    practiceSection
                        .padding(.horizontal, 16)
                        .id("practice")

                    pagesGrid
                }
                .padding(.vertical, 16)
            }
            .onChange(of: scrollTopToken) { _, _ in
                withAnimation { proxy.scrollTo("top", anchor: .top) }
            }
            .onChange(of: cockpitStep) { _, step in
                // Reveal the Speaking-exercises toggle when its callout opens.
                if step == 2 { withAnimation { proxy.scrollTo("practice", anchor: .top) } }
            }
        }
    }

    // Dialog bodies extracted — inlining them in `body`'s modifier chain pushed
    // the type-checker over its complexity limit.
    @ViewBuilder
    private var drillChooserButtons: some View {
        Button("Writing") { practiceDestination = .quiz }
        if settingsManager.speakingEnabled {
            Button("Speaking") { practiceDestination = .speaking }
        }
        Button("Listening") { practiceDestination = .listening }
        Button("Cancel", role: .cancel) { }
    }

    @ViewBuilder
    private var listenSpeakChooserButtons: some View {
        Button("Spanish → Spanish & English") { practiceDestination = .repeatPractice }
        Button("English → Spanish") { practiceDestination = .translateSpeak }
        Button("Cancel", role: .cancel) { }
    }

    @ViewBuilder
    private func destinationView(_ destination: PracticeDestination) -> some View {
        switch destination {
        case .quiz:          QuizView(comic: comic)
        case .speaking:      SpeakingTestView(comic: comic)
        case .listening:     ListeningTestView(comic: comic)
        case .repeatPractice: RepeatPracticeView(comic: comic)
        case .translateSpeak: RepeatPracticeView(comic: comic, reverse: true)
        case .repeatListen:  RepeatListenView(comic: comic)
        case .originListen:  OriginListenView(comic: comic)
        case .flowPractice:  FlowPracticeView(comic: comic)
        }
    }

    // MARK: - Trailing Toolbar
    @ViewBuilder
    private var trailingToolbar: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
            } label: {
                Image(systemName: help.isActive ? "questionmark.circle.fill" : "questionmark.circle")
            }

            // The graduation-cap practice menu was removed in favour of the Practice
            // button + popup. `practiceMenu` and the .quiz/.speaking/.listening
            // destinations are kept (unused) so the single-word practice can be
            // wired in elsewhere later.

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Action Buttons
    private var hasProgress: Bool {
        progressManager.getProgress(for: comic.id) != nil
    }

    // Indigo brand accent (reserved for primary actions).
    private var accentColor: Color { Color(red: 91/255, green: 91/255, blue: 214/255) }

    // Whether the most recent interaction with this comic was a practice session,
    // so the primary button mirrors the Library's "Continue practicing" label.
    private var lastWasPractice: Bool {
        hasProgress && progressManager.interactionKind(for: comic.id) == "practice"
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Primary action — accent, fills the remaining width. Mirrors what the
                // user was last doing: continue reading, continue practicing, or start.
                Text(hasProgress ? (lastWasPractice ? "Continue practicing" : "Continue reading") : "Start reading")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(accentColor, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.comigoInk, lineWidth: 2))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if lastWasPractice {
                            launchPractice(restart: false)   // resume the last mode
                        } else {
                            startNormalReading(startingPage)
                        }
                    }
                    .explains("Start reading",
                              "Open the comic and start reading — it picks up from where you left off.")

                // Restart — white, hugs its label. Restarts whichever activity the
                // primary button reflects (practice in the same mode, or reading).
                if hasProgress {
                    Text("Restart")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 15)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.comigoInk, lineWidth: 2))
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if lastWasPractice {
                                launchPractice(restart: true)   // same mode, from the start
                            } else {
                                startNormalReading(firstPage)
                            }
                        }
                        .explains("Restart",
                                  "Start over from the beginning — the same practice mode, or reading.")
                }
            }

            // When the primary button is practice-focused, keep reading one tap away.
            // Same width as "Continue practicing" and aligned under it: an invisible
            // Restart-sized placeholder reserves the right column so this fills the left.
            if lastWasPractice {
                HStack(spacing: 12) {
                    Text("Continue reading instead")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.comigoInk, lineWidth: 2))
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                        .contentShape(Rectangle())
                        .onTapGesture { startNormalReading(startingPage) }

                    // Invisible, matches the Restart button's width to keep alignment.
                    Text("Restart")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .padding(.horizontal, 22)
                        .frame(height: 0)
                        .hidden()
                }
            }
        }
    }

    // Launch the last-used practice mode. `restart` clears the saved spot so it
    // begins from the first sentence; otherwise it resumes where it left off.
    private func launchPractice(restart: Bool) {
        if restart {
            progressManager.clearPracticePosition(for: comic.id)
            progressManager.clearWordPosition(for: comic.id)
            progressManager.clearPracticeBubble(for: comic.id)
        }
        let mode = progressManager.lastPracticeMode(for: comic.id)
        if mode == "readSpeak" {
            // Continue = pick up where practice left off (same page + bubble);
            // Restart = cover, no bubble.
            if restart {
                startReadAndSpeak(from: firstPage, bubbleId: nil)
            } else {
                startReadAndSpeak(from: startingPage, bubbleId: progressManager.practiceBubbleId(for: comic.id))
            }
        } else if let dest = PracticeDestination(modeKey: mode) {
            practiceDestination = dest
        } else {
            // No recorded mode — let the user pick one.
            withAnimation(.easeInOut(duration: 0.2)) { showPracticeOptions = true }
        }
    }



    // MARK: - Practice Options (floating panel)
    @ViewBuilder
    private var practiceOptionsOverlay: some View {
        if showPracticeOptions {
            ZStack {
                Rectangle()
                    .fill(.thickMaterial)   // strong frost so the page behind (incl. the
                    .ignoresSafeArea()      // inline Practice section) doesn't show through
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showPracticeOptions = false }
                    }

                // Same Practice content as the home (comic-detail) section.
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Practice")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.bottom, 2)

                        practiceOptionsContent
                    }
                    .padding(18)
                }
                .frame(maxWidth: 360, maxHeight: 560)
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showPracticeOptions = false }
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
                .padding(.horizontal, 24)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            .zIndex(10)
        }
    }

    // MARK: - Practice Menu (graduation cap)
    private var practiceMenu: some View {
        Menu {
            Section("Sentence Practice") {
                Button {
                    practiceDestination = .repeatPractice
                } label: {
                    Label("Repeat Practice", systemImage: "mouth.fill")
                }
                Button {
                    practiceDestination = .repeatListen
                } label: {
                    Label("Repeat Listen", systemImage: "headphones")
                }
                Button {
                    practiceDestination = .originListen
                } label: {
                    Label("Origin Listen", systemImage: "play.circle")
                }
                // Flow Practice is hidden until it's ready (AI behaviour / English
                // handling still being refined). Re-enable by restoring this button.
                // Button {
                //     practiceDestination = .flowPractice
                // } label: {
                //     Label("Flow Practice", systemImage: "bubble.left.and.bubble.right")
                // }
            }

            Section("Practice Key Words") {
                Button {
                    practiceDestination = .quiz
                } label: {
                    Label("Writing", systemImage: "pencil.line")
                }

                Button {
                    practiceDestination = .speaking
                } label: {
                    Label("Speaking", systemImage: "mic.fill")
                }

                Button {
                    practiceDestination = .listening
                } label: {
                    Label("Listening", systemImage: "headphones")
                }
            }

            Section("Reading and Speaking Practice") {
                Toggle(isOn: Binding(
                    get: { settingsManager.speakingPracticeMode },
                    set: { newValue in
                        settingsManager.speakingPracticeMode = newValue
                        if newValue { settingsManager.listeningPracticeMode = false }
                    }
                )) {
                    Label("Speaking Practice Mode", systemImage: "bubble.left.and.text.bubble.right")
                }

                Toggle(isOn: Binding(
                    get: { settingsManager.listeningPracticeMode },
                    set: { newValue in
                        settingsManager.listeningPracticeMode = newValue
                        if newValue { settingsManager.speakingPracticeMode = false }
                    }
                )) {
                    Label("Listening Practice Mode", systemImage: "headphones")
                }
            }
        } label: {
            let activePractice = settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
            Image(systemName: "graduationcap.fill")
                .font(.body)
                .foregroundStyle(activePractice ? .green : .accentColor)
        }
    }

    // Collection (series) name shown in the nav bar — comic view only, so the
    // collection detail view's bar stays clean.
    @ViewBuilder
    private var navBarCollectionTitle: some View {
        if let collectionTitle = comic.collectionTitle, !collectionTitle.isEmpty {
            VStack(spacing: 0) {
                Text(collectionTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if let collectionTitleEn = comic.collectionTitleEn, !collectionTitleEn.isEmpty {
                    Text(collectionTitleEn)
                        .font(.caption2)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Cover Banner (image only; title sits below so it never covers art)
    private var coverBanner: some View {
        // GeometryReader fixes the box size so the image fills + crops inside it
        // (top-aligned), instead of the image's intrinsic width leaking out and
        // widening the whole layout for certain cover aspect ratios.
        GeometryReader { geo in
            ComicImage(imageName: comic.coverLandscape ?? comic.coverImage, comicId: comic.id)
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(height: 208)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
    }

    /// Title + English subtitle + level/pages, shown BELOW the banner so it never
    /// covers the art. Uses adaptive label colours (dark/grey in light mode, white
    /// in dark mode).
    private var bannerCaption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(comic.title)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            if let titleEn = comic.titleEn, !titleEn.isEmpty {
                Text(titleEn)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < levelFilledDots ? Color.primary : Color.primary.opacity(0.25))
                            .frame(width: 6, height: 6)
                    }
                }
                Text(comic.level.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("· \(comic.pages.count) pages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var levelFilledDots: Int {
        switch comic.level {
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        }
    }

    private var descriptionParagraph: some View {
        Text(comic.description)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Practice Section (README §5)
    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRACTICE")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            practiceOptionsContent
        }
    }

    // Shared by the inline Practice section and the end-of-episode popup, so both
    // look identical (toggle + mode cards + drill).
    @ViewBuilder
    private var practiceOptionsContent: some View {
        speakingToggleCard

        if settingsManager.speakingEnabled {
            practiceModeCard(icon: "text.bubble.fill",
                             title: "Read & speak", tag: "ON SCREEN",
                             description: "Look at the English. Listen to the Spanish and repeat back. Reveal text if needed.",
                             action: { startReadAndSpeak() })
            practiceModeCard(icon: "headphones",
                             title: "Listen & speak", tag: "OFF SCREEN",
                             description: "Screen off, eyes free. Hear each line and speak — Spanish → English, or English → Spanish.",
                             action: { showingListenSpeakChooser = true })
        } else {
            practiceModeCard(icon: "headphones",
                             title: "Just listen", tag: "OFF SCREEN",
                             description: "Screen off, eyes free. Hear each line and its meaning — no speaking.",
                             action: { practiceDestination = .repeatListen })
            practiceModeCard(icon: "play.circle",
                             title: "Listen in Spanish", tag: "OFF SCREEN",
                             description: "Screen off, eyes free. Play the whole comic in Spanish, start to finish — no English, no speaking.",
                             action: { practiceDestination = .originListen })
            speakingOffNote
        }

        drillCard
    }

    private var speakingToggleCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Speaking exercises")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(settingsManager.speakingEnabled
                     ? "Repeat lines aloud and get pronunciation feedback."
                     : "Off — practice is listen-only.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $settingsManager.speakingEnabled.animation(.easeInOut(duration: 0.2)))
                .labelsHidden()
                .tint(accentColor)
        }
        .padding(13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.comigoInk, lineWidth: 2))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .calloutAnchor("comic.speaking")
    }

    private func practiceModeCard(icon: String, title: String, tag: String,
                                  description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 44, height: 44)
                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(tag)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(0.12), in: Capsule())
                    }
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.comigoInk, lineWidth: 2))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var speakingOffNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text("Speaking is off, so the on-screen read-and-speak mode is hidden. Turn speaking on to practise saying lines aloud.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var drillCard: some View {
        Button {
            showingDrillChooser = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Drill the key words")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(settingsManager.speakingEnabled
                         ? "Writing · Speaking · Listening"
                         : "Writing · Listening")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.comigoInk, lineWidth: 2))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// On-screen "Read & speak" from the Practice menu: resume where the learner
    /// left off — same page AND same bubble (mirrors "Continue reading"). Restart
    /// routes through the `from:` variant with the cover and no bubble.
    private func startReadAndSpeak() {
        if practiceFromEnd {
            // Episode just finished → restart from the cover, no saved bubble.
            progressManager.clearPracticePosition(for: comic.id)
            progressManager.clearWordPosition(for: comic.id)
            progressManager.clearPracticeBubble(for: comic.id)
            startReadAndSpeak(from: firstPage)
            return
        }
        startReadAndSpeak(from: startingPage, bubbleId: progressManager.practiceBubbleId(for: comic.id))
    }

    /// On-screen "Read & speak": text stays visible, learner speaks each line.
    /// Mirrors the legacy On-Screen guided run. Opens at `page`, at `bubbleId` when set.
    private func startReadAndSpeak(from page: Page, bubbleId: String? = nil) {
        settingsManager.speakingPracticeMode = true
        settingsManager.listeningPracticeMode = false
        guidedOnScreen = true
        pendingBubbleId = bubbleId
        showPracticeOptions = false
        progressManager.setPracticeMode(comic.id, mode: "readSpeak")
        selectedPage = page
    }

    // Pages sorted by pageNumber for navigation
    private var sortedPages: [Page] {
        comic.pages.sorted { $0.pageNumber < $1.pageNumber }
    }

    // The first page (cover)
    private var firstPage: Page {
        sortedPages.first ?? comic.pages[0]
    }

    /// Open a page for plain reading. Clears any leftover practice-mode flags so
    /// the reader shows the real (text) artwork, not the empty-bubble practice art.
    private func startNormalReading(_ page: Page) {
        settingsManager.speakingPracticeMode = false
        settingsManager.listeningPracticeMode = false
        guidedOnScreen = false
        pendingBubbleId = nil   // plain reading never auto-opens a bubble
        selectedPage = page
    }

    private var startingPage: Page {
        if let progress = progressManager.getProgress(for: comic.id),
           let page = comic.pages.first(where: { $0.pageNumber == progress.pageNumber }) {
            return page
        }
        // Return the first page (cover)
        return firstPage
    }

    // MARK: - Pages Grid
    private var pagesGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(comic.pages) { page in
                PageThumbnail(page: page, comic: comic, isCover: page.pageNumber <= 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        startNormalReading(page)
                    }
                    .explainsIf(page.id == comic.pages.first?.id,
                                "Jump to a page",
                                "Tap any page thumbnail to open the comic straight at that page.")
            }
        }
        .padding(.horizontal, 16)
        .clipped()
    }

}

// MARK: - Page Thumbnail
struct PageThumbnail: View {
    let page: Page
    let comic: Comic
    var isCover: Bool = false
    @EnvironmentObject var progressManager: ReadingProgressManager
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let practiceActive = settingsManager.speakingPracticeMode || settingsManager.listeningPracticeMode
                let imageName = practiceActive
                    ? (page.noTextImage ?? page.masterImage)
                    : page.masterImage
                ComicImage(imageName: imageName, comicId: comic.id)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: isCover ? .top : .center)
            }
            // Portrait page aspect (2:3), matching the actual comic page art,
            // instead of the old fixed square-ish height.
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipped()
                .overlay(
                    Rectangle()
                        .stroke(isCurrentPage ? .green : Color.clear, lineWidth: 3)
                )

            HStack {
                Text("Page \(page.pageNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isCurrentPage {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var isCurrentPage: Bool {
        progressManager.getProgress(for: comic.id)?.pageNumber == page.pageNumber
    }
}

// MARK: - Practice Modes Help
/// Explains each entry in the practice (graduation-cap) menu. Shown when the
/// hat is tapped in help mode.
struct PracticeModesHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Mode: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
        let detail: String
    }

    private let sentenceModes: [Mode] = [
        Mode(icon: "mouth.fill", name: "Repeat Practice",
             detail: "Listen to each sentence, then say it back. The app checks your pronunciation and understanding before moving on."),
        Mode(icon: "headphones", name: "Repeat Listen",
             detail: "Hear each sentence in Spanish and recall its meaning, then reveal the translation — listening practice, hands-free."),
        Mode(icon: "play.circle", name: "Origin Listen",
             detail: "Sit back and listen to the whole story read aloud, sentence by sentence."),
        // Flow Practice hidden until ready — restore alongside the menu button.
        // Mode(icon: "bubble.left.and.bubble.right", name: "Flow Practice",
        //      detail: "Have a live chat with the AI that weaves in the words and phrases from this comic — used in new situations, so you have to understand and reply with them."),
    ]

    private let keyWordModes: [Mode] = [
        Mode(icon: "pencil.line", name: "Writing",
             detail: "Quiz yourself by typing the Spanish for each key word from the comic."),
        Mode(icon: "mic.fill", name: "Speaking",
             detail: "Say each key word out loud; the app listens and checks your pronunciation."),
        Mode(icon: "headphones", name: "Listening",
             detail: "Hear a key word in Spanish and say what it means in English."),
    ]

    private let practiceToggles: [Mode] = [
        Mode(icon: "bubble.left.and.text.bubble.right", name: "Speaking Practice Mode",
             detail: "Hides the Spanish text while you read, so you try to say each line yourself before revealing it."),
        Mode(icon: "headphones", name: "Listening Practice Mode",
             detail: "Hides the text and asks for the English meaning as you read — a listening-first way through the comic."),
    ]

    var body: some View {
        NavigationStack {
            List {
                section("Sentence Practice", sentenceModes)
                section("Practice Key Words", keyWordModes)
                section("Reading and Speaking Practice", practiceToggles)
            }
            .navigationTitle("Practice modes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, _ modes: [Mode]) -> some View {
        Section(title) {
            ForEach(modes) { mode in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: mode.icon)
                        .font(.title3)
                        .foregroundStyle(.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mode.name)
                            .font(.headline)
                        Text(mode.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ComicDetailView(comic: ComicData.allComics[0])
            .environmentObject(ReadingProgressManager())
            .environmentObject(SettingsManager())
    }
}
