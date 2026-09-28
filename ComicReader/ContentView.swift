import SwiftUI
import UIKit
import StoreKit
import Combine

struct ContentView: View {
    @State private var selectedTab: Tab = .library
    @State private var libraryNavigationPath = NavigationPath()
    @State private var showSplash = true
    // Debug-only: "--paywall-preview" launch arg opens the paywall sheet over the
    // library, for scripted App Store review screenshots.
    @State private var showDebugPaywall = false
    // App appearance override, set from Settings → Appearance: "system"/"light"/"dark".
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil   // follow the system
        }
    }

    // Returning user = has launched before (flag set on first Get started) or
    // already has reading progress. They see "Continue learning".
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    // Asked once, right after the landing screen, until a level is chosen —
    // a Comigo screen, not a system prompt, and unrelated to analytics consent.
    @AppStorage(SpanishLevel.storageKey) private var spanishLevelRaw = ""
    // Free-trial offer on the landing screen: eligible new-model users only
    // (StoreKit-confirmed), independent of analytics consent.
    @ObservedObject private var store = StoreService.shared
    @State private var showTrialPaywall = false
    @EnvironmentObject private var progressManager: ReadingProgressManager
    @EnvironmentObject private var notebookManager: NotebookManager
    private var returningUser: Bool {
        hasLaunchedBefore || !progressManager.progressMap.isEmpty
    }

    enum Tab {
        case library
        case vocabulary
        case notebook
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
                    ctaTitle: returningUser ? "Continue learning" : "Get started",
                    onGetStarted: enterApp,
                    trialOffer: store.showsTrialBanner ? LandingView.TrialOffer(
                        days: StoreService.trialDays(store.monthlyProduct) ?? 7,
                        priceLine: store.monthlyProduct.map {
                            "then \($0.displayPrice) / \(StoreService.billingPeriodText($0)) · cancel anytime"
                        }) : nil,
                    onStartTrial: { showTrialPaywall = true }
                )
                // The trial button is the way in for eligible new users: whether
                // they start the trial or close the paywall, they then enter the app.
                .sheet(isPresented: $showTrialPaywall, onDismiss: enterApp) { PaywallView(source: .landingScreen) }
            } else if SpanishLevel(rawValue: spanishLevelRaw) == nil {
                SpanishLevelView { level in
                    withAnimation(.easeInOut(duration: 0.35)) { SpanishLevel.select(level) }
                }
                .transition(.opacity)
            } else {
                tabs
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
            ContentView.warmUpNotebook()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--paywall-preview") {
                showSplash = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showDebugPaywall = true }
            }
            #endif
        }
        .sheet(isPresented: $showDebugPaywall) { PaywallView(source: nil) }
    }

    private func enterApp() {
        hasLaunchedBefore = true
        withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
    }

    /// Pay the one-time costs (custom-font glyph load + keyboard subsystem init)
    /// during the splash, so the Notebook opens and accepts typing without the
    /// first-use hitch.
    private static var didWarmUp = false
    static func warmUpNotebook() {
        guard !didWarmUp else { return }
        didWarmUp = true

        // Force CoreText to load + lay out the handwritten font's glyphs.
        for name in ["ComicRelief-Regular", "ComicRelief-Bold"] {
            let label = UILabel()
            label.font = UIFont(name: name, size: 17)
            label.text = "warming up"
            label.sizeToFit()
        }

        // Pre-warm the keyboard so the first tap-to-type doesn't stall.
        // WELL after launch: keyboard-subsystem init runs on the main thread
        // and can take seconds — at +0.3s it landed exactly on the user's
        // first taps and made the whole app feel dead on arrival.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { warmUpKeyboard() }
    }

    /// One-time keyboard-subsystem init. Also fired when the Notebook tab
    /// opens, so a note created within seconds of launch doesn't stall.
    private static var didWarmKeyboard = false
    static func warmUpKeyboard() {
        guard !didWarmKeyboard else { return }
        didWarmKeyboard = true
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { didWarmKeyboard = false; return }
        let field = UITextField(frame: .zero)
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
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
                NotebookView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedTab = .library
                            }
                        }
                    }
            }
            .tabItem {
                Label("Notebook", systemImage: "book.closed")
            }
            .badge(notebookManager.unreadCount)
            .tag(Tab.notebook)
            .onChange(of: selectedTab) { _, tab in
                // Opening the Notebook clears the unread badge — and warms the
                // keyboard while the user browses, so the first note editor
                // opens without the one-time keyboard-init stall.
                if tab == .notebook {
                    notebookManager.markAllAdminRead()
                    ContentView.warmUpKeyboard()
                }
            }

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

// MARK: - iPad readable width

extension View {
    /// Constrain page content to a readable centred column on iPad. No-op on
    /// iPhone, where the screen is narrower than the cap anyway.
    func readableColumn(_ maxWidth: CGFloat = 700) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Landing / Splash

// Design tokens for the landing screen (match the rest of the refresh).
enum Brand {
    static let accent        = Color(red: 0x5B/255, green: 0x5B/255, blue: 0xD6/255) // #5B5BD6
    static let yellow        = Color(red: 0xFF/255, green: 0xD2/255, blue: 0x3F/255) // #FFD23F
    static let violet        = Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255) // #6E40F0
    static let ink           = Color(red: 0x15/255, green: 0x17/255, blue: 0x2A/255) // #15172A (bubble outline)
    static let bg            = Color(red: 0xF4/255, green: 0xF1/255, blue: 0xED/255) // #F4F1ED
    static let textPrimary   = Color(red: 0x1F/255, green: 0x1B/255, blue: 0x18/255) // #1F1B18
    static let textSecondary = Color(red: 0x75/255, green: 0x6E/255, blue: 0x67/255) // #756E67
    static let textTertiary  = Color(red: 0x6B/255, green: 0x63/255, blue: 0x5C/255) // #6B635C

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Luckiest Guy — comic display font, for headlines.
    static func display(_ size: CGFloat) -> Font {
        Font.custom("LuckiestGuy-Regular", size: size)
    }

    /// Inter — body font (variable; weights applied via .weight()).
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.custom("Inter", size: size).weight(weight)
    }
}

