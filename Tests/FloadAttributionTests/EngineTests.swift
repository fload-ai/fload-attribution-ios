import XCTest
@testable import FloadAttribution

final class EngineTests: XCTestCase {
    // MARK: The first launch

    func testFirstLaunchSendsTheInstallOnceAcrossLaunches() async throws {
        let harness = Harness()
        let first = try XCTUnwrap(harness.launch())
        await first.flush()

        XCTAssertEqual(harness.transport.paths, ["/attribution/v1/installs"])
        let request = try XCTUnwrap(harness.transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fload-Write-Key"), Harness.key)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let afterFirst = await first.snapshot
        XCTAssertTrue(afterFirst.queue.isEmpty)

        let second = try XCTUnwrap(harness.launch())
        await second.flush()
        XCTAssertEqual(harness.transport.requests.count, 1, "a relaunch sends nothing again")
        let afterSecond = await second.snapshot
        XCTAssertEqual(afterSecond.installReference, afterFirst.installReference)
    }

    func testInstallBodyCarriesTheTokenAndTheFirstLaunchFacts() async throws {
        let harness = Harness()
        let engine = try XCTUnwrap(harness.launch())
        harness.clock.advance(5)
        await engine.flush()

        let body = try XCTUnwrap(harness.transport.bodies.first)
        let state = await engine.snapshot
        XCTAssertEqual(body["installReference"] as? String, state.installReference)
        XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertEqual(body["appId"] as? String, "com.example.app")
        XCTAssertEqual(body["appVersion"] as? String, "1.2.3")
        XCTAssertEqual(body["appBuild"] as? String, "45")
        XCTAssertEqual(body["osVersion"] as? String, "18.1")
        XCTAssertEqual(body["deviceModel"] as? String, "iPhone16,2")
        XCTAssertEqual(body["locale"] as? String, "en_US")
        XCTAssertEqual(body["firstLaunchAt"] as? String, "2027-01-15T08:00:00.000Z")
        XCTAssertEqual(body["sdk"] as? [String: String], ["name": "fload-attribution-ios", "version": Fload.sdkVersion])
        XCTAssertEqual(body["appleAds"] as? [String: String], [
            "status": "token",
            "token": "dG9rZW4=",
            "tokenCreatedAt": "2027-01-15T08:00:05.000Z",
        ])
        XCTAssertNil(body["appUserId"])
        XCTAssertNil(body["playReferrer"])
    }

    // MARK: Apple's token

    func testUnsupportedPlatformIsSentAsUnsupportedOs() async throws {
        let harness = Harness(tokens: FakeTokens(.unsupported))
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        let ads = harness.transport.bodies.first?["appleAds"] as? [String: String]
        XCTAssertEqual(ads, ["status": "unsupported_os"])
    }

    func testTokenErrorIsSentWithoutAToken() async throws {
        let harness = Harness(tokens: FakeTokens(.failure))
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        let ads = harness.transport.bodies.first?["appleAds"] as? [String: String]
        XCTAssertEqual(ads, ["status": "token_error"])
    }

    func testRetryableTokenFailureWaitsThenSendsTokenErrorAfterThreeTries() async throws {
        let harness = Harness(tokens: FakeTokens(.retryableFailure))
        let engine = try XCTUnwrap(harness.launch())

        for expectedWait in [4.0, 8.0, 16.0] {
            await engine.flush()
            XCTAssertTrue(harness.transport.requests.isEmpty)
            harness.clock.advance(expectedWait - 0.5)
            await engine.flush()
            XCTAssertTrue(harness.transport.requests.isEmpty, "not before \(expectedWait) s")
            harness.clock.advance(0.5)
        }
        await engine.flush()
        XCTAssertEqual(harness.tokens.callCount, 4)
        let ads = harness.transport.bodies.first?["appleAds"] as? [String: String]
        XCTAssertEqual(ads, ["status": "token_error"])
    }

    func testRetryableTokenFailureThatRecoversSendsTheToken() async throws {
        let harness = Harness(tokens: FakeTokens(.retryableFailure, .token("bGF0ZXI=")))
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        harness.clock.advance(4)
        await engine.flush()
        let ads = harness.transport.bodies.first?["appleAds"] as? [String: String]
        XCTAssertEqual(ads?["token"], "bGF0ZXI=")
    }

    func testEachRetryAsksAppleForAFreshToken() async throws {
        let harness = Harness(tokens: FakeTokens(.token("Zmlyc3Q="), .token("c2Vjb25k")))
        harness.transport.script(status: 503)
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        harness.clock.advance(2)
        await engine.flush()

        let tokens = harness.transport.bodies.map { ($0["appleAds"] as? [String: String])?["token"] }
        XCTAssertEqual(tokens, ["Zmlyc3Q=", "c2Vjb25k"])
        let requestIds = harness.transport.bodies.map { $0["requestId"] as? String }
        XCTAssertEqual(Set(requestIds).count, 1, "a retry keeps its request id")
    }

    // MARK: Statuses

    func testServerErrorBacksOffExponentiallyAndKeepsTheIds() async throws {
        let harness = Harness()
        harness.transport.script(status: 500)
        harness.transport.script(status: 502)
        harness.transport.script(.failure(URLError(.notConnectedToInternet)))
        let engine = try XCTUnwrap(harness.launch())

        await engine.flush() // 500: wait 2 s
        harness.clock.advance(1.9)
        await engine.flush()
        XCTAssertEqual(harness.transport.requests.count, 1)
        harness.clock.advance(0.1)
        await engine.flush() // 502: wait 4 s
        harness.clock.advance(4)
        await engine.flush() // offline: wait 8 s
        let waiting = await engine.snapshot
        XCTAssertEqual(waiting.queue.first?.failures, 3)
        XCTAssertEqual(waiting.queue.first?.nextAttemptAt, harness.clock.now + 8)
        harness.clock.advance(8)
        await engine.flush() // 202

        XCTAssertEqual(harness.transport.requests.count, 4)
        let done = await engine.snapshot
        XCTAssertTrue(done.queue.isEmpty)
        let ids = harness.transport.bodies.map { "\($0["requestId"] ?? "")|\($0["installReference"] ?? "")" }
        XCTAssertEqual(Set(ids).count, 1)
    }

    func testRateLimitWaitsRetryAfter() async throws {
        let harness = Harness()
        harness.transport.script(status: 429, retryAfter: "30")
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        harness.clock.advance(29)
        await engine.flush()
        XCTAssertEqual(harness.transport.requests.count, 1)
        harness.clock.advance(1)
        await engine.flush()
        XCTAssertEqual(harness.transport.requests.count, 2)
        let state = await engine.snapshot
        XCTAssertTrue(state.queue.isEmpty)
    }

    func testRefusedRequestsAreDropped() async throws {
        for status in [400, 401, 413] {
            let harness = Harness()
            harness.transport.script(status: status)
            let engine = try XCTUnwrap(harness.launch())
            await engine.flush()
            let state = await engine.snapshot
            XCTAssertTrue(state.queue.isEmpty, "HTTP \(status) drops the request")
        }
    }

    func testRevokedKeyStopsForGoodUntilANewKey() async throws {
        let harness = Harness()
        harness.transport.script(status: 410)
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        harness.clock.advance(7 * 24 * 3600)
        await engine.flush()
        await engine.setUserId("user-1")
        await engine.flush()
        XCTAssertEqual(harness.transport.requests.count, 1)

        let relaunched = try XCTUnwrap(harness.launch())
        await relaunched.flush()
        XCTAssertEqual(harness.transport.requests.count, 1, "the revoked key stays stopped after a relaunch")

        let newKey = try XCTUnwrap(harness.launch(key: "fload_pk_rotated_9876543210"))
        await newKey.flush()
        XCTAssertEqual(harness.transport.paths, ["/attribution/v1/installs", "/attribution/v1/installs"])
        XCTAssertEqual(harness.transport.bodies.last?["appUserId"] as? String, "user-1")
        XCTAssertEqual(harness.transport.requests.last?.value(forHTTPHeaderField: "X-Fload-Write-Key"), "fload_pk_rotated_9876543210")
    }

    func testRequestsOlderThanThirtyDaysAreDropped() async throws {
        let harness = Harness()
        harness.transport.script(status: 503)
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        harness.clock.advance(30 * 24 * 3600 + 1)
        await engine.flush()
        XCTAssertEqual(harness.transport.requests.count, 1)
        let state = await engine.snapshot
        XCTAssertTrue(state.queue.isEmpty)
    }

    func testAFailedRequestHoldsBackTheOnesBehindIt() async throws {
        let harness = Harness()
        harness.transport.script(status: 503)
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        await engine.setUserId("anonymous") // rides in the install
        await engine.setUserId("signed-in") // an identify, due now
        await engine.flush()
        XCTAssertEqual(harness.transport.paths, ["/attribution/v1/installs"], "the identify waits for the install")
    }

    // MARK: User id

    func testUserIdSetBeforeTheInstallGoesInsideIt() async throws {
        let harness = Harness()
        let engine = try XCTUnwrap(harness.launch())
        await engine.setUserId("  $RCAnonymousID:abc  ")
        await engine.flush()
        XCTAssertEqual(harness.transport.paths, ["/attribution/v1/installs"])
        XCTAssertEqual(harness.transport.bodies.first?["appUserId"] as? String, "$RCAnonymousID:abc")
    }

    func testUserIdAfterTheInstallIsAnIdentify() async throws {
        let harness = Harness()
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        await engine.setUserId("user-1")
        await engine.setUserId("user-1")
        await engine.flush()

        XCTAssertEqual(harness.transport.paths, ["/attribution/v1/installs", "/attribution/v1/identify"])
        let identify = try XCTUnwrap(harness.transport.bodies.last)
        let state = await engine.snapshot
        XCTAssertEqual(Set(identify.keys), ["requestId", "installReference", "platform", "appUserId"])
        XCTAssertEqual(identify["installReference"] as? String, state.installReference)
        XCTAssertEqual(identify["platform"] as? String, "ios")
        XCTAssertEqual(identify["appUserId"] as? String, "user-1")
    }

    func testTheSameUserIdOnALaterLaunchSendsNothing() async throws {
        let harness = Harness()
        let first = try XCTUnwrap(harness.launch())
        await first.setUserId("user-1")
        await first.flush()
        let second = try XCTUnwrap(harness.launch())
        await second.setUserId("user-1")
        await second.flush()
        XCTAssertEqual(harness.transport.requests.count, 1)
    }

    func testASecondUserIdBeforeTheInstallIsAnIdentify() async throws {
        let harness = Harness()
        let engine = try XCTUnwrap(harness.launch())
        await engine.setUserId("anonymous")
        await engine.setUserId("signed-in")
        await engine.flush()
        XCTAssertEqual(harness.transport.paths, ["/attribution/v1/installs", "/attribution/v1/identify"])
        XCTAssertEqual(harness.transport.bodies.first?["appUserId"] as? String, "anonymous")
        XCTAssertEqual(harness.transport.bodies.last?["appUserId"] as? String, "signed-in")
    }

    func testInvalidUserIdsAreIgnored() async throws {
        let harness = Harness()
        let engine = try XCTUnwrap(harness.launch())
        await engine.setUserId("   ")
        await engine.setUserId(String(repeating: "x", count: 257))
        await engine.flush()
        XCTAssertNil(harness.transport.bodies.first?["appUserId"])
        XCTAssertEqual(harness.transport.requests.count, 1)
    }

    func testQueuedIdentifiesAreCapped() async throws {
        let harness = Harness()
        harness.transport.script(status: 503)
        let engine = try XCTUnwrap(harness.launch())
        await engine.setUserId("first")
        for index in 0..<30 {
            await engine.setUserId("user-\(index)")
        }
        let state = await engine.snapshot
        let identifies = state.queue.filter { $0.kind == .identify }
        XCTAssertEqual(identifies.count, Delivery.maxQueuedIdentifies)
        XCTAssertEqual(identifies.last?.appUserId, "user-29", "the newest are kept")
    }

    // MARK: Storage

    func testUnreadableStorageSitsTheLaunchOut() {
        let store = MemoryStore()
        store.result = .unreadable
        let harness = Harness(store: store)
        XCTAssertNil(harness.launch())
        XCTAssertNil(store.state, "no new install is written over an unreadable one")
    }

    func testCorruptStorageStartsAFreshInstall() async throws {
        let store = MemoryStore()
        store.result = .corrupt
        let harness = Harness(store: store)
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        XCTAssertEqual(harness.transport.paths, ["/attribution/v1/installs"])
    }

    func testAFailingSaveStillSendsThisLaunch() async throws {
        let store = MemoryStore()
        store.failSaves = true
        let harness = Harness(store: store)
        let engine = try XCTUnwrap(harness.launch())
        await engine.flush()
        XCTAssertEqual(harness.transport.requests.count, 1)
    }

    func testTheQueueSurvivesARelaunch() async throws {
        let harness = Harness()
        harness.transport.script(status: 503)
        let first = try XCTUnwrap(harness.launch())
        await first.flush()
        await first.setUserId("user-1")
        let pending = await first.snapshot

        harness.clock.advance(60)
        let second = try XCTUnwrap(harness.launch())
        let restored = await second.snapshot
        XCTAssertEqual(restored, pending)
        await second.flush()
        XCTAssertEqual(harness.transport.paths, ["/attribution/v1/installs", "/attribution/v1/installs"])
        XCTAssertEqual(harness.transport.bodies.last?["appUserId"] as? String, "user-1")
        let done = await second.snapshot
        XCTAssertTrue(done.queue.isEmpty)
    }
}
