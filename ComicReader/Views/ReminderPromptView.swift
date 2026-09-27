import SwiftUI

/// "Want a little reminder?" — Comigo's own question, offered once after the
/// first completed comic. Only "Allow reminders" leads to iOS's permission prompt.
struct ReminderPromptView: View {
    @ObservedObject var reminders: ReminderService
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(Brand.violet)
                Text("Want a little reminder?")
                    .font(Brand.body(20, .heavy))
            }
            Text("Comigo can remind you if you haven't read any Spanish for a few days.")
                .font(Brand.body(15.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    reminders.notNow()
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(Brand.body(15, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.comigoInk, lineWidth: 1.5))
                }
                Button {
                    working = true
                    Task {
                        await reminders.allowReminders()
                        working = false
                        dismiss()
                    }
                } label: {
                    Text(working ? "One moment…" : "Allow reminders")
                        .font(Brand.body(15, .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Brand.violet, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.comigoInk, lineWidth: 1.5))
                }
                .disabled(working)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(22)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
        // Swiping it away counts as "Not now" — the offer isn't repeated.
        .onDisappear { if reminders.promptAnswer == nil { reminders.notNow() } }
    }
}
