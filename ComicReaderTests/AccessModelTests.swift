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
        let outcome = await store.purchase(product, source: nil)
        XCTAssertEqual(outcome, .success, "purchase of \(id)")
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

// MARK: - Download storage check

@MainActor
final class DownloadStorageTests: XCTestCase {
    func testStorageNeededIsAboutTwiceTheBundlePlusAMargin() {
        // 94 MB bundle: zip + unzipped copy (2.2×) + 40 MB margin ≈ 247 MB
        let need = ComicStoreService.storageNeededBytes(fileSizeMB: 94)
        XCTAssertEqual(Double(need) / (1024 * 1024), 94 * 2.2 + 40, accuracy: 1)
        // Tiny or unknown sizes still ask for a sensible minimum.
        XCTAssertGreaterThan(ComicStoreService.storageNeededBytes(fileSizeMB: 0), 50 * 1024 * 1024)
    }

    func testMessageNamesTheNumbersAndWhereToFreeSpace() {
        let msg = ComicStoreService.notEnoughStorageMessage(fileSizeMB: 94, availableBytes: 120 * 1024 * 1024)
        XCTAssertTrue(msg.contains("about 247 MB free"), msg)
        XCTAssertTrue(msg.contains("the phone has 120 MB"), msg)
        XCTAssertTrue(msg.contains("iPhone Storage"), msg)
    }

    func testAvailableStorageIsReadableForARealFolder() {
        let bytes = ComicStoreService.availableStorageBytes(at: FileManager.default.temporaryDirectory)
        XCTAssertNotNil(bytes)
        XCTAssertGreaterThan(bytes ?? 0, 0)
    }
}

// MARK: - Free preview (pure)

/// Who gets the free preview and how far it reaches: the cover and the first
/// StoreService.previewPages story pages of any comic the reader isn't
/// entitled to. Nothing anyone already has is taken away.
@MainActor
final class FreePreviewRuleTests: XCTestCase {
    typealias C = AccessModelService.Classification
    private func access(_ entitled: Bool, _ c: C, ep: Int?, collection: String? = "el_visitante") -> StoreService.ComicAccess {
        StoreService.access(entitled: entitled, classification: c, episodeNumber: ep, collectionId: collection)
    }

    func testThreeStoryPagesAfterTheCover() {
        XCTAssertEqual(StoreService.previewPages, 3)
        for page in 1...4 { XCTAssertTrue(StoreService.isPageReadable(pageNumber: page, access: .preview), "page \(page)") }
        XCTAssertFalse(StoreService.isPageReadable(pageNumber: 5, access: .preview), "page four of the story meets the paywall")
        XCTAssertFalse(StoreService.isPageReadable(pageNumber: 12, access: .preview))
        for page in [1, 5, 40] { XCTAssertTrue(StoreService.isPageReadable(pageNumber: page, access: .full)) }
    }

    func testEntitledCustomersKeepEverythingUnderEveryModel() {
        for c in [C.legacy, .unknown, .newModel] {
            XCTAssertEqual(access(true, c, ep: 1), .full)
            XCTAssertEqual(access(true, c, ep: 7), .full)
            XCTAssertEqual(access(true, c, ep: nil, collection: nil), .full)
        }
    }

    func testLegacyUsersKeepTheirFreeFirstEpisodesAndPreviewTheRest() {
        for c in [C.legacy, .unknown] {
            XCTAssertEqual(access(false, c, ep: 1), .full, "first episode: free in full, as before")
            XCTAssertEqual(access(false, c, ep: nil, collection: nil), .full, "standalone comic: free in full, as before")
            XCTAssertEqual(access(false, c, ep: 2), .preview, "later episodes: the preview, where there was nothing")
        }
    }

    func testNewModelUsersWithoutAnEntitlementPreviewEveryComic() {
        XCTAssertEqual(access(false, .newModel, ep: 1), .preview)
        XCTAssertEqual(access(false, .newModel, ep: 5), .preview)
        XCTAssertEqual(access(false, .newModel, ep: nil, collection: nil), .preview)
    }

    /// The preview is defined by the page number the export gives each page —
    /// the same rule the reader, the thumbnails and the saved position use.
    func testAccessMatchesTheOldUnlockRuleExactly() {
        for c in [C.legacy, .unknown, .newModel] {
            for entitled in [true, false] {
                for ep in [1, 2, 9] {
                    let unlocked = StoreService.isUnlocked(entitled: entitled, classification: c, episodeNumber: ep, collectionId: "x")
                    XCTAssertEqual(access(entitled, c, ep: ep), unlocked ? .full : .preview)
                }
            }
        }
    }
}

/// Where the reader opens and when a page turn goes ahead, for a preview:
/// never beyond the last free page, however the page was asked for (a saved
/// position, a thumbnail, a word's context, a cross-page move).
final class ReaderPreviewGateTests: XCTestCase {
    private func pages(_ count: Int) -> [Page] {
        (1...count).map { Page(id: "p\($0)", pageNumber: $0, masterImage: "img\($0)", panels: []) }
    }

