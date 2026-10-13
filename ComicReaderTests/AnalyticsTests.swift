import XCTest
@testable import ComicReader

final class RecordingBackend: AnalyticsBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [(name: String, properties: [String: Any])] = []
    private var _setUps: [(token: String, host: String)] = []
    private var _optIns = 0
    private var _optOuts = 0

    var events: [(name: String, properties: [String: Any])] { lock.withLock { _events } }
    var setUps: [(token: String, host: String)] { lock.withLock { _setUps } }
    var optIns: Int { lock.withLock { _optIns } }
    var optOuts: Int { lock.withLock { _optOuts } }

    func setUp(projectToken: String, host: String) { lock.withLock { _setUps.append((projectToken, host)) } }
    func capture(_ event: String, properties: [String: Any]) { lock.withLock { _events.append((event, properties)) } }
    func optIn() { lock.withLock { _optIns += 1 } }
    func optOut() { lock.withLock { _optOuts += 1 } }
    func distinctId() -> String { "0192c6a4-anon" }
}

@MainActor
final class AnalyticsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var backend: RecordingBackend!
    private var backendsMade = 0
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AnalyticsTests.\(UUID().uuidString)")
        backend = RecordingBackend()
        backendsMade = 0
    }

    private var consentChanges: [Bool] = []

    private func makeService(token: String? = "phc_test", consent: AnalyticsConsent? = .granted) -> AnalyticsService {
        if let consent { defaults.set(consent.rawValue, forKey: AnalyticsService.consentKey) }
        let config = AnalyticsConfiguration(environment: .development, projectToken: token, host: "https://eu.i.posthog.com")
        return AnalyticsService(defaults: defaults, configuration: config,
                                makeBackend: { [unowned self] in self.backendsMade += 1; return self.backend },
                                now: { [unowned self] in self.clock },
                                log: { _ in },
                                onConsentChange: { [unowned self] in self.consentChanges.append($0) })
    }

    /// Started, with the entitlement known, so events are sent straight away.
    private func readyService(token: String? = "phc_test", consent: AnalyticsConsent? = .granted) -> AnalyticsService {
        let s = makeService(token: token, consent: consent)
        s.start()
        s.entitlement = .free
        s.waitForBackend()
        return s
    }

    private func sentNames(_ s: AnalyticsService) -> [String] {
        s.waitForBackend()
        return backend.events.map(\.name)
    }

    // MARK: Vocabulary

    func testEventNamesAreTheApprovedSnakeCaseVocabulary() {
        let events: [AnalyticsEvent] = [
            .appOpened,
            .collectionViewed(collectionId: "c", collectionName: "C", level: "beginner"),
            .comicStarted(comicId: "x", comicName: "X", collectionId: "c", level: "beginner", isFree: true),
            .comicPageViewed(comicId: "x", pageNumber: 1, totalPages: 9),
            .comicCompleted(comicId: "x", comicName: "X", collectionId: "c", level: "beginner"),
            .audioPlayed(comicId: "x", pageNumber: 2, audioType: .sentence),
            .translationRevealed(comicId: "x", pageNumber: 2),
            .practiceStarted(comicId: "x", practiceType: .quiz),
            .practiceCompleted(comicId: "x", practiceType: .quiz),
            .lockedContentTapped(comicId: "x", collectionId: "c"),
            .paywallViewed(source: .comicLocked),
            .trialOfferViewed(source: .comicLocked, productId: "p"),
            .trialStarted(productId: "p", source: .landingScreen),
            .subscriptionStarted(productId: "p"),
            .purchaseCompleted(productId: "p", purchaseType: .lifetime),
            .landingViewed(returning: false, trialOfferShown: true),
            .landingCtaTapped(cta: .getStarted, trialOfferShown: false),
            .paywallDismissed(source: .landingScreen, mode: .freeTrial),
            .purchaseAttempted(source: .comicLocked, mode: .subscribe, productId: "p"),
            .purchaseResult(source: .comicLocked, productId: "p", result: .pending),
            .onboardingStep(step: .creatorMessageOpened),
        ]
        XCTAssertEqual(events.map(\.name), [
            "app_opened", "collection_viewed", "comic_started", "comic_page_viewed", "comic_completed",
            "audio_played", "translation_revealed", "practice_started", "practice_completed",
            "locked_content_tapped", "paywall_viewed", "trial_offer_viewed", "trial_started",
            "subscription_started", "purchase_completed",
            "landing_viewed", "landing_cta_tapped", "paywall_dismissed", "purchase_attempted", "purchase_result", "onboarding_step",
        ])
        // Only structured metadata — no key could carry dialogue, translations or user text.
        let allowed: Set<String> = ["collection_id", "collection_name", "level", "comic_id", "comic_name", "is_free",
                                    "page_number", "total_pages", "audio_type", "practice_type", "source",
                                    "product_id", "purchase_type", "returning", "trial_offer_shown", "cta", "mode",
                                    "result", "step"]
        let snake = try! NSRegularExpression(pattern: "^[a-z]+(_[a-z]+)*$")
        for e in events {
            XCTAssertNotNil(snake.firstMatch(in: e.name, range: NSRange(e.name.startIndex..., in: e.name)), e.name)
            XCTAssertTrue(Set(e.properties.keys).isSubset(of: allowed), "\(e.name): \(e.properties.keys)")
        }
    }

    func testControlledValuesAreSnakeCase() {
        XCTAssertEqual(PaywallSource.allCases.map(\.rawValue), ["comic_locked", "settings", "trial_expired", "landing_screen"])
        XCTAssertEqual(AudioType.allCases.map(\.rawValue), ["sentence", "word"])
        XCTAssertEqual(PurchaseType.allCases.map(\.rawValue), ["subscription", "lifetime"])
        XCTAssertEqual(Entitlement.allCases.map(\.rawValue), ["free", "trial", "subscribed", "lifetime"])
        XCTAssertEqual(AccessModel.allCases.map(\.rawValue), ["legacy", "new_model"])
    }

    func testPracticeTypesComeFromTheReadersModeKeys() {
        for dest in [PracticeDestination.quiz, .speaking, .listening, .repeatPractice, .translateSpeak,
                     .repeatListen, .originListen, .keyPhrases] {
            XCTAssertNotNil(PracticeType(modeKey: dest.modeKey), dest.modeKey)
        }
        XCTAssertEqual(PracticeType(modeKey: "readSpeak"), .readSpeak)
        XCTAssertEqual(PracticeType(modeKey: "translateSpeak")?.rawValue, "translate_speak")
        XCTAssertNil(PracticeType(modeKey: PracticeDestination.flowPractice.modeKey), "Flow Practice is hidden")
    }

    func testUnknownOptionalValuesAreOmittedNotBlank() {
        let p = AnalyticsEvent.audioPlayed(comicId: "x", pageNumber: nil, audioType: .word).properties
        XCTAssertNil(p["page_number"])
        XCTAssertEqual(p["audio_type"] as? String, "word")
        XCTAssertNil(AnalyticsEvent.lockedContentTapped(comicId: "x", collectionId: nil).properties["collection_id"])
    }

    // MARK: Delivery

    func testCommonPropertiesAreAttached() {
        let s = readyService()
        s.accessModel = .legacy
        s.track(.paywallViewed(source: .settings))
        s.waitForBackend()
        let p = backend.events.last!.properties
        XCTAssertEqual(p["source"] as? String, "settings")
        XCTAssertEqual(p["entitlement"] as? String, "free")
        XCTAssertEqual(p["access_model"] as? String, "legacy")
        XCTAssertNotNil(p["app_version"])
        XCTAssertNotNil(p["build_number"])
    }

    func testAccessModelIsLeftOutUntilKnown() {
        let s = readyService()
        s.track(.paywallViewed(source: .settings))
        s.waitForBackend()
        XCTAssertNil(backend.events.last!.properties["access_model"])
    }

    func testEventsWaitForTheFirstEntitlementReadThenCarryIt() {
        let s = makeService()
        s.start()
        s.track(.comicPageViewed(comicId: "x", pageNumber: 1, totalPages: 5))
        s.waitForBackend()
        XCTAssertTrue(backend.events.isEmpty, "held until the entitlement is known")
        s.entitlement = .subscribed
        s.waitForBackend()
        XCTAssertEqual(backend.events.last?.name, "comic_page_viewed")
        XCTAssertEqual(backend.events.last?.properties["entitlement"] as? String, "subscribed")
    }

    func testDuplicateWithinWindowIsDroppedButLaterRepeatIsKept() {
        let s = readyService()
        let before = sentNames(s).count
        let page3 = AnalyticsEvent.comicPageViewed(comicId: "x", pageNumber: 3, totalPages: 9)
        s.track(page3)
        s.track(page3)                                   // same lifecycle tick, reported twice
        clock += AnalyticsService.dedupeWindow + 0.1
        s.track(page3)                                   // genuinely came back to page 3
        s.track(.comicPageViewed(comicId: "x", pageNumber: 4, totalPages: 9))
        XCTAssertEqual(sentNames(s).count - before, 3)
    }

    func testNoTokenMeansNothingIsSent() {
        let s = readyService(token: nil)
        s.track(.paywallViewed(source: .settings))
        s.waitForBackend()
        XCTAssertEqual(backendsMade, 0)
        XCTAssertTrue(backend.events.isEmpty)
    }

    func testBackendIsSetUpOnceWithTheProjectToken() {
        let s = readyService()
        s.track(.paywallViewed(source: .settings))
        s.track(.paywallViewed(source: .comicLocked))
        s.waitForBackend()
        XCTAssertEqual(backendsMade, 1)
        XCTAssertEqual(backend.setUps.map(\.token), ["phc_test"])
        XCTAssertEqual(backend.setUps.map(\.host), ["https://eu.i.posthog.com"])
    }

    // MARK: Consent

    func testBeforeAnyChoiceNothingIsCapturedAndTheSDKIsNeverCreated() {
        let s = readyService(consent: nil)
        XCTAssertTrue(s.needsConsentChoice)
        s.track(.paywallViewed(source: .settings))
        s.track(.comicPageViewed(comicId: "x", pageNumber: 1, totalPages: 5))
        s.withDistinctId { _ in XCTFail("no analytics ID without consent") }
        s.waitForBackend()
        XCTAssertEqual(backendsMade, 0, "PostHog is never initialised, so it makes no network requests")
        XCTAssertTrue(backend.events.isEmpty)
    }

    func testAllowStartsCollectionAndCountsThisVisitAsAnOpen() {
        let s = readyService(consent: nil)
        s.setConsent(true)
        XCTAssertFalse(s.needsConsentChoice)
        s.track(.paywallViewed(source: .settings))
        XCTAssertEqual(sentNames(s), ["app_opened", "paywall_viewed"])
        XCTAssertEqual(backend.optIns, 1)
        XCTAssertEqual(consentChanges, [true])
        XCTAssertEqual(defaults.string(forKey: AnalyticsService.consentKey), "granted")
    }

    func testNoThanksSendsNothingAndIsRemembered() {
        let s = readyService(consent: nil)
        s.setConsent(false)
        s.track(.paywallViewed(source: .settings))
        s.waitForBackend()
        XCTAssertEqual(backendsMade, 0)
        XCTAssertFalse(s.needsConsentChoice, "the card doesn't come back")
        XCTAssertEqual(defaults.string(forKey: AnalyticsService.consentKey), "denied")
        XCTAssertFalse(makeService(consent: nil).isEnabled, "a later launch keeps the answer")
    }

    func testDeclinedAtLaunchNeverCreatesTheSDK() {
        let s = readyService(consent: .denied)
        s.track(.appOpened)
        s.waitForBackend()
        XCTAssertEqual(backendsMade, 0)
        XCTAssertTrue(backend.events.isEmpty)
    }

    func testOptingOutLaterStopsCaptureAndRemovesAttribution() {
        let s = readyService()
        s.track(.paywallViewed(source: .settings))
        s.waitForBackend()
        let sent = backend.events.count
        s.setConsent(false)
        s.track(.paywallViewed(source: .comicLocked))
        s.waitForBackend()
        XCTAssertEqual(backend.events.count, sent)
        XCTAssertEqual(backend.optOuts, 1)
        XCTAssertEqual(consentChanges, [false], "purchase-attribution mapping is deleted")
    }

    func testOptingBackInResumes() {
        let s = readyService()
        s.track(.paywallViewed(source: .settings))
        s.setConsent(false)
        s.setConsent(true)
        clock += 1
        s.track(.paywallViewed(source: .settings))
        s.waitForBackend()
        XCTAssertEqual(backend.events.filter { $0.name == "paywall_viewed" }.count, 2)
        XCTAssertGreaterThanOrEqual(backend.optIns, 2, "opt-in at setup and on opting back in")
        XCTAssertEqual(consentChanges, [false, true])
    }

    func testDecliningDiscardsEventsStillWaitingToBeSent() {
        let s = makeService()
        s.start()
        s.track(.paywallViewed(source: .settings))   // held: entitlement not yet known
        s.setConsent(false)
        s.entitlement = .free
        s.waitForBackend()
        XCTAssertTrue(backend.events.isEmpty)
    }

    func testAnalyticsIdIsOnlyAvailableWithConsent() {
        let s = readyService()
        let got = expectation(description: "distinct id")
        s.withDistinctId { id in XCTAssertEqual(id, "0192c6a4-anon"); got.fulfill() }
        wait(for: [got], timeout: 2)
    }

    // MARK: Environment

    func testEnvironmentClassification() {
        XCTAssertEqual(AnalyticsEnvironment.classify(isDebugBuild: true, isSimulator: false, receiptName: "receipt"), .development)
        XCTAssertEqual(AnalyticsEnvironment.classify(isDebugBuild: false, isSimulator: true, receiptName: "receipt"), .development)
        XCTAssertEqual(AnalyticsEnvironment.classify(isDebugBuild: false, isSimulator: false, receiptName: "sandboxReceipt"), .development, "TestFlight")
        XCTAssertEqual(AnalyticsEnvironment.classify(isDebugBuild: false, isSimulator: false, receiptName: "receipt"), .production, "App Store")
        XCTAssertEqual(AnalyticsEnvironment.current, .development, "this test run is a Debug build on the Simulator")
    }

    func testDeviceDetailsAreStrippedBeforeSending() {
        let stripped = PostHogAnalyticsBackend.strippedProperties
        for key in ["$device_model", "$device_manufacturer", "$screen_width", "$network_wifi", "$locale", "$timezone"] {
            XCTAssertTrue(stripped.contains(key), key)
        }
        XCTAssertFalse(stripped.contains("$app_version"))
        XCTAssertFalse(stripped.contains("$os_version"))
    }

    // MARK: app_opened

    func testReturningToForegroundOnlyCountsAsAnOpenAfterThirtyMinutes() {
        let s = readyService()
        let opens = { self.sentNames(s).filter { $0 == "app_opened" }.count }
        let initial = opens()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        clock += 5 * 60
        s.handleWillEnterForeground()
        XCTAssertEqual(opens(), initial, "5 minutes away is the same visit")
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        clock += AnalyticsService.reopenAfter
        s.handleWillEnterForeground()
        XCTAssertEqual(opens(), initial + 1)
    }
}

