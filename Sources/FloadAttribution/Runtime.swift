import Foundation

/// The one SDK instance behind ``Fload``'s static calls: builds the engine on
/// the first `configure`, and holds a user id set before it.
final class Runtime: @unchecked Sendable {
    static let shared = Runtime()

    private enum Start {
        case started(Engine, bufferedUserId: String?)
        case alreadyConfigured
        case unavailable
    }

    private let lock = NSLock()
    private var engine: Engine?
    private var triggers: FlushTriggers?
    private var reference: String?
    private var bufferedUserId: String?

    var installReference: String? {
        lock.withLock { reference }
    }

    func configure(key: String, options: FloadOptions) {
        let logger = SDKLogger(level: options.logLevel)
        guard WriteKey.isWellFormed(key) else {
            logger.error("Fload.configure: the key must be a write key (fload_pk_…). Attribution is off.")
            return
        }
        switch start(key: key, options: options, logger: logger) {
        case .alreadyConfigured:
            logger.warning("Fload.configure was called more than once; the first call stands.")
        case .unavailable:
            logger.error("Fload: its storage cannot be read yet. Attribution is off for this launch.")
        case let .started(made, bufferedUserId):
            let flushTriggers = FlushTriggers { await made.flush() }
            lock.withLock { triggers = flushTriggers }
            Task {
                if let bufferedUserId { await made.setUserId(bufferedUserId) }
                await made.flush()
            }
        }
    }

    func setUserId(_ userId: String) {
        let current: Engine? = lock.withLock {
            if engine == nil { bufferedUserId = userId }
            return engine
        }
        guard let current else { return }
        Task { await current.setUserId(userId) }
    }

    private func start(key: String, options: FloadOptions, logger: SDKLogger) -> Start {
        lock.withLock {
            guard engine == nil else { return .alreadyConfigured }
            guard let store = try? FileStateStore.inApplicationSupport() else { return .unavailable }
            let environment = Environment.live(endpoint: options.endpoint, store: store, logger: logger)
            guard let state = Bootstrap.loadOrCreate(environment: environment) else { return .unavailable }
            let made = Engine(key: key, state: state, environment: environment)
            engine = made
            reference = state.installReference
            defer { bufferedUserId = nil }
            return .started(made, bufferedUserId: bufferedUserId)
        }
    }
}

enum WriteKey {
    static let prefix = "fload_pk_"
    static let header = "X-Fload-Write-Key"

    /// What the server's `appWriteKey` policy accepts: the prefix, at most 128 characters.
    static func isWellFormed(_ key: String) -> Bool {
        let length = key.utf16.count
        return key.hasPrefix(prefix) && length > prefix.utf16.count && length <= 128
    }
}
