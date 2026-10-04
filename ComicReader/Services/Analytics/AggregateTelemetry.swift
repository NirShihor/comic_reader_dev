import Foundation
import UIKit

/// Anonymous aggregate usage counts — the second, separate telemetry layer.
///
/// Counts of actions (a page read, a practice finished, a paywall shown), sent
/// in small batches to the Comigo server, which forwards them to PostHog under
/// ONE fixed identity for the whole app. Nothing in this path identifies a
/// person, device, install or session: no PostHog distinct ID, no session ID,
/// no appAccountToken, no vendor/advertising ID, no generated ID of any kind,
/// no device model, locale, timezone or location, and never any text. Events
/// are held in memory only — nothing is written to disk, and a batch that
/// can't be sent is dropped, not retried.
///
/// On by default and independently switchable off in Settings → Privacy;
/// turning it off clears anything buffered at once. It never touches the
/// opt-in PostHog SDK layer (AnalyticsService), whose events keep their own
/// names — the two never share an event name, so nobody is counted twice.
protocol AggregateTelemetryTransport: AnyObject, Sendable {
    /// Posts `body` (JSON) to `url`; `completion(true)` on a 2xx. Never throws.
    func post(_ body: Data, to url: URL, completion: @escaping @Sendable (Bool) -> Void)
}

final class URLSessionTelemetryTransport: AggregateTelemetryTransport {
    func post(_ body: Data, to url: URL, completion: @escaping @Sendable (Bool) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion((200..<300).contains(code))
        }.resume()
    }
}

/// One counted action: an `aggregate_*` name and its allow-listed properties.
struct AggregateEvent: Equatable {
    let name: String
    let properties: [String: AnyHashable]

    /// Property keys each event may carry — mirrors the server's allow-list.
    /// Anything else on the source event (a Spanish level, a product tier the
    /// server doesn't list, …) is left out here and rejected there.
    static let allowedProperties: [String: Set<String>] = [
        "aggregate_app_opened": [],
        "aggregate_collection_viewed": ["collection_id", "collection_name", "level"],
        "aggregate_comic_started": ["comic_id", "comic_name", "collection_id", "level", "is_free"],
        "aggregate_comic_page_viewed": ["comic_id", "page_number", "total_pages"],
        "aggregate_comic_completed": ["comic_id", "comic_name", "collection_id", "level"],
        "aggregate_audio_played": ["comic_id", "page_number", "audio_type"],
        "aggregate_translation_revealed": ["comic_id", "page_number"],
        "aggregate_practice_started": ["comic_id", "practice_type"],
        "aggregate_practice_completed": ["comic_id", "practice_type"],
        "aggregate_locked_content_tapped": ["comic_id", "collection_id"],
        "aggregate_paywall_viewed": ["source"],
        "aggregate_trial_offer_viewed": ["source", "product_id"],
    ]
    static let commonProperties: Set<String> = ["app_version", "build_number", "entitlement", "access_model"]

    /// The aggregate counterpart of an analytics event, or nil for events that
    /// have none (purchases, trial starts and level choices are not counted).
    init?(_ event: AnalyticsEvent) {
        let aggregateName: String
        switch event {
        case .appOpened: aggregateName = "aggregate_app_opened"
        case .collectionViewed: aggregateName = "aggregate_collection_viewed"
        case .comicStarted: aggregateName = "aggregate_comic_started"
        case .comicPageViewed: aggregateName = "aggregate_comic_page_viewed"
        case .comicCompleted: aggregateName = "aggregate_comic_completed"
        case .audioPlayed: aggregateName = "aggregate_audio_played"
        case .translationRevealed: aggregateName = "aggregate_translation_revealed"
        case .practiceStarted: aggregateName = "aggregate_practice_started"
        case .practiceCompleted: aggregateName = "aggregate_practice_completed"
        case .lockedContentTapped: aggregateName = "aggregate_locked_content_tapped"
        case .paywallViewed: aggregateName = "aggregate_paywall_viewed"
        case .trialOfferViewed: aggregateName = "aggregate_trial_offer_viewed"
        case .trialStarted, .subscriptionStarted, .purchaseCompleted, .spanishLevelSelected: return nil
        }
        let allowed = Self.allowedProperties[aggregateName] ?? []
        var props: [String: AnyHashable] = [:]
        for (key, value) in event.properties where allowed.contains(key) {
            if let v = value as? AnyHashable { props[key] = v }
        }
        name = aggregateName
        properties = props
    }
}