/// Hand-drawn yellow underline squiggle, ported from the mockup SVG (viewBox 0 0 240 10).
private struct Squiggle: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 240, sy = rect.height / 10
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
        var p = Path()
        p.move(to: pt(2, 5))
        p.addQuadCurve(to: pt(80, 5),  control: pt(41, 1))
        p.addQuadCurve(to: pt(160, 5), control: pt(120, 9))
        p.addQuadCurve(to: pt(238, 5), control: pt(199, 1))
        return p
    }
}

/// First-run / landing screen — COMIGO logo on a solid violet field with the
/// "Spanish." tagline and "Get started" CTA.
struct LandingView: View {
    struct TrialOffer: Equatable {
        let days: Int
        let priceLine: String?
    }

    var ctaTitle: String = "Get started"
    var onGetStarted: () -> Void = {}
    /// Shown only when StoreKit says this new-model user is eligible.
    var trialOffer: TrialOffer? = nil
    var onStartTrial: () -> Void = {}
    // iPad (regular width): the iPhone layout's hand-tuned offsets pin content
    // low and stretch the CTA — centre a fixed-width column instead.
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    var body: some View {
        ZStack {
            Brand.violet.ignoresSafeArea()

            // Content, pinned to the bottom (iPhone) / centred (iPad)
            VStack(spacing: 0) {
                Spacer()

                Image("comicgo_logo_yoni_1_alpha_layer_2")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 271)
                    .shadow(color: Brand.textPrimary.opacity(0.12), radius: 12, x: 0, y: 6)
                    .padding(.bottom, 46)
                    .offset(y: isPad ? 0 : -125)

                // Tagline — "Spanish." in Luckiest Guy (yellow period), the line
                // below in Inter with a yellow squiggle underline.
                VStack(spacing: 6) {
                    (Text("Spanish").tracking(-1.5)
                        + Text(".").font(Brand.display(42)).foregroundColor(Brand.yellow))
                        .font(Brand.display(34))

                    (Text("One comic at a time") + Text("."))
                        .font(Brand.body(21, .heavy))
                        .overlay(alignment: .bottom) {
                            Squiggle()
                                .stroke(Brand.yellow, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .frame(height: 10)
                                .offset(y: 8)
                        }
                }
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                // Lift the text toward the (offset-raised) logo so the gap up
                // to the logo matches the gap down to the button (~100pt each).
                .offset(y: isPad ? 0 : -70)

                Text("Read and listen to comics in Spanish, tap sentences and words to understand them and practice out loud.")
                    .font(Brand.body(15.5))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 280)
                    .offset(y: isPad ? 0 : -70)
                    .padding(.top, 24)

                // Eligible new users: the free trial is the way in (the paywall
                // opens, then they enter the app either way). Everyone else:
                // Get started / Continue learning.
                if let trialOffer {
                    Button(action: onStartTrial) {
                        VStack(spacing: 3) {
                            Label("Start your \(trialOffer.days)-day free trial", systemImage: "sparkles")
                                .font(Brand.body(16, .heavy))
                            if let line = trialOffer.priceLine {
                                Text(line)
                                    .font(Brand.body(12.5, .semibold))
                                    .opacity(0.75)
                            }
                        }
                        .foregroundColor(Brand.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Brand.ink, lineWidth: 3.5))
                        .shadow(color: Brand.ink.opacity(0.25), radius: 10, x: 0, y: 8)
                    }
                    .padding(.top, 30)
                    .transition(.opacity)
                } else {
                    Button(action: onGetStarted) {
                        Text(ctaTitle)
                            .font(Brand.body(16, .heavy))
                            .foregroundColor(Brand.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Brand.ink, lineWidth: 3.5))
                            .shadow(color: Brand.ink.opacity(0.25), radius: 10, x: 0, y: 8)
                    }
                    .padding(.top, 30)
                }

                if isPad { Spacer() }
            }
            .frame(maxWidth: isPad ? 480 : .infinity)
            .padding(.horizontal, 30)
            .padding(.bottom, isPad ? 0 : 46)
        }
    }
}

// MARK: - Mosaic backdrop
// Two columns of comic tiles. Swap MosaicTile's fill for real cover Images:
//   MosaicTile { Image("cover_rey").resizable().scaledToFill() }
// The warm gradient above handles the dimming, so tiles need no overlay of their own.
private struct MosaicBackdrop: View {
    // Primary violet from the v4 HTML mockup (--violet: #6E40F0).
    private let panel = Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)
    var body: some View {
        panel
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

// MARK: - Notebook

/// A single notebook page: a title and free-form body text the user writes.
/// Pages saved from a hotspot also carry a deep link back into the comic
/// (optional fields, so previously stored pages decode unchanged).
struct NotebookPage: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String = ""
    var body: String = ""
    var linkComicId: String? = nil
    var linkPageNumber: Int? = nil
    var linkHotspotId: String? = nil

    var hasComicLink: Bool { linkComicId != nil && linkHotspotId != nil }
}

private let notebookHighlightColor = Color.yellow.opacity(0.55)

/// Render a note body, turning ==marked== spans into yellow highlights.
func notebookHighlighted(_ s: String) -> AttributedString {
    var result = AttributedString("")
    var rest = Substring(s)
    while let open = rest.range(of: "==") {
        result += AttributedString(String(rest[..<open.lowerBound]))
        let after = rest[open.upperBound...]
        if let close = after.range(of: "==") {
            var hi = AttributedString(String(after[..<close.lowerBound]))
            hi.backgroundColor = notebookHighlightColor
            result += hi
            rest = after[close.upperBound...]
        } else {
            result += AttributedString("==" + String(after))
            return result
        }
    }
    result += AttributedString(String(rest))
    return result
}

/// A UITextView-backed editor that shows ==marked== text as live yellow
/// highlights and provides a keyboard toolbar "Highlight" button. The stored
/// value stays a plain string with ==markers== (iOS 17 compatible).
struct HighlightingTextView: UIViewRepresentable {
    @Binding var markup: String
    var font: UIFont
    var textColor: UIColor

