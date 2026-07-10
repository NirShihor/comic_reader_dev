import SwiftUI
import UIKit

// MARK: - Tap-to-explain help mode
//
// A lightweight, in-place help system. A "?" button toggles help mode for a
// screen. While it's on, every control tagged with `.explains(...)` shows a
// subtle highlight *in place* (nothing dims — the screen stays live), and
// tapping a highlighted control shows a small bubble that points right at it
// and explains what it does. Tap the bubble (or "?") to dismiss.
//
// The bubble is drawn by us (not a system popover, which adapts to a full-screen
// sheet on iPhone) so it stays compact and identical on every device.
//
// Usage:
//   1. At the screen root:   @StateObject private var help = HelpModeController()
//                            ... .environmentObject(help).helpTooltipLayer()
//   2. A "?" toolbar button: HelpModeButton()   (or call help.toggle())
//   3. Tag each control:     SomeButton().explains("Play", "Plays the sentence aloud.")

@MainActor
final class HelpModeController: ObservableObject {
    /// Whether help mode is currently on for the screen.
    @Published var isActive = false
    /// The id of the control whose explanation bubble is currently shown.
    @Published var activeID: String?
    /// Title/body of the currently shown explanation.
    @Published var activeTitle = ""
    @Published var activeText = ""

    func toggle() {
        isActive.toggle()
        if !isActive { activeID = nil }
    }

    func tap(_ id: String, _ title: String, _ text: String) {
        if activeID == id {
            activeID = nil
        } else {
            activeTitle = title
            activeText = text
            activeID = id
        }
    }
}

// MARK: - Tagging controls

extension View {
    /// Tag a control with an explanation shown in help mode. `title` is a short
    /// label; `text` is one or two sentences on what the control does.
    func explains(_ title: String, _ text: String, id: String? = nil) -> some View {
        modifier(ExplainsModifier(id: id ?? title, title: title, text: text))
    }

    /// Conditionally tag — handy inside ForEach to explain only the first of a
    /// repeating control (e.g. one representative word).
    @ViewBuilder
    func explainsIf(_ condition: Bool, _ title: String, _ text: String, id: String? = nil) -> some View {
        if condition { explains(title, text, id: id) } else { self }
    }
}

private struct HelpAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { current, _ in current }
    }
}

private struct ExplainsModifier: ViewModifier {
    @EnvironmentObject private var help: HelpModeController
    let id: String
    let title: String
    let text: String

    func body(content: Content) -> some View {
        content
            .overlay {
                if help.isActive {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        )
                        .padding(-3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.15)) {
                                help.tap(id, title, text)
                            }
                        }
                        .transition(.opacity)
                }
            }
            .anchorPreference(key: HelpAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - Tooltip layer (drawn once per screen, above the controls)

extension View {
    /// Draws the active explanation bubble. Apply at the screen root, after
    /// `.environmentObject(help)`, so it sits above every tagged control.
    /// `bannerEdge` chooses which edge the "help is on" strip sits on — pass `.top`
    /// on screens where a panel occupies the bottom (e.g. the reader's bubble popup),
    /// so the strip doesn't cover it.
    func helpTooltipLayer(bannerEdge: VerticalEdge = .bottom) -> some View {
        overlayPreferenceValue(HelpAnchorKey.self) { anchors in
            GeometryReader { proxy in
                HelpTooltipOverlay(anchors: anchors, proxy: proxy)
            }
            .ignoresSafeArea()
        }
        // A persistent banner (respecting the safe area) telling the user how to
        // close help — otherwise the auto-opened explainers look stuck.
        .overlay(alignment: bannerEdge == .top ? .top : .bottom) { HelpCloseBanner(edge: bannerEdge) }
    }
}

/// Shown at the top while help mode is on, so users know to tap "?" to close.
/// Tapping the banner itself also closes help.
private struct HelpCloseBanner: View {
    var edge: VerticalEdge = .bottom
    @EnvironmentObject private var help: HelpModeController

    var body: some View {
        if help.isActive {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.white))
                    Text("Help is on — tap ? (top right) or here to close")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.blue))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(edge == .top ? .top : .bottom, 10)
            .transition(.move(edge: edge == .top ? .top : .bottom).combined(with: .opacity))
            .zIndex(100)
        }
    }
}

private struct HelpTooltipOverlay: View {
    let anchors: [String: Anchor<CGRect>]
    let proxy: GeometryProxy
    @EnvironmentObject private var help: HelpModeController
    @State private var size: CGSize = .zero

    private let arrowH: CGFloat = 4
    private let arrowW: CGFloat = 18
    private let gap: CGFloat = 0   // hug the target element
    private let margin: CGFloat = 12

