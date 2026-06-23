import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .library
    @State private var libraryNavigationPath = NavigationPath()
    @State private var showSplash = true

    enum Tab {
        case library
        case vocabulary
        case settings
    }

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--coachmark-preview") {
            CoachmarkPreviewHarness()
        } else {
            mainBody
        }
        #else
        mainBody
        #endif
    }

    var mainBody: some View {
        // Show the splash ALONE first — don't mount the TabView/LibraryView behind
        // it. On a cold first-download launch, mounting the library kicks off the
        // catalog fetch + comic loading + image decoding, and that main-thread
        // contention is what made the spin/typing stutter and mistime. Deferring it
        // until the splash is done keeps the intro smooth.
        Group {
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
                }
            } else {
                tabs
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $libraryNavigationPath) {
                LibraryView()
                    .navigationDestination(for: Comic.self) { comic in
                        ComicDetailView(comic: comic)
                    }
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(Tab.library)

            NavigationStack {
                VocabularyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedTab = .library
                            }
                        }
                    }
            }
            .tabItem {
                Label("Vocabulary", systemImage: "bookmark.fill")
            }
            .tag(Tab.vocabulary)

            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedTab = .library
                            }
                        }
                    }
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(Tab.settings)
        }
        .tint(.primary)
    }
}

// MARK: - Splash / Home

/// Launch screen: blue background with the Comigo logo bubble spinning in from
/// the left, fast, and coming to a stop in the top third of the page.
struct SplashView: View {
    var onEnter: () -> Void

    @State private var animate = false
    @State private var started = false
    @State private var typed1 = ""   // "Learn Spanish" — revealed char by char
    @State private var typed2 = ""   // "one comic at a time"

    private let line1 = "Learn Spanish"
    private let line2 = "One comic at a time."

    @State private var revealed = [Bool](repeating: false, count: 7)
    @State private var blackBg = false      // black backdrop behind the finished montage
    @State private var showButton = false   // "Start Reading" button below the montage

    // Reveal order by panel-file number 1,7,3,6,2,4,5 → 0-based layer indices.
    private let revealOrder = [0, 6, 2, 5, 1, 3, 4]
    private let montageAspect: CGFloat = 720.0 / 1084.0
    // Match the logo's own background so its white square blends into the page —
    // only the bubble outline appears to spin.
    private let bgColor = Color.white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                bgColor.ignoresSafeArea()

                Image("ComigoLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(geo.size.width * 0.5, 200))
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.33)  // a bit lower, closer to the text
                    .opacity(animate ? 1 : 0)                                    // simple fade in

                // Tagline under the logo, typed on over two lines in the comic font.
                // Fixed height + top alignment so line 1 stays put as line 2 types in.
                VStack(alignment: .leading, spacing: 6) {
                    Text(typed1)
                    Text(typed2)
                }
                .font(.custom("ComicRelief-Bold", size: 26))
                .tracking(-0.8)   // tighten spacing so the longer line fits on one row
                .foregroundStyle(.black)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                // Fixed-width block, content pinned top-left, so characters type out
                // left-to-right from a fixed left edge (not growing from the centre).
                .frame(width: geo.size.width * 0.9, height: 90, alignment: .topLeading)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.60)

                // Black backdrop that fades in behind the finished montage.
                Color.black.ignoresSafeArea().opacity(blackBg ? 1 : 0)

                // Comic-panel montage, assembled one panel at a time over the page.
                montageView(in: geo)

                // Button below the montage — advances to the comics.
                Button(action: onEnter) {
                    Text("Start Reading")
                        .font(.custom("ComicRelief-Bold", size: 16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.16, green: 0.45, blue: 0.92))
                        .clipShape(Capsule())
                }
                .position(x: geo.size.width / 2, y: geo.size.height * 0.955)
                .opacity(showButton ? 1 : 0)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            Task { await runIntro() }
        }
    }

    /// Deterministic intro order, robust on a cold launch (first download):
    /// let the first real layout happen, spin the logo in, then — only after the
    /// full animation has run — type the tagline.
    // The full montage, masked so only the revealed panels show. Sized to fill the
    // screen width and centred; the white letterbox margins blend with the page.
    @ViewBuilder
    private func montageView(in geo: GeometryProxy) -> some View {
        let mW = geo.size.width
        let mH = mW / montageAspect
        ZStack {
            // Each layer is the full canvas with one panel painted in its exact
            // place (transparent elsewhere) — stacking them rebuilds the page, and
            // fading them in one at a time assembles it panel by panel.
            ForEach(0..<7, id: \.self) { i in
                Image("SplashLayer\(i + 1)")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: mW, height: mH)
                    .opacity(revealed[i] ? 1 : 0)
            }
        }
        .frame(width: mW, height: mH)
        .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }

    @MainActor
    private func runIntro() async {
        // The view's initial frame can be zero on a fresh launch; a short wait lets
        // it lay out before we animate, and keeps the sequence in order.
        try? await Task.sleep(nanoseconds: 400_000_000)
        withAnimation(.easeIn(duration: 1.0)) {
            animate = true   // fade the logo in
        }
        // Wait for the fade plus a brief beat before typing.
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        await typeTagline()
        // Hold for 2 seconds after the tagline finishes before the panels start.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        // Bring the comic panels in one at a time until they cover the page.
        for idx in revealOrder {
            withAnimation(.easeOut(duration: 0.3)) { revealed[idx] = true }
            try? await Task.sleep(nanoseconds: 640_000_000)
        }
        // Quick black backdrop behind the montage…
        withAnimation(.easeIn(duration: 0.3)) { blackBg = true }
        // …then wait 3 seconds on the framed montage before the button appears.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        withAnimation(.easeIn(duration: 0.25)) { showButton = true }
    }

    /// Reveals the two lines one character at a time with slightly uneven timing
    /// so it reads like real typing, with a beat between the lines.
    @MainActor
    private func typeTagline() async {
        for ch in line1 {
            typed1.append(ch)
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.025...0.075) * 1_000_000_000))
        }
        try? await Task.sleep(nanoseconds: 350_000_000)     // slight pause before line 2
        for ch in line2 {
            typed2.append(ch)
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.025...0.075) * 1_000_000_000))
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsManager())
        .environmentObject(ReadingProgressManager())
}

