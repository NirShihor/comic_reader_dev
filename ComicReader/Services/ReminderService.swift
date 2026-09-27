import Foundation
import UserNotifications
import UIKit

/// The slice of UNUserNotificationCenter the reminders need (tests use a fake).
protocol NotificationScheduling: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest) async
    func removePending(identifiers: [String])
}

final class SystemNotificationCenter: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }
    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async -> Bool { (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false }
    func add(_ request: UNNotificationRequest) async { try? await center.add(request) }
    func removePending(identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
}

/// Rolling local inactivity reminders: 3 and 7 days after the most recent
/// meaningful use (reading or practising). Entirely on the device — nothing
/// about activity or the schedule is sent anywhere.
///
/// Permission is never requested on launch. After the first completed comic,
/// the app offers "Want a little reminder?"; only "Allow reminders" asks iOS.
/// "Not now" is remembered and the offer isn't repeated (Settings → Reminders
/// can turn them on at any time).
@MainActor
final class ReminderService: ObservableObject {
    static let shared = ReminderService()

    static let identifiers = ["comigo.inactivity.3d", "comigo.inactivity.7d"]
    static let delays: [TimeInterval] = [3 * 86_400, 7 * 86_400]
    /// Engagements closer together than this don't re-schedule (the reminder
    /// may then fire up to this much earlier than exactly 3/7 days).
    static let rescheduleThrottle: TimeInterval = 60 * 60

    enum PromptAnswer: String { case allowed, notNow }

    /// What Settings shows, from the user's choice AND iOS's actual permission.
    enum SettingsState: Equatable {
        case on                 // chosen, and iOS allows notifications
        case off                // not chosen (or turned off in the app)
        case blockedInSystem    // iOS notifications are off for Comigo — only iOS Settings can change that
    }

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var promptAnswer: PromptAnswer?
    @Published private(set) var enabled: Bool
    @Published private(set) var firstComicCompleted: Bool

    private let center: NotificationScheduling
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastScheduledAt: Date?

    private enum Key {
        static let answer = "reminders.promptAnswer"
        static let enabled = "reminders.enabled"
        static let firstComic = "reminders.firstComicCompleted"
    }

    init(center: NotificationScheduling = SystemNotificationCenter(),
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.center = center
        self.defaults = defaults
        self.now = now
        promptAnswer = defaults.string(forKey: Key.answer).flatMap(PromptAnswer.init(rawValue:))
        enabled = defaults.bool(forKey: Key.enabled)
        firstComicCompleted = defaults.bool(forKey: Key.firstComic)
    }

    private var systemAllows: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    var settingsState: SettingsState {
        if authorization == .denied { return .blockedInSystem }
        return enabled && systemAllows ? .on : .off
    }

    /// Offer the in-app prompt: after the first completed comic, never
    /// answered before, and iOS hasn't already refused (then only Settings can help).
    var shouldOfferPrompt: Bool {
        firstComicCompleted && promptAnswer == nil && !enabled && authorization != .denied
    }

    /// At launch and on every return to the foreground: pick up changes made
    /// in iOS Settings. Never asks for permission.
    func startObserving() {
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshAuthorization() }
        }
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        authorization = await center.authorizationStatus()
        if !systemAllows { center.removePending(identifiers: Self.identifiers) }
    }

    /// The reader moved past the last page of a comic (the End of Episode moment).
    func markComicCompleted() {
        guard !firstComicCompleted else { return }
        firstComicCompleted = true
        defaults.set(true, forKey: Key.firstComic)
    }

    /// "Allow reminders" (prompt) or switching them on in Settings. Asks iOS
    /// only if it hasn't decided yet; returns whether reminders are now on.
    @discardableResult
    func allowReminders() async -> Bool {
        answer(.allowed)
        await refreshAuthorization()
        if authorization == .notDetermined {
            _ = await center.requestAuthorization()
            await refreshAuthorization()
        }
        setEnabled(systemAllows)
        if systemAllows { await schedule() }
        return systemAllows
    }

    func notNow() {
        answer(.notNow)
    }

    /// Settings switch turned off.
    func disableReminders() {
        setEnabled(false)
        center.removePending(identifiers: Self.identifiers)
    }

    /// Meaningful use — a reading session or a practice session. Replaces any
    /// outstanding reminders with new ones 3 and 7 days from now.
    func recordEngagement() async {
        guard enabled else { return }
        if let last = lastScheduledAt, now().timeIntervalSince(last) < Self.rescheduleThrottle { return }
        await refreshAuthorization()
        guard systemAllows else { return }
        await schedule()
    }

    private func schedule() async {
        center.removePending(identifiers: Self.identifiers)
        for (id, delay) in zip(Self.identifiers, Self.delays) {
            let content = UNMutableNotificationContent()
            content.title = "Your Spanish stories are waiting"
            content.body = "Continue reading with Comigo and see what happens next."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        lastScheduledAt = now()
    }

    private func answer(_ value: PromptAnswer) {
        promptAnswer = value
        defaults.set(value.rawValue, forKey: Key.answer)
    }

    private func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: Key.enabled)
    }

    /// iOS's notification settings page for Comigo.
    static var systemSettingsURL: URL? {
        URL(string: UIApplication.openNotificationSettingsURLString)
    }
}
