import XCTest
@testable import FloadAttribution

/// Against a LOCAL Fload API only (`pnpm dev:api` in a worktree; never
/// production). Skipped unless both are set, e.g. through xcodebuild:
///
///     TEST_RUNNER_FLOAD_E2E_ENDPOINT=http://localhost:4101 \
///     TEST_RUNNER_FLOAD_E2E_KEY=fload_pk_… xcodebuild test …
///
/// The real URLSession transport and file store; only Apple's token is faked
/// (the Simulator has none). Prints the install reference so the rows can be
/// checked in the worktree's database.
final class LocalIngestE2ETests: XCTestCase {
    func testInstallThenIdentifyAgainstALocalApi() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let endpointText = env["FLOAD_E2E_ENDPOINT"], let key = env["FLOAD_E2E_KEY"],
              let endpoint = URL(string: endpointText)
        else {
            throw XCTSkip("FLOAD_E2E_ENDPOINT and FLOAD_E2E_KEY are not set")
        }
        let host = endpoint.host ?? ""
        try XCTSkipUnless(["localhost", "127.0.0.1", "::1"].contains(host), "local APIs only")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fload-e2e-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileStateStore(directory: directory)
        let transport = RecordingTransport()
        var environment = Environment.live(endpoint: endpoint, store: store, logger: SDKLogger(level: .debug))
        environment.transport = transport
        environment.tokens = FixedToken(token: "ZTJlLXRva2VuLS0" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        environment.schedulesWakeups = false

        let state = try XCTUnwrap(Bootstrap.loadOrCreate(environment: environment))
        let engine = Engine(key: key, state: state, environment: environment)
        await engine.flush()
        await engine.setUserId("e2e-user-\(UUID().uuidString.prefix(8))")
        await engine.flush()

        // A relaunch that sends the same install again: the server takes the repeat.
        var replay = state
        replay.queue = [QueuedRequest(
            requestId: state.queue[0].requestId,
            kind: .install,
            createdAt: Date(),
            nextAttemptAt: Date()
        )]
        replay.lastUserId = nil
        let repeated = Engine(key: key, state: replay, environment: environment)
        await repeated.flush()

        XCTAssertEqual(transport.statuses, [202, 202, 202])
        let done = await engine.snapshot
        XCTAssertTrue(done.queue.isEmpty)
        print("FLOAD_E2E_INSTALL_REFERENCE=\(state.installReference)")
    }
}

private struct FixedToken: AttributionTokenProvider {
    let token: String
    func token() async -> TokenResult { .token(token) }
}

private final class RecordingTransport: Transport, @unchecked Sendable {
    private let inner = URLSessionTransport()
    private let lock = NSLock()
    private var recorded: [Int] = []

    var statuses: [Int] { lock.withLock { recorded } }

    func send(_ request: URLRequest) async throws -> TransportResponse {
        let response = try await inner.send(request)
        lock.withLock { recorded.append(response.status) }
        return response
    }
}
