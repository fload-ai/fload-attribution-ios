import CryptoKit
import Foundation

/// The queue's owner: sends due requests one at a time, oldest first, and
/// keeps the queue on disk after every change.
actor Engine {
    private let key: String
    private let keyFingerprint: String
    private let environment: Environment
    private var state: StoredState
    private var flushing = false
    private var flushAgain = false
    /// The request being sent right now; it is not edited while in flight.
    private var inFlight: String?
    private var wakeTask: Task<Void, Never>?
    private var warnedKeyRefused = false

    init(key: String, state: StoredState, environment: Environment) {
        self.key = key
        keyFingerprint = Self.fingerprint(key)
        self.state = state
        self.environment = environment
    }

    var snapshot: StoredState { state }

    // MARK: User id

    func setUserId(_ raw: String) {
        guard let userId = AppUserId.validated(raw) else {
            environment.logger.warning("Fload.setUserId: the id must be 1 to 256 characters; ignored.")
            return
        }
        guard userId != state.lastUserId else { return }
        state.lastUserId = userId

        if let index = state.queue.firstIndex(where: { $0.kind == .install }),
           state.queue[index].requestId != inFlight,
           state.queue[index].appUserId == nil {
            state.queue[index].appUserId = userId
        } else {
            let now = environment.now()
            state.queue.append(QueuedRequest(
                requestId: environment.makeId(),
                kind: .identify,
                createdAt: now,
                nextAttemptAt: now,
                appUserId: userId
            ))
            trimIdentifies()
        }
        persist()
        if environment.schedulesWakeups {
            Task { await self.flush() }
        }
    }

    private func trimIdentifies() {
        var excess = state.queue.filter { $0.kind == .identify }.count - Delivery.maxQueuedIdentifies
        state.queue.removeAll { request in
            guard excess > 0, request.kind == .identify, request.requestId != inFlight else { return false }
            excess -= 1
            return true
        }
    }

    // MARK: Sending

    /// Sends every due request, in order, until one has to wait. A call made
    /// while a flush runs makes that flush go round once more.
    func flush() async {
        guard !flushing else {
            flushAgain = true
            return
        }
        flushing = true
        repeat {
            flushAgain = false
            await sendDue()
        } while flushAgain
        flushing = false
        scheduleWake()
    }

    private var revoked: Bool { state.revokedKeys.contains(keyFingerprint) }

    /// When a refused (401) key may be tried again; nil when it is not refused.
    private var refusedUntil: Date? { state.refusedKeys[keyFingerprint] }

    private func sendDue() async {
        guard !revoked else { return }
        dropExpired()
        if let refusedUntil, refusedUntil > environment.now() {
            warnKeyRefused()
            return
        }
        while let head = state.queue.first, head.nextAttemptAt <= environment.now() {
            let outcome = await attempt(head)
            guard apply(outcome, to: head.requestId) else { return }
        }
    }

    private func dropExpired() {
        let now = environment.now()
        let before = state.queue.count
        state.queue.removeAll { now.timeIntervalSince($0.createdAt) > Delivery.maxAge }
        if state.queue.count != before {
            environment.logger.warning("Fload: dropped requests older than 30 days.")
            persist()
        }
    }

    private enum Attempt {
        case sent(Outcome)
        /// Apple's token is not ready yet; try the install again later.
        case awaitingToken
    }

    private func attempt(_ request: QueuedRequest) async -> Attempt {
        inFlight = request.requestId
        defer { inFlight = nil }
        let urlRequest: URLRequest
        do {
            switch request.kind {
            case .install:
                guard let body = await installBody(for: request) else { return .awaitingToken }
                urlRequest = try Wire.request(endpoint: environment.endpoint, path: Wire.installsPath, key: key, body: body)
            case .identify:
                urlRequest = try Wire.request(
                    endpoint: environment.endpoint,
                    path: Wire.identifyPath,
                    key: key,
                    body: Wire.Identify(
                        requestId: request.requestId,
                        installReference: state.installReference,
                        appUserId: request.appUserId ?? ""
                    )
                )
            }
        } catch {
            return .sent(.dropped(status: 0))
        }
        do {
            let response = try await environment.transport.send(urlRequest)
            return .sent(Delivery.outcome(of: response))
        } catch {
            return .sent(.retry)
        }
    }

    /// The install's body with a token made now (each token lives 24 hours,
    /// so a retry asks for a fresh one). Nil while Apple's error is worth waiting out.
    private func installBody(for request: QueuedRequest) async -> Wire.Install? {
        let token = await environment.tokens.token()
        if token == .retryableFailure, request.tokenFailures < Delivery.maxTokenRetries {
            return nil
        }
        let device = state.device
        // Read the user id after the await: setUserId may have run meanwhile.
        let appUserId = state.queue.first { $0.requestId == request.requestId }?.appUserId
        return Wire.Install(
            requestId: request.requestId,
            installReference: state.installReference,
            appId: device.appId,
            appVersion: device.appVersion,
            appBuild: device.appBuild,
            osVersion: device.osVersion,
            deviceModel: device.deviceModel,
            locale: device.locale,
            firstLaunchAt: Wire.timestamp(state.firstLaunchAt),
            appleAds: Wire.appleAds(token, at: environment.now()),
            appUserId: appUserId
        )
    }

    /// Records an attempt's result. False when this round should stop.
    private func apply(_ attempt: Attempt, to requestId: String) -> Bool {
        guard let index = state.queue.firstIndex(where: { $0.requestId == requestId }) else { return true }
        let now = environment.now()
        defer { persist() }
        switch attempt {
        case .awaitingToken:
            state.queue[index].tokenFailures += 1
            state.queue[index].nextAttemptAt = now + Backoff.delay(
                afterFailures: state.queue[index].tokenFailures + 1, // 4 s, 8 s, 16 s
                jitter: environment.jitter()
            )
            return false
        case .sent(.delivered):
            environment.logger.info("Fload: \(state.queue[index].kind.rawValue) accepted.")
            state.queue.remove(at: index)
            state.refusedKeys[keyFingerprint] = nil
            return true
        case .sent(.keyRefused):
            state.refusedKeys[keyFingerprint] = now + Delivery.refusedKeyPause
            warnKeyRefused()
            return false
        case let .sent(.dropped(status)):
            environment.logger.error("Fload: the \(state.queue[index].kind.rawValue) was refused (HTTP \(status)) and dropped.")
            state.queue.remove(at: index)
            return true
        case .sent(.revoked):
            environment.logger.error("Fload: this write key was revoked (HTTP 410). The SDK stops sending with it.")
            state.revokedKeys.append(keyFingerprint)
            return false
        case let .sent(.rateLimited(after)):
            state.queue[index].nextAttemptAt = now + after
            return false
        case .sent(.retry):
            state.queue[index].failures += 1
            state.queue[index].nextAttemptAt = now + Backoff.delay(
                afterFailures: state.queue[index].failures,
                jitter: environment.jitter()
            )
            return false
        }
    }

    /// One warning a launch while Fload does not know this key.
    private func warnKeyRefused() {
        guard !warnedKeyRefused else { return }
        warnedKeyRefused = true
        environment.logger.warning("Fload: ingest key refused (HTTP 401). Check the key passed to Fload.configure; installs stay queued and the key is tried again every 24 hours.")
    }

    private func persist() {
        do {
            try environment.store.save(state)
        } catch {
            environment.logger.error("Fload: could not save its queue; it is kept in memory for this launch.")
        }
    }

    // MARK: Wake-ups

    /// While the app runs, sleeps until the head request is due and flushes then.
    private func scheduleWake() {
        wakeTask?.cancel()
        wakeTask = nil
        guard environment.schedulesWakeups, !revoked, let head = state.queue.first else { return }
        let due = max(head.nextAttemptAt, refusedUntil ?? .distantPast)
        let delay = max(0, due.timeIntervalSince(environment.now()))
        wakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    static func fingerprint(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
