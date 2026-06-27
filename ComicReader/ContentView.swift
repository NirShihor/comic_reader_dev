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
                LandingView(
                    onGetStarted: { withAnimation(.easeInOut(duration: 0.4)) { showSplash = false } }
                )
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

// MARK: - Landing / Splash

// Design tokens for the landing screen (match the rest of the refresh).
private enum Brand {
    static let accent        = Color(red: 0x5B/255, green: 0x5B/255, blue: 0xD6/255) // #5B5BD6
    static let bg            = Color(red: 0xF4/255, green: 0xF1/255, blue: 0xED/255) // #F4F1ED
    static let textPrimary   = Color(red: 0x1F/255, green: 0x1B/255, blue: 0x18/255) // #1F1B18
    static let textSecondary = Color(red: 0x75/255, green: 0x6E/255, blue: 0x67/255) // #756E67
    static let textTertiary  = Color(red: 0x6B/255, green: 0x63/255, blue: 0x5C/255) // #6B635C

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// First-run / landing screen — COMIGO logo over a curated comic mosaic, warm
/// wash fading into the app background, indigo "Get started" CTA.
struct LandingView: View {
    var onGetStarted: () -> Void = {}

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()

            // 1) Comic mosaic backdrop (top ~66% of the screen)
            GeometryReader { geo in
                MosaicBackdrop()
                    .frame(height: geo.size.height * 0.66)
                    .clipped()
                    // Soft warm wash over the panels.
                    .overlay(
                        LinearGradient(
                            colors: [Brand.bg.opacity(0.18), Brand.bg.opacity(0.28)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    // Dissolve the bottom into the page: the mosaic fades to fully
                    // transparent before its own edge, so there is no line — the
                    // identical Brand.bg behind shows straight through.
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.00),
                                .init(color: .white, location: 0.66),
                                .init(color: .clear, location: 0.96),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea(edges: .top)
            }

            // 3) Content, pinned to the bottom
            VStack(spacing: 0) {
                Spacer()

                Image("comigo-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 226)
                    .shadow(color: Brand.textPrimary.opacity(0.12), radius: 12, x: 0, y: 6)
                    .padding(.bottom, 46)

                // Tagline — note the indigo period
                VStack(spacing: 0) {
                    Text("Spanish.")
                    (Text("One comic at a time")
                        + Text(".").foregroundColor(Brand.accent))
                }
                .font(Brand.rounded(27, .heavy))
                .foregroundColor(Brand.textPrimary)
                .multilineTextAlignment(.center)

                Text("Read and listen to comics in Spanish, tap sentences and words to understand them and practice out loud.")
                    .font(.system(size: 15.5))
                    .foregroundColor(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 280)
                    .padding(.top, 14)

                Button(action: onGetStarted) {
                    Text("Get started")
                        .font(Brand.rounded(16, .heavy))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Brand.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: Brand.accent.opacity(0.30), radius: 11, x: 0, y: 10)
                }
                .padding(.top, 30)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 46)
        }
    }
}

// MARK: - Mosaic backdrop
// Two columns of comic tiles. Swap MosaicTile's fill for real cover Images:
//   MosaicTile { Image("cover_rey").resizable().scaledToFill() }
// The warm gradient above handles the dimming, so tiles need no overlay of their own.
private struct MosaicBackdrop: View {
    var body: some View {
        HStack(spacing: 6) {
            VStack(spacing: 6) {
                MosaicTile(color: Color(red: 0x7C/255, green: 0x5A/255, blue: 0x3A/255)).frame(height: 188)
                MosaicTile(color: Color(red: 0x3E/255, green: 0x56/255, blue: 0x41/255)).frame(height: 150)
                MosaicTile(color: Color(red: 0x5C/255, green: 0x73/255, blue: 0x55/255)) // fills remainder
            }
            VStack(spacing: 6) {
                MosaicTile(color: Color(red: 0x9A/255, green: 0x8C/255, blue: 0x72/255)).frame(height: 132)
                MosaicTile(color: Color(red: 0x2F/255, green: 0x5D/255, blue: 0x62/255)).frame(height: 206)
                MosaicTile(color: Color(red: 0x5A/255, green: 0x4A/255, blue: 0x6A/255)) // fills remainder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct MosaicTile<Content: View>: View {
    var color: Color = .gray
    @ViewBuilder var content: () -> Content

    init(color: Color, @ViewBuilder content: @escaping () -> Content = { EmptyView() }) {
        self.color = color
        self.content = content
    }

    var body: some View {
        ZStack {
            color
            content()
            // subtle hatch so placeholder tiles read as comic panels (remove with real art)
            GeometryReader { g in
                Path { p in
                    let step: CGFloat = 16
                    var x = -g.size.height
                    while x < g.size.width {
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x + g.size.height, y: g.size.height))
                        x += step
                    }
                }
                .stroke(Color.white.opacity(0.06), lineWidth: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsManager())
        .environmentObject(ReadingProgressManager())
}

#Preview("Landing") {
    LandingView()
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