#Preview("Splash") {
    SplashView(onEnter: {})
}

#if DEBUG
/// Screenshot-only harness: opens the panel reading screen on a rich in-memory
/// comic with the feature tour armed, so the coachmark overlay can be captured.
/// Launch with `--coachmark-preview` (and optional `--coachmark-step N`).
struct CoachmarkPreviewHarness: View {
    @EnvironmentObject var settingsManager: SettingsManager

    private static let comic: Comic = {
        let words = [
            Word(id: "w1", text: "Me", meaning: "myself", baseForm: "me"),
            Word(id: "w2", text: "escondí", meaning: "I hid", baseForm: "esconder"),
            Word(id: "w3", text: "detrás", meaning: "behind", baseForm: "detrás"),
            Word(id: "w4", text: "de", meaning: "of", baseForm: "de"),
            Word(id: "w5", text: "la", meaning: "the", baseForm: "la"),
            Word(id: "w6", text: "puerta", meaning: "door", baseForm: "puerta"),
        ]
        let sentence = Sentence(
            id: "s1",
            text: "Me escondí detrás de la puerta",
            translation: "I hid behind the door",
            grammarNote: "“Escondí” is the preterite (completed past) of esconder. The reflexive “me” shows he hid himself.",
            audioUrl: "preview-audio",
            words: words
        )
        let bubble = Bubble(id: "b1", type: .speech, positionX: 0.1, positionY: 0.1,
                            width: 0.8, height: 0.2, sentences: [sentence])
        let panel = Panel(id: "p1", artworkImage: "sample_cover", noTextImage: nil,
                          floating: false, corners: nil, panelOrder: 1,
                          tapZoneX: 0, tapZoneY: 0, tapZoneWidth: 0.5, tapZoneHeight: 0.5,
                          bubbles: [bubble])
        let page = Page(id: "pg1", pageNumber: 1, masterImage: "sample_cover", panels: [panel])
        let review = ReviewWord(word: words[1], panelId: "p1", pageId: "pg1")
        return Comic(id: "preview-comic", title: "Tour Preview", description: "",
                     coverImage: "sample_cover", level: .beginner, isPremium: false,
                     pages: [page], reviewWords: [review])
    }()

    var body: some View {
        let comic = Self.comic
        Group {
            // Smoke-test a rolled-out screen: just launching it exercises the
            // help env wiring (the tooltip layer reads @EnvironmentObject on
            // first render, so a misorder would crash on appear).
            if ProcessInfo.processInfo.arguments.contains("--flow-preview") {
                NavigationStack { FlowPracticeView(comic: comic) }
            } else if ProcessInfo.processInfo.arguments.contains("--practice-help-preview") {
                PracticeModesHelpView()
            } else if ProcessInfo.processInfo.arguments.contains("--quiz-preview") {
                NavigationStack { QuizView(comic: comic) }
            } else {
                PanelView(
                    comic: comic,
                    page: comic.pages[0],
                    panel: comic.pages[0].panels[0],
                    hotspots: [],
                    navigateToPage: .constant(nil)
                )
            }
        }
        .environmentObject(settingsManager)
    }
}
#endif
