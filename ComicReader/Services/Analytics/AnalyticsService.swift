import Foundation
import UIKit
import os

/// Where analytics go. Only `PostHogAnalyticsBackend` knows about PostHog;
/// tests substitute a recording backend.
protocol AnalyticsBackend: AnyObject, Sendable {
    func setUp(projectToken: String, host: String)
    func capture(_ event: String, properties: [String: Any])
    func optIn()
    func optOut()
    /// The anonymous ID events are sent under.
    func distinctId() -> String
}

enum AnalyticsEnvironment: String {
    case development
    case production

    /// Debug builds, the Simulator and TestFlight builds (which carry a sandbox
    /// receipt — the same test PostHog's own `$is_testflight` uses) all report to
    /// the development project, so testing never reaches production analytics.
    static var current: AnalyticsEnvironment {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return classify(isDebugBuild: debug, isSimulator: simulator,
                        receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
    }

    static func classify(isDebugBuild: Bool, isSimulator: Bool, receiptName: String?) -> AnalyticsEnvironment {
        if isDebugBuild || isSimulator || receiptName == "sandboxReceipt" { return .development }
        return .production
    }
}

/// Project token + host for the current environment, from Info.plist
/// (`PostHogHost`, `PostHogProductionToken`, `PostHogDevelopmentToken`).
/// These are PostHog *project* tokens (phc_…), which are designed to ship in
/// client apps; no personal or secret PostHog key belongs here.
struct AnalyticsConfiguration {
    let environment: AnalyticsEnvironment
    let projectToken: String?
    let host: String

    static func load(bundle: Bundle = .main, environment: AnalyticsEnvironment = .current) -> AnalyticsConfiguration {
        func value(_ key: String) -> String? {
            let v = (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (v?.isEmpty ?? true) ? nil : v
        }
        let token = value(environment == .production ? "PostHogProductionToken" : "PostHogDevelopmentToken")
        return AnalyticsConfiguration(
            environment: environment,
            projectToken: token?.hasPrefix("phc_") == true ? token : nil,
            host: value("PostHogHost") ?? "https://eu.i.posthog.com"
        )
    }
}

enum AnalyticsConsent: String {
    case granted
    case denied
}

/// The app's single entry point for product analytics. Observational only:
/// nothing in reading, audio, practice or StoreKit waits on it or depends on
/// it, and every failure mode (no consent, no token, offline, SDK trouble)
/// ends in "nothing is sent", never in an error surfaced to the app.
///
/// Analytics is opt-in: until the user chooses "Allow analytics", nothing is
/// captured or held, and the PostHog SDK is never initialised — so it makes no
/// network requests at all.
@MainActor
final class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService(waitsForAccessModel: true)

    static let consentKey = "analytics.consent"
    private static let logger = Logger(subsystem: "net.comigo.reader", category: "Analytics")

    /// The user's choice; nil until they make one.
    @Published private(set) var consent: AnalyticsConsent?

    var isEnabled: Bool { consent == .granted }
    var needsConsentChoice: Bool { consent == nil }

    /// Current entitlement, reported by StoreService from StoreKit.
    var entitlement: Entitlement? {
        didSet { entitlementKnown = true; flushIfReady() }
    }

    /// Set once AccessModelService has classified this Apple ID from its
    /// original App Store acquisition. Left out of events until then (and when
    /// the classification can't be established).
    var accessModel: AccessModel?

    /// AccessModelService's answer; nil = couldn't be established.
    func accessModelResolved(_ model: AccessModel?) {
        accessModel = model
        accessModelKnown = true
        flushIfReady()
    }

    private let defaults: UserDefaults
    private let configuration: AnalyticsConfiguration
    private let makeBackend: () -> AnalyticsBackend
    private let now: () -> Date
    private let log: (String) -> Void
    private let onConsentChange: (Bool) -> Void
    private let workQueue = DispatchQueue(label: "net.comigo.analytics", qos: .utility)
    private let waitsForAccessModel: Bool
    private var accessModelKnown = false

    private var backend: AnalyticsBackend?
    private var backendOptedOut = false
    private var started = false
    private var entitlementKnown = false
    private var readinessTimedOut = false
    private var pending: [AnalyticsEvent] = []
    private var lastSent: [String: Date] = [:]
    private var backgroundedAt: Date?
    private var sessionOpenTracked = false

    /// Two identical events closer together than this are one occurrence
    /// reported twice by lifecycle callbacks.
    static let dedupeWindow: TimeInterval = 0.5
    /// A return to the foreground after at least this long counts as a new open.
    static let reopenAfter: TimeInterval = 30 * 60
    /// Events (never the UI) wait at most this long for the first entitlement
    /// read, so they carry it; after that they go without.
    static let readinessTimeout: TimeInterval = 3
    static let maxPending = 200

    init(defaults: UserDefaults = .standard,
         configuration: AnalyticsConfiguration = .load(),
         makeBackend: @escaping () -> AnalyticsBackend = { PostHogAnalyticsBackend() },
         now: @escaping () -> Date = Date.init,
         log: ((String) -> Void)? = nil,
         onConsentChange: ((Bool) -> Void)? = nil,
         waitsForAccessModel: Bool = false) {
        self.defaults = defaults
        self.waitsForAccessModel = waitsForAccessModel
        self.configuration = configuration
        self.makeBackend = makeBackend
        self.now = now
        #if DEBUG
        // Shows in the Xcode console, and via `log stream` / Console.app.
        self.log = log ?? { Self.logger.info("\($0, privacy: .public)") }
        #else
        self.log = log ?? { _ in }
        #endif
        self.onConsentChange = onConsentChange ?? { granted in
            Task { @MainActor in PurchaseAttribution.shared.consentChanged(granted: granted) }
        }
        consent = (defaults.string(forKey: Self.consentKey)).flatMap(AnalyticsConsent.init(rawValue:))
    }