    static let highlightColor = UIColor.systemYellow.withAlphaComponent(0.55)

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.textColor = textColor
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.typingAttributes = [.font: font, .foregroundColor: textColor]
        tv.attributedText = Self.attributed(from: markup, font: font, color: textColor)

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(title: "🖍 Highlight", style: .plain, target: context.coordinator, action: #selector(Coordinator.toggleHighlight)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.endEditing))
        ]
        tv.inputAccessoryView = toolbar
        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only resync if the external value changed (avoids clobbering edits).
        if Self.markup(from: uiView.attributedText) != markup {
            let sel = uiView.selectedRange
            uiView.attributedText = Self.attributed(from: markup, font: font, color: textColor)
            uiView.selectedRange = sel
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: HighlightingTextView
        weak var textView: UITextView?
        init(_ parent: HighlightingTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.markup = HighlightingTextView.markup(from: textView.attributedText)
        }

        @objc func toggleHighlight() {
            guard let tv = textView, tv.selectedRange.length > 0 else { return }
            let range = tv.selectedRange
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            var allHighlighted = true
            mutable.enumerateAttribute(.backgroundColor, in: range, options: []) { value, _, _ in
                if value == nil { allHighlighted = false }
            }
            if allHighlighted {
                mutable.removeAttribute(.backgroundColor, range: range)
            } else {
                mutable.addAttribute(.backgroundColor, value: HighlightingTextView.highlightColor, range: range)
            }
            mutable.addAttribute(.font, value: parent.font, range: NSRange(location: 0, length: mutable.length))
            mutable.addAttribute(.foregroundColor, value: parent.textColor, range: NSRange(location: 0, length: mutable.length))
            tv.attributedText = mutable
            tv.selectedRange = range
            tv.typingAttributes = [.font: parent.font, .foregroundColor: parent.textColor]
            parent.markup = HighlightingTextView.markup(from: mutable)
        }

        @objc func endEditing() { textView?.resignFirstResponder() }
    }

    static func attributed(from markup: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        var rest = Substring(markup)
        while let open = rest.range(of: "==") {
            result.append(NSAttributedString(string: String(rest[..<open.lowerBound]), attributes: base))
            let after = rest[open.upperBound...]
            if let close = after.range(of: "==") {
                var hiAttrs = base
                hiAttrs[.backgroundColor] = highlightColor
                result.append(NSAttributedString(string: String(after[..<close.lowerBound]), attributes: hiAttrs))
                rest = after[close.upperBound...]
            } else {
                result.append(NSAttributedString(string: "==" + String(after), attributes: base))
                return result
            }
        }
        result.append(NSAttributedString(string: String(rest), attributes: base))
        return result
    }

    static func markup(from attributed: NSAttributedString) -> String {
        var out = ""
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.backgroundColor, in: full, options: []) { value, range, _ in
            let sub = (attributed.string as NSString).substring(with: range)
            out += value != nil ? "==\(sub)==" : sub
        }
        return out
    }
}

// MARK: Admin notes (ship with the app)
//
// These pages are compiled into the app, so every user gets them and they're
// always available offline. To EDIT them, just change the text below: start a
// new page with a line beginning "# " (that becomes the page title); everything
// until the next "# " is that page's body. Plain text, real line breaks — no
// JSON escaping. (We can later move this to a server feed if you want to update
// notes without shipping a new build.)
private let adminNotesSource = """
# Ser vs. Estar
Both mean "to be", but:
• SER — permanent / essential traits: who/what something is. "Soy de España." "Es médico."
• ESTAR — states & locations that can change: how/where something is right now. "Estoy cansado." "Está en casa."

# Por vs. Para
• POR — reason, cause, exchange, duration, "through/by". "Gracias por la ayuda." "Por la mañana."
• PARA — purpose, destination, deadline, recipient. "Es para ti." "Salgo para Madrid."

# The Personal "a"
When the direct object of a verb is a specific person (or a loved pet), add "a":
"Veo a María." "Busco a mi hermano."
No "a" for things: "Veo la casa."
"""

