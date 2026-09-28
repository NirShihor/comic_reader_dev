import XCTest
import StoreKit
import StoreKitTest
@testable import ComicReader

// MARK: - Classification (pure: AppTransaction record → access model)

@MainActor
final class AccessModelClassificationTests: XCTestCase {
    typealias R = AccessModelService.Record
    private func classify(_ version: String, _ env: AppStore.Environment = .production, verified: Bool = true,
                          override: AccessModelService.TesterOverride = .automatic) -> AccessModelService.Classification {
        AccessModelService.classify(R(originalAppVersion: version, environment: env, verified: verified), testerOverride: override)
    }

    func testBuildsBefore200AreLegacy() {
        for build in ["1", "119", "124", "125", "199", " 125 "] {
            XCTAssertEqual(classify(build), .legacy, build)
        }
    }

    func testBuild200AndLaterAreNewModel() {
        for build in ["200", "201", "350", "10000"] {
            XCTAssertEqual(classify(build), .newModel, build)
        }
    }

    func testAnythingUnsafeIsUnknownNeverNewModel() {
        for build in ["1.0", "", "abc", "125a", "2.0.0", "-5"] {
            XCTAssertEqual(classify(build), .unknown, "'\(build)' must not become new model")
        }
        XCTAssertEqual(classify("250", verified: false), .unknown, "unverified AppTransaction")
        XCTAssertEqual(AccessModelService.classify(nil, testerOverride: .automatic), .unknown, "no AppTransaction")
    }

    func testSandboxAndXcodeUseTheTesterChoice() {
        // Apple reports originalAppVersion "1.0" outside production.
        XCTAssertEqual(classify("1.0", .sandbox), .newModel, "TestFlight defaults to the new model")
        XCTAssertEqual(classify("1.0", .sandbox, override: .legacy), .legacy)
        XCTAssertEqual(classify("1.0", .xcode, override: .newModel), .newModel)
        XCTAssertEqual(classify("1.0", .xcode, override: .legacy), .legacy)
    }

    func testProductionIgnoresTheTesterChoice() {
        XCTAssertEqual(classify("250", override: .legacy), .newModel)
        XCTAssertEqual(classify("125", override: .newModel), .legacy)
    }

    func testTheCutoffIsBuild200() {
        XCTAssertEqual(AccessModelService.firstNewModelBuild, 200)
    }
}

// MARK: - Resolving: failures never reduce access; no local state involved

@MainActor
final class AccessModelResolveTests: XCTestCase {
    struct Unavailable: Error {}
    /// Defaults to App Store build semantics (the strict rules real users get).
    private func service(appStoreBuild: Bool = true,
                         _ fetch: @escaping () async throws -> AccessModelService.Record) -> AccessModelService {
        AccessModelService(defaults: UserDefaults(suiteName: "AccessModelResolveTests.\(UUID().uuidString)")!,
                           isAppStoreBuild: appStoreBuild, fetchRecord: fetch)
    }
    private let legacyRecord = AccessModelService.Record(originalAppVersion: "125", environment: .production, verified: true)
    private let newRecord = AccessModelService.Record(originalAppVersion: "200", environment: .production, verified: true)

    func testUntilResolvedTheClassificationIsUnknown() {
        XCTAssertEqual(service({ self.newRecord }).classification, .unknown)
    }

    func testStoreKitUnavailableStaysUnknown() async {
        let s = service { throw Unavailable() }
        await s.resolve()
        XCTAssertEqual(s.classification, .unknown)
        XCTAssertFalse(s.isNewModel)
    }

    func testAFailureNeverReplacesAnEstablishedAnswer() async {
        var next: AccessModelService.Record? = legacyRecord
        let s = service { if let r = next { return r } else { throw Unavailable() } }
        await s.resolve()
        XCTAssertEqual(s.classification, .legacy)
        next = nil
        await s.resolve()
        XCTAssertEqual(s.classification, .legacy, "a later StoreKit error keeps legacy")
        next = AccessModelService.Record(originalAppVersion: "garbage", environment: .production, verified: true)
        await s.resolve()
        XCTAssertEqual(s.classification, .legacy, "a later unparseable answer keeps legacy")
    }

    func testReinstallOrNewDeviceGivesTheSameAnswer() async {
        // A fresh service with empty local storage stands in for a reinstall
        // or another device signed into the same Apple ID: only the
        // AppTransaction (the same signed record) decides.
        for record in [legacyRecord, newRecord] {
            let first = service { record }; await first.resolve()
            let reinstalled = service { record }; await reinstalled.resolve()
            XCTAssertEqual(first.classification, reinstalled.classification)
            XCTAssertNotEqual(first.classification, .unknown)
        }
    }

