import Foundation
import StoreKit
import UIKit

/// Which access model this Apple ID is on, from Apple's signed record of when
/// it first acquired Comigo (`AppTransaction.originalAppVersion` — on iOS the
/// build number of that first download).
///
/// - legacy: first acquired before build 200 — keeps "first episode of every
///   collection free", forever, whatever happens to any trial or subscription.
/// - newModel: first acquired from build 200 — reading needs an active trial,
///   subscription or lifetime unlock.
/// - unknown: not (yet) established safely — treated exactly like legacy, so a
///   StoreKit outage or a verification/parsing problem can never take access
///   away from an existing user.
///
/// Nothing local (install or launch dates, stored flags) takes part: the same
/// Apple ID gets the same answer after a reinstall or on another device.
@MainActor
final class AccessModelService: ObservableObject {
    static let shared = AccessModelService()

    /// The first App Store build that ships the new access model. Builds
    /// 1…125 were released under the old model (125 = last, confirmed in
    /// App Store Connect); 126…199 are deliberately never used.
    static let firstNewModelBuild = 200

    enum Classification: String, Equatable {
        case legacy
        case newModel
        case unknown
    }

    /// Sandbox / TestFlight / Xcode only: Apple always reports
    /// originalAppVersion "1.0" there, so testers pick the model instead.
    enum TesterOverride: String, CaseIterable {
        case automatic, legacy, newModel
    }

    /// What we read from AppTransaction — the only input to classification.
    struct Record: Equatable {
        let originalAppVersion: String
        let environment: AppStore.Environment
        let verified: Bool
    }

    static let testerOverrideKey = "accessModel.testerOverride"

    @Published private(set) var classification: Classification = .unknown
    /// True when Apple says this is a sandbox/Xcode install (never in the App Store build).
    @Published private(set) var isTestEnvironment = false

    var isNewModel: Bool { classification == .newModel }

    private let fetchRecord: () async throws -> Record
    private let defaults: UserDefaults
    /// False for Xcode, TestFlight and App Review builds (sandbox receipt / Debug).
    private let isAppStoreBuild: Bool
    private var resolving = false

    init(defaults: UserDefaults = .standard,
         isAppStoreBuild: Bool = AnalyticsEnvironment.current == .production,
         fetchRecord: @escaping () async throws -> Record = AccessModelService.appTransactionRecord) {
        self.defaults = defaults
        self.isAppStoreBuild = isAppStoreBuild
        self.fetchRecord = fetchRecord
    }

    /// Reads StoreKit's cached/signed AppTransaction. Never asks the user to
    /// sign in (that only happens in `refreshAfterRestore`, a user action).
    nonisolated static func appTransactionRecord() async throws -> Record {
        let result = try await AppTransaction.shared
        switch result {
        case .verified(let t):
            return Record(originalAppVersion: t.originalAppVersion, environment: t.environment, verified: true)
        case .unverified(let t, _):
            return Record(originalAppVersion: t.originalAppVersion, environment: t.environment, verified: false)
        }
    }

    var testerOverride: TesterOverride {
        get { defaults.string(forKey: Self.testerOverrideKey).flatMap(TesterOverride.init(rawValue:)) ?? .automatic }
        set {
            defaults.set(newValue.rawValue, forKey: Self.testerOverrideKey)
            Task { await resolve() }
        }
    }

    static func classify(_ record: Record?, testerOverride: TesterOverride) -> Classification {
        guard let record, record.verified else { return .unknown }
        switch record.environment {
        case .production:
            let build = record.originalAppVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !build.isEmpty, build.allSatisfy(\.isNumber), let number = Int(build) else { return .unknown }
            return number < firstNewModelBuild ? .legacy : .newModel
        case .sandbox, .xcode:
            return testerClassification(testerOverride)
        default:
            return .unknown
        }
    }

    /// Resolves at launch, on returning to the foreground while still unknown,
    /// and after a restore. Runs in the background; until it succeeds the app
    /// uses legacy rules. A failure never replaces an answer already found.
    ///
    /// App Store builds only ever classify from a verified production
    /// AppTransaction — anything else stays unknown (= legacy access). In
    /// Xcode / TestFlight / App Review builds the sandbox often can't supply
    /// the record, so there the tester choice (default: new model) is used
    /// instead of falling back to legacy.
    func resolve() async {
        guard !resolving else { return }
        resolving = true
        defer { resolving = false }
        let record = try? await fetchRecord()
        if let record {
            isTestEnvironment = record.environment == .sandbox || record.environment == .xcode
        }
        var result = Self.classify(record, testerOverride: testerOverride)
        if result == .unknown && !isAppStoreBuild {
            isTestEnvironment = true
            result = Self.testerClassification(testerOverride)
        }
        if result == .unknown && classification != .unknown { return }
        guard result != .unknown else { return }
        apply(result)
    }

    static func testerClassification(_ override: TesterOverride) -> Classification {
        override == .legacy ? .legacy : .newModel
    }

    /// After "Restore purchases" (a user action), ask Apple for a fresh
    /// AppTransaction — this may show an App Store sign-in — then re-resolve.
    func refreshAfterRestore() async {
        _ = try? await AppTransaction.refresh()
        await resolve()
    }

    func startObserving() {
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.classification == .unknown else { return }
                Task { await self.resolve() }
            }
        }
        Task { await resolve() }
    }

    #if DEBUG
    /// Unit tests only: put the shared service in a given state.
    func setForTesting(_ result: Classification, testEnvironment: Bool = false) {
        isTestEnvironment = testEnvironment
        classification = result
    }
    #endif

    private func apply(_ result: Classification) {
        guard result != classification else { return }
        classification = result
        AnalyticsService.shared.accessModelResolved(result.analyticsValue)
        PurchaseAttribution.shared.syncMapping()
    }
}

extension AccessModelService.Classification {
    var analyticsValue: AccessModel? {
        switch self {
        case .legacy: return .legacy
        case .newModel: return .newModel
        case .unknown: return nil
        }
    }
}