/// Global notebook store. Admin pages are authored in the generator and fetched
/// from the server (cached on-device, so they stay available offline); the
/// compiled `adminNotesSource` is only a fallback before the first fetch.
/// User pages are device-local and editable, persisted to UserDefaults.
final class NotebookManager: ObservableObject {
    /// Read-only grammar pages from the server (cached). Updated on launch.
    @Published var adminPages: [NotebookPage]
    /// User-created pages, stored on this device.
    @Published var userPages: [NotebookPage] { didSet { save() } }
    /// Admin note ids the user has hidden on this device.
    @Published var hiddenAdminIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenAdminIds), forKey: hiddenKey) }
    }
    /// Admin note ids the user has OPENED — drives the unread badge on the tab.
    @Published var readAdminIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(readAdminIds), forKey: readKey) }
    }
    /// AUTO-ADDED user notes (hotspot saves) the user hasn't visited yet —
    /// they count toward the tab badge like unread admin notes.
    @Published var unreadUserIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(unreadUserIds), forKey: unreadUserKey) }
    }

    private let storageKey = "notebookPages.v1"
    private let adminCacheKey = "notebookAdminCache.v1"
    private let hiddenKey = "notebookHiddenAdmin.v1"
    private let readKey = "notebookReadAdmin.v1"
    private let unreadUserKey = "notebookUnreadUser.v1"

    /// Admin pages the user hasn't hidden.
    var visibleAdminPages: [NotebookPage] { adminPages.filter { !hiddenAdminIds.contains($0.id) } }
    /// Visible admin notes the user hasn't opened yet.
    var unreadAdminCount: Int { visibleAdminPages.filter { !readAdminIds.contains($0.id) }.count }
    /// Tab badge: unread admin notes + auto-added user notes not yet visited.
    var unreadCount: Int {
        let userUnread = userPages.filter { unreadUserIds.contains($0.id) }.count
        return unreadAdminCount + userUnread
    }
    func markAdminRead(_ id: String) { readAdminIds.insert(id) }
    /// Opening the Notebook clears the badge — everything visible counts as seen.
    func markAllAdminRead() {
        readAdminIds.formUnion(visibleAdminPages.map { $0.id })
        unreadUserIds.removeAll()
    }
    /// Admin pages the user has hidden.
    var hiddenAdminPages: [NotebookPage] { adminPages.filter { hiddenAdminIds.contains($0.id) } }

    func setAdminHidden(_ id: String, _ hidden: Bool) {
        if hidden { hiddenAdminIds.insert(id) } else { hiddenAdminIds.remove(id) }
    }

    init() {
        hiddenAdminIds = Set(UserDefaults.standard.array(forKey: "notebookHiddenAdmin.v1") as? [String] ?? [])
        readAdminIds = Set(UserDefaults.standard.array(forKey: "notebookReadAdmin.v1") as? [String] ?? [])
        unreadUserIds = Set(UserDefaults.standard.array(forKey: "notebookUnreadUser.v1") as? [String] ?? [])
        // Admin: prefer the cached server copy; otherwise the compiled fallback.
        if let cached = UserDefaults.standard.data(forKey: adminCacheKey),
           let decoded = try? JSONDecoder().decode([NotebookPage].self, from: cached) {
            adminPages = decoded
        } else {
            adminPages = NotebookManager.parseAdminNotes(adminNotesSource)
        }
        // User pages.
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([NotebookPage].self, from: data) {
            userPages = decoded
        } else {
            userPages = []
        }
        // Refresh admin notes from the server in the background.
        Task { await fetchAdminNotes() }
    }

    /// Fetch the global admin notebook from the server and cache it. On failure
    /// (offline, etc.) the cached/fallback pages remain in place.
    @MainActor
    func fetchAdminNotes() async {
        guard let url = URL(string: "\(Secrets.serverBaseURL)/api/reader/notebook") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            struct Payload: Decodable {
                struct Note: Decodable { let id: String; let title: String; let body: String }
                let notes: [Note]
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let pages = payload.notes.map { NotebookPage(id: $0.id, title: $0.title, body: $0.body) }
            if let encoded = try? JSONEncoder().encode(pages) {
                UserDefaults.standard.set(encoded, forKey: adminCacheKey)
            }
            adminPages = pages
        } catch {
            // Keep whatever we already have (cache or fallback).
        }
    }

    /// Insert a new user page or update an existing one (matched by id).
    func upsert(_ page: NotebookPage, markUnread: Bool = false) {
        if let idx = userPages.firstIndex(where: { $0.id == page.id }) {
            userPages[idx] = page
        } else {
            // Newest note on top (manual pages and auto-saved hotspot notes
            // alike). Existing notes keep their position when edited.
            userPages.insert(page, at: 0)
            if markUnread { unreadUserIds.insert(page.id) }
        }
    }

    func delete(_ page: NotebookPage) {
        userPages.removeAll { $0.id == page.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(userPages) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Split the admin source into pages on lines beginning with "# ".
    static func parseAdminNotes(_ src: String) -> [NotebookPage] {
        var pages: [NotebookPage] = []
        var title: String?
        var bodyLines: [String] = []
        func flush() {
            guard let t = title else { return }
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            pages.append(NotebookPage(id: "admin-\(pages.count)", title: t, body: body))
        }
        for line in src.components(separatedBy: "\n") {
            if line.hasPrefix("# ") {
                flush()
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                bodyLines = []
            } else {
                bodyLines.append(line)
            }
        }
        flush()
        return pages
    }
}

/// A resolved "Open in comic" destination from a note's hotspot link.
private struct NotebookLinkTarget: Identifiable {
    let id = UUID()
    let comic: Comic
    let page: Page
    let hotspotId: String
}

/// Handwritten-style notebook. Cream paper pages in the Comic Relief face.
struct NotebookView: View {
    @EnvironmentObject private var notebook: NotebookManager
    @State private var editingPage: NotebookPage?
    @State private var readingPage: NotebookPage?
    @State private var showingHelp = false
    @State private var linkTarget: NotebookLinkTarget?
    @State private var linkError: String?

    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    /// Resolve a note's hotspot link against the comics on this device and open
    /// it — or explain why we can't (comic deleted / not downloaded).
    private func openComicLink(_ page: NotebookPage) {
        guard let comicId = page.linkComicId, let hotspotId = page.linkHotspotId else { return }
        guard let comic = LocalComicStorage.shared.downloadedComics.first(where: { $0.id == comicId }) else {
            linkError = "This comic isn't on your device any more. Re-download it from your Library, then try the link again."
            return
        }
        let sorted = comic.pages.sorted { $0.pageNumber < $1.pageNumber }
        guard let target = sorted.first(where: { $0.pageNumber == page.linkPageNumber }) ?? sorted.first else {
            linkError = "This comic has no pages on this device."
            return
        }
        linkTarget = NotebookLinkTarget(comic: comic, page: target, hotspotId: hotspotId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // "My notes" first (newest on top); admin notes below, in
                // their original (earliest-first) order.
                sectionHeader("My notes")
                if notebook.userPages.isEmpty {
                    Text("Tap + to add a note.")
                        .font(.custom("ComicRelief-Regular", size: 16))
                        .foregroundColor(Self.ink.opacity(0.55))
                        .padding(.vertical, 4)
                } else {
                    ForEach(notebook.userPages) { page in
                        NotebookPaper(page: page, locked: false,
                                      onOpenLink: page.hasComicLink ? { openComicLink(page) } : nil)
                            .onTapGesture { editingPage = page }
                            .contextMenu {
                                Button(role: .destructive) {
                                    notebook.delete(page)
                                } label: {
                                    Label("Delete note", systemImage: "trash")
                                }
                            }
                    }
                }

                if !notebook.visibleAdminPages.isEmpty {
                    sectionHeader("Admin Notes")
                    ForEach(notebook.visibleAdminPages) { page in
                        NotebookPaper(page: page, locked: true)
                            .onTapGesture { readingPage = page; notebook.markAdminRead(page.id) }
                            .contextMenu {
                                Button {
                                    notebook.setAdminHidden(page.id, true)
                                } label: {
                                    Label("Hide note", systemImage: "eye.slash")
                                }
                            }
                    }
                }

                if !notebook.hiddenAdminPages.isEmpty {
                    DisclosureGroup("Hidden admin notes (\(notebook.hiddenAdminPages.count))") {
                        ForEach(notebook.hiddenAdminPages) { page in
                            HStack {
                                Text(page.title.isEmpty ? "Untitled" : page.title)
                                    .font(.custom("ComicRelief-Regular", size: 16))
                                    .foregroundColor(Self.ink.opacity(0.7))
                                    .lineLimit(1)
                                Spacer()
                                Button("Unhide") { notebook.setAdminHidden(page.id, false) }
                                    .font(.custom("ComicRelief-Bold", size: 14))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .font(.custom("ComicRelief-Bold", size: 14))
                    .foregroundColor(Self.ink.opacity(0.6))
                    .tint(Self.ink.opacity(0.6))
                }

            }
            .padding()
        }
        .background(Color(red: 0.93, green: 0.91, blue: 0.85).ignoresSafeArea())
        .navigationTitle("Notebook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingPage = NotebookPage()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            NotebookHelpView()
        }
        .sheet(item: $editingPage) { page in
            NotebookPageEditor(page: page, onSave: { updated in
                // Don't keep an entirely empty page.
                if updated.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && updated.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    notebook.delete(updated)
                } else {
                    notebook.upsert(updated)
                }
            }, onDelete: {
                notebook.delete(page)
            })
        }
        .sheet(item: $readingPage) { page in
            NotebookPageReader(page: page, onCopyToMyNotes: {
                // Make an independent, editable copy in My notes (keeps admin highlights).
                let copy = NotebookPage(title: page.title, body: page.body)
                notebook.upsert(copy)
            }, onHide: {
                notebook.setAdminHidden(page.id, true)
            })
        }
        // "Open in comic": present the page full-screen and auto-open the hotspot
        // (mirrors the Vocabulary "see in context" pattern).
        .fullScreenCover(item: $linkTarget) { target in
            NavigationStack {
                PageView(
                    comic: target.comic,
                    page: target.page,
                    initialHotspotId: target.hotspotId,
                    savesProgress: false,
                    presentedModally: true
                )
            }
            .environmentObject(SettingsManager())
            .environmentObject(ReadingProgressManager())
        }
        .alert("Can't open link", isPresented: Binding(
            get: { linkError != nil },
            set: { if !$0 { linkError = nil } }
        )) {
            Button("OK", role: .cancel) { linkError = nil }
        } message: {
            Text(linkError ?? "")
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom("ComicRelief-Bold", size: 14))
            .foregroundColor(Self.ink.opacity(0.5))
            .padding(.top, 4)
    }
}

/// One page rendered as cream paper with faint rules.
private struct NotebookPaper: View {
    let page: NotebookPage
    var locked: Bool = false
    /// Set on pages saved from a hotspot — renders an "Open in comic" action
    /// that jumps straight back to the hotspot.
    var onOpenLink: (() -> Void)? = nil
    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if !page.title.isEmpty {
                    Text(page.title)
                        .font(.custom("ComicRelief-Bold", size: 20.4))
                        .foregroundColor(Self.ink)
                }
                Spacer(minLength: 8)
                if locked {
                    Text("ADMIN")
                        .font(.custom("ComicRelief-Bold", size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)))
                }
            }
            Text(page.body.isEmpty ? AttributedString("Tap to write…") : notebookHighlighted(page.body))
                .font(.custom("ComicRelief-Regular", size: 19))
                .foregroundColor(page.body.isEmpty ? Self.ink.opacity(0.4) : Self.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(6)
                .lineLimit(locked ? 6 : nil)

            if page.hasComicLink, let onOpenLink {
                Button(action: onOpenLink) {
                    Label("Open in comic", systemImage: "book.fill")
                        .font(.custom("ComicRelief-Bold", size: 15))
                }
                .buttonStyle(.borderless)
                .tint(Color(red: 0x27/255, green: 0xAE/255, blue: 0x60/255))
                .padding(.top, 2)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.paper))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(locked
                        ? Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)   // logo purple — Admin
                        : Color(red: 0x27/255, green: 0xAE/255, blue: 0x60/255),  // green — My Notes
                        lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
    }
}

