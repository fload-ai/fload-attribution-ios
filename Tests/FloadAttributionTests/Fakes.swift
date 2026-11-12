import Foundation
@testable import FloadAttribution

final class FakeTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var scripted: [Result<TransportResponse, Error>] = []
    private var sent: [URLRequest] = []

    /// Answers in order; once they run out, every request gets 202.
    func script(_ answers: Result<TransportResponse, Error>...) {
        lock.withLock { scripted.append(contentsOf: answers) }
    }

    func script(status: Int, retryAfter: String? = nil) {
        script(.success(TransportResponse(status: status, retryAfter: retryAfter)))
    }

    var requests: [URLRequest] { lock.withLock { sent } }

    var bodies: [[String: Any]] {
        requests.map { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        }
    }

    var paths: [String] { requests.map { $0.url?.path ?? "" } }

    func send(_ request: URLRequest) async throws -> TransportResponse {
        let answer: Result<TransportResponse, Error> = lock.withLock {
            sent.append(request)
            return scripted.isEmpty ? .success(TransportResponse(status: 202)) : scripted.removeFirst()
        }
        return try answer.get()
    }
}

final class FakeTokens: AttributionTokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [TokenResult]
    private var calls = 0
    private var fallback: TokenResult

    init(_ results: TokenResult...) {
        self.results = results
        fallback = results.last ?? .token("dG9rZW4=")
    }

    var callCount: Int { lock.withLock { calls } }

    func token() async -> TokenResult {
        lock.withLock {
            calls += 1
            return results.isEmpty ? fallback : results.removeFirst()
        }
    }
}

final class MemoryStore: StateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: StoredState?
    var result: LoadResult?
    var failSaves = false

    var state: StoredState? { lock.withLock { stored } }

    func load() -> LoadResult {
        lock.withLock {
            if let result { return result }
            return stored.map(LoadResult.loaded) ?? .missing
        }
    }

    func save(_ state: StoredState) throws {
        try lock.withLock {
            if failSaves { throw CocoaError(.fileWriteUnknown) }
            stored = state
        }
    }
}

final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

struct DeviceFixture {
    static let facts = DeviceFacts(
        appId: "com.example.app",
        appVersion: "1.2.3",
        appBuild: "45",
        osVersion: "18.1",
        deviceModel: "iPhone16,2",
        locale: "en_US"
    )
}

/// One app's SDK, with every outside dependency faked.
final class Harness {
    static let key = "fload_pk_test_0123456789"

    let transport = FakeTransport()
    let tokens: FakeTokens
    let store: MemoryStore
    let clock = ManualClock()
    let ids = Counter()
    var jitter = 1.0
    var wrapper: FloadWrapper?
    var device = DeviceFixture.facts

    init(tokens: FakeTokens = FakeTokens(.token("dG9rZW4=")), store: MemoryStore = MemoryStore()) {
        self.tokens = tokens
        self.store = store
    }

    var environment: Environment {
        let clock = clock
        let ids = ids
        let jitter = jitter
        let device = device
        return Environment(
            endpoint: URL(string: "https://ingest.example.test")!,
            transport: transport,
            tokens: tokens,
            store: store,
            device: { device },
            now: { clock.now },
            jitter: { jitter },
            makeId: { "id-\(String(format: "%08d", ids.next()))" },
            logger: SDKLogger(level: .none),
            schedulesWakeups: false,
            sdk: Wire.SDK(wrapper: wrapper)
        )
    }

    /// A launch: loads the stored state (or starts the install) and builds the engine.
    func launch(key: String = Harness.key) -> Engine? {
        guard let state = Bootstrap.loadOrCreate(environment: environment) else { return nil }
        return Engine(key: key, state: state, environment: environment)
    }
}
