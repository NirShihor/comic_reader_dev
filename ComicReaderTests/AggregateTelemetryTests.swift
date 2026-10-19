import XCTest
@testable import ComicReader

/// Records what the aggregate layer would send, instead of sending it.
final class RecordingTransport: AggregateTelemetryTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _posts: [(url: URL, body: [String: Any])] = []
    var succeed = true
    var posts: [(url: URL, body: [String: Any])] { lock.withLock { _posts } }
    func post(_ body: Data, to url: URL, completion: @escaping @Sendable (Bool) -> Void) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        lock.withLock { _posts.append((url, json)) }
        completion(succeed)
    }
}

/// A transport whose request stays in flight until the test completes it.
final class HeldTransport: AggregateTelemetryTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [@Sendable (Bool) -> Void] = []
    func post(_ body: Data, to url: URL, completion: @escaping @Sendable (Bool) -> Void) {
        lock.withLock { completions.append(completion) }
    }
    func complete(success: Bool) {
        let c = lock.withLock { completions.removeFirst() }
        c(success)
    }
}

@MainActor
final class AggregateTelemetryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var transport: RecordingTransport!
    private let endpoint = URL(string: "https://example.test/api/reader/telemetry")!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AggregateTelemetryTests.\(UUID().uuidString)")
        transport = RecordingTransport()
    }

    private func makeService(environment: AnalyticsEnvironment = .production, flushAfter: TimeInterval = 30,
                             entitlement: Entitlement? = .free, accessModel: AccessModel? = .newModel) -> AggregateTelemetryService {
        AggregateTelemetryService(defaults: defaults, environment: environment, endpoint: endpoint, transport: transport,
                                  flushAfter: flushAfter, context: { (entitlement, accessModel) })
    }

    private func events(_ post: (url: URL, body: [String: Any])) -> [[String: Any]] {
        post.body["events"] as? [[String: Any]] ?? []
    }

    // MARK: Mapping and allow-list

    func testEveryCountedEventMapsToItsAggregateNameWithOnlyAllowedProperties() {
        let cases: [(AnalyticsEvent, String, [String: AnyHashable])] = [
            (.appOpened, "aggregate_app_opened", [:]),
            (.collectionViewed(collectionId: "col-1", collectionName: "EL REY NEGRO", level: "beginner"),
             "aggregate_collection_viewed", ["collection_id": "col-1", "collection_name": "EL REY NEGRO", "level": "beginner"]),
            (.comicStarted(comicId: "comic-1", comicName: "La casa", collectionId: "col-1", level: "beginner", isFree: true, access: .full),
             "aggregate_comic_started", ["comic_id": "comic-1", "comic_name": "La casa", "collection_id": "col-1", "level": "beginner", "is_free": true, "access": "full"]),
            (.comicStarted(comicId: "comic-2", comicName: "La carta", collectionId: "col-1", level: "beginner", isFree: false, access: .preview),
             "aggregate_comic_started", ["comic_id": "comic-2", "comic_name": "La carta", "collection_id": "col-1", "level": "beginner", "is_free": false, "access": "preview"]),
            (.previewLimitReached(comicId: "comic-2", collectionId: "col-1", level: "beginner"),
             "aggregate_preview_limit_reached", ["comic_id": "comic-2", "collection_id": "col-1", "level": "beginner"]),
            (.paywallViewed(source: .previewLimit), "aggregate_paywall_viewed", ["source": "preview_limit"]),
            (.comicPageViewed(comicId: "comic-1", pageNumber: 3, totalPages: 14),
             "aggregate_comic_page_viewed", ["comic_id": "comic-1", "page_number": 3, "total_pages": 14]),
            (.comicCompleted(comicId: "comic-1", comicName: "La casa", collectionId: nil, level: "beginner"),
             "aggregate_comic_completed", ["comic_id": "comic-1", "comic_name": "La casa", "level": "beginner"]),
            (.audioPlayed(comicId: "comic-1", pageNumber: 2, audioType: .word),
             "aggregate_audio_played", ["comic_id": "comic-1", "page_number": 2, "audio_type": "word"]),
            (.translationRevealed(comicId: "comic-1", pageNumber: nil),
             "aggregate_translation_revealed", ["comic_id": "comic-1"]),
            (.practiceStarted(comicId: "comic-1", practiceType: .readSpeak, access: .preview),
             "aggregate_practice_started", ["comic_id": "comic-1", "practice_type": "read_speak", "access": "preview"]),
            (.practiceCompleted(comicId: "comic-1", practiceType: .quiz),
             "aggregate_practice_completed", ["comic_id": "comic-1", "practice_type": "quiz"]),
            (.lockedContentTapped(comicId: "comic-9", collectionId: "col-1"),
             "aggregate_locked_content_tapped", ["comic_id": "comic-9", "collection_id": "col-1"]),
            (.paywallViewed(source: .comicLocked), "aggregate_paywall_viewed", ["source": "comic_locked"]),
            (.trialOfferViewed(source: .settings, productId: "com.comigo.unlimited.monthly"),
             "aggregate_trial_offer_viewed", ["source": "settings", "product_id": "com.comigo.unlimited.monthly"]),
            // Trial-conversion stages (1.2.2)
            (.landingViewed(returning: false, trialOfferShown: true),
             "aggregate_landing_viewed", ["returning": false, "trial_offer_shown": true]),
            (.landingCtaTapped(cta: .startTrial, trialOfferShown: true),
             "aggregate_landing_cta_tapped", ["cta": "start_trial", "trial_offer_shown": true]),
            (.paywallDismissed(source: .landingScreen, mode: .freeTrial),
             "aggregate_paywall_dismissed", ["source": "landing_screen", "mode": "free_trial"]),
            (.purchaseAttempted(source: .comicLocked, mode: .freeTrial, productId: "com.comigo.unlimited.monthly"),
             "aggregate_purchase_attempted", ["source": "comic_locked", "mode": "free_trial", "product_id": "com.comigo.unlimited.monthly"]),
            (.purchaseResult(source: .landingScreen, productId: "com.comigo.unlimited.monthly", result: .cancelled),
             "aggregate_purchase_result", ["source": "landing_screen", "product_id": "com.comigo.unlimited.monthly", "result": "cancelled"]),
            (.trialStarted(productId: "com.comigo.unlimited.monthly", source: .landingScreen),
             "aggregate_trial_started", ["product_id": "com.comigo.unlimited.monthly", "source": "landing_screen"]),
            (.trialStarted(productId: "com.comigo.unlimited.monthly", source: nil),
             "aggregate_trial_started", ["product_id": "com.comigo.unlimited.monthly"]),
            (.onboardingStep(step: .levelSelected), "aggregate_onboarding_step", ["step": "level_selected"]),
        ]
        for (event, name, props) in cases {
            let a = AggregateEvent(event)
            XCTAssertEqual(a?.name, name)
            XCTAssertEqual(a?.properties, props, name)
            XCTAssertTrue(a!.name.hasPrefix("aggregate_"), "never the opt-in layer's name")
            XCTAssertNotEqual(a!.name, event.name)
        }
    }

    func testPaidPurchasesAndLevelChoicesAreNotCountedButATrialStartIs() {
        XCTAssertNil(AggregateEvent(.subscriptionStarted(productId: "p")))
        XCTAssertNil(AggregateEvent(.purchaseCompleted(productId: "p", purchaseType: .lifetime)))
        XCTAssertNil(AggregateEvent(.spanishLevelSelected(level: .beginner)))
        XCTAssertEqual(AggregateEvent(.trialStarted(productId: "p", source: nil))?.name, "aggregate_trial_started")
    }

    func testTheAllowListCoversExactlyTheCountedEvents() {
        XCTAssertEqual(AggregateEvent.allowedProperties.count, 20)
        XCTAssertEqual(AggregateEvent.commonProperties, ["app_version", "build_number", "entitlement", "access_model"])
    }

    /// Every stage value is a closed enumeration: a count can say how a
    /// purchase ended, never why.
    func testStageValuesAreClosedEnumerationsAndNeverCarryText() {
        XCTAssertEqual(Set(PurchaseResult.allCases.map(\.rawValue)), ["success", "cancelled", "pending", "failed"])
        XCTAssertEqual(Set(LandingCTA.allCases.map(\.rawValue)), ["get_started", "continue_learning", "start_trial"])
        XCTAssertEqual(Set(PaywallOffer.allCases.map(\.rawValue)), ["free_trial", "subscribe", "trial_expired"])
        XCTAssertEqual(Set(OnboardingStep.allCases.map(\.rawValue)), ["level_selected", "creator_message_opened", "library_first_viewed"])
        let failed = AggregateEvent(.purchaseResult(source: .comicLocked, productId: "p", result: .failed))!
        XCTAssertEqual(Set(failed.properties.keys), ["source", "product_id", "result"], "no error, message or code key exists to carry text")
    }

    // MARK: Nothing identifying

    func testTheRequestCarriesNoIdentifierOfAnyKind() {
        let s = makeService()
        s.record(.comicPageViewed(comicId: "comic-1", pageNumber: 1, totalPages: 5))
        s.record(.audioPlayed(comicId: "comic-1", pageNumber: 1, audioType: .sentence))
        s.flush()
        XCTAssertEqual(transport.posts.count, 1)
        let post = transport.posts[0]
        XCTAssertEqual(post.url, endpoint)
        XCTAssertEqual(Set(post.body.keys), ["environment", "events"], "the body is the environment and the events — nothing else")
        let text = String(decoding: try! JSONSerialization.data(withJSONObject: post.body), as: UTF8.self)
        for forbidden in ["distinct", "session", "token", "device", "install", "idfv", "idfa", "vendor", "locale", "timezone",
                          "uuid", "\"ip\"", "user_agent", "spanish_level", "timestamp", "email"] {
            XCTAssertFalse(text.lowercased().contains(forbidden), "'\(forbidden)' must not appear: \(text)")
        }
        for e in events(post) {
            let keys = Set((e["properties"] as? [String: Any] ?? [:]).keys)
            XCTAssertTrue(keys.isSubset(of: AggregateEvent.allowedProperties[e["name"] as! String]!.union(AggregateEvent.commonProperties)))
        }
    }

    func testNothingIsWrittenToDiskExceptTheOptOutChoice() {
        let s = makeService()
        s.record(.appOpened)
        s.record(.comicStarted(comicId: "comic-1", comicName: "x", collectionId: nil, level: "beginner", isFree: true, access: .full))
        s.flush()
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("telemetry.") }.isEmpty, "nothing persisted while on")
        s.setEnabled(false)
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("telemetry.") }, [AggregateTelemetryService.enabledKey])
        XCTAssertEqual(defaults.bool(forKey: AggregateTelemetryService.enabledKey), false)
    }

    func testCommonPropertiesAreCoarseTiersOnly() {
        let s = makeService(entitlement: .trial, accessModel: .legacy)
        s.record(.appOpened)
        s.flush()
        let props = events(transport.posts[0])[0]["properties"] as? [String: Any] ?? [:]
        XCTAssertEqual(props["entitlement"] as? String, "trial")
        XCTAssertEqual(props["access_model"] as? String, "legacy")
        XCTAssertEqual(Set(props.keys).subtracting(["app_version", "build_number"]), ["entitlement", "access_model"])
        let unknown = makeService(entitlement: nil, accessModel: nil)
        unknown.record(.appOpened)
        unknown.flush()
        let props2 = events(transport.posts[1])[0]["properties"] as? [String: Any] ?? [:]
        XCTAssertNil(props2["entitlement"]); XCTAssertNil(props2["access_model"])
    }

    // MARK: Environment separation

    func testEachBuildKindDeclaresItsEnvironment() {
        let prod = makeService(environment: .production)
        prod.record(.appOpened); prod.flush()
        XCTAssertEqual(transport.posts[0].body["environment"] as? String, "production")
        let dev = makeService(environment: .development)
        dev.record(.appOpened); dev.flush()
        XCTAssertEqual(transport.posts[1].body["environment"] as? String, "development")
        XCTAssertEqual(AnalyticsEnvironment.classify(isDebugBuild: false, isSimulator: false, receiptName: "sandboxReceipt"), .development, "TestFlight")
        XCTAssertEqual(AnalyticsEnvironment.classify(isDebugBuild: false, isSimulator: false, receiptName: "receipt"), .production)
    }

    // MARK: Opt-out

    func testOffDiscardsBufferedEventsAtOnceAndRecordsNothingMore() {
        let s = makeService()
        s.record(.appOpened)
        s.record(.comicPageViewed(comicId: "comic-1", pageNumber: 1, totalPages: 5))
        XCTAssertEqual(s.bufferedForTesting.count, 2)
        s.setEnabled(false)
        XCTAssertTrue(s.bufferedForTesting.isEmpty, "cleared immediately")
        s.record(.paywallViewed(source: .settings))
        s.flush()
        XCTAssertTrue(s.bufferedForTesting.isEmpty)
        XCTAssertTrue(transport.posts.isEmpty, "nothing sent after opting out")
        XCTAssertFalse(s.isEnabled)
        XCTAssertFalse(makeService().isEnabled, "the choice is remembered")
    }

    func testBackOnResumesCounting() {
        let s = makeService()
        s.setEnabled(false)
        s.setEnabled(true)
        s.record(.appOpened)
        s.flush()
        XCTAssertEqual(transport.posts.count, 1)
    }

    func testDefaultIsOn() {
        XCTAssertTrue(makeService().isEnabled)
    }

    // MARK: Batching

    func testABatchGoesWhenItReachesTheBatchSize() {
        let s = makeService()
        for i in 1...(AggregateTelemetryService.batchSize - 1) { s.record(.comicPageViewed(comicId: "comic-1", pageNumber: i, totalPages: 50)) }
        XCTAssertTrue(transport.posts.isEmpty)
        s.record(.comicPageViewed(comicId: "comic-1", pageNumber: 20, totalPages: 50))
        XCTAssertEqual(transport.posts.count, 1)
        XCTAssertEqual(events(transport.posts[0]).count, AggregateTelemetryService.batchSize)
        XCTAssertTrue(s.bufferedForTesting.isEmpty)
    }

    func testABatchGoesAfterTheDelay() async throws {
        let s = makeService(flushAfter: 0.05)
        s.record(.appOpened)
        XCTAssertTrue(transport.posts.isEmpty)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(transport.posts.count, 1)
        XCTAssertEqual(events(transport.posts[0]).count, 1)
    }

    func testFlushSendsEverythingBufferedAndEmptiesTheBuffer() {
        let s = makeService()
        s.record(.appOpened)
        s.record(.paywallViewed(source: .landingScreen))
        s.flush()
        s.flush()
        XCTAssertEqual(transport.posts.count, 1, "an empty buffer sends nothing")
        XCTAssertEqual(events(transport.posts[0]).map { $0["name"] as? String }, ["aggregate_app_opened", "aggregate_paywall_viewed"])
    }

    func testManyEventsGoOutInBatchesOfTheBatchSizeAndNothingAccumulates() {
        let s = makeService()
        for i in 1...(AggregateTelemetryService.batchSize * 3) {
            s.record(.audioPlayed(comicId: "comic-1", pageNumber: i % 20 + 1, audioType: .word))
        }
        XCTAssertEqual(transport.posts.count, 3)
        XCTAssertTrue(transport.posts.allSatisfy { events($0).count == AggregateTelemetryService.batchSize })
        XCTAssertTrue(s.bufferedForTesting.isEmpty)
        XCTAssertLessThanOrEqual(AggregateTelemetryService.batchSize, AggregateTelemetryService.maxBuffered)
    }

    // MARK: Leaving the foreground

    /// A batch flushed on the way to the background is held open by a
    /// background task for exactly as long as the request runs — begun on
    /// flush, ended when the transport answers (success or not), never
    /// begun when there is nothing to send.
    func testAFlushHoldsTheProcessUntilTheRequestCompletes() {
        var begun = 0, ended = 0
        let slow = HeldTransport()
        let s = AggregateTelemetryService(defaults: defaults, environment: .production, endpoint: endpoint, transport: slow,
                                          flushAfter: 30, context: { (.free, .newModel) },
                                          holdProcess: { begun += 1; return { ended += 1 } })
        s.flush()
        XCTAssertEqual(begun, 0, "nothing buffered, nothing held")
        s.record(.landingViewed(returning: false, trialOfferShown: true))
        s.flush()
        XCTAssertEqual(begun, 1)
        XCTAssertEqual(ended, 0, "still in flight")
        slow.complete(success: false)
        XCTAssertEqual(ended, 1, "released when the request ends, even on failure")
        s.record(.appOpened)
        s.flush()
        slow.complete(success: true)
        XCTAssertEqual(begun, 2)
        XCTAssertEqual(ended, 2)
    }

    func testAFailedSendIsDroppedNotRetried() {
        transport.succeed = false
        let s = makeService()
        s.record(.appOpened)
        s.flush()
        XCTAssertEqual(transport.posts.count, 1)
        XCTAssertTrue(s.bufferedForTesting.isEmpty)
        s.flush()
        XCTAssertEqual(transport.posts.count, 1, "no retry")
    }

    // MARK: Through AnalyticsService (both layers, independent)

    func testAnalyticsServiceFeedsTheAggregateLayerWhateverTheConsent() {
        for consent in [nil, AnalyticsConsent.denied, AnalyticsConsent.granted] {
            var counted: [String] = []
            let d = UserDefaults(suiteName: "AggregateTelemetryTests.svc.\(UUID().uuidString)")!
            if let consent { d.set(consent.rawValue, forKey: AnalyticsService.consentKey) }
            let backend = RecordingBackend()
            let config = AnalyticsConfiguration(environment: .development, projectToken: "phc_test", host: "https://eu.i.posthog.com")
            let s = AnalyticsService(defaults: d, configuration: config, makeBackend: { backend }, log: { _ in },
                                     onConsentChange: { _ in }, aggregate: { counted.append($0.name) })
            s.start()
            s.entitlement = .free
            s.track(.comicPageViewed(comicId: "comic-1", pageNumber: 1, totalPages: 5))
            s.track(.comicPageViewed(comicId: "comic-1", pageNumber: 1, totalPages: 5))   // duplicate within the window
            s.waitForBackend()
            XCTAssertEqual(counted, ["app_opened", "comic_page_viewed"], "counted once each, consent \(String(describing: consent))")
            XCTAssertEqual(backend.events.map(\.name), consent == .granted ? ["app_opened", "comic_page_viewed"] : [],
                           "the opt-in layer still needs consent")
        }
    }

    /// The trial-conversion stages are counted with consent nil or denied —
    /// a new customer can't have been asked yet (the card needs pages read,
    /// reading needs the trial) — and reach the opt-in layer only with consent.
    func testTrialConversionStagesAreCountedWithoutConsent() {
        let stages: [AnalyticsEvent] = [
            .landingViewed(returning: false, trialOfferShown: true),
            .landingCtaTapped(cta: .startTrial, trialOfferShown: true),
            .purchaseAttempted(source: .landingScreen, mode: .freeTrial, productId: "com.comigo.unlimited.monthly"),
            .purchaseResult(source: .landingScreen, productId: "com.comigo.unlimited.monthly", result: .success),
            .trialStarted(productId: "com.comigo.unlimited.monthly", source: .landingScreen),
            .paywallDismissed(source: .comicLocked, mode: .freeTrial),
            .onboardingStep(step: .libraryFirstViewed),
        ]
        for consent in [nil, AnalyticsConsent.denied, AnalyticsConsent.granted] {
            var counted: [AnalyticsEvent] = []
            let d = UserDefaults(suiteName: "AggregateTelemetryTests.stages.\(UUID().uuidString)")!
            if let consent { d.set(consent.rawValue, forKey: AnalyticsService.consentKey) }
            let backend = RecordingBackend()
            let config = AnalyticsConfiguration(environment: .development, projectToken: "phc_test", host: "https://eu.i.posthog.com")
            let s = AnalyticsService(defaults: d, configuration: config, makeBackend: { backend }, log: { _ in },
                                     onConsentChange: { _ in }, aggregate: { counted.append($0) })
            s.start()
            s.entitlement = .free
            stages.forEach(s.track)
            s.waitForBackend()
            let aggregateNames = counted.compactMap { AggregateEvent($0)?.name }
            XCTAssertEqual(aggregateNames, ["aggregate_app_opened", "aggregate_landing_viewed", "aggregate_landing_cta_tapped",
                                            "aggregate_purchase_attempted", "aggregate_purchase_result", "aggregate_trial_started",
                                            "aggregate_paywall_dismissed", "aggregate_onboarding_step"],
                           "consent \(String(describing: consent))")
            XCTAssertEqual(backend.events.count, consent == .granted ? stages.count + 1 : 0, "the opt-in layer still needs consent")
        }
    }

    func testGrantingConsentLaterDoesNotCountASecondOpen() {
        var counted: [String] = []
        let d = UserDefaults(suiteName: "AggregateTelemetryTests.svc2.\(UUID().uuidString)")!
        let config = AnalyticsConfiguration(environment: .development, projectToken: "phc_test", host: "https://eu.i.posthog.com")
        let s = AnalyticsService(defaults: d, configuration: config, makeBackend: { RecordingBackend() }, log: { _ in },
                                 onConsentChange: { _ in }, aggregate: { counted.append($0.name) })
        s.start()
        s.setConsent(true)
        XCTAssertEqual(counted.filter { $0 == "app_opened" }.count, 1)
    }
}