/// Read-only viewer for admin (grammar) pages, with a "copy to My Notes" action
/// so the user can make an editable, highlightable personal copy.
private struct NotebookPageReader: View {
    @Environment(\.dismiss) private var dismiss
    let page: NotebookPage
    var onCopyToMyNotes: () -> Void
    var onHide: () -> Void
    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(page.title)
                        .font(.custom("ComicRelief-Bold", size: 23.8))
                        .foregroundColor(Self.ink)
                    Text(notebookHighlighted(page.body))
                        .font(.custom("ComicRelief-Regular", size: 20))
                        .foregroundColor(Self.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(7)

                    Button {
                        onCopyToMyNotes()
                        dismiss()
                    } label: {
                        Label("Copy admin note to My Notes for editing", systemImage: "square.and.pencil")
                            .font(.custom("ComicRelief-Bold", size: 16))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255))
                    .padding(.top, 12)

                    Button {
                        onHide()
                        dismiss()
                    } label: {
                        Label("Hide note", systemImage: "eye.slash")
                            .font(.custom("ComicRelief-Regular", size: 15))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(Self.ink.opacity(0.6))
                    .padding(.top, 2)
                }
                .padding(24)
            }
            .background(Self.paper.ignoresSafeArea())
            .navigationTitle("Admin Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Explains how the notebook works.
private struct NotebookHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)
    private static let purple = Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)
    private static let green = Color(red: 0x27/255, green: 0xAE/255, blue: 0x60/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    block("Two kinds of notes", Self.ink, """
                    There are two sections in your notebook.
                    """)

                    block("📘 Admin Notes (purple border)", Self.purple, """
                    Grammar and tips from Comigo. They’re read-only here and update on their own — you can’t edit them directly, but you can copy or hide them.
                    """)

                    block("📗 My Notes (green border)", Self.green, """
                    Your own notes. Tap + at the top to add one, then tap a note to write and edit it.
                    """)

                    block("🖍 Highlighting", Self.ink, """
                    While editing a note, select some text and tap “Highlight” to mark it yellow. Tap it again to remove the highlight.
                    """)

                    block("Copy an admin note", Self.ink, """
                    Open an admin note and tap “Copy admin note to My Notes for editing” — the button is at the BOTTOM of the note. You’ll get your own editable copy (with its highlights) in My Notes.
                    """)

                    block("Hide an admin note", Self.ink, """
                    Open an admin note and tap “Hide note” at the BOTTOM (or press and hold the card). Hidden notes move into “Hidden admin notes” — tap Unhide to bring one back.
                    """)

                    block("Delete one of My Notes", Self.ink, """
                    Open your note and tap “Delete note” at the BOTTOM (or press and hold the card). Admin notes can’t be deleted — only hidden.
                    """)
                }
                .padding(24)
            }
            .background(Self.paper.ignoresSafeArea())
            .navigationTitle("How the notebook works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func block(_ title: String, _ titleColor: Color, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.custom("ComicRelief-Bold", size: 19))
                .foregroundColor(titleColor)
            Text(text)
                .font(.custom("ComicRelief-Regular", size: 16))
                .foregroundColor(Self.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Editor sheet for a single page.
private struct NotebookPageEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var page: NotebookPage
    var onSave: (NotebookPage) -> Void
    var onDelete: (() -> Void)? = nil

    private static let paper = Color(red: 0.99, green: 0.98, blue: 0.94)
    private static let ink = Color(red: 0.14, green: 0.15, blue: 0.22)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $page.title)
                    .font(.custom("ComicRelief-Bold", size: 22))
                    .foregroundColor(Self.ink)
                Divider()
                HighlightingTextView(
                    markup: $page.body,
                    font: UIFont(name: "ComicRelief-Regular", size: 19) ?? .systemFont(ofSize: 19),
                    textColor: UIColor(Self.ink)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete note", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding()
            .background(Self.paper.ignoresSafeArea())
            .navigationTitle("Edit page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onSave(page); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}


// MARK: - Store (Comigo Unlimited subscription)

/// StoreKit 2 wrapper for Comigo Unlimited: a monthly subscription (with a
/// free-trial introductory offer for eligible customers) or a one-time
/// lifetime unlock (non-consumable). StoreKit is the only source of truth for
/// entitlement, trial eligibility, trial state and expiry — no local timers.
///
/// Access rule (see `isUnlocked`): an active trial, paid subscription or
/// lifetime unlock opens everything, for every access model. Without one,
/// legacy users (and anyone not yet classified) keep the first episode of
/// every collection free; new-model users can browse but not read.
@MainActor
final class StoreService: ObservableObject {
    static let shared = StoreService()
    static let monthlyProductID = "com.comigo.unlimited.monthly"
    static let lifetimeProductID = "com.comigo.unlimited.lifetime"

    @Published private(set) var hasUnlimited = false
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var lifetimeProduct: Product?
    /// free / trial / subscribed / lifetime, from verified current entitlements.
    @Published private(set) var entitlement: Entitlement = .free
    /// End of the active free trial (StoreKit's expiration date for that period).
    @Published private(set) var trialEndsAt: Date?
    /// Next renewal of an active paid subscription.
    @Published private(set) var renewsAt: Date?
    /// The customer's last monthly period was the free trial, it has ended, and
    /// no paid period followed (StoreKit's latest transaction for the product).
    @Published private(set) var trialExpired = false
    /// StoreKit says this customer is eligible for the free-trial offer.
    @Published private(set) var freeTrialAvailable = false
    /// Apple's renewal info for the monthly subscription: false once the
    /// customer has turned auto-renew off (access continues to the period end).
    @Published private(set) var autoRenews: Bool?
    private var updatesTask: Task<Void, Never>?
    private var accessModelObservation: AnyCancellable?

    private init() {
        // Access depends on the access model as well; re-render gated views when it resolves.
        accessModelObservation = AccessModelService.shared.$classification.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Keep entitlement current across renewals/refunds/family sharing.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update {
                    await t.finish()
                    self?.reportPurchase(t, purchasedHere: false)
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func loadProducts() async {
        let products = (try? await Product.products(for: [Self.monthlyProductID, Self.lifetimeProductID])) ?? []
        monthlyProduct = products.first { $0.id == Self.monthlyProductID }
        lifetimeProduct = products.first { $0.id == Self.lifetimeProductID }
    }

    func refreshEntitlement() async {
        // Active subscription (trial or paid, incl. Apple's billing grace
        // period) OR the lifetime unlock — a non-consumable stays in
        // currentEntitlements forever unless refunded (revocationDate).
        var active = false
        var kind = Entitlement.free
        var trialEnd: Date?, renewal: Date?
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement,
               t.productID == Self.monthlyProductID || t.productID == Self.lifetimeProductID,
               t.revocationDate == nil {
                active = true
                if t.productID == Self.lifetimeProductID {
                    kind = .lifetime
                } else if kind != .lifetime {
                    if Self.isFreeTrialPeriod(t) {
                        kind = .trial; trialEnd = t.expirationDate
                    } else {
                        kind = .subscribed; renewal = t.expirationDate
                    }
                }
            }
        }
        entitlement = kind
        trialEndsAt = kind == .trial ? trialEnd : nil
        renewsAt = kind == .subscribed ? renewal : nil
        trialExpired = !active ? await Self.lastPeriodWasUnconvertedTrial() : false
        if let monthly = monthlyProduct {
            freeTrialAvailable = await isEligibleForFreeTrial(monthly)
            autoRenews = nil
            if kind == .trial || kind == .subscribed,
               let status = try? await monthly.subscription?.status.first,
               case .verified(let info) = status.renewalInfo {
                autoRenews = info.willAutoRenew
            }
        }
        AnalyticsService.shared.entitlement = kind
        #if DEBUG
        // Marketing recordings on the Simulator: `-demo.unlimited YES` opens every episode
        // without a purchase (debug builds only — never in the App Store build).
        if UserDefaults.standard.bool(forKey: "demo.unlimited") { active = true }
        #endif
        hasUnlimited = active
    }

    /// Returns true when the purchase completed and the entitlement is live.
    func purchase(_ product: Product) async throws -> Bool {
        // Attribution token only when the user has opted into analytics.
        let token = PurchaseAttribution.shared.tokenForPurchase()
        let result = try await product.purchase(options: token.map { [.appAccountToken($0)] } ?? [])
        switch result {
        case .success(let verification):
            if case .verified(let t) = verification {
                await t.finish()
                reportPurchase(t, purchasedHere: true)
            }
            await refreshEntitlement()
            return hasUnlimited
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
        // A restore is also the moment to fix a classification StoreKit
        // couldn't provide earlier (may ask the user to sign in).
        if AccessModelService.shared.classification == .unknown {
            await AccessModelService.shared.refreshAfterRestore()
        }
    }

    /// True when StoreKit's latest monthly transaction is a free-trial period
    /// that has ended (no paid renewal followed it, or it would be the latest).
    static func lastPeriodWasUnconvertedTrial(now: Date = Date()) async -> Bool {
        guard let latest = await Transaction.latest(for: monthlyProductID),
              case .verified(let t) = latest else { return false }
        return isFreeTrialPeriod(t) && t.revocationDate == nil && (t.expirationDate ?? .distantFuture) <= now
    }

    // MARK: - Purchase analytics
    // The app reports the moments only it sees reliably: a free trial starting
    // and a lifetime purchase. Paid subscription periods (direct starts, trial
    // conversions, renewals) are reported by the server from App Store Server
    // Notifications, so no event has two sources.

    private static let reportedKey = "analytics.reportedTransactions"

    /// `purchasedHere`: the transaction came back from this device's own
    /// purchase call. Otherwise (Transaction.updates — Ask to Buy approvals,
    /// purchases on the user's other devices, restores) it's only reported when
    /// it carries this install's attribution token, i.e. it was started here.
    func reportPurchase(_ t: StoreKit.Transaction, purchasedHere: Bool,
                        analytics: AnalyticsService = .shared,
                        defaults: UserDefaults = .standard,
                        installToken: UUID?? = .none) {
        let installToken = installToken ?? PurchaseAttribution.shared.existingToken
        guard analytics.isEnabled,
              t.revocationDate == nil,
              t.ownershipType == .purchased,
              purchasedHere || (t.appAccountToken != nil && t.appAccountToken == installToken)
        else { return }
        // Once per transaction: the purchase result and Transaction.updates can
        // both deliver the same transaction, and updates replay at launch.
        var reported = defaults.stringArray(forKey: Self.reportedKey) ?? []
        let id = String(t.id)
        guard !reported.contains(id), let event = Self.purchaseEvent(for: t) else { return }
        analytics.track(event)
        reported.append(id)
        defaults.set(Array(reported.suffix(100)), forKey: Self.reportedKey)
    }

    /// The app-side purchase event for a verified transaction, if any: a paid
    /// lifetime purchase, or the first transaction of a subscription whose
    /// period is its free trial. Paid subscription periods → nil (server's job).
    static func purchaseEvent(for t: StoreKit.Transaction) -> AnalyticsEvent? {
        if t.productID == lifetimeProductID {
            // Free lifetime unlocks (offer codes) aren't purchases.
            guard t.price.map({ $0 > 0 }) ?? true else { return nil }
            return .purchaseCompleted(productId: t.productID, purchaseType: .lifetime)
        }
        if t.productID == monthlyProductID, t.id == t.originalID, isFreeTrialPeriod(t) {
            return .trialStarted(productId: t.productID)
        }
        return nil
    }

    /// Whether `product` offers a free-trial introductory offer this user is
    /// eligible for, according to StoreKit.
    func isEligibleForFreeTrial(_ product: Product) async -> Bool {
        guard let sub = product.subscription, sub.introductoryOffer?.paymentMode == .freeTrial else { return false }
        return await sub.isEligibleForIntroOffer
    }

    /// Call when a paywall has put the free-trial offer for `product` on
    /// screen. Sends `trial_offer_viewed` only if StoreKit confirms this user is
    /// eligible for that free trial — so a paywall shown to someone who has
    /// already used their trial doesn't count. Once per paywall presentation is
    /// the caller's job (as with paywall_viewed).
    func trialOfferShown(_ product: Product, source: PaywallSource, analytics: AnalyticsService = .shared) async {
        guard await isEligibleForFreeTrial(product) else { return }
        analytics.track(.trialOfferViewed(source: source, productId: product.id))
    }

    /// The current period of this subscription transaction is its free-trial
    /// introductory offer. (iOS 17.0–17.1 can't read the payment mode; the only
    /// introductory offer Comigo configures is the free trial.)
    static func isFreeTrialPeriod(_ t: StoreKit.Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return t.offer?.type == .introductory && t.offer?.paymentMode == .freeTrial
        }
        return t.offerType == .introductory
    }

    /// The legacy free rule: first episode of every collection, and standalone comics.
    static func isFreeEpisode(episodeNumber: Int?, collectionId: String?) -> Bool {
        guard collectionId != nil else { return true }
        return (episodeNumber ?? 1) == 1
    }

    /// Free without any entitlement under this access model. Unknown is
    /// treated as legacy: access is never withdrawn on uncertainty.
    static func isFree(episodeNumber: Int?, collectionId: String?,
                       classification: AccessModelService.Classification) -> Bool {
        classification != .newModel && isFreeEpisode(episodeNumber: episodeNumber, collectionId: collectionId)
    }

    /// An active trial, paid subscription or lifetime unlock opens everything,
    /// whatever the access model; otherwise only the model's free episodes.
    static func isUnlocked(entitled: Bool, classification: AccessModelService.Classification,
                           episodeNumber: Int?, collectionId: String?) -> Bool {
        entitled || isFree(episodeNumber: episodeNumber, collectionId: collectionId, classification: classification)
    }

    func isUnlocked(episodeNumber: Int?, collectionId: String?) -> Bool {
        Self.isUnlocked(entitled: hasUnlimited, classification: AccessModelService.shared.classification,
                        episodeNumber: episodeNumber, collectionId: collectionId)
    }

    // MARK: - Paywall state

    enum PaywallMode: Equatable {
        /// StoreKit says the customer is eligible for the free trial.
        case freeTrial
        /// Not eligible (e.g. already had a trial): plain subscribe/lifetime.
        case subscribe
        /// New-model customer whose trial ended without a paid period.
        case trialExpired
    }

    static func paywallMode(isNewModel: Bool, trialExpired: Bool, entitled: Bool, eligibleForTrial: Bool) -> PaywallMode {
        if isNewModel && trialExpired && !entitled { return .trialExpired }
        return eligibleForTrial ? .freeTrial : .subscribe
    }

    /// The paywall's analytics source: a new-model customer whose trial has
    /// ended is reported as `trial_expired`, however they reached it.
    static func analyticsSource(requested: PaywallSource?, mode: PaywallMode) -> PaywallSource? {
        guard let requested else { return nil }
        return mode == .trialExpired ? .trialExpired : requested
    }

    func currentPaywallMode() async -> PaywallMode {
        if monthlyProduct == nil { await loadProducts() }
        let eligible: Bool
        if let monthly = monthlyProduct { eligible = await isEligibleForFreeTrial(monthly) } else { eligible = false }
        return Self.paywallMode(isNewModel: AccessModelService.shared.isNewModel, trialExpired: trialExpired,
                                entitled: hasUnlimited, eligibleForTrial: eligible)
    }

    /// Eligible new-model customers without an entitlement get the "Start your
    /// 7-day free trial" offer on the landing screen and on locked episodes.
    /// Independent of analytics consent.
    var showsTrialBanner: Bool {
        AccessModelService.shared.isNewModel && !hasUnlimited && freeTrialAvailable
    }

    /// Length of the free trial in days, from the product's introductory offer.
    static func trialDays(_ product: Product?) -> Int? {
        guard let offer = product?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        switch period.unit {
        case .day: return period.value * offer.periodCount
        case .week: return period.value * 7 * offer.periodCount
        default: return nil
        }
    }

    /// "month", "year", "3 months"… for the product's billing period.
    static func billingPeriodText(_ product: Product?) -> String {
        guard let period = product?.subscription?.subscriptionPeriod else { return "month" }
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    enum StoreError: LocalizedError {
        case productUnavailable
        var errorDescription: String? { "The subscription isn't available right now. Please try again in a moment." }
    }
}

// MARK: - Paywall

struct PaywallView: View {
    /// What opened the paywall, for analytics; nil for the debug screenshot preview.
    let source: PaywallSource?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = StoreService.shared
    @ObservedObject private var access = AccessModelService.shared
    @State private var mode: StoreService.PaywallMode?
    @State private var purchasing = false
    @State private var restoring = false
    @State private var errorMessage: String?
    @State private var viewTracked = false

    private let violet = Color(red: 0x6E/255, green: 0x40/255, blue: 0xF0/255)
    private let ink = Color(red: 0x15/255, green: 0x17/255, blue: 0x2A/255)

    private var monthly: Product? { store.monthlyProduct }
    private var period: String { StoreService.billingPeriodText(monthly) }
    private var trialDays: Int { StoreService.trialDays(monthly) ?? 7 }

    private var headline: String {
        switch mode {
        case .freeTrial: return "Try Comigo free for \(trialDays) days"
        case .trialExpired: return "Your free trial has ended"
        default: return "Keep the story going"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .accessibilityLabel("Close")
            }
            .padding([.top, .horizontal], 18)

            ScrollView {
                VStack(spacing: 0) {
                    Image("comicgo_logo_yoni_1_alpha_layer_2")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 170)

                    Text(headline)
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                    if mode == .trialExpired {
                        Text("Subscribe to keep reading every comic.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.top, 6)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        if mode == .freeTrial {
                            paywallRow("sparkles", "Full access free for \(trialDays) days")
                        }
                        paywallRow("book.fill", "Every episode of every series — current and future")
                        paywallRow("waveform", "All audio, translations and practice modes")
                        paywallRow("plus.circle.fill", "New comics added regularly")
                        if !access.isNewModel {
                            paywallRow("gift.fill", "The first episode of every series stays free")
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, 18)
                }
                .padding(.bottom, 12)
            }

            VStack(spacing: 10) {
                subscribeButton
                if let lifetime = store.lifetimeProduct {
                    Button {
                        purchase(lifetime)
                    } label: {
                        VStack(spacing: 3) {
                            Text("Lifetime access")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                            Text("\(lifetime.displayPrice) once · yours forever")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .opacity(0.85)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 2))
                    }
                    .disabled(purchasing)
                }
                if let terms = subscriptionTerms {
                    Text(terms)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 28)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
            }

            Button(restoring ? "Restoring…" : "Restore purchases") { restore() }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .disabled(restoring)
                .padding(.top, 10)

            HStack(spacing: 18) {
                Link("Privacy Policy", destination: URL(string: "https://comigo.net/privacy")!)
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.footnote)
            .foregroundColor(.white.opacity(0.7))
            .padding(.top, 8)
            .padding(.bottom, 22)
        }
        .background(violet.ignoresSafeArea())
        .task { await resolveMode() }
        .onChange(of: store.hasUnlimited) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    @ViewBuilder
    private var subscribeButton: some View {
        Button {
            purchase(monthly)
        } label: {
            VStack(spacing: 3) {
                Text(purchasing ? "One moment…" : (mode == .freeTrial ? "Start free trial" : "Subscribe"))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                if let monthly {
                    Text(mode == .freeTrial
                         ? "\(trialDays) days free, then \(monthly.displayPrice) / \(period)"
                         : "\(monthly.displayPrice) / \(period) · cancel anytime")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
            }
            .foregroundColor(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ink, lineWidth: 3))
        }
        .disabled(purchasing || mode == nil)
    }

    /// Apple's required auto-renewal disclosure, with StoreKit's localised price.
    private var subscriptionTerms: String? {
        guard let monthly else { return nil }
        if mode == .freeTrial {
            return "Your \(trialDays)-day free trial automatically becomes a \(monthly.displayPrice)/\(period) subscription unless you cancel at least 24 hours before it ends. Payment is charged to your Apple Account when the trial ends; the subscription renews automatically each \(period) until cancelled. Cancel anytime in Settings → Apple Account → Subscriptions."
        }
        return "Comigo Unlimited is \(monthly.displayPrice)/\(period), charged to your Apple Account, and renews automatically unless cancelled at least 24 hours before the end of the current period. Cancel anytime in Settings → Apple Account → Subscriptions."
    }

    private func paywallRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.yellow)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
    }

    /// Works out which offer this customer gets (StoreKit eligibility), then
    /// records the view once — with trial_expired as the source for a
    /// new-model customer whose trial has ended.
    private func resolveMode() async {
        let resolved = await store.currentPaywallMode()
        mode = resolved
        guard !viewTracked, let source = StoreService.analyticsSource(requested: source, mode: resolved) else { return }
        viewTracked = true
        AnalyticsService.shared.track(.paywallViewed(source: source))
        if resolved == .freeTrial, let monthly {
            await store.trialOfferShown(monthly, source: source)
        }
    }

    private func purchase(_ product: Product?) {
        errorMessage = nil
        guard let product else {
            // Products not loaded yet (offline / App Store hiccup) — retry the fetch.
            errorMessage = StoreService.StoreError.productUnavailable.errorDescription
            Task { await store.loadProducts(); await resolveMode() }
            return
        }
        purchasing = true
        Task {
            do {
                let ok = try await StoreService.shared.purchase(product)
                if ok { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
            purchasing = false
        }
    }

    private func restore() {
        restoring = true
        errorMessage = nil
        Task {
            await store.restore()
            restoring = false
            if store.hasUnlimited {
                dismiss()
            } else {
                errorMessage = "No active Comigo Unlimited purchase was found for this Apple Account."
                await resolveMode()
            }
        }
    }
}
