import Foundation

/// What to do with a request after one attempt.
enum Outcome: Equatable, Sendable {
    /// 2xx: Fload has it (a repeat included). Delete it.
    case delivered
    /// Fload will never take it (400, 413). Delete it.
    case dropped(status: Int)
    /// 401: the key is unknown to Fload. Keep the queue (a wrong key in one
    /// build must not lose its installs) and pause this key for a day.
    case keyRefused
    /// 410: the key was revoked. Stop sending with it, for good.
    case revoked
    /// 429: wait what the server asked, then go on.
    case rateLimited(after: TimeInterval)
    /// 5xx, an unexpected status, or no answer: back off and retry.
    case retry
}

enum Delivery {
    /// A request older than this is dropped unsent. Apple's token lives 24
    /// hours, but the install itself is still worth counting late.
    static let maxAge: TimeInterval = 30 * 24 * 3600
    /// The most identifies kept; the server keeps 10 user ids per install.
    static let maxQueuedIdentifies = 20
    /// Times Apple's token is asked for again before the install goes without it.
    static let maxTokenRetries = 3
    /// How long a refused (401) key waits before it is tried again.
    static let refusedKeyPause: TimeInterval = 24 * 3600

    static func outcome(of response: TransportResponse) -> Outcome {
        switch response.status {
        case 200..<300:
            return .delivered
        case 400, 413:
            return .dropped(status: response.status)
        case 401:
            return .keyRefused
        case 410:
            return .revoked
        case 429:
            return .rateLimited(after: retryAfter(response.retryAfter))
        default:
            return .retry
        }
    }

    /// `Retry-After` in seconds, between 1 s and 1 h; a minute when absent or a date.
    static func retryAfter(_ header: String?) -> TimeInterval {
        guard let header, let seconds = Int(header.trimmingCharacters(in: .whitespaces)) else {
            return 60
        }
        return TimeInterval(min(max(seconds, 1), 3600))
    }
}

/// Exponential backoff: 2 s after the first failure, doubling, at most 6 h,
/// each delay scaled by a jitter factor in [0.5, 1] so phones that went
/// offline together do not come back together.
enum Backoff {
    static let base: TimeInterval = 2
    static let cap: TimeInterval = 6 * 3600

    static func delay(afterFailures failures: Int, jitter: Double) -> TimeInterval {
        let exponent = Double(min(max(failures, 1), 32) - 1)
        let raw = min(cap, base * pow(2, exponent))
        return raw * min(max(jitter, 0.5), 1)
    }
}
