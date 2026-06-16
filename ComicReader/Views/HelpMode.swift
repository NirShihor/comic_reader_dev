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
    func helpTooltipLayer() -> some View {
        overlayPreferenceValue(HelpAnchorKey.self) { anchors in
            GeometryReader { proxy in
                HelpTooltipOverlay(anchors: anchors, proxy: proxy)
            }
            .ignoresSafeArea()
        }
    }
}

private struct HelpTooltipOverlay: View {
    let anchors: [String: Anchor<CGRect>]
    let proxy: GeometryProxy
    @EnvironmentObject private var help: HelpModeController
    @State private var size: CGSize = .zero

    private let arrowH: CGFloat = 8
    private let arrowW: CGFloat = 18
    private let gap: CGFloat = 8
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
                    .fill(Color(.secondarySystemBackground))
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
                .padding(.trailing, 20) // leave room for the close button
            Text(help.activeText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                help.activeID = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
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
