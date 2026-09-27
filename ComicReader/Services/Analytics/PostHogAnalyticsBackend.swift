import Foundation
import PostHog

/// The only file that talks to the PostHog SDK. Everything automatic is off:
/// the app sends its own named events and nothing else — no screen or
/// lifecycle autocapture, no taps, no session replay, no surveys, no feature
/// flags, no push-token registration, no crash capture, no person profiles,
/// and no IP-based location.
final class PostHogAnalyticsBackend: AnalyticsBackend, @unchecked Sendable {
    /// Device details the SDK attaches to every event that Comigo's analysis
    /// doesn't need. Stripped on the device, before an event is queued or sent.
    /// Kept: app version/build, OS name/version, device type (iPhone/iPad) and
    /// the SDK's session ID.
    static let strippedProperties: Set<String> = [
        "$device_manufacturer", "$device_model", "$device_name", "$is_emulator",
        "$is_ios_running_on_mac", "$is_mac_catalyst_app", "$is_sideloaded",
        "$network_wifi", "$network_cellular", "$network_carrier",
        "$screen_width", "$screen_height", "$screen_name",
        "$locale", "$timezone", "$recording_status",
    ]
    /// The SDK's own debugging metadata (queue size, session timing, replay
    /// settings) — technical diagnostics we don't collect.
    static let strippedPrefixes = ["$sdk_debug_"]

    func setUp(projectToken: String, host: String) {
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.captureElementInteractions = false
        config.captureSwiftUIElementInteractions = false
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        config.sessionReplay = false
        config.surveys = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.errorTrackingConfig.autoCapture = false
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.setBeforeSend { event in
            for key in event.properties.keys
            where Self.strippedProperties.contains(key) || Self.strippedPrefixes.contains(where: { key.hasPrefix($0) }) {
                event.properties.removeValue(forKey: key)
            }
            event.properties["$geoip_disable"] = true
            return event
        }
        PostHogSDK.shared.setup(config)
    }

    func capture(_ event: String, properties: [String: Any]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    func optIn() { PostHogSDK.shared.optIn() }

    func optOut() { PostHogSDK.shared.optOut() }

    func distinctId() -> String { PostHogSDK.shared.getDistinctId() }
}
