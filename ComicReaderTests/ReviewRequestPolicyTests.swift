import XCTest
@testable import ComicReader

/// WHEN the App Store rating request is made: eligible once two different
/// comics have been finished, made on the next Library visit with nothing
/// else up (and the scene active), once per installation — never from the
/// reader, never again after that.
@MainActor
final class ReviewRequestPolicyTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ReviewRequestPolicyTests.\(UUID().uuidString)")
    }

    private func policy() -> ReviewRequestPolicy { ReviewRequestPolicy(defaults: defaults) }

    /// The Library's situation for the policy, with the screen state given
    /// (what LibraryView.reviewSituation builds from its own state).
    private func situation(_ p: ReviewRequestPolicy, onboarding: Bool = false, other: Bool = false,
                           sceneActive: Bool = true) -> ReviewRequestPolicy.Situation {
        .init(due: p.isDue, onboardingActive: onboarding, otherPresentation: other, sceneActive: sceneActive)
    }

    /// What PageView does at the End of Episode moment of a plain reading session.
    private func finish(_ comicId: String, _ p: ReviewRequestPolicy) { p.recordComicCompleted(comicId) }

    // MARK: Distinct comics

    func testOneComicIsNotEnough() {
        let p = policy()
        finish("western-1", p)
        XCTAssertFalse(p.isEligible)
        XCTAssertFalse(p.isDue)
        XCTAssertFalse(ReviewRequestPolicy.shouldRequest(situation(p)))
    }

    func testReadingTheSameComicTwiceDoesNotCount() {
        let p = policy()
        finish("western-1", p)
        finish("western-1", p)
        finish("western-1", p)
        XCTAssertEqual(p.completedComicIds, ["western-1"])
        XCTAssertFalse(p.isEligible, "re-reading one comic isn't a second comic")
    }

    func testTheSecondDistinctComicMakesItEligible() {
        let p = policy()
        finish("western-1", p)
        finish("western-2", p)
        XCTAssertTrue(p.isEligible)
        XCTAssertTrue(p.isDue)
    }

    func testCompletionsAddUpAcrossLaunchesAndStopGrowingAfterTheMilestone() {
        finish("western-1", policy())
        let later = policy()
        XCTAssertEqual(later.completedComicIds, ["western-1"], "persisted: the next launch remembers the first")
        XCTAssertFalse(later.isEligible)
        finish("mystery-1", later)
        XCTAssertTrue(later.isEligible)
        XCTAssertTrue(policy().isEligible, "and the milestone itself survives a relaunch")
        finish("mystery-2", later)
        finish("mystery-3", later)
        XCTAssertEqual(later.completedComicIds.count, 2, "a milestone, not a reading log")
    }

    // MARK: Where and when it's asked

    /// Finishing a comic makes nothing happen: the reader never consults the
    /// policy, and from the Library's point of view the reader is "something
    /// else on screen" until the user comes back.
    func testReachingTheMilestoneInsideTheReaderRequestsNothingThere() {
        let p = policy()
        var requestedWhileReading = 0
        for id in ["a", "b", "c"] {
            finish(id, p)
            if ReviewRequestPolicy.shouldRequest(situation(p, other: true)) { requestedWhileReading += 1 }
        }
        XCTAssertTrue(p.isDue)
        XCTAssertEqual(requestedWhileReading, 0)
    }

    func testAskedOnTheNextQuietLibraryVisit() {
        let p = policy()
        finish("a", p); finish("b", p)
        XCTAssertTrue(ReviewRequestPolicy.shouldRequest(situation(p)), "back on the Library, nothing else up")
    }

    func testNeverOverOnboardingOrAnotherPresentationOrInTheBackground() {
        let p = policy()
        finish("a", p); finish("b", p)
        XCTAssertFalse(ReviewRequestPolicy.shouldRequest(situation(p, onboarding: true)), "a first-run tooltip or help replay")
        XCTAssertFalse(ReviewRequestPolicy.shouldRequest(situation(p, other: true)), "a sheet, the analytics card, the reminder offer, the creator message, an alert")
        XCTAssertFalse(ReviewRequestPolicy.shouldRequest(situation(p, onboarding: true, other: true)))
        XCTAssertFalse(ReviewRequestPolicy.shouldRequest(situation(p, sceneActive: false)), "scene not active")
        XCTAssertTrue(p.isDue, "nothing was consumed — it waits for a later visit")
        XCTAssertTrue(ReviewRequestPolicy.shouldRequest(situation(p)), "the later visit, quiet")
    }

    /// The Library composes the rating request's situation from the same
    /// state the analytics card uses, plus the card itself: whenever the card
    /// should show, the request must not.
    func testYieldsToTheAnalyticsCard() {
        let p = policy()
        finish("a", p); finish("b", p)
        let cardPending = AnalyticsConsentPrompt.Situation(consent: nil, eligible: true, onboardingActive: false, otherPresentation: false)
        XCTAssertTrue(AnalyticsConsentPrompt.shouldShow(cardPending))
        let review = ReviewRequestPolicy.Situation(due: p.isDue, onboardingActive: cardPending.onboardingActive,
                                                   otherPresentation: cardPending.otherPresentation || AnalyticsConsentPrompt.shouldShow(cardPending),
                                                   sceneActive: true)
        XCTAssertFalse(ReviewRequestPolicy.shouldRequest(review))
        let cardAnswered = AnalyticsConsentPrompt.Situation(consent: .granted, eligible: true, onboardingActive: false, otherPresentation: false)
        let reviewAfter = ReviewRequestPolicy.Situation(due: p.isDue, onboardingActive: false,
                                                        otherPresentation: AnalyticsConsentPrompt.shouldShow(cardAnswered), sceneActive: true)
        XCTAssertTrue(ReviewRequestPolicy.shouldRequest(reviewAfter))
    }

    // MARK: Once per installation

    func testAskedOnceAndRememberedAcrossLaunchesAndVersions() {
        let p = policy()
        finish("a", p); finish("b", p)
        XCTAssertTrue(ReviewRequestPolicy.shouldRequest(situation(p)))
        p.markRequested()   // what the Library does just before requestReview()
        XCTAssertTrue(p.requested)
        XCTAssertFalse(p.isDue)
        XCTAssertFalse(ReviewRequestPolicy.shouldRequest(situation(p)), "the same visit, again")
        let nextLaunch = policy()
        XCTAssertTrue(nextLaunch.requested, "persisted")
        XCTAssertFalse(nextLaunch.isDue, "a later launch — or a later app version on the same install — doesn't ask again")
        finish("c", nextLaunch); finish("d", nextLaunch)
        XCTAssertFalse(nextLaunch.isDue, "more comics don't reopen it")
        XCTAssertEqual(defaults.bool(forKey: ReviewRequestPolicy.requestedKey), true)
    }

    func testMarkingRequestedBeforeEligibilityStillSticks() {
        // Defensive: the flag is independent of the milestone.
        let p = policy()
        p.markRequested()
        finish("a", p); finish("b", p)
        XCTAssertTrue(p.isEligible)
        XCTAssertFalse(p.isDue)
    }
}
