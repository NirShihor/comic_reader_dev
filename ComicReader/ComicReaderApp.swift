import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AnalyticsService.shared.start()
        AggregateTelemetryService.shared.start()
        // Classify the access model (AppTransaction) and read the StoreKit
        // entitlement in the background. Nothing waits on either: until they
        // answer, the app uses legacy (never-reduced) access rules.
        AccessModelService.shared.startObserving()
        // Reads the current notification permission only; never requests it.
        ReminderService.shared.startObserving()
        _ = StoreService.shared
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadHelper.backgroundCompletionHandlers[identifier] = completionHandler
    }
}

@main
struct ComicReaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var progressManager = ReadingProgressManager()
    @StateObject private var notebookManager = NotebookManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsManager)
                .environmentObject(progressManager)
                .environmentObject(notebookManager)
        }
    }
}
