import SwiftUI

/// First-run analytics choice. Non-blocking: it sits at the bottom of the
/// Library until answered, the app works fully either way, and both answers
/// are equally easy (same size, same weight) — neither is the "default".
struct AnalyticsConsentCard: View {
    let onChoice: (Bool) -> Void

    private let accent = Color(red: 91/255, green: 91/255, blue: 214/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Help improve Comigo", systemImage: "chart.bar.fill")
                .font(.headline)
            Text("Would you like to share usage information to help us understand how Comigo is used and improve the app?")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("It's linked to a random ID, never to your name, email or Apple ID, never includes your voice or answers, and is never used for ads. You can change this anytime in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Privacy Policy", destination: URL(string: "https://comigo.net/privacy")!)
                .font(.footnote.weight(.semibold))
            HStack(spacing: 10) {
                choiceButton("No thanks", granted: false)
                choiceButton("Allow analytics", granted: true)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.comigoInk, lineWidth: 2))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }

    private func choiceButton(_ title: String, granted: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onChoice(granted)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
