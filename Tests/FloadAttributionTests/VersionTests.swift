import XCTest
@testable import FloadAttribution

/// The version every install reports is the release's: `VERSION`, which CI
/// checks against the tag (`.github/workflows/ci.yml`).
final class VersionTests: XCTestCase {
    private func versionFile() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FloadAttributionTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // the package
        return try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testSdkVersionIsTheReleaseVersion() throws {
        XCTAssertEqual(Fload.sdkVersion, try versionFile())
        XCTAssertEqual(FLDAttribution.sdkVersion, try versionFile())
    }

    func testTheWireCarriesTheReleaseVersion() throws {
        let version = try versionFile()
        XCTAssertEqual(Wire.SDK().version, version)
        let request = try Wire.request(
            endpoint: URL(string: "https://ingest.fload.com")!,
            path: Wire.identifyPath,
            key: Harness.key,
            body: Wire.Identify(requestId: "request-1", installReference: "install-1", appUserId: "user_1")
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "fload-attribution-ios/\(version)")
    }
}