// MARK: - App-side purchase events, against real StoreKit test transactions

import StoreKit
import StoreKitTest

@MainActor
final class PurchaseEventTests: XCTestCase {
    private var session: SKTestSession!
    private let monthly = StoreService.monthlyProductID
    private let lifetime = StoreService.lifetimeProductID

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ComigoStore", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
    }

    private var recorder: RecordingBackend!
    private var analyticsDefaults: UserDefaults!
    /// What the anonymous aggregate layer was told (its event names).
    private var counted: [String] = []

    /// An analytics service (opted in unless told otherwise) that records what
    /// it would send to the opt-in layer, and what it counts anonymously.
    private func analytics(consent: AnalyticsConsent? = .granted) -> AnalyticsService {
        recorder = RecordingBackend()
        counted = []
        analyticsDefaults = UserDefaults(suiteName: "PurchaseEventTests.\(UUID().uuidString)")
        if let consent { analyticsDefaults.set(consent.rawValue, forKey: AnalyticsService.consentKey) }
        let config = AnalyticsConfiguration(environment: .development, projectToken: "phc_test", host: "https://eu.i.posthog.com")
        let s = AnalyticsService(defaults: analyticsDefaults, configuration: config,
                                 makeBackend: { [unowned self] in self.recorder },
                                 log: { _ in }, onConsentChange: { _ in },
                                 aggregate: { [unowned self] in if let a = AggregateEvent($0) { self.counted.append(a.name) } })
        s.start()
        s.entitlement = .free
        return s
    }

    /// What was sent, apart from the launch's app_opened.
    private func sent(_ s: AnalyticsService) -> [String] {
        s.waitForBackend()
        return recorder.events.map(\.name).filter { $0 != "app_opened" }
    }

    private func buy(_ id: String, token: UUID? = nil) async throws -> StoreKit.Transaction {
        let products = try await Product.products(for: [id])
        let product = try XCTUnwrap(products.first)
        let result = try await product.purchase(options: token.map { [.appAccountToken($0)] } ?? [])
        guard case .success(.verified(let t)) = result else { throw XCTSkip("purchase did not complete: \(result)") }
        await t.finish()
        return t
    }

    func testStartingTheFreeTrialIsTrialStarted() async throws {
        let products = try await Product.products(for: [monthly])
        let product = try XCTUnwrap(products.first)
        let eligible = await StoreService.shared.isEligibleForFreeTrial(product)
        XCTAssertTrue(eligible, "a new customer sees the 7-day trial")
        let t = try await buy(monthly)
        XCTAssertTrue(StoreService.isFreeTrialPeriod(t))
        XCTAssertEqual(StoreService.purchaseEvent(for: t)?.name, "trial_started")
        XCTAssertEqual(StoreService.purchaseEvent(for: t)?.properties["product_id"] as? String, monthly)
    }

    func testTrialConversionAndRenewalsAreLeftToTheServer() async throws {
        let trial = try await buy(monthly)
        try session.forceRenewalOfSubscription(productIdentifier: monthly)
        try await Task.sleep(nanoseconds: 500_000_000)
        let latestResult = await StoreKit.Transaction.latest(for: monthly)
        let latest = try XCTUnwrap(latestResult)
        guard case .verified(let paid) = latest else { return XCTFail("unverified renewal") }
        XCTAssertNotEqual(paid.id, trial.id)
        XCTAssertFalse(StoreService.isFreeTrialPeriod(paid), "the renewal is the first paid period")
        XCTAssertNil(StoreService.purchaseEvent(for: paid), "subscription_started / renewed come from the server")
    }

    func testDirectPaidSubscriptionIsLeftToTheServer() async throws {
        _ = try await buy(monthly)
        try session.expireSubscription(productIdentifier: monthly)
        try await Task.sleep(nanoseconds: 500_000_000)
        let products = try await Product.products(for: [monthly])
        let product = try XCTUnwrap(products.first)
        let eligibleAgain = await StoreService.shared.isEligibleForFreeTrial(product)
        XCTAssertFalse(eligibleAgain, "one trial per customer")
        let paid = try await buy(monthly)
        XCTAssertFalse(StoreService.isFreeTrialPeriod(paid))
        XCTAssertNil(StoreService.purchaseEvent(for: paid))
    }

    func testLifetimePurchaseIsPurchaseCompleted() async throws {
        let t = try await buy(lifetime)
        let event = try XCTUnwrap(StoreService.purchaseEvent(for: t))
        XCTAssertEqual(event.name, "purchase_completed")
        XCTAssertEqual(event.properties["purchase_type"] as? String, "lifetime")
    }

    func testRefundedTransactionCarriesRevocation() async throws {
        let t = try await buy(lifetime)
        try session.refundTransaction(identifier: UInt(t.id))
        var revoked: Date?
        for _ in 0..<30 where revoked == nil {
            try await Task.sleep(nanoseconds: 200_000_000)
            for await result in StoreKit.Transaction.all {
                if case .verified(let x) = result, x.id == t.id { revoked = x.revocationDate }
            }
        }
        XCTAssertNotNil(revoked, "reportPurchase ignores revoked transactions; the server reports the refund")
    }

    func testTrialOfferViewedOnlyForEligibleUsers() async throws {
        let products = try await Product.products(for: [monthly])
        let product = try XCTUnwrap(products.first)
        let a = analytics()
        await StoreService.shared.trialOfferShown(product, source: .comicLocked, analytics: a)
        XCTAssertEqual(sent(a), ["trial_offer_viewed"])
        XCTAssertEqual(recorder.events.last?.properties["product_id"] as? String, monthly)
        XCTAssertEqual(recorder.events.last?.properties["source"] as? String, "comic_locked")

        // Trial used and over: the paywall may still show, but it isn't a trial offer view.
        _ = try await buy(monthly)
        try session.expireSubscription(productIdentifier: monthly)
        try await Task.sleep(nanoseconds: 500_000_000)
        let b = analytics()
        await StoreService.shared.trialOfferShown(product, source: .comicLocked, analytics: b)
        XCTAssertEqual(sent(b), [])
    }

    func testTrialStartedIsReportedOnceEvenWhenStoreKitDeliversItTwice() async throws {
        let token = UUID()
        let t = try await buy(monthly, token: token)
        let a = analytics()
        StoreService.shared.reportPurchase(t, purchasedHere: true, source: .landingScreen, analytics: a, defaults: analyticsDefaults, installToken: token)
        StoreService.shared.reportPurchase(t, purchasedHere: false, analytics: a, defaults: analyticsDefaults, installToken: token)
        XCTAssertEqual(sent(a), ["trial_started"])
        XCTAssertEqual(recorder.events.last?.properties["entitlement"] as? String, "free", "common properties attached")
        XCTAssertEqual(recorder.events.last?.properties["source"] as? String, "landing_screen")
        XCTAssertEqual(counted.filter { $0 == "aggregate_trial_started" }.count, 1, "counted once anonymously too")
    }

    /// A verified trial start is counted anonymously whatever the consent —
    /// and still only once per transaction, across launches (the record is
    /// persisted) and across the two delivery paths.
    func testTrialStartIsCountedAnonymouslyWithoutConsentAndStillOnlyOnce() async throws {
        let t = try await buy(monthly)
        for consent in [AnalyticsConsent.denied, nil] {
            let a = analytics(consent: consent)
            StoreService.shared.reportPurchase(t, purchasedHere: true, source: .comicLocked, analytics: a, defaults: analyticsDefaults, installToken: nil)
            StoreService.shared.reportPurchase(t, purchasedHere: true, source: .comicLocked, analytics: a, defaults: analyticsDefaults, installToken: nil)
            XCTAssertEqual(sent(a), [], "the opt-in layer needs consent (\(String(describing: consent)))")
            XCTAssertEqual(counted.filter { $0 == "aggregate_trial_started" }.count, 1, "counted once (\(String(describing: consent)))")
            // Next launch, same install: Transaction.updates replays it — already recorded.
            let later = AnalyticsService(defaults: analyticsDefaults, configuration: AnalyticsConfiguration(environment: .development, projectToken: "phc_test", host: "https://eu.i.posthog.com"),
                                         makeBackend: { RecordingBackend() }, log: { _ in }, onConsentChange: { _ in },
                                         aggregate: { [unowned self] in if let x = AggregateEvent($0) { self.counted.append(x.name) } })
            later.start(); later.entitlement = .free
            StoreService.shared.reportPurchase(t, purchasedHere: true, analytics: later, defaults: analyticsDefaults, installToken: nil)
            XCTAssertEqual(counted.filter { $0 == "aggregate_trial_started" }.count, 1, "not again after a relaunch")
        }
    }

    func testTransactionsFromElsewhereAreOnlyReportedWithThisInstallsToken() async throws {
        let t = try await buy(lifetime, token: UUID())   // bought with another install's token
        let a = analytics()
        StoreService.shared.reportPurchase(t, purchasedHere: false, analytics: a, defaults: analyticsDefaults, installToken: UUID())
        XCTAssertEqual(sent(a), [])
        StoreService.shared.reportPurchase(t, purchasedHere: false, analytics: a, defaults: analyticsDefaults, installToken: t.appAccountToken)
        XCTAssertEqual(sent(a), ["purchase_completed"])
    }

    func testPaidPurchasesWithoutConsentAreNotReportedAnywhere() async throws {
        let t = try await buy(lifetime)
        for consent in [AnalyticsConsent.denied, nil] {
            let a = analytics(consent: consent)
            StoreService.shared.reportPurchase(t, purchasedHere: true, analytics: a, defaults: analyticsDefaults, installToken: nil)
            XCTAssertEqual(sent(a), [])
            XCTAssertEqual(counted, ["aggregate_app_opened"], "a paid purchase has no anonymous count")
        }
    }

    // MARK: Purchase outcomes (StoreService.purchase)

    func testASuccessfulTrialPurchaseIsCountedAsAttemptResultAndTrialStart() async throws {
        let products = try await Product.products(for: [monthly])
        let product = try XCTUnwrap(products.first)
        let a = analytics(consent: nil)
        // The test session reuses transaction ids across runs, so the
        // once-per-transaction record must be this test's own, not the app's.
        let outcome = await StoreService.shared.purchase(product, source: .landingScreen, analytics: a, defaults: analyticsDefaults)
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(counted, ["aggregate_app_opened", "aggregate_trial_started", "aggregate_purchase_result"],
                       "the start is reported from the verified transaction, then the call's outcome; the tap is the paywall's")
        XCTAssertEqual(sent(a), [], "no consent: nothing to the opt-in layer")
    }

    func testAPendingPurchaseIsCountedAsPendingAndUnlocksNothing() async throws {
        session.askToBuyEnabled = true
        let products = try await Product.products(for: [monthly])
        let product = try XCTUnwrap(products.first)
        let a = analytics()
        await StoreService.shared.refreshEntitlement()
        let entitledBefore = StoreService.shared.hasUnlimited   // other StoreKit tests may have left one
        let outcome = await StoreService.shared.purchase(product, source: .comicLocked, analytics: a, defaults: analyticsDefaults)
        XCTAssertEqual(outcome, .pending)
        XCTAssertEqual(counted.last, "aggregate_purchase_result")
        XCTAssertFalse(counted.contains("aggregate_trial_started"))
        XCTAssertEqual(sent(a).last, "purchase_result")
        XCTAssertEqual(recorder.events.last?.properties["result"] as? String, "pending")
        await StoreService.shared.refreshEntitlement()
        XCTAssertEqual(StoreService.shared.hasUnlimited, entitledBefore, "a pending purchase changes no entitlement")
    }

    func testAFailedPurchaseIsCountedAsFailedWithoutTheError() async throws {
        session.failTransactionsEnabled = true
        let products = try await Product.products(for: [monthly])
        let product = try XCTUnwrap(products.first)
        let a = analytics()
        let outcome = await StoreService.shared.purchase(product, source: .comicLocked, analytics: a, defaults: analyticsDefaults)
        guard case .failed(let error) = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertFalse(error.localizedDescription.isEmpty, "the paywall gets the error to show")
        let props = try XCTUnwrap(recorder.events.last?.properties)
        XCTAssertEqual(recorder.events.last?.name, "purchase_result")
        XCTAssertEqual(props["result"] as? String, "failed")
        XCTAssertEqual(Set(props.keys).intersection(["error", "message", "code", "description", "reason"]), [], "the error never travels")
        XCTAssertFalse(counted.contains("aggregate_trial_started"))
    }

    func testEveryOutcomeHasItsStageValueAndCancelledIsOneOfThem() {
        XCTAssertEqual(StoreService.PurchaseOutcome.success.analyticsValue, .success)
        XCTAssertEqual(StoreService.PurchaseOutcome.cancelled.analyticsValue, .cancelled)
        XCTAssertEqual(StoreService.PurchaseOutcome.pending.analyticsValue, .pending)
        XCTAssertEqual(StoreService.PurchaseOutcome.failed(StoreService.StoreError.notUnlocked).analyticsValue, .failed)
    }

    func testTheDebugPreviewPaywallCountsNothing() async throws {
        let products = try await Product.products(for: [monthly])
        let product = try XCTUnwrap(products.first)
        let a = analytics()
        _ = await StoreService.shared.purchase(product, source: nil, analytics: a, defaults: analyticsDefaults)
        XCTAssertFalse(counted.contains("aggregate_purchase_result"))
        XCTAssertFalse(sent(a).contains("purchase_result"))
    }

    func testAccessModelIsAttachedOnceTheSubscriptionModelSetsIt() async throws {
        let t = try await buy(lifetime)
        for model in [AccessModel.legacy, .newModel] {
            let a = analytics()
            a.accessModel = model
            StoreService.shared.reportPurchase(t, purchasedHere: true, analytics: a, defaults: analyticsDefaults, installToken: nil)
            a.waitForBackend()
            XCTAssertEqual(recorder.events.last?.properties["access_model"] as? String, model.rawValue)
        }
    }

}
