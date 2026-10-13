import Foundation
import SwiftUI

// The Comigo analytics vocabulary. Every event the app can send is a case
// here, with typed properties — so names and property keys stay stable
// snake_case, and nothing free-form (dialogue, translations, user text) can
// reach the analytics provider. Adding an event means adding a case.

enum PaywallSource: String, CaseIterable {
    case comicLocked = "comic_locked"
    case settings
    case trialExpired = "trial_expired"
    case landingScreen = "landing_screen"
}

enum PracticeType: String, CaseIterable {
    case quiz
    case speaking
    case listening
    case repeatPractice = "repeat_practice"
    case translateSpeak = "translate_speak"
    case repeatListen = "repeat_listen"
    case originListen = "origin_listen"
    case keyPhrases = "key_phrases"
    case readSpeak = "read_speak"

    /// Maps the reader's persisted practice-mode keys onto the analytics
    /// vocabulary. Flow Practice is hidden in the app and deliberately absent.
    init?(modeKey: String) {
        switch modeKey {
        case "quiz": self = .quiz
        case "speaking": self = .speaking
        case "listening": self = .listening
        case "repeatPractice": self = .repeatPractice
        case "translateSpeak": self = .translateSpeak
        case "repeatListen": self = .repeatListen
        case "originListen": self = .originListen
        case "keyPhrases": self = .keyPhrases
        case "readSpeak": self = .readSpeak
        default: return nil
        }
    }
}

enum AudioType: String, CaseIterable {
    case sentence
    case word
}

enum PurchaseType: String, CaseIterable {
    case subscription
    case lifetime
}

enum Entitlement: String, CaseIterable {
    case free
    case trial
    case subscribed
    case lifetime
}

enum AccessModel: String, CaseIterable {
    case legacy
    case newModel = "new_model"
}

// Trial-conversion stages (1.2.2). Every value is a closed enumeration: a
// stage count can carry an outcome, never an error message or anything typed.

enum LandingCTA: String, CaseIterable {
    case getStarted = "get_started"
    case continueLearning = "continue_learning"
    case startTrial = "start_trial"
}

/// Which offer the paywall showed (StoreService.PaywallMode, as reported).
enum PaywallOffer: String, CaseIterable {
    case freeTrial = "free_trial"
    case subscribe
    case trialExpired = "trial_expired"
}

/// How a StoreKit purchase call ended. `failed` is the fact alone — the
/// error itself is never reported.
enum PurchaseResult: String, CaseIterable {
    case success
    case cancelled
    case pending
    case failed
}

enum OnboardingStep: String, CaseIterable {
    case levelSelected = "level_selected"
    case creatorMessageOpened = "creator_message_opened"
    case libraryFirstViewed = "library_first_viewed"
}

enum AnalyticsEvent {
    case appOpened
    case collectionViewed(collectionId: String?, collectionName: String, level: String)
    case comicStarted(comicId: String, comicName: String, collectionId: String?, level: String, isFree: Bool)
    case comicPageViewed(comicId: String, pageNumber: Int, totalPages: Int)
    case comicCompleted(comicId: String, comicName: String, collectionId: String?, level: String)
    case audioPlayed(comicId: String, pageNumber: Int?, audioType: AudioType)
    case translationRevealed(comicId: String, pageNumber: Int?)
    case practiceStarted(comicId: String, practiceType: PracticeType)
    case practiceCompleted(comicId: String, practiceType: PracticeType)
    case lockedContentTapped(comicId: String, collectionId: String?)
    case paywallViewed(source: PaywallSource)
    case trialOfferViewed(source: PaywallSource, productId: String)
    /// `source`: the paywall the trial was started from, when it was this
    /// device's own purchase call; nil for Transaction.updates.
    case trialStarted(productId: String, source: PaywallSource?)
    case subscriptionStarted(productId: String)
    case purchaseCompleted(productId: String, purchaseType: PurchaseType)
    case spanishLevelSelected(level: SpanishLevel)
    // Trial-conversion stages
    case landingViewed(returning: Bool, trialOfferShown: Bool)
    case landingCtaTapped(cta: LandingCTA, trialOfferShown: Bool)
    case paywallDismissed(source: PaywallSource, mode: PaywallOffer)
    case purchaseAttempted(source: PaywallSource, mode: PaywallOffer, productId: String)
    case purchaseResult(source: PaywallSource, productId: String, result: PurchaseResult)
    case onboardingStep(step: OnboardingStep)

