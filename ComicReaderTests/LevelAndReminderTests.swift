import XCTest
import UserNotifications
@testable import ComicReader

// MARK: - Spanish level

@MainActor
final class SpanishLevelTests: XCTestCase {
    private var levelDefaults: UserDefaults!
    private var analyticsDefaults: UserDefaults!
    private var backend: RecordingBackend!
    private var backendsMade = 0

    override func setUp() {
        super.setUp()
        levelDefaults = UserDefaults(suiteName: "SpanishLevelTests.level.\(UUID().uuidString)")
        analyticsDefaults = UserDefaults(suiteName: "SpanishLevelTests.analytics.\(UUID().uuidString)")
        backend = RecordingBackend()
        backendsMade = 0
    }

    private func analytics(consent: AnalyticsConsent?) -> AnalyticsService {
        if let consent { analyticsDefaults.set(consent.rawValue, forKey: AnalyticsService.consentKey) }
        let config = AnalyticsConfiguration(environment: .development, projectToken: "phc_test", host: "https://eu.i.posthog.com")
        let s = AnalyticsService(defaults: analyticsDefaults, configuration: config,
                                 makeBackend: { [unowned self] in self.backendsMade += 1; return self.backend },
                                 log: { _ in }, onConsentChange: { _ in },
                                 spanishLevel: { [unowned self] in SpanishLevel.stored(in: self.levelDefaults) })
        s.start()
        s.entitlement = .free
        return s
    }

    private func sent(_ s: AnalyticsService) -> [(name: String, properties: [String: Any])] {
        s.waitForBackend()
        return backend.events
    }

    func testStableStoredValues() {
        XCTAssertEqual(SpanishLevel.allCases.map(\.rawValue), ["complete_beginner", "beginner", "intermediate", "advanced"])
        XCTAssertEqual(SpanishLevel.allCases.map(\.title), ["Complete beginner", "Beginner", "Intermediate", "Advanced"])
    }

    func testFirstRunAsksUntilALevelIsChosenAndTheChoiceSurvivesRelaunch() {
        XCTAssertNil(SpanishLevel.stored(in: levelDefaults), "first run: no level yet, so the question shows")
        SpanishLevel.select(.intermediate, defaults: levelDefaults, analytics: analytics(consent: nil))
        // A relaunch reads the same stored value — the question isn't shown again.
        XCTAssertEqual(SpanishLevel.stored(in: levelDefaults), .intermediate)
        XCTAssertEqual(levelDefaults.string(forKey: SpanishLevel.storageKey), "intermediate")
    }

    func testChangingTheLevelSendsTheEventAgainButReselectingDoesNot() {
        let a = analytics(consent: .granted)
        SpanishLevel.select(.beginner, defaults: levelDefaults, analytics: a)
        SpanishLevel.select(.beginner, defaults: levelDefaults, analytics: a)
        SpanishLevel.select(.advanced, defaults: levelDefaults, analytics: a)
        let selections = sent(a).filter { $0.name == "spanish_level_selected" }
        XCTAssertEqual(selections.map { $0.properties["spanish_level"] as? String }, ["beginner", "advanced"])
    }

    func testWithAnalyticsDeclinedNothingIsSentButTheLevelIsStored() {
        let a = analytics(consent: .denied)
        SpanishLevel.select(.completeBeginner, defaults: levelDefaults, analytics: a)
        a.track(.paywallViewed(source: .settings))
        a.waitForBackend()
        XCTAssertEqual(backendsMade, 0, "no PostHog at all")
        XCTAssertEqual(SpanishLevel.stored(in: levelDefaults), .completeBeginner)
    }

