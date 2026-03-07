import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        List {
            // Practice Section
            Section {
                Toggle(isOn: $settingsManager.speakingPracticeMode) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speaking Practice Mode")
                            Text("Show English text in comic bubbles and practice speaking Spanish")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.blue)
                    }
                }
            } header: {
                Text("Practice")
            }

            // Reading Section
            Section {
                Toggle(isOn: $settingsManager.autoPlayAudio) {
                    Label("Auto-play audio", systemImage: "speaker.wave.2.fill")
                }

                Toggle(isOn: $settingsManager.hapticFeedback) {
                    Label("Haptic feedback", systemImage: "hand.tap.fill")
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
                    Text("Profile")
                        .navigationTitle("Profile")
                } label: {
                    Label("Profile", systemImage: "person.fill")
                }

                NavigationLink {
                    Text("Subscription")
                        .navigationTitle("Subscription")
                } label: {
                    Label("Subscription", systemImage: "creditcard.fill")
                }
            } header: {
                Text("Account")
            }

            // About Section
            Section {
                NavigationLink {
                    Text("Help content")
                        .navigationTitle("Help")
                } label: {
                    Label("Help", systemImage: "questionmark.circle.fill")
                }

                NavigationLink {
                    Text("Terms of Service content")
                        .navigationTitle("Terms of Service")
                } label: {
                    Label("Terms of Service", systemImage: "doc.text.fill")
                }
            } header: {
                Text("About")
            }

            // Version
            Section {
                HStack {
                    Spacer()
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(SettingsManager())
    }
}