@MainActor
final class AggregateTelemetryService: ObservableObject {
    static let shared = AggregateTelemetryService()

    static let enabledKey = "telemetry.aggregateCounts"
    /// A batch goes when it reaches this many events…
    static let batchSize = 20
    /// …or this long after its first event, or when the app goes to the background.
    static let flushAfter: TimeInterval = 30
    /// Never more than this in memory; older events are dropped, not spooled.
    static let maxBuffered = 50

    /// Settings → Privacy → "Anonymous usage counts". Default on.
    @Published private(set) var isEnabled: Bool

    private let defaults: UserDefaults
    private let environment: AnalyticsEnvironment
    private let endpoint: URL
    private let transport: AggregateTelemetryTransport
    private let flushAfter: TimeInterval
    /// Entitlement and access model, as AnalyticsService knows them (both are
    /// coarse tiers — never an identifier).
    private let context: () -> (entitlement: Entitlement?, accessModel: AccessModel?)
    private var buffer: [AggregateEvent] = []
    private var flushTask: Task<Void, Never>?
    private var started = false
    private(set) var batchesSent = 0

    init(defaults: UserDefaults = .standard,
         environment: AnalyticsEnvironment = .current,
         endpoint: URL = URL(string: "\(Secrets.serverBaseURL)/api/reader/telemetry")!,
         transport: AggregateTelemetryTransport = URLSessionTelemetryTransport(),
         flushAfter: TimeInterval = AggregateTelemetryService.flushAfter,
         context: (() -> (entitlement: Entitlement?, accessModel: AccessModel?))? = nil) {
        self.defaults = defaults
        self.environment = environment
        self.endpoint = endpoint
        self.transport = transport
        self.flushAfter = flushAfter
        self.context = context ?? { (AnalyticsService.shared.entitlement, AnalyticsService.shared.accessModel) }
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Called once at launch: a batch still in memory is sent when the app
    /// leaves the foreground, since it would otherwise be lost.
    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    /// Settings → Privacy. Off discards whatever is buffered immediately.
    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        defaults.set(on, forKey: Self.enabledKey)
        if !on {
            buffer.removeAll()
            flushTask?.cancel()
            flushTask = nil
        }
    }

    /// Count an analytics event, if it has an aggregate counterpart.
    func record(_ event: AnalyticsEvent) {
        guard isEnabled, let aggregate = AggregateEvent(event) else { return }
        if buffer.count >= Self.maxBuffered { buffer.removeFirst() }
        buffer.append(aggregate)
        if buffer.count >= Self.batchSize {
            flush()
        } else if flushTask == nil {
            let delay = flushAfter
            flushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.flushTask = nil
                self?.flush()
            }
        }
    }

    /// Send what is buffered now. The buffer is cleared before the request
    /// goes out: a failed send loses the batch — there is no retry queue.
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard isEnabled, !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()
        guard let body = Self.body(for: batch, environment: environment, common: commonProperties) else { return }
        batchesSent += 1
        transport.post(body, to: endpoint) { _ in }
    }

    /// What the server may use to break counts down — coarse values only.
    var commonProperties: [String: AnyHashable] {
        var p: [String: AnyHashable] = [:]
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !v.isEmpty { p["app_version"] = v }
        if let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !b.isEmpty { p["build_number"] = b }
        let (entitlement, accessModel) = context()
        if let entitlement { p["entitlement"] = entitlement.rawValue }
        if let accessModel { p["access_model"] = accessModel.rawValue }
        return p
    }

    /// The request body: { environment, events: [{ name, properties }] } —
    /// and nothing else.
    static func body(for batch: [AggregateEvent], environment: AnalyticsEnvironment, common: [String: AnyHashable]) -> Data? {
        let events: [[String: Any]] = batch.map { e in
            ["name": e.name, "properties": e.properties.merging(common) { own, _ in own }]
        }
        return try? JSONSerialization.data(withJSONObject: ["environment": environment.rawValue, "events": events])
    }

    /// Tests: what is waiting to be sent.
    var bufferedForTesting: [AggregateEvent] { buffer }
}