    func testAChoiceMadeBeforeConsentIsNotReportedLaterButLaterEventsCarryTheLevel() {
        let a = analytics(consent: nil)
        SpanishLevel.select(.intermediate, defaults: levelDefaults, analytics: a)   // before any consent choice
        a.setConsent(true)
        a.track(.paywallViewed(source: .settings))
        let events = sent(a)
        XCTAssertFalse(events.contains { $0.name == "spanish_level_selected" }, "no retroactive selection event")
        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.allSatisfy { $0.properties["spanish_level"] as? String == "intermediate" },
                      "events after consent carry the current level")
    }

    func testEventsAreSegmentedByTheCurrentLevel() {
        let a = analytics(consent: .granted)
        SpanishLevel.select(.beginner, defaults: levelDefaults, analytics: a)
        a.track(.comicPageViewed(comicId: "x", pageNumber: 2, totalPages: 9))
        SpanishLevel.select(.advanced, defaults: levelDefaults, analytics: a)
        a.track(.comicPageViewed(comicId: "x", pageNumber: 3, totalPages: 9))
        let pages = sent(a).filter { $0.name == "comic_page_viewed" }
        XCTAssertEqual(pages.map { $0.properties["spanish_level"] as? String }, ["beginner", "advanced"])
    }

    func testTurningAnalyticsOffKeepsTheStoredLevel() {
        let a = analytics(consent: .granted)
        SpanishLevel.select(.advanced, defaults: levelDefaults, analytics: a)
        a.setConsent(false)
        XCTAssertEqual(SpanishLevel.stored(in: levelDefaults), .advanced)
    }

    func testNoLevelMeansNoLevelProperty() {
        let a = analytics(consent: .granted)
        a.track(.paywallViewed(source: .settings))
        XCTAssertTrue(sent(a).allSatisfy { $0.properties["spanish_level"] == nil })
    }
}

// MARK: - Inactivity reminders

final class FakeNotificationCenter: NotificationScheduling {
    var status: UNAuthorizationStatus
    var grantOnRequest = true
    private(set) var requestCount = 0
    private(set) var pending: [String: (request: UNNotificationRequest, addedAt: Date)] = [:]
    let clock: () -> Date

    init(status: UNAuthorizationStatus, clock: @escaping () -> Date) {
        self.status = status
        self.clock = clock
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async -> Bool {
        requestCount += 1
        status = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }
    func add(_ request: UNNotificationRequest) async { pending[request.identifier] = (request, clock()) }
    func removePending(identifiers: [String]) { identifiers.forEach { pending[$0] = nil } }

    /// When each pending reminder would fire.
    func fireDates() -> [String: Date] {
        pending.mapValues { entry in
            entry.addedAt.addingTimeInterval((entry.request.trigger as! UNTimeIntervalNotificationTrigger).timeInterval)
        }
    }
    /// iOS delivered it: it's no longer pending.
    func deliver(_ id: String) { pending[id] = nil }
}

@MainActor
final class ReminderTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    private var clock = Date(timeIntervalSince1970: 2_000_000_000)
    private var defaults: UserDefaults!
    private var center: FakeNotificationCenter!

    override func setUp() {
        super.setUp()
        clock = t0
        defaults = UserDefaults(suiteName: "ReminderTests.\(UUID().uuidString)")
        center = FakeNotificationCenter(status: .notDetermined, clock: { [unowned self] in self.clock })
    }

    private func service() -> ReminderService {
        ReminderService(center: center, defaults: defaults, now: { [unowned self] in self.clock })
    }

    private let id3 = "comigo.inactivity.3d", id7 = "comigo.inactivity.7d"

    func testNothingIsRequestedOrScheduledOnLaunch() async {
        let r = service()
        await r.refreshAuthorization()
        await r.recordEngagement()
        XCTAssertEqual(center.requestCount, 0, "no system permission prompt on first launch")
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertFalse(r.shouldOfferPrompt, "no reminder offer before the first completed comic")
    }

    func testTheOfferAppearsOnlyAfterTheFirstCompletedComic() async {
        let r = service()
        await r.refreshAuthorization()
        await r.recordEngagement()   // reading, but not finished
        XCTAssertFalse(r.shouldOfferPrompt)
        r.markComicCompleted()
        XCTAssertTrue(r.shouldOfferPrompt)
        XCTAssertEqual(center.requestCount, 0, "the offer is Comigo's own card, not the iOS prompt")
    }

    func testNotNowIsRememberedAndNeverRepeated() async {
        let r = service()
        r.markComicCompleted()
        r.notNow()
        XCTAssertFalse(r.shouldOfferPrompt)
        r.markComicCompleted()
        XCTAssertFalse(service().shouldOfferPrompt, "still not offered after a relaunch")
        XCTAssertEqual(center.requestCount, 0)
        XCTAssertEqual(r.settingsState, .off, "can still be turned on in Settings")
    }

