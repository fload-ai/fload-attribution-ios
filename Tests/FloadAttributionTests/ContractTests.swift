import XCTest
@testable import FloadAttribution

/// The wire contract as the server states it
/// (`packages/shared-types/src/contracts/attribution-ingest.ts`), checked on
/// what the SDK builds.
final class ContractTests: XCTestCase {
    private static let installKeys: Set<String> = [
        "requestId", "installReference", "platform", "appId", "appVersion", "appBuild",
        "osVersion", "deviceModel", "locale", "sdk", "firstLaunchAt", "appleAds",
        "playReferrer", "appUserId",
    ]
    private static let phoneId = try! NSRegularExpression(pattern: "^[A-Za-z0-9._:-]{8,128}$")

    private func matchesPhoneId(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }
        return Self.phoneId.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    func testLiveIdsAreValidPhoneIds() {
        let id = Environment.live(
            endpoint: URL(string: "https://ingest.fload.com")!,
            store: MemoryStore(),
            logger: SDKLogger(level: .none)
        ).makeId()
        XCTAssertTrue(matchesPhoneId(id), id)
    }

    func testInstallWithTheLongestTokenFitsTheBodyLimit() throws {
        let token = String(repeating: "A", count: AppleToken.maxLength)
        let install = Wire.Install(
            requestId: UUID().uuidString.lowercased(),
            installReference: UUID().uuidString.lowercased(),
            appId: String(repeating: "a", count: 256),
            appVersion: String(repeating: "v", count: 64),
            appBuild: String(repeating: "b", count: 64),
            osVersion: String(repeating: "o", count: 64),
            deviceModel: String(repeating: "d", count: 64),
            locale: String(repeating: "l", count: 64),
            firstLaunchAt: Wire.timestamp(Date()),
            appleAds: Wire.appleAds(.token(token), at: Date()),
            appUserId: String(repeating: "u", count: 256)
        )
        let request = try Wire.request(
            endpoint: URL(string: "https://ingest.fload.com")!,
            path: Wire.installsPath,
            key: Harness.key,
            body: install
        )
        XCTAssertLessThan(request.httpBody?.count ?? .max, 8 * 1024, "the install route's body limit")
        XCTAssertEqual(request.url?.absoluteString, "https://ingest.fload.com/attribution/v1/installs")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertTrue(Set(json.keys).isSubset(of: Self.installKeys))
        XCTAssertTrue(matchesPhoneId(json["requestId"]))
        XCTAssertTrue(matchesPhoneId(json["installReference"]))
    }

    func testEndpointWithAPathAndTrailingSlash() throws {
        let request = try Wire.request(
            endpoint: URL(string: "http://localhost:4101/")!,
            path: Wire.identifyPath,
            key: Harness.key,
            body: Wire.Identify(requestId: "req-00000001", installReference: "ins-00000001", appUserId: "u")
        )
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:4101/attribution/v1/identify")
    }

    func testTokenIsSentExactlyWhenStatusIsToken() {
        let now = Date()
        XCTAssertNotNil(Wire.appleAds(.token("YQ=="), at: now).token)
        for result in [TokenResult.unsupported, .failure, .retryableFailure] {
            let ads = Wire.appleAds(result, at: now)
            XCTAssertNil(ads.token)
            XCTAssertNil(ads.tokenCreatedAt)
            XCTAssertTrue(["unsupported_os", "token_error"].contains(ads.status))
        }
    }

    func testTimestampsAreIsoWithOffset() {
        XCTAssertEqual(Wire.timestamp(Date(timeIntervalSince1970: 0.25)), "1970-01-01T00:00:00.250Z")
    }

    func testAppleTokenValidation() {
        XCTAssertEqual(AppleToken.validated(" abc+/=_-\n"), .token("abc+/=_-"))
        XCTAssertEqual(AppleToken.validated(""), .failure)
        XCTAssertEqual(AppleToken.validated("has space"), .failure)
        XCTAssertEqual(AppleToken.validated(String(repeating: "A", count: 4097)), .failure)
    }

    func testWriteKeyShape() {
        XCTAssertTrue(WriteKey.isWellFormed("fload_pk_abc"))
        XCTAssertFalse(WriteKey.isWellFormed("fload_pk_"))
        XCTAssertFalse(WriteKey.isWellFormed("fload_sk_abc"))
        XCTAssertFalse(WriteKey.isWellFormed("fload_pk_" + String(repeating: "a", count: 120)))
    }

    func testStatusesMapToTheContractsActions() {
        XCTAssertEqual(Delivery.outcome(of: .init(status: 202)), .delivered)
        XCTAssertEqual(Delivery.outcome(of: .init(status: 200)), .delivered)
        XCTAssertEqual(Delivery.outcome(of: .init(status: 400)), .dropped(status: 400))
        XCTAssertEqual(Delivery.outcome(of: .init(status: 401)), .keyRefused)
        XCTAssertEqual(Delivery.outcome(of: .init(status: 413)), .dropped(status: 413))
        XCTAssertEqual(Delivery.outcome(of: .init(status: 410)), .revoked)
        XCTAssertEqual(Delivery.outcome(of: .init(status: 429, retryAfter: "12")), .rateLimited(after: 12))
        for status in [404, 408, 500, 502, 503, 504] {
            XCTAssertEqual(Delivery.outcome(of: .init(status: status)), .retry, "HTTP \(status)")
        }
    }

    func testRetryAfterBounds() {
        XCTAssertEqual(Delivery.retryAfter(nil), 60)
        XCTAssertEqual(Delivery.retryAfter("Wed, 21 Oct 2026 07:28:00 GMT"), 60)
        XCTAssertEqual(Delivery.retryAfter("0"), 1)
        XCTAssertEqual(Delivery.retryAfter("99999"), 3600)
    }

    func testBackoffDoublesToItsCapWithJitter() {
        XCTAssertEqual(Backoff.delay(afterFailures: 1, jitter: 1), 2)
        XCTAssertEqual(Backoff.delay(afterFailures: 5, jitter: 1), 32)
        XCTAssertEqual(Backoff.delay(afterFailures: 5, jitter: 0.5), 16)
        XCTAssertEqual(Backoff.delay(afterFailures: 40, jitter: 1), 6 * 3600)
        XCTAssertEqual(Backoff.delay(afterFailures: 1, jitter: 7), 2, "jitter is clamped")
    }

    func testDeviceTextIsTrimmedAndCut() {
        XCTAssertNil(DeviceInfo.shortText("  "))
        XCTAssertEqual(DeviceInfo.shortText(" 1.0 "), "1.0")
        let long = DeviceInfo.shortText(String(repeating: "é", count: 40) + String(repeating: "👍", count: 40))
        XCTAssertEqual(long?.utf16.count, 64)
        XCTAssertEqual(DeviceInfo.appId(nil), "unknown")
    }

    func testCurrentDeviceFactsFitTheContract() {
        let facts = DeviceInfo.current()
        XCTAssertFalse(facts.appId.isEmpty)
        for value in [facts.appVersion, facts.appBuild, facts.osVersion, facts.deviceModel, facts.locale] {
            XCTAssertLessThanOrEqual(value?.utf16.count ?? 0, 64)
        }
        XCTAssertNotNil(facts.osVersion)
        XCTAssertNotNil(facts.deviceModel)
    }
}
