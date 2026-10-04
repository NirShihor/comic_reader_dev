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
            (.comicStarted(comicId: "comic-1", comicName: "La casa", collectionId: "col-1", level: "beginner", isFree: true),
             "aggregate_comic_started", ["comic_id": "comic-1", "comic_name": "La casa", "collection_id": "col-1", "level": "beginner", "is_free": true]),
            (.comicPageViewed(comicId: "comic-1", pageNumber: 3, totalPages: 14),
             "aggregate_comic_page_viewed", ["comic_id": "comic-1", "page_number": 3, "total_pages": 14]),
            (.comicCompleted(comicId: "comic-1", comicName: "La casa", collectionId: nil, level: "beginner"),
             "aggregate_comic_completed", ["comic_id": "comic-1", "comic_name": "La casa", "level": "beginner"]),
            (.audioPlayed(comicId: "comic-1", pageNumber: 2, audioType: .word),
             "aggregate_audio_played", ["comic_id": "comic-1", "page_number": 2, "audio_type": "word"]),
            (.translationRevealed(comicId: "comic-1", pageNumber: nil),
             "aggregate_translation_revealed", ["comic_id": "comic-1"]),
            (.practiceStarted(comicId: "comic-1", practiceType: .readSpeak),
             "aggregate_practice_started", ["comic_id": "comic-1", "practice_type": "read_speak"]),
            (.practiceCompleted(comicId: "comic-1", practiceType: .quiz),
             "aggregate_practice_completed", ["comic_id": "comic-1", "practice_type": "quiz"]),
            (.lockedContentTapped(comicId: "comic-9", collectionId: "col-1"),
             "aggregate_locked_content_tapped", ["comic_id": "comic-9", "collection_id": "col-1"]),
            (.paywallViewed(source: .comicLocked), "aggregate_paywall_viewed", ["source": "comic_locked"]),
            (.trialOfferViewed(source: .settings, productId: "com.comigo.unlimited.monthly"),
             "aggregate_trial_offer_viewed", ["source": "settings", "product_id": "com.comigo.unlimited.monthly"]),
        ]
        for (event, name, props) in cases {
            let a = AggregateEvent(event)
            XCTAssertEqual(a?.name, name)
            XCTAssertEqual(a?.properties, props, name)
            XCTAssertTrue(a!.name.hasPrefix("aggregate_"), "never the opt-in layer's name")
            XCTAssertNotEqual(a!.name, event.name)
        }
    }

    func testPurchasesTrialStartsAndLevelChoicesAreNotCounted() {
        XCTAssertNil(AggregateEvent(.trialStarted(productId: "p")))
        XCTAssertNil(AggregateEvent(.subscriptionStarted(productId: "p")))
        XCTAssertNil(AggregateEvent(.purchaseCompleted(productId: "p", purchaseType: .lifetime)))
        XCTAssertNil(AggregateEvent(.spanishLevelSelected(level: .beginner)))
    }

    func testTheAllowListCoversExactlyTheCountedEvents() {
        XCTAssertEqual(AggregateEvent.allowedProperties.count, 12)
        XCTAssertEqual(AggregateEvent.commonProperties, ["app_version", "build_number", "entitlement", "access_model"])
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
        s.record(.comicStarted(comicId: "comic-1", comicName: "x", collectionId: nil, level: "beginner", isFree: true))
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