    func testTestBuildsUseTheNewModelWhenTheSandboxCantSupplyTheRecord() async {
        let s = service(appStoreBuild: false) { throw Unavailable() }
        await s.resolve()
        XCTAssertEqual(s.classification, .newModel, "TestFlight / Xcode / App Review see the new-customer experience")
        XCTAssertTrue(s.isTestEnvironment, "and the tester picker is available")
        let unverified = service(appStoreBuild: false) {
            AccessModelService.Record(originalAppVersion: "1.0", environment: .sandbox, verified: false)
        }
        await unverified.resolve()
        XCTAssertEqual(unverified.classification, .newModel)
    }

    func testTestBuildsHonourTheLegacyTesterChoiceWhenTheRecordIsUnavailable() async {
        let defaults = UserDefaults(suiteName: "AccessModelResolveTests.legacyChoice.\(UUID().uuidString)")!
        defaults.set(AccessModelService.TesterOverride.legacy.rawValue, forKey: AccessModelService.testerOverrideKey)
        let s = AccessModelService(defaults: defaults, isAppStoreBuild: false) { throw Unavailable() }
        await s.resolve()
        XCTAssertEqual(s.classification, .legacy)
    }

    func testAppStoreBuildsNeverUseTheTesterFallback() async {
        let s = service(appStoreBuild: true) { throw Unavailable() }
        await s.resolve()
        XCTAssertEqual(s.classification, .unknown, "real users: unknown stays unknown (= legacy access)")
        XCTAssertFalse(s.isTestEnvironment)
    }

    func testTesterChoiceOnlyMattersOutsideProduction() async {
        let sandbox = AccessModelService.Record(originalAppVersion: "1.0", environment: .sandbox, verified: true)
        let s = service { sandbox }
        await s.resolve()
        XCTAssertEqual(s.classification, .newModel)
        XCTAssertTrue(s.isTestEnvironment)
        let prod = service { self.legacyRecord }
        await prod.resolve()
        XCTAssertFalse(prod.isTestEnvironment, "the tester picker is hidden in the App Store build")
    }
}

// MARK: - Access rule and paywall state (pure)

@MainActor
final class AccessRuleTests: XCTestCase {
    typealias C = AccessModelService.Classification
    private func unlocked(_ entitled: Bool, _ c: C, ep: Int?, collection: String? = "el_visitante") -> Bool {
        StoreService.isUnlocked(entitled: entitled, classification: c, episodeNumber: ep, collectionId: collection)
    }

    func testTrialSubscriptionOrLifetimeUnlockEverythingForEveryModel() {
        for c in [C.legacy, .unknown, .newModel] {
            XCTAssertTrue(unlocked(true, c, ep: 1))
            XCTAssertTrue(unlocked(true, c, ep: 5))
            XCTAssertTrue(unlocked(true, c, ep: nil, collection: nil))
        }
    }

    func testLegacyKeepsTheFirstEpisodeOfEveryCollectionFree() {
        XCTAssertTrue(unlocked(false, .legacy, ep: 1))
        XCTAssertTrue(unlocked(false, .legacy, ep: nil, collection: nil), "standalone comics")
        XCTAssertFalse(unlocked(false, .legacy, ep: 2))
    }

    func testUnknownIsTreatedExactlyLikeLegacy() {
        for ep in [1, 2, 3] {
            XCTAssertEqual(unlocked(false, .unknown, ep: ep), unlocked(false, .legacy, ep: ep))
        }
        XCTAssertTrue(unlocked(false, .unknown, ep: nil, collection: nil))
    }

    func testNewModelHasNothingFreeWithoutAnEntitlement() {
        XCTAssertFalse(unlocked(false, .newModel, ep: 1))
        XCTAssertFalse(unlocked(false, .newModel, ep: 2))
        XCTAssertFalse(unlocked(false, .newModel, ep: nil, collection: nil))
        XCTAssertFalse(StoreService.isFree(episodeNumber: 1, collectionId: "x", classification: .newModel), "analytics is_free")
    }

    func testPaywallModes() {
        typealias M = StoreService.PaywallMode
        XCTAssertEqual(StoreService.paywallMode(isNewModel: true, trialExpired: false, entitled: false, eligibleForTrial: true), M.freeTrial)
        XCTAssertEqual(StoreService.paywallMode(isNewModel: true, trialExpired: false, entitled: false, eligibleForTrial: false), M.subscribe)
        XCTAssertEqual(StoreService.paywallMode(isNewModel: true, trialExpired: true, entitled: false, eligibleForTrial: false), M.trialExpired)
        XCTAssertEqual(StoreService.paywallMode(isNewModel: false, trialExpired: true, entitled: false, eligibleForTrial: false), M.subscribe,
                       "a legacy user's ended trial just returns them to their free episodes")
        XCTAssertEqual(StoreService.paywallMode(isNewModel: false, trialExpired: false, entitled: false, eligibleForTrial: true), M.freeTrial,
                       "legacy users Apple deems eligible also get the trial")
    }

