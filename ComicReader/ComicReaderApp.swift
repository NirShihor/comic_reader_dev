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
        // Comics left part-way through a progressive download (the app was
        // killed, the connection dropped) carry on — now and whenever the app
        // comes back to the foreground.
        Task { await ComicStoreService.shared.resumePartialDownloads() }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { await ComicStoreService.shared.resumePartialDownloads() }
        }
        // …and when the network returns, including downloads that failed for
        // lack of it (the reader may be waiting on one of their pages).
        ComicAssetAvailability.shared.onNetworkReturned = {
            Task { await ComicStoreService.shared.resumePartialDownloads(retryingFailed: true) }
        }
        ComicAssetAvailability.shared.startMonitoringNetwork()
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
