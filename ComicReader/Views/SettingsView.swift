import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    var body: some View {
        List {
            // Appearance Section
            Section {
                Picker(selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
            } header: {
                Text("Appearance")
            }

            // Reading Section
            Section {
                Toggle(isOn: $settingsManager.autoPlayAudio) {
                    Label("Auto-play audio", systemImage: "speaker.wave.2.fill")
                }

                Toggle(isOn: $settingsManager.hapticFeedback) {
                    Label("Haptic feedback", systemImage: "hand.tap.fill")
                }

                Toggle(isOn: $settingsManager.recordCueSound) {
                    Label("Speaking cue sound", systemImage: "waveform.and.mic")
                }

                Picker(selection: $settingsManager.playbackSpeed) {
                    Text("0.5x").tag(0.5)
                    Text("0.75x").tag(0.75)
                    Text("1x").tag(1.0)
                    Text("1.25x").tag(1.25)
                    Text("1.5x").tag(1.5)
                } label: {
                    Label("Playback Speed", systemImage: "speedometer")
                }
            } header: {
                Text("Reading")
            }

            // Account Section
            Section {
                NavigationLink {
                    SubscriptionSettingsView()
                } label: {
                    Label("Subscription", systemImage: "creditcard.fill")
                }
            } header: {
                Text("Account")
            }

            // About Section
            Section {
                Label("Tap ? on any screen to see what each button does.",
                      systemImage: "questionmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "mailto:nir@comigo.net")!) {
                    Label("Contact & feedback", systemImage: "envelope.fill")
                }

                Link(destination: URL(string: "https://comigo.net/privacy.html")!) {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }

                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    Label("Terms of Use", systemImage: "doc.text.fill")
                }
            } header: {
                Text("About")
            }

            // Version (real values from the bundle, not a hard-coded string)
            Section {
                HStack {
                    Spacer()
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Subscription settings
/// Real subscription status + actions, backed by StoreService. Replaces the
/// old placeholder screen.
struct SubscriptionSettingsView: View {
    @StateObject private var store = StoreService.shared
    @State private var showPaywall = false
    @State private var restoring = false

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Comigo Unlimited", systemImage: store.hasUnlimited ? "checkmark.seal.fill" : "lock.fill")
                    Spacer()
                    Text(store.hasUnlimited ? "Active" : "Not subscribed")
                        .foregroundStyle(store.hasUnlimited ? .green : .secondary)
                }
            } footer: {
                Text("The first episode of every series is free. Comigo Unlimited unlocks every episode — as a monthly subscription or a one-time lifetime purchase.")
            }

            Section {
                if !store.hasUnlimited {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("View plans", systemImage: "sparkles")
                    }
                }

                Button {
                    restoring = true
                    Task {
                        await store.restore()
                        restoring = false
                    }
                } label: {
                    HStack {
                        Label("Restore purchases", systemImage: "arrow.clockwise")
                        if restoring {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(restoring)

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    Label("Manage subscription", systemImage: "gearshape.fill")
                }
            }
        }
        .navigationTitle("Subscription")
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .task { await store.refreshEntitlement() }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(SettingsManager())
    }
}
