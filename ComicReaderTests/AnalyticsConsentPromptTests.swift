import XCTest
@testable import ComicReader

/// WHEN "Help improve Comigo" is asked: eligible once a few pages of a comic
/// have been read, shown on the next Library visit, never over the first-run
/// tooltips or another prompt, once. The services the Library feeds into the
/// decision are real (their persistence is what makes the existing choices
/// and the milestone survive relaunches).
@MainActor
final class AnalyticsConsentPromptTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AnalyticsConsentPromptTests.\(UUID().uuidString)")
    }

    private func analytics() -> AnalyticsService {
        let config = AnalyticsConfiguration(environment: .development, projectToken: "phc_test", host: "https://eu.i.posthog.com")
        return AnalyticsService(defaults: defaults, configuration: config, makeBackend: { RecordingBackend() }, log: { _ in })
    }

    private func prompt() -> AnalyticsConsentPrompt { AnalyticsConsentPrompt(defaults: defaults) }

    private func reminders() -> ReminderService {
        ReminderService(center: FakeNotificationCenter(status: .notDetermined, clock: Date.init), defaults: defaults)
    }

    /// The Library's situation from the services, with the screen state given.
    private func situation(_ a: AnalyticsService, _ p: AnalyticsConsentPrompt, _ r: ReminderService? = nil,
                           onboarding: Bool = false, other: Bool = false) -> AnalyticsConsentPrompt.Situation {
        .init(consent: a.consent, eligible: p.isEligible,
              onboardingActive: onboarding, otherPresentation: other || (r?.shouldOfferPrompt ?? false))
    }

    /// The reader reads `n` story pages (what PageView does at each page view
    /// past the cover — see `readerRecords`).
    private func read(_ n: Int, _ p: AnalyticsConsentPrompt) { for _ in 0..<n { p.recordPageRead() } }

    /// PageView's rule: a page view counts only past the first page (the cover,
    /// which the exports number 1 — the story starts on the second page).
    private func readerRecords(pageIndex: Int, _ p: AnalyticsConsentPrompt) {
        if pageIndex > 0 { p.recordPageRead() }
    }

    // MARK: The milestone

    func testPagesZeroToTwoDoNotMakeItEligible() {
        let p = prompt()
        for n in 0..<AnalyticsConsentPrompt.pagesForEligibility {
            XCTAssertFalse(p.isEligible, "after \(n) page(s)")
            XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(analytics(), p)), "after \(n) page(s)")
            p.recordPageRead()
        }
    }

    func testTheThirdPageMakesItEligibleAndThatSurvivesRelaunch() {
        let p = prompt()
        read(3, p)
        XCTAssertTrue(p.isEligible)
        XCTAssertTrue(prompt().isEligible, "persisted: a new instance (next launch) still qualifies")
        XCTAssertEqual(defaults.integer(forKey: AnalyticsConsentPrompt.pagesReadKey), 3)
        read(50, p)
        XCTAssertEqual(p.pagesRead, 3, "capped — a page count, not a reading log")
    }

    func testTheCoverDoesNotCount() {
        let p = prompt()
        readerRecords(pageIndex: 0, p)   // opened on the cover
        XCTAssertEqual(p.pagesRead, 0, "the cover isn't a page read")
        readerRecords(pageIndex: 1, p)
        readerRecords(pageIndex: 2, p)
        XCTAssertEqual(p.pagesRead, 2)
        XCTAssertFalse(p.isEligible, "cover + two story pages isn't enough")
        readerRecords(pageIndex: 1, p)   // swiped back to page 1 — still a story page view
        XCTAssertTrue(p.isEligible, "the third story-page view")
        let q = AnalyticsConsentPrompt(defaults: UserDefaults(suiteName: "AnalyticsConsentPromptTests.cover.\(UUID().uuidString)")!)
        readerRecords(pageIndex: 0, q); readerRecords(pageIndex: 0, q); readerRecords(pageIndex: 0, q)
        XCTAssertFalse(q.isEligible, "lingering on the cover never qualifies")
    }

    func testPagesReadAcrossLaunchesAddUp() {
        read(2, prompt())
        let later = prompt()
        XCTAssertFalse(later.isEligible)
        later.recordPageRead()
        XCTAssertTrue(later.isEligible)
    }

    // MARK: Where and when it shows

    /// Reading a page makes nothing appear: the reader has no card and the
    /// policy answers the Library only. Inside the reader the Library is off
    /// screen, so the moment of eligibility shows nothing.
    func testReachingTheMilestoneInsideTheReaderShowsNothingThere() {
        let p = prompt()
        var shownWhileReading = 0
        for _ in 0..<5 {
            p.recordPageRead()   // what the reader does; it never calls shouldShow
            // The reader is the current presentation from the Library's point of view.
            if AnalyticsConsentPrompt.shouldShow(situation(analytics(), p, other: true)) { shownWhileReading += 1 }
        }
        XCTAssertTrue(p.isEligible)
        XCTAssertEqual(shownWhileReading, 0)
    }

    func testAppearsOnTheNextLibraryVisit() {
        let a = analytics(), p = prompt()
        read(3, p)
        XCTAssertTrue(AnalyticsConsentPrompt.shouldShow(situation(a, p)), "back on the Library, nothing else up")
    }

    func testCannotInterruptOnboardingOrHelp() {
        let a = analytics(), p = prompt()
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(a, p, onboarding: true)), "fresh install, tooltips under way")
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(a, p, onboarding: false)), "between tooltips, nothing read yet")
        read(3, p)
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(a, p, onboarding: true)), "eligible, but a tooltip or a help replay is up")
        XCTAssertTrue(AnalyticsConsentPrompt.shouldShow(situation(a, p, onboarding: false)))
    }

    func testCannotInterruptAnotherPresentation() {
        let a = analytics(), p = prompt(), r = reminders()
        read(3, p)
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(a, p, other: true)), "a sheet (paywall, purchase, creator message) is up")
        r.markComicCompleted()
        XCTAssertTrue(r.shouldOfferPrompt)
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(a, p, r)), "the reminder offer comes first")
        r.notNow()
        XCTAssertTrue(AnalyticsConsentPrompt.shouldShow(situation(a, p, r)))
    }

    // MARK: Choices already made

    func testExistingAllowIsPreserved() {
        defaults.set(AnalyticsConsent.granted.rawValue, forKey: AnalyticsService.consentKey)
        let a = analytics(), p = prompt()
        read(3, p)
        XCTAssertEqual(a.consent, .granted)
        XCTAssertTrue(a.isEnabled)
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(a, p)))
    }

    func testExistingNoThanksIsPreserved() {
        defaults.set(AnalyticsConsent.denied.rawValue, forKey: AnalyticsService.consentKey)
        let a = analytics(), p = prompt()
        read(3, p)
        XCTAssertEqual(a.consent, .denied)
        XCTAssertFalse(a.isEnabled)
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(a, p)))
    }

    func testDoesNotReappearOnceAnswered() {
        let a = analytics(), p = prompt()
        read(3, p)
        XCTAssertTrue(AnalyticsConsentPrompt.shouldShow(situation(a, p)))
        a.setConsent(false)
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(a, p)))
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(analytics(), prompt())), "the answer is persisted across launches")
        let b = analytics()
        b.setConsent(true)
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(b, p)))
    }

    /// An install from before this change: onboarding long done, plenty read,
    /// no choice stored. Nothing is chosen for them; they're asked once they've
    /// read a few more pages, on the next Library visit.
    func testExistingUsersWithoutAChoiceAreHandledSafely() {
        defaults.set(true, forKey: "creatorMessage.seen")
        defaults.set(true, forKey: "help.seen.library-title")
        defaults.set(true, forKey: "help.seen.choose-collection")
        defaults.set(true, forKey: "analytics.consentCardDeferred")   // the old deferral flag, now ignored
        defaults.set(true, forKey: "reminders.firstComicCompleted")
        let a = analytics(), p = prompt()
        XCTAssertNil(a.consent)
        XCTAssertFalse(p.isEligible)
        XCTAssertFalse(AnalyticsConsentPrompt.shouldShow(situation(a, p)))
        read(3, p)
        XCTAssertTrue(AnalyticsConsentPrompt.shouldShow(situation(a, p)))
        XCTAssertNil(a.consent, "nothing has been chosen on the user's behalf")
        XCTAssertNil(defaults.string(forKey: AnalyticsService.consentKey))
    }

    // MARK: The other layer

    /// The anonymous aggregate counts run whatever the optional choice — or
    /// none — and the milestone neither reads nor writes anything of theirs.
    func testAggregateCountsRunRegardlessOfTheOptionalChoice() {
        for consent in [nil, AnalyticsConsent.denied, AnalyticsConsent.granted] {
            var counted: [String] = []
            let d = UserDefaults(suiteName: "AnalyticsConsentPromptTests.agg.\(UUID().uuidString)")!
            if let consent { d.set(consent.rawValue, forKey: AnalyticsService.consentKey) }
            let config = AnalyticsConfiguration(environment: .development, projectToken: "phc_test", host: "https://eu.i.posthog.com")
            let s = AnalyticsService(defaults: d, configuration: config, makeBackend: { RecordingBackend() }, log: { _ in },
                                     aggregate: { counted.append($0.name) })
            s.start()
            s.entitlement = .free
            s.track(.comicPageViewed(comicId: "comic-1", pageNumber: 1, totalPages: 5))
            s.waitForBackend()
            XCTAssertEqual(counted, ["app_opened", "comic_page_viewed"], "consent \(String(describing: consent))")
            let p = AnalyticsConsentPrompt(defaults: d)
            for _ in 0..<3 { p.recordPageRead() }
            XCTAssertEqual(Set(d.dictionaryRepresentation().keys.filter { $0.hasPrefix("analytics.") }).subtracting([AnalyticsService.consentKey, AnalyticsConsentPrompt.pagesReadKey]), [],
                           "the milestone writes only its own key")
        }
    }
}