    func testOpensOnTheRequestedPageWhenItIsFree() {
        let p = pages(12)
        for i in 0...3 { XCTAssertEqual(PageView.openingIndex(requested: i, pages: p, access: .preview), i) }
        for i in [0, 4, 11] { XCTAssertEqual(PageView.openingIndex(requested: i, pages: p, access: .full), i) }
    }

    func testOpensOnTheLastFreePageWhenAskedForOneBeyondThePreview() {
        let p = pages(12)
        for i in [4, 5, 11] { XCTAssertEqual(PageView.openingIndex(requested: i, pages: p, access: .preview), 3, "requested index \(i)") }
    }

    func testAnUnknownOrShortComicOpensSafely() {
        XCTAssertEqual(PageView.openingIndex(requested: 40, pages: pages(12), access: .preview), 0, "out of range: the cover")
        XCTAssertEqual(PageView.openingIndex(requested: 2, pages: pages(3), access: .preview), 2, "shorter than the preview: every page")
        XCTAssertEqual(PageView.openingIndex(requested: 0, pages: [], access: .preview), 0)
    }

    func testTurningIntoThePreviewGoesAheadAndTurningPastItDoesNot() {
        let p = pages(12)
        XCTAssertTrue(PageView.mayTurn(to: 1, pages: p, access: .preview))
        XCTAssertTrue(PageView.mayTurn(to: 3, pages: p, access: .preview), "the third story page")
        XCTAssertFalse(PageView.mayTurn(to: 4, pages: p, access: .preview), "the fourth: the paywall")
        XCTAssertFalse(PageView.mayTurn(to: 11, pages: p, access: .preview))
        XCTAssertTrue(PageView.mayTurn(to: 4, pages: p, access: .full))
        XCTAssertTrue(PageView.mayTurn(to: 11, pages: p, access: .full))
        XCTAssertFalse(PageView.mayTurn(to: 12, pages: p, access: .full), "past the end is never a page turn")
    }

    /// Pages are gated by their numbers, not their order in the array.
    func testGateFollowsPageNumbersNotArrayOrder() {
        let shuffled = pages(12).reversed().sorted { $0.pageNumber < $1.pageNumber }
        XCTAssertEqual(PageView.openingIndex(requested: 7, pages: shuffled, access: .preview), 3)
        XCTAssertEqual(shuffled[3].pageNumber, 4)
    }
}

/// What the practice modes may draw on: the preview's own pages, in order —
/// always a prefix of the whole comic's, so a saved spot means the same thing
/// before and after subscribing.
@MainActor
final class PreviewPracticeContentTests: XCTestCase {
    private func word(_ id: String) -> Word { Word(id: id, text: id, meaning: id) }
    private func comic(pages count: Int, wordsPerPage: Int = 2, practiceWords: Int = 3) -> Comic {
        let pages = (1...count).map { Page(id: "p\($0)", pageNumber: $0, masterImage: "img\($0)", panels: []) }
        var words: [ReviewWord] = []
        for p in pages { for k in 0..<wordsPerPage { words.append(ReviewWord(word: word("\(p.id)-w\(k)"), panelId: "panel", pageId: p.id)) } }
        for k in 0..<practiceWords { words.append(ReviewWord(word: word("kp-w\(k)"), panelId: "panel", pageId: "p1001")) }
        var c = Comic(id: "c", title: "C", description: "", coverImage: "cover", level: .beginner, isPremium: false, pages: pages.reversed())
        c.reviewWords = words
        return c
    }

    func testThePreviewPractisesTheCoverAndThreeStoryPagesInOrder() {
        let c = comic(pages: 12)
        XCTAssertEqual(StoreService.readablePages(of: c, access: .preview).map(\.pageNumber), [1, 2, 3, 4])
        XCTAssertEqual(StoreService.readablePages(of: c, access: .full).map(\.pageNumber), Array(1...12), "sorted, whatever the array order")
    }

    func testThePreviewsPagesAreAPrefixOfTheWholeComics() {
        let c = comic(pages: 12)
        let preview = StoreService.readablePages(of: c, access: .preview).map(\.id)
        let full = StoreService.readablePages(of: c, access: .full).map(\.id)
        XCTAssertEqual(Array(full.prefix(preview.count)), preview)
    }

    func testDrillWordsComeOnlyFromThePreviewPagesNeverFromKeyPhrasePages() {
        let c = comic(pages: 12, wordsPerPage: 2, practiceWords: 3)
        let preview = StoreService.readableReviewWords(of: c, access: .preview)
        XCTAssertEqual(preview.count, 8, "two words on each of the cover and three story pages")
        XCTAssertTrue(preview.allSatisfy { ["p1", "p2", "p3", "p4"].contains($0.pageId) })
        let full = StoreService.readableReviewWords(of: c, access: .full)
        XCTAssertEqual(full.count, 27, "everything, key-phrase pages included")
        XCTAssertEqual(Array(full.prefix(8).map(\.word.id)), preview.map(\.word.id), "a prefix: a saved word index survives subscribing")
    }

    func testAShortComicPreviewsInFull() {
        let c = comic(pages: 3)
        XCTAssertEqual(StoreService.readablePages(of: c, access: .preview).count, 3)
        XCTAssertEqual(StoreService.readableReviewWords(of: c, access: .preview).count, 6)
    }
}
