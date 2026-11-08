import ObjectiveC
import XCTest
@testable import FloadAttribution

/// The Objective-C names are a public contract: .NET, Unity, React Native and
/// Kotlin/Native bridges call them by name.
final class ObjectiveCTests: XCTestCase {
    func testTheClassAndSelectorsKeepTheirNames() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString("FLDAttribution"))
        for selector in [
            "sdkVersion",
            "configureWithKey:",
            "configureWithKey:endpoint:logLevel:",
            "setUserId:",
            "installReference",
        ] {
            XCTAssertNotNil(class_getClassMethod(cls, NSSelectorFromString(selector)), selector)
        }
    }

    func testLogLevelsMatchTheSwiftOnes() {
        let pairs: [(FLDLogLevel, FloadLogLevel, Int)] = [
            (.none, .none, 0), (.error, .error, 1), (.warning, .warning, 2), (.info, .info, 3), (.debug, .debug, 4),
        ]
        for (objc, swift, raw) in pairs {
            XCTAssertEqual(objc.rawValue, raw)
            XCTAssertEqual(FLDAttribution.options(endpoint: nil, logLevel: objc).logLevel, swift)
        }
    }

    func testEndpointFallsBackToProduction() {
        XCTAssertEqual(FLDAttribution.options(endpoint: nil, logLevel: .warning).endpoint, FloadOptions().endpoint)
        XCTAssertEqual(FLDAttribution.options(endpoint: "not a url", logLevel: .warning).endpoint, FloadOptions().endpoint)
        XCTAssertEqual(FLDAttribution.options(endpoint: "/relative", logLevel: .warning).endpoint, FloadOptions().endpoint)
        XCTAssertEqual(
            FLDAttribution.options(endpoint: "http://localhost:3901", logLevel: .debug).endpoint,
            URL(string: "http://localhost:3901")
        )
    }

    func testObjectiveCCallersNameTheirWrapper() {
        let options = FLDAttribution.options(endpoint: nil, logLevel: .warning, wrapperName: "react-native", wrapperVersion: "1.2.0")
        XCTAssertEqual(options.wrapper, FloadWrapper(name: "react-native", version: "1.2.0"))
        XCTAssertNil(FLDAttribution.options(endpoint: nil, logLevel: .warning).wrapper)
        XCTAssertNil(FLDAttribution.options(endpoint: nil, logLevel: .warning, wrapperName: "unity", wrapperVersion: nil).wrapper)
        XCTAssertNotNil(NSClassFromString("FLDAttribution").flatMap { cls in
            (cls as AnyObject).responds(to: NSSelectorFromString("configureWithKey:endpoint:logLevel:wrapperName:wrapperVersion:")) ? cls : nil
        })
    }
}
