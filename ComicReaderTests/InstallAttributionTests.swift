import XCTest
import StoreKit
@testable import ComicReader

final class InstallAttributionTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "InstallAttributionTests.\(UUID().uuidString)")
    }

    func testFirstLaunchRegistersTheInstallValue() {
        var sent: [InstallAttribution.ConversionValue] = []
        let made = InstallAttribution.registerLaunch(defaults: defaults) { value, completion in
            sent.append(value)
            completion(nil)
        }
        XCTAssertTrue(made)
        XCTAssertEqual(sent, [InstallAttribution.installed])
        XCTAssertEqual(sent.first?.fine, 0)
        XCTAssertEqual(sent.first?.coarse, .low)
        XCTAssertTrue(defaults.bool(forKey: InstallAttribution.registeredKey))
    }

    func testLaterLaunchesDoNotResend() {
        _ = InstallAttribution.registerLaunch(defaults: defaults) { _, completion in completion(nil) }
        var calls = 0
        let made = InstallAttribution.registerLaunch(defaults: defaults) { _, _ in calls += 1 }
        XCTAssertFalse(made)
        XCTAssertEqual(calls, 0)
    }

    func testAFailedRegistrationIsRetriedNextLaunch() {
        _ = InstallAttribution.registerLaunch(defaults: defaults) { _, completion in
            completion(SKANError(.unknown))
        }
        XCTAssertFalse(defaults.bool(forKey: InstallAttribution.registeredKey))
        var calls = 0
        let made = InstallAttribution.registerLaunch(defaults: defaults) { _, completion in
            calls += 1
            completion(nil)
        }
        XCTAssertTrue(made)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(defaults.bool(forKey: InstallAttribution.registeredKey))
    }

    /// Apple accepts fine values 0…63 only; the install value must be in range.
    func testInstallValueIsWithinApplesRange() {
        XCTAssert((0...63).contains(InstallAttribution.installed.fine))
    }
}