    func testAllowingAsksIOSOnceAndSchedules3And7DayReminders() async {
        let r = service()
        r.markComicCompleted()
        let on = await r.allowReminders()
        XCTAssertTrue(on)
        XCTAssertEqual(center.requestCount, 1)
        XCTAssertEqual(center.fireDates(), [id3: t0.addingTimeInterval(3 * day), id7: t0.addingTimeInterval(7 * day)])
        let content = center.pending[id3]!.request.content
        XCTAssertEqual(content.title, "Your Spanish stories are waiting")
        XCTAssertEqual(content.body, "Continue reading with Comigo and see what happens next.")
        XCTAssertFalse((center.pending[id3]!.request.trigger as! UNTimeIntervalNotificationTrigger).repeats)
        XCTAssertEqual(r.settingsState, .on)
        XCTAssertFalse(r.shouldOfferPrompt)
    }

    func testAnAlreadyGrantedPermissionIsNotRequestedAgain() async {
        center.status = .authorized
        let r = service()
        await r.allowReminders()
        XCTAssertEqual(center.requestCount, 0)
        XCTAssertEqual(center.pending.count, 2)
    }

    func testEngagementRollsBothRemindersForward() async {
        let r = service()
        await r.allowReminders()
        clock = t0.addingTimeInterval(2 * 3600)
        await r.recordEngagement()
        XCTAssertEqual(center.fireDates(), [id3: clock.addingTimeInterval(3 * day), id7: clock.addingTimeInterval(7 * day)])
    }

    func testRapidEngagementDoesNotChurnTheSchedule() async {
        let r = service()
        await r.allowReminders()
        clock = t0.addingTimeInterval(20 * 60)   // page turns 20 minutes later
        await r.recordEngagement()
        XCTAssertEqual(center.fireDates()[id3], t0.addingTimeInterval(3 * day), "unchanged within the throttle")
    }

    func testReturningBetweenDay3AndDay7ReplacesTheOldDay7Reminder() async {
        let r = service()
        await r.allowReminders()
        clock = t0.addingTimeInterval(3 * day); center.deliver(id3)   // 3-day reminder shown
        clock = t0.addingTimeInterval(4 * day)                          // they come back and read
        await r.recordEngagement()
        XCTAssertEqual(center.fireDates(), [id3: clock.addingTimeInterval(3 * day), id7: clock.addingTimeInterval(7 * day)])
        XCTAssertNotEqual(center.fireDates()[id7], t0.addingTimeInterval(7 * day), "the old day-7 reminder is gone")
    }

    func testDecliningTheSystemPromptLeavesRemindersOffAndSettingsShowsWhy() async {
        center.grantOnRequest = false
        let r = service()
        r.markComicCompleted()
        let on = await r.allowReminders()
        XCTAssertFalse(on)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(r.settingsState, .blockedInSystem)
        XCTAssertFalse(r.shouldOfferPrompt, "no second offer once iOS said no")
    }

    func testTurningNotificationsOffInIOSSettingsStopsRemindersAndSettingsIsNotMisleading() async {
        let r = service()
        await r.allowReminders()
        center.status = .denied                     // user switched them off in iOS Settings
        await r.refreshAuthorization()
        XCTAssertTrue(center.pending.isEmpty, "pending reminders cleared")
        XCTAssertEqual(r.settingsState, .blockedInSystem, "not shown as on")
        clock = t0.addingTimeInterval(2 * day)
        await r.recordEngagement()
        XCTAssertTrue(center.pending.isEmpty, "nothing scheduled while iOS blocks notifications")
        center.status = .authorized                 // and back on again in iOS Settings
        await r.refreshAuthorization()
        await r.recordEngagement()
        XCTAssertEqual(r.settingsState, .on)
        XCTAssertEqual(center.pending.count, 2)
    }

    func testSettingsSwitchReflectsTheAppChoiceAndIOSPermission() async {
        let r = service()
        XCTAssertEqual(r.settingsState, .off)
        await r.allowReminders()
        XCTAssertEqual(r.settingsState, .on)
        r.disableReminders()
        XCTAssertEqual(r.settingsState, .off)
        XCTAssertTrue(center.pending.isEmpty)
        clock = t0.addingTimeInterval(3 * 3600)
        await r.recordEngagement()
        XCTAssertTrue(center.pending.isEmpty, "turned off in the app: engagement schedules nothing")
        center.status = .provisional
        await r.allowReminders()
        XCTAssertEqual(r.settingsState, .on, "provisional permission counts as allowed")
    }

    func testSchedulingIsEntirelyLocal() async {
        // The service's only dependency is the local notification centre —
        // reminders work with no server, account or network.
        let r = service()
        await r.allowReminders()
        XCTAssertEqual(Set(center.pending.keys), [id3, id7])
        XCTAssertEqual(ReminderService.delays, [3 * day, 7 * day])
    }
}
