import Foundation
import StoreKit
import os

/// Apple's privacy-preserving install attribution (SKAdNetwork; the system
/// mirrors the call into AdAttributionKit). Ad networks — Meta's App promotion
/// campaigns included — only learn of an install from the postback the
/// *device* sends them, and Apple documents that the advertised app must
/// "register an app installation by updating the conversion value when the
/// user first launches the app". Without that call no postback is ever sent,
/// and Ads Manager reports no installs.
///
/// Nothing here identifies anyone. The app hands Apple a conversion value
/// (a fine value 0–63 and a coarse low/medium/high); the device, days later,
/// sends the ad network a crowd-anonymised postback with no user or device
/// data. No App Tracking Transparency prompt is involved and nothing is sent
/// by the app itself. The system ignores the call when no ad impression is
/// pending for this app, so it is harmless on an install that came from
/// anywhere else.
///
/// This is separate from analytics: it does not depend on the PostHog consent
/// choice or the anonymous usage counts, and never touches either.
enum InstallAttribution {
    /// A conversion value as Apple's APIs take it. Meta's Events Manager
    /// schema ("custom integration") must describe the same meanings.
    struct ConversionValue: Equatable {
        let fine: Int
        let coarse: SKAdNetwork.CoarseConversionValue
    }

    /// "Installed and opened" — the only value reported for now.
    static let installed = ConversionValue(fine: 0, coarse: .low)

    /// UserDefaults key: set once a launch has been registered without error,
    /// so later launches don't resend (and, once richer values exist, don't
    /// overwrite a higher value with the install value).
    static let registeredKey = "installAttribution.registered"

    private static let logger = Logger(subsystem: "net.comigo.reader", category: "InstallAttribution")

    typealias Updater = (ConversionValue, @escaping @Sendable (Error?) -> Void) -> Void

    /// Call at launch. Registers the installation with Apple on the first
    /// launch (retried on later launches only if that call reported an error).
    /// Returns whether a registration call was made — for tests and logs.
    @discardableResult
    static func registerLaunch(defaults: UserDefaults = .standard,
                               update: Updater = systemUpdate) -> Bool {
        guard !defaults.bool(forKey: registeredKey) else {
            logger.debug("already registered — nothing to do")
            return false
        }
        let value = installed
        // UserDefaults is thread-safe; it just isn't marked Sendable.
        nonisolated(unsafe) let defaults = defaults
        update(value) { error in
            if let error {
                logger.error("registration failed: \(error.localizedDescription, privacy: .public)")
            } else {
                defaults.set(true, forKey: registeredKey)
                logger.info("install registered (fine \(value.fine), coarse low)")
            }
        }
        return true
    }

    /// The real call. `lockWindow: false` leaves the first conversion window
    /// open so a later, more valuable update can still replace this one.
    /// Made off the main thread: the call reaches the system's attribution
    /// daemon over XPC and must never hold up launch or the UI. The timings
    /// logged are diagnostics for exactly that.
    static func systemUpdate(_ value: ConversionValue, completion: @escaping @Sendable (Error?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let started = Date()
            SKAdNetwork.updatePostbackConversionValue(value.fine, coarseValue: value.coarse, lockWindow: false) { error in
                logger.info("Apple answered after \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
                completion(error)
            }
            logger.debug("call returned after \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
        }
    }
}