    // MARK: - Lifecycle

    /// Called once from the app delegate at launch. Synchronous and cheap: it
    /// registers observers and returns — nothing here waits on StoreKit, the
    /// network or PostHog.
    func start() {
        guard !started else { return }
        started = true
        log("[Analytics] environment: \(configuration.environment.rawValue)"
            + (configuration.projectToken == nil ? " (no project token — events are logged, not sent)" : "")
            + " — consent: \(consent?.rawValue ?? "not chosen yet")")

        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.backgroundedAt = self?.now() }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWillEnterForeground() }
        }

        // A background relaunch (e.g. to finish a comic download) is not an
        // open; the first real foregrounding afterwards is.
        if UIApplication.shared.applicationState == .background {
            backgroundedAt = .distantPast
        } else {
            trackAppOpened()
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.readinessTimeout * 1_000_000_000))
            self?.readinessTimedOut = true
            self?.flushIfReady()
        }
    }

    func handleWillEnterForeground() {
        guard let since = backgroundedAt else { return }
        backgroundedAt = nil
        if now().timeIntervalSince(since) >= Self.reopenAfter {
            sessionOpenTracked = false
            trackAppOpened()
        }
    }

    private func trackAppOpened() {
        guard isEnabled, !sessionOpenTracked else { return }
        sessionOpenTracked = true
        track(.appOpened)
    }

    // MARK: - Consent

    /// The user's answer — from the first-run card or Settings → Privacy.
    func setConsent(_ granted: Bool) {
        let new: AnalyticsConsent = granted ? .granted : .denied
        guard new != consent else { return }
        consent = new
        defaults.set(new.rawValue, forKey: Self.consentKey)
        if granted {
            log("[Analytics] consent granted")
            if let backend, backendOptedOut {
                backendOptedOut = false
                workQueue.async { backend.optIn() }
            }
            // The visit in which they said yes counts as an open.
            if started, UIApplication.shared.applicationState != .background { trackAppOpened() }
        } else {
            log("[Analytics] consent declined — nothing is captured or sent")
            pending.removeAll()
            if let backend {
                backendOptedOut = true
                workQueue.async { backend.optOut() }
            }
        }
        onConsentChange(granted)
    }

    // MARK: - Tracking

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else {
            log("[Analytics] \(event.name) — not captured (\(consent == nil ? "no consent yet" : "declined"))")
            return
        }
        let key = event.dedupeKey
        let t = now()
        if let last = lastSent[key], t.timeIntervalSince(last) < Self.dedupeWindow {
            log("[Analytics] \(event.name) — duplicate within \(Self.dedupeWindow)s, dropped")
            return
        }
        lastSent[key] = t
        if lastSent.count > 500 { lastSent = lastSent.filter { t.timeIntervalSince($0.value) < Self.dedupeWindow } }

        if isReady {
            send(event)
        } else if pending.count < Self.maxPending {
            pending.append(event)
        }
    }

    /// A tap on a word's (or its forms') speaker button. Only attributed —
    /// and so only sent — where a comic context exists (reading and practice).
    func trackWordAudio(_ context: AnalyticsComicContext?) {
        guard let context else { return }
        track(.audioPlayed(comicId: context.comicId, pageNumber: context.pageNumber, audioType: .word))
    }

    /// Properties attached to every event.
    var commonProperties: [String: Any] {
        var p: [String: Any] = [
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build_number": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        ]
        if let entitlement { p["entitlement"] = entitlement.rawValue }
        if let accessModel { p["access_model"] = accessModel.rawValue }
        return p
    }

    /// Runs `body` with the analytics ID on the analytics queue — only when
    /// the user has opted in and the SDK is configured; otherwise never.
    func withDistinctId(_ body: @escaping @Sendable (String) -> Void) {
        guard let backend = activeBackend() else { return }
        workQueue.async { body(backend.distinctId()) }
    }

    /// Events (never the UI) wait for the first entitlement read — and, in the
    /// app, the access-model classification — up to `readinessTimeout`.
    private var isReady: Bool {
        started && (readinessTimedOut || (entitlementKnown && (accessModelKnown || !waitsForAccessModel)))
    }

    private func flushIfReady() {
        guard isReady, !pending.isEmpty else { return }
        let queued = pending
        pending.removeAll()
        guard isEnabled else { return }
        queued.forEach(send)
    }

    private func send(_ event: AnalyticsEvent) {
        let properties = event.properties.merging(commonProperties) { own, _ in own }
        #if DEBUG
        let lines = properties.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        log((["[Analytics]", "event: \(event.name)"] + lines).joined(separator: "\n"))
        #endif
        guard let backend = activeBackend() else { return }
        let name = event.name
        workQueue.async { backend.capture(name, properties: properties) }
    }

    /// Creates and sets up the SDK on first use — which can only happen after
    /// consent, since nothing reaches here without it.
    private func activeBackend() -> AnalyticsBackend? {
        guard isEnabled, let token = configuration.projectToken else { return nil }
        if let backend { return backend }
        let made = makeBackend()
        backend = made
        let host = configuration.host
        workQueue.async {
            made.setUp(projectToken: token, host: host)
            // The SDK persists opt-out across launches; the user's current
            // choice (here: yes) is the one that counts.
            made.optIn()
        }
        return made
    }

    /// Blocks until every backend call issued so far has run (tests only).
    func waitForBackend() { workQueue.sync {} }
}
