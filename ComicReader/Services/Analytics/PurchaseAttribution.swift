import Foundation

/// Lets the server attribute App Store subscription events (renewals, trial
/// conversions — which happen while the app is closed) to the same anonymous
/// analytics user, without giving Apple the analytics ID.
///
/// A random UUID, created on this device, is passed to StoreKit as the
/// purchase's `appAccountToken`; Apple returns it in its server notifications.
/// Only while the user has opted into analytics, the app tells the Comigo
/// server which analytics ID that UUID belongs to. Opting out deletes that
/// mapping on the server. Purchasing and entitlement never depend on any of this.
@MainActor
final class PurchaseAttribution {
    static let shared = PurchaseAttribution()

    private static let tokenKey = "purchaseAttribution.token"
    private static let registeredKey = "purchaseAttribution.registered"
    private let defaults: UserDefaults
    private let endpoint: URL

    init(defaults: UserDefaults = .standard,
         endpoint: URL = URL(string: "\(Secrets.serverBaseURL)/api/reader/purchase-attribution")!) {
        self.defaults = defaults
        self.endpoint = endpoint
    }

    /// The token already stored on this device, if any purchase used one.
    var existingToken: UUID? {
        defaults.string(forKey: Self.tokenKey).flatMap(UUID.init(uuidString:))
    }

    /// The `appAccountToken` for a purchase starting now — nil unless the user
    /// has opted into analytics (then no token is attached and nothing is
    /// attributed). Also (re)registers the mapping.
    func tokenForPurchase() -> UUID? {
        guard AnalyticsService.shared.isEnabled else { return nil }
        let token: UUID
        if let existing = existingToken {
            token = existing
        } else {
            token = UUID()
            defaults.set(token.uuidString, forKey: Self.tokenKey)
        }
        syncMapping()
        return token
    }

    func consentChanged(granted: Bool) {
        if granted {
            syncMapping()
        } else {
            unregister()
        }
    }

    /// Registers token → analytics ID with the server when it isn't already
    /// registered for the current analytics ID. Fire-and-forget; retried at
    /// the next purchase or consent change.
    func syncMapping() {
        guard AnalyticsService.shared.isEnabled, let token = existingToken else { return }
        let accessModel = AnalyticsService.shared.accessModel?.rawValue
        let endpoint = endpoint
        let alreadyRegistered = defaults.string(forKey: Self.registeredKey)
        AnalyticsService.shared.withDistinctId { distinctId in
            let marker = "\(token.uuidString)|\(distinctId)|\(accessModel ?? "")"
            guard marker != alreadyRegistered else { return }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: String] = ["token": token.uuidString.lowercased(), "distinctId": distinctId]
            if let accessModel { body["accessModel"] = accessModel }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request) { _, response, _ in
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                Task { @MainActor in PurchaseAttribution.shared.defaults.set(marker, forKey: Self.registeredKey) }
            }.resume()
        }
    }

    /// Deletes the server-side mapping. The token itself stays on the device
    /// (Apple keeps it on existing subscriptions), so opting back in later
    /// re-links them.
    private func unregister() {
        defaults.removeObject(forKey: Self.registeredKey)
        guard let token = existingToken else { return }
        var request = URLRequest(url: endpoint.appendingPathComponent(token.uuidString.lowercased()))
        request.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: request).resume()
    }
}
