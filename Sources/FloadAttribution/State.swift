import Foundation

/// What the SDK keeps on disk: the install's identity and the requests Fload
/// has not accepted yet.
struct StoredState: Codable, Equatable, Sendable {
    var version = 1
    /// Random, made on the first launch with the SDK; names this install to Fload.
    var installReference: String
    var firstLaunchAt: Date
    var device: DeviceFacts
    /// Unsent requests, oldest first. Sent in this order, one at a time.
    var queue: [QueuedRequest]
    /// The last user id handed over for sending, so a repeat sends nothing.
    var lastUserId: String?
    /// SHA-256 of each write key Fload answered 410 (revoked) for.
    var revokedKeys: [String] = []
    /// SHA-256 of each write key Fload answered 401 (unknown) for, and when
    /// to try it again.
    var refusedKeys: [String: Date] = [:]
}

extension StoredState {
    /// Fields added after the first version are optional on disk, so a
    /// newer SDK reads the state an older one wrote.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        installReference = try container.decode(String.self, forKey: .installReference)
        firstLaunchAt = try container.decode(Date.self, forKey: .firstLaunchAt)
        device = try container.decode(DeviceFacts.self, forKey: .device)
        queue = try container.decode([QueuedRequest].self, forKey: .queue)
        lastUserId = try container.decodeIfPresent(String.self, forKey: .lastUserId)
        revokedKeys = try container.decodeIfPresent([String].self, forKey: .revokedKeys) ?? []
        refusedKeys = try container.decodeIfPresent([String: Date].self, forKey: .refusedKeys) ?? [:]
    }
}

/// The app and device as they were on the install's first launch.
struct DeviceFacts: Codable, Equatable, Sendable {
    var appId: String
    var appVersion: String?
    var appBuild: String?
    var osVersion: String?
    var deviceModel: String?
    var locale: String?
}

struct QueuedRequest: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case install
        case identify
    }

    /// Sent unchanged on every retry.
    var requestId: String
    var kind: Kind
    var createdAt: Date
    /// Failed attempts in a row that count toward the backoff.
    var failures = 0
    var nextAttemptAt: Date
    var appUserId: String?
    /// Times Apple's token could not be made yet (install only).
    var tokenFailures = 0
}

/// Loads the stored state, or starts a new install when there is none.
enum Bootstrap {
    /// Nil when the storage exists but cannot be read yet (a locked device
    /// before its first unlock): starting a new install then would count
    /// this one twice, so the SDK sits this launch out.
    static func loadOrCreate(environment: Environment) -> StoredState? {
        let logger = environment.logger
        switch environment.store.load() {
        case let .loaded(state):
            return state
        case .unreadable:
            return nil
        case .corrupt:
            logger.warning("Fload: its stored state was unreadable and was reset.")
            return newInstall(environment: environment)
        case .missing:
            return newInstall(environment: environment)
        }
    }

    private static func newInstall(environment: Environment) -> StoredState {
        let now = environment.now()
        let state = StoredState(
            installReference: environment.makeId(),
            firstLaunchAt: now,
            device: environment.device(),
            queue: [
                QueuedRequest(
                    requestId: environment.makeId(),
                    kind: .install,
                    createdAt: now,
                    nextAttemptAt: now
                ),
            ]
        )
        do {
            try environment.store.save(state)
        } catch {
            environment.logger.error("Fload: could not save the new install; it will be sent this launch only.")
        }
        environment.logger.info("Fload: new install.")
        return state
    }
}
