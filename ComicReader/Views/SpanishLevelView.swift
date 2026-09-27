import SwiftUI

/// First-run "What's your Spanish level?" screen, shown once after the landing
/// screen until a level is chosen. Independent of analytics consent.
struct SpanishLevelView: View {
    let onContinue: (SpanishLevel) -> Void
    @State private var selected: SpanishLevel?

    var body: some View {
        ZStack {
            Brand.violet.ignoresSafeArea()
            VStack(spacing: 0) {
                Text("What's your Spanish level?")
                    .font(Brand.display(30))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 36)
                    .padding(.bottom, 22)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(SpanishLevel.allCases) { level in
                            option(level)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }

                Button {
                    if let selected { onContinue(selected) }
                } label: {
                    Text("Continue")
                        .font(Brand.body(16, .heavy))
                        .foregroundColor(Brand.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(selected == nil ? 0.55 : 1),
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Brand.ink, lineWidth: 3.5))
                }
                .buttonStyle(.plain)
                .disabled(selected == nil)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .readableColumn(560)
        }
    }

    private func option(_ level: SpanishLevel) -> some View {
        let isSelected = selected == level
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selected = level
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.title)
                        .font(Brand.body(17, .heavy))
                        .foregroundColor(Brand.ink)
                    Text(level.detail)
                        .font(Brand.body(14))
                        .foregroundColor(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? Brand.violet : Brand.ink.opacity(0.35))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Brand.yellow : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Brand.ink, lineWidth: isSelected ? 3 : 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