    func testTrialExpiredIsTheAnalyticsSourceForNewModelUsersWhoseTrialEnded() {
        XCTAssertEqual(StoreService.analyticsSource(requested: .comicLocked, mode: .trialExpired), .trialExpired)
        XCTAssertEqual(StoreService.analyticsSource(requested: .landingScreen, mode: .trialExpired), .trialExpired)
        XCTAssertEqual(StoreService.analyticsSource(requested: .comicLocked, mode: .subscribe), .comicLocked)
        XCTAssertEqual(StoreService.analyticsSource(requested: .settings, mode: .freeTrial), .settings)
        XCTAssertNil(StoreService.analyticsSource(requested: nil, mode: .trialExpired), "debug preview isn't tracked")
    }
}

// MARK: - End to end against StoreKit test transactions

@MainActor
final class SubscriptionAccessStoreKitTests: XCTestCase {
    private var session: SKTestSession!
    private var store: StoreService { StoreService.shared }
    private let monthly = StoreService.monthlyProductID
    private let lifetime = StoreService.lifetimeProductID

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ComigoStore", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        await store.loadProducts()
        await store.refreshEntitlement()
    }

    override func tearDown() async throws {
        AccessModelService.shared.setForTesting(.unknown)
    }

    /// StoreKit test changes land asynchronously; refresh until `condition` holds.
    private func settle(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<40 {
            await store.refreshEntitlement()
            if condition() { return }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        XCTFail("timed out waiting for: \(what)")
    }

    private func buy(_ id: String) async throws {
        let product = try XCTUnwrap(id == monthly ? store.monthlyProduct : store.lifetimeProduct)
        let ok = try await store.purchase(product)
        XCTAssertTrue(ok, "purchase of \(id)")
    }

    private func isUnlocked(ep: Int) -> Bool { store.isUnlocked(episodeNumber: ep, collectionId: "el_visitante") }

    func testBrandNewUserIsOfferedTheTrialAndCannotReadYet() async throws {
        AccessModelService.shared.setForTesting(.newModel)
        try await settle("eligible") { store.freeTrialAvailable }
        XCTAssertEqual(store.entitlement, .free)
        XCTAssertTrue(store.showsTrialBanner)
        XCTAssertEqual(StoreService.trialDays(store.monthlyProduct), 7)
        let mode = await store.currentPaywallMode()
        XCTAssertEqual(mode, .freeTrial)
        XCTAssertFalse(isUnlocked(ep: 1), "nothing is free for a new-model user")
    }

    func testActiveTrialUnlocksEverythingAndIsTheTrialEntitlement() async throws {
        AccessModelService.shared.setForTesting(.newModel)
        try await buy(monthly)
        try await settle("trial active") { store.entitlement == .trial }
        XCTAssertTrue(store.hasUnlimited)
        XCTAssertNotNil(store.trialEndsAt)
        XCTAssertTrue(isUnlocked(ep: 1) && isUnlocked(ep: 4))
        XCTAssertFalse(store.showsTrialBanner, "no banner once the trial has started")
    }

    func testTurningAutoRenewOffDuringTheTrialKeepsAccessUntilItEnds() async throws {
        AccessModelService.shared.setForTesting(.newModel)
        try await buy(monthly)
        try await settle("trial active") { store.entitlement == .trial }
        let latestTx = await StoreKit.Transaction.latest(for: monthly)
        let t = try XCTUnwrap(latestTx)
        guard case .verified(let tx) = t else { return XCTFail("unverified") }
        try session.disableAutoRenewForTransaction(identifier: UInt(tx.id))
        try await settle("auto-renew off") { store.autoRenews == false }
        XCTAssertEqual(store.entitlement, .trial, "still in the trial")
        XCTAssertTrue(isUnlocked(ep: 3))
    }

    func testWhenTheTrialEndsANewModelUserIsLockedAndSeesTrialExpired() async throws {
        AccessModelService.shared.setForTesting(.newModel)
        try await buy(monthly)
        try await settle("trial active") { store.entitlement == .trial }
        try session.expireSubscription(productIdentifier: monthly)
        try await settle("trial expired") { store.trialExpired }
        XCTAssertFalse(store.hasUnlimited)
        XCTAssertEqual(store.entitlement, .free)
        XCTAssertFalse(isUnlocked(ep: 1))
        XCTAssertFalse(store.freeTrialAvailable, "one trial per customer")
        XCTAssertFalse(store.showsTrialBanner)
        let mode = await store.currentPaywallMode()
        XCTAssertEqual(mode, .trialExpired)
    }

    func testALegacyUsersEndedTrialReturnsThemToTheirFreeEpisodes() async throws {
        AccessModelService.shared.setForTesting(.legacy)
        try await buy(monthly)
        try await settle("trial active") { store.entitlement == .trial }
        try session.expireSubscription(productIdentifier: monthly)
        try await settle("trial expired") { store.trialExpired }
        XCTAssertEqual(AccessModelService.shared.classification, .legacy, "legacy status unchanged")
        XCTAssertTrue(isUnlocked(ep: 1), "first episode free again")
        XCTAssertFalse(isUnlocked(ep: 2))
        let mode = await store.currentPaywallMode()
        XCTAssertEqual(mode, .subscribe, "no trial-expired screen for legacy users")
    }

    func testTrialConvertingToPaidIsTheSubscribedEntitlement() async throws {
        AccessModelService.shared.setForTesting(.newModel)
        try await buy(monthly)
        try await settle("trial active") { store.entitlement == .trial }
        try session.forceRenewalOfSubscription(productIdentifier: monthly)
        try await settle("paid") { store.entitlement == .subscribed }
        XCTAssertTrue(isUnlocked(ep: 6))
        XCTAssertNotNil(store.renewsAt)
        XCTAssertNil(store.trialEndsAt)
    }

    func testIneligibleCustomersAreNotPromisedATrial() async throws {
        AccessModelService.shared.setForTesting(.legacy)
        try await buy(monthly)
        try session.expireSubscription(productIdentifier: monthly)
        try await settle("trial used") { !store.hasUnlimited && store.trialExpired }
        let mode = await store.currentPaywallMode()
        XCTAssertEqual(mode, .subscribe)
        XCTAssertFalse(store.freeTrialAvailable)
    }

    func testLifetimeUnlocksEverythingForANewModelUserAndARefundRemovesIt() async throws {
        AccessModelService.shared.setForTesting(.newModel)
        try await buy(lifetime)
        try await settle("lifetime") { store.entitlement == .lifetime }
        XCTAssertTrue(isUnlocked(ep: 1) && isUnlocked(ep: 9))
        XCTAssertFalse(store.showsTrialBanner)
        let latestTx = await StoreKit.Transaction.latest(for: lifetime)
        let t = try XCTUnwrap(latestTx)
        guard case .verified(let tx) = t else { return XCTFail("unverified") }
        try session.refundTransaction(identifier: UInt(tx.id))
        try await settle("refunded") { store.entitlement == .free }
        XCTAssertFalse(isUnlocked(ep: 1))
    }

    func testUnknownClassificationKeepsLegacyAccess() async throws {
        AccessModelService.shared.setForTesting(.unknown)
        try await settle("free") { store.entitlement == .free }
        XCTAssertTrue(isUnlocked(ep: 1), "never withdraw access on uncertainty")
        XCTAssertFalse(store.showsTrialBanner, "the new-model banner needs a confirmed new-model user")
    }

    func testTrialAndPurchasingDoNotDependOnAnalyticsConsent() async throws {
        let analytics = AnalyticsService.shared
        let previous = UserDefaults.standard.string(forKey: AnalyticsService.consentKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AnalyticsService.consentKey) }
            else { UserDefaults.standard.removeObject(forKey: AnalyticsService.consentKey) }
        }
        analytics.setConsent(false)
        AccessModelService.shared.setForTesting(.newModel)
        try await settle("eligible") { store.freeTrialAvailable }
        XCTAssertTrue(store.showsTrialBanner, "banner shown with analytics declined")
        try await buy(monthly)
        try await settle("trial active") { store.entitlement == .trial }
        let latestTx = await StoreKit.Transaction.latest(for: monthly)
        let t = try XCTUnwrap(latestTx)
        guard case .verified(let tx) = t else { return XCTFail("unverified") }
        XCTAssertNil(tx.appAccountToken, "no attribution token without analytics consent")
        await store.restore()
        XCTAssertTrue(store.hasUnlimited, "restore works with analytics declined")
    }
}

@MainActor
final class RealAppTransactionTests: XCTestCase {
    func testTheRealAppTransactionIsNeverProductionOutsideTheAppStore() async throws {
        let record: AccessModelService.Record
        do { record = try await AccessModelService.appTransactionRecord() }
        catch { throw XCTSkip("AppTransaction unavailable in this test host: \(error)") }
        XCTAssertNotEqual(record.environment, .production)
        let s = AccessModelService(defaults: UserDefaults(suiteName: "RealAppTransactionTests")!)
        await s.resolve()
        XCTAssertTrue(s.isTestEnvironment)
        XCTAssertNotEqual(s.classification, .unknown, "tester choice applies outside production")
    }
}