    var name: String {
        switch self {
        case .appOpened: return "app_opened"
        case .collectionViewed: return "collection_viewed"
        case .comicStarted: return "comic_started"
        case .comicPageViewed: return "comic_page_viewed"
        case .comicCompleted: return "comic_completed"
        case .audioPlayed: return "audio_played"
        case .translationRevealed: return "translation_revealed"
        case .practiceStarted: return "practice_started"
        case .practiceCompleted: return "practice_completed"
        case .lockedContentTapped: return "locked_content_tapped"
        case .paywallViewed: return "paywall_viewed"
        case .trialOfferViewed: return "trial_offer_viewed"
        case .trialStarted: return "trial_started"
        case .subscriptionStarted: return "subscription_started"
        case .purchaseCompleted: return "purchase_completed"
        case .spanishLevelSelected: return "spanish_level_selected"
        case .landingViewed: return "landing_viewed"
        case .landingCtaTapped: return "landing_cta_tapped"
        case .paywallDismissed: return "paywall_dismissed"
        case .purchaseAttempted: return "purchase_attempted"
        case .purchaseResult: return "purchase_result"
        case .onboardingStep: return "onboarding_step"
        }
    }

    /// Event-specific properties. Optional values that are unknown are left
    /// out rather than sent as empty strings.
    var properties: [String: Any] {
        var p: [String: Any] = [:]
        func set(_ key: String, _ value: Any?) { if let value { p[key] = value } }
        switch self {
        case .appOpened:
            break
        case let .collectionViewed(collectionId, collectionName, level):
            set("collection_id", collectionId)
            set("collection_name", collectionName)
            set("level", level)
        case let .comicStarted(comicId, comicName, collectionId, level, isFree):
            set("comic_id", comicId)
            set("comic_name", comicName)
            set("collection_id", collectionId)
            set("level", level)
            set("is_free", isFree)
        case let .comicPageViewed(comicId, pageNumber, totalPages):
            set("comic_id", comicId)
            set("page_number", pageNumber)
            set("total_pages", totalPages)
        case let .comicCompleted(comicId, comicName, collectionId, level):
            set("comic_id", comicId)
            set("comic_name", comicName)
            set("collection_id", collectionId)
            set("level", level)
        case let .audioPlayed(comicId, pageNumber, audioType):
            set("comic_id", comicId)
            set("page_number", pageNumber)
            set("audio_type", audioType.rawValue)
        case let .translationRevealed(comicId, pageNumber):
            set("comic_id", comicId)
            set("page_number", pageNumber)
        case let .practiceStarted(comicId, practiceType), let .practiceCompleted(comicId, practiceType):
            set("comic_id", comicId)
            set("practice_type", practiceType.rawValue)
        case let .lockedContentTapped(comicId, collectionId):
            set("comic_id", comicId)
            set("collection_id", collectionId)
        case let .paywallViewed(source):
            set("source", source.rawValue)
        case let .trialOfferViewed(source, productId):
            set("source", source.rawValue)
            set("product_id", productId)
        case let .trialStarted(productId, source):
            set("product_id", productId)
            set("source", source?.rawValue)
        case let .subscriptionStarted(productId):
            set("product_id", productId)
        case let .purchaseCompleted(productId, purchaseType):
            set("product_id", productId)
            set("purchase_type", purchaseType.rawValue)
        case let .spanishLevelSelected(level):
            set("spanish_level", level.rawValue)
        case let .landingViewed(returning, trialOfferShown):
            set("returning", returning)
            set("trial_offer_shown", trialOfferShown)
        case let .landingCtaTapped(cta, trialOfferShown):
            set("cta", cta.rawValue)
            set("trial_offer_shown", trialOfferShown)
        case let .paywallDismissed(source, mode):
            set("source", source.rawValue)
            set("mode", mode.rawValue)
        case let .purchaseAttempted(source, mode, productId):
            set("source", source.rawValue)
            set("mode", mode.rawValue)
            set("product_id", productId)
        case let .purchaseResult(source, productId, result):
            set("source", source.rawValue)
            set("product_id", productId)
            set("result", result.rawValue)
        case let .onboardingStep(step):
            set("step", step.rawValue)
        }
        return p
    }

    /// Identity for duplicate suppression: the same event with the same
    /// properties arriving twice within the dedupe window is one occurrence
    /// reported twice by SwiftUI lifecycle callbacks, not two user actions.
    var dedupeKey: String {
        let props = properties.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "\(name)?\(props)"
    }
}

/// The comic (and page, while reading) a view is showing, so controls deep in
/// the tree — the bubble card, word pop-ups — can attribute their events.
struct AnalyticsComicContext: Equatable {
    let comicId: String
    let pageNumber: Int?
}

private struct AnalyticsComicContextKey: EnvironmentKey {
    static let defaultValue: AnalyticsComicContext? = nil
}

extension EnvironmentValues {
    var analyticsComicContext: AnalyticsComicContext? {
        get { self[AnalyticsComicContextKey.self] }
        set { self[AnalyticsComicContextKey.self] = newValue }
    }
}