    var body: some View {
        if let id = help.activeID, let anchor = anchors[id] {
            let rect = proxy[anchor]
            let container = proxy.size
            let placeAbove = rect.midY > container.height / 2

            let halfW = size.width / 2
            let centerX = min(max(rect.midX, margin + halfW), container.width - margin - halfW)
            let centerY = placeAbove
                ? rect.minY - gap - arrowH - size.height / 2
                : rect.maxY + gap + arrowH + size.height / 2
            let arrowX = min(max(rect.midX, centerX - halfW + 12), centerX + halfW - 12)

            ZStack(alignment: .topLeading) {
                Triangle()
                    .fill(Color.orange)
                    .frame(width: arrowW, height: arrowH)
                    .rotationEffect(.degrees(placeAbove ? 180 : 0))
                    .position(
                        x: arrowX,
                        y: placeAbove
                            ? centerY + size.height / 2 + arrowH / 2 - 0.5
                            : centerY - size.height / 2 - arrowH / 2 + 0.5
                    )

                bubble
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: SizeKey.self, value: g.size)
                        }
                    )
                    .onPreferenceChange(SizeKey.self) { size = $0 }
                    .position(x: centerX, y: centerY)
            }
            .frame(width: container.width, height: container.height)
            .transition(.opacity)
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(help.activeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.trailing, 20) // leave room for the close button
            Text(help.activeText)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                help.activeID = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .padding(6)
            .accessibilityLabel("Close")
        }
    }
}

private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// A small upward-pointing triangle used as the bubble's arrow tail.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A floating affordance shown only in help mode, for things that aren't a
/// tappable control — gestures (swiping) or whole-area actions (tap a panel).
/// It reads as a hint chip and, tapped, explains itself like any other control.
struct HelpHint: View {
    @EnvironmentObject private var help: HelpModeController
    let icon: String
    let label: String
    let title: String
    let text: String
    /// When true, the icon nudges left↔right to suggest a swipe.
    var animatedSwipe: Bool = false

    @State private var nudge = false

    var body: some View {
        if help.isActive {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .offset(x: animatedSwipe ? (nudge ? 5 : -5) : 0)
                Text(label)
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.ultraThinMaterial))
            .explains(title, text, id: "hint.\(title)")
            .transition(.scale.combined(with: .opacity))
            .onAppear {
                if animatedSwipe {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        nudge = true
                    }
                }
            }
        }
    }
}

/// A "?" toggle for the navigation bar. Fills in when help mode is active.
struct HelpModeButton: View {
    @EnvironmentObject private var help: HelpModeController

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { help.toggle() }
        } label: {
            Image(systemName: help.isActive ? "questionmark.circle.fill" : "questionmark.circle")
        }
        .accessibilityLabel(help.isActive ? "Exit help" : "Help")
    }
}

// MARK: - First-visit auto-trigger

enum HelpDebug {
    /// While true, first-run tooltips show EVERY time (ignoring their "seen"
    /// memory) so they can be reviewed without reinstalling. DEBUG builds only —
    /// release/TestFlight always behaves once-only, so nothing leaks to users.
    /// To test real once-only behaviour in a debug build, flip this to false.
    static var forceShowTooltips: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

extension View {
    /// Auto-open help mode the FIRST time this screen/element is seen (per `key`,
    /// remembered forever), then never again automatically — the "?" button still
    /// toggles it on demand as usual. Apply AFTER `.environmentObject(help)`, and
    /// pass the same `help` controller so it flips the right one.
    func helpFirstVisit(_ key: String, _ help: HelpModeController) -> some View {
        modifier(HelpFirstVisit(key: key, help: help))
    }
}

private struct HelpFirstVisit: ViewModifier {
    let help: HelpModeController
    @AppStorage private var seen: Bool

    init(key: String, help: HelpModeController) {
        self.help = help
        _seen = AppStorage(wrappedValue: false, "help.seen.\(key)")
    }

    func body(content: Content) -> some View {
        content.onAppear {
            if !HelpDebug.forceShowTooltips {
                guard !seen else { return }
                seen = true
            }
            // Let the screen settle before the highlights appear.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.2)) { help.isActive = true }
            }
        }
    }
}

// MARK: - Help intro callout

/// A one-time callout that points up at the "?" help button (top-right), telling
/// the reader help is available. Colour-matched to the button's indigo accent so
/// the two read as linked. Tapping it dismisses. Place with
/// `.overlay(alignment: .topTrailing)`.
struct HelpIntroCallout: View {
    let text: String
    var icon: String? = "questionmark.circle.fill"
    var accent: Color = Color(red: 232/255, green: 169/255, blue: 60/255)   // #E8A93C amber
    var arrowEdge: HorizontalAlignment = .trailing   // which side the up-arrow sits on
    var arrowInset: CGFloat = 16                     // how far in from that edge
    var maxWidth: CGFloat = 250
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: arrowEdge, spacing: 0) {
            Triangle()
                .fill(accent)
                .frame(width: 20, height: 10)
                .padding(arrowEdge == .leading ? Edge.Set.leading : Edge.Set.trailing, arrowInset)
            HStack(alignment: .top, spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.subheadline)
                }
                Text(text)
                    .font(.subheadline).fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color(red: 0.24, green: 0.15, blue: 0.02))   // dark, readable on the amber
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .frame(maxWidth: maxWidth)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(text)
    }
}
