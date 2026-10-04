import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("demo.hideCues") private var hideCues = false
    @ObservedObject private var analytics = AnalyticsService.shared
    @ObservedObject private var aggregateCounts = AggregateTelemetryService.shared
    @ObservedObject private var reminders = ReminderService.shared
    @AppStorage(SpanishLevel.storageKey) private var spanishLevelRaw = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    private var hideCuesBinding: Binding<Bool> {
        Binding(get: { hideCues }, set: { hideCues = $0 })
    }

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

            // Learning Section
            Section {
                NavigationLink {
                    SpanishLevelSettingsView()
                } label: {
                    HStack {
                        Label("Spanish level", systemImage: "graduationcap.fill")
                        Spacer()
                        Text(SpanishLevel(rawValue: spanishLevelRaw)?.title ?? "Not set")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Learning")
            }

            // Reminders Section — reflects iOS's actual notification permission.
            Section {
                if reminders.settingsState == .blockedInSystem {
                    HStack {
                        Label("Inactivity reminders", systemImage: "bell.slash.fill")
                        Spacer()
                        Text("Off in iOS Settings").foregroundStyle(.secondary)
                    }
                    Button {
                        if let url = ReminderService.systemSettingsURL { openURL(url) }
                    } label: {
                        Label("Open iOS Settings", systemImage: "gear")
                    }
                } else {
                    Toggle(isOn: Binding(
                        get: { reminders.settingsState == .on },
                        set: { on in
                            if on { Task { await reminders.allowReminders() } } else { reminders.disableReminders() }
                        })) {
                        Label("Inactivity reminders", systemImage: "bell.fill")
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text(reminders.settingsState == .blockedInSystem
                     ? "Notifications for Comigo are turned off in iOS Settings. Turn them on there to get reminders."
                     : "A gentle nudge if you haven't read any Spanish for 3 days, and again after 7. Set up on this device only — nothing is sent to us.")
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

            // Privacy Section — two separate things: anonymous counts (default
            // on, switchable off) and optional individual analytics (opt-in).
            Section {
                Toggle(isOn: Binding(get: { aggregateCounts.isEnabled }, set: { aggregateCounts.setEnabled($0) })) {
                    Label("Anonymous usage counts", systemImage: "number")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("On by default; switch it off here any time. Counts of actions — a page read, a practice finished, a paywall shown — are sent without any identifier: no account, device, install or session ID, no name, email or Apple ID, no location, and never your voice, your answers or any text. They can't be linked to you or combined into a profile. Turning this off also discards any counts not yet sent.")
            }

            Section {
                Toggle(isOn: Binding(get: { analytics.isEnabled }, set: { analytics.setConsent($0) })) {
                    Label("Share usage analytics", systemImage: "chart.bar.fill")
                }
            } footer: {
                Text("Optional and off unless you choose to share. Individual usage statistics — such as which pages are read and which features are used, in sequence — help us understand how Comigo is used. They're linked to a random ID, not to your name, email or Apple ID, never include your voice, your answers or anything you type, and are never used for advertising. Turning this off stops them immediately.")
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

            // Diagnostics
            Section {
                NavigationLink {
                    SpeechLogView()
                } label: {
                    Label("Speech log", systemImage: "waveform")
                }

                Toggle(isOn: hideCuesBinding) {
                    Label("Hide reading cues", systemImage: "hand.point.up.left")
                }

                if AccessModelService.shared.isTestEnvironment {
                    AccessModelTesterRow()
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Speech log: a short on-device record of speaking-practice attempts, for troubleshooting microphone issues — nothing is uploaded. Hide reading cues: turns off the pointing-hand hint on page arrival (useful for screen recordings).")
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
        .task { await reminders.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reminders.refreshAuthorization() } }
        }
    }
}

/// Settings → Spanish level: change the level chosen on first run.
struct SpanishLevelSettingsView: View {
    @AppStorage(SpanishLevel.storageKey) private var spanishLevelRaw = ""

    var body: some View {
        List {
            Section {
                ForEach(SpanishLevel.allCases) { level in
                    Button {
                        SpanishLevel.select(level)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(level.title).foregroundStyle(.primary)
                                Text(level.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if spanishLevelRaw == level.rawValue {
                                Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text("Stored on this device.")
            }
        }
        .navigationTitle("Spanish level")
    }
}

// MARK: - Speech diagnostics log
/// Read-only viewer for the WhisperDiag rolling attempt log, with Copy for
/// pasting into a bug report.
struct SpeechLogView: View {
    @State private var entries: [WhisperDiag] = []
    @State private var copied = false

    var body: some View {
        List {
            if entries.isEmpty {
                Text("No attempts recorded yet. Do some speaking practice, then check back here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entries.reversed())) { e in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(e.outcome)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(e.outcome == "ok" ? Color.green : Color.orange)
                        Spacer()
                        Text(e.date, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(e.route) · peak \(String(format: "%.1f", e.peakDb)) dB · \(e.buffers) buffers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !e.heard.isEmpty {
                        Text("Heard: “\(e.heard)”").font(.caption)
                    }
                    if !e.expected.isEmpty {
                        Text("Expected: “\(e.expected)”").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Speech log")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear") {
                    WhisperDiag.clear()
                    entries = []
                }
                .disabled(entries.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(copied ? "Copied ✓" : "Copy") {
                    UIPasteboard.general.string = WhisperDiag.exportText()
                    copied = true
                }
                .disabled(entries.isEmpty)
            }
        }
        .onAppear { entries = WhisperDiag.load() }
    }
}

// MARK: - Subscription settings
/// Subscription status + actions, all from StoreKit via StoreService.
struct SubscriptionSettingsView: View {
    @StateObject private var store = StoreService.shared
    @ObservedObject private var access = AccessModelService.shared
    @State private var showPaywall = false
    @State private var showManage = false
    @State private var restoring = false

    private var status: (title: String, detail: String?, active: Bool) {
        let date = { (d: Date?) in d.map { $0.formatted(date: .abbreviated, time: .omitted) } }
        switch store.entitlement {
        case .lifetime:
            return ("Lifetime access", nil, true)
        case .subscribed:
            let verb = store.autoRenews == false ? "Ends" : "Renews"
            return ("Comigo Unlimited", date(store.renewsAt).map { "\(verb) \($0)" }, true)
        case .trial:
            let then = store.autoRenews == false
                ? " Auto-renew is off, so it won't become a paid subscription."
                : (store.monthlyProduct.map { " Then \($0.displayPrice)/\(StoreService.billingPeriodText($0)) unless cancelled." } ?? "")
            return ("Free trial", (date(store.trialEndsAt).map { "Ends \($0)." } ?? "") + then, true)
        case .free:
            return (store.trialExpired && access.isNewModel ? "Free trial ended" : "Not subscribed", nil, false)
        }
    }

    private var footer: String {
        access.isNewModel
            ? "Comigo Unlimited unlocks every episode — as a monthly subscription (with a free trial if you're eligible) or a one-time lifetime purchase."
            : "The first episode of every series is free. Comigo Unlimited unlocks every episode — as a monthly subscription or a one-time lifetime purchase."
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Label(status.title, systemImage: status.active ? "checkmark.seal.fill" : "lock.fill")
                    Spacer()
                    Text(status.active ? "Active" : "Inactive")
                        .foregroundStyle(status.active ? .green : .secondary)
                }
                if let detail = status.detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text(footer)
            }

            Section {
                if !store.hasUnlimited {
                    Button {
                        showPaywall = true
                    } label: {
                        Label(store.freeTrialAvailable ? "Start your free trial" : "View plans", systemImage: "sparkles")
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

                Button {
                    showManage = true
                } label: {
                    Label("Manage subscription", systemImage: "gearshape.fill")
                }
            }
        }
        .navigationTitle("Subscription")
        .sheet(isPresented: $showPaywall) { PaywallView(source: .settings) }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .onChange(of: showManage) { _, open in
            if !open { Task { await store.refreshEntitlement() } }
        }
        .task { await store.refreshEntitlement() }
    }
}

/// Sandbox / TestFlight / Xcode only: Apple reports originalAppVersion "1.0"
/// outside production, so testers choose the access model here. The App Store
/// build never shows this and ignores the setting.
struct AccessModelTesterRow: View {
    @ObservedObject private var access = AccessModelService.shared
    @State private var choice = AccessModelService.shared.testerOverride

    var body: some View {
        Picker(selection: $choice) {
            Text("Automatic (new model)").tag(AccessModelService.TesterOverride.automatic)
            Text("Legacy user").tag(AccessModelService.TesterOverride.legacy)
            Text("New-model user").tag(AccessModelService.TesterOverride.newModel)
        } label: {
            Label("Access model (testing)", systemImage: "person.badge.clock")
        }
        .onChange(of: choice) { _, value in access.testerOverride = value }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(SettingsManager())
    }
}
