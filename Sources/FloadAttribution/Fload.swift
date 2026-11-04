import Foundation

/// Fload install attribution.
///
/// Call ``configure(key:options:)`` once at launch. On an app's first launch
/// the SDK reports the install to Fload with Apple's AdServices attribution
/// token, and keeps it queued on disk until Fload has it, across launches and
/// network loss. No IDFA, no App Tracking Transparency prompt.
///
/// ```swift
/// Fload.configure(key: "fload_pk_…")
/// Fload.setUserId(Purchases.shared.appUserID)   // optional
/// ```
public enum Fload {
    /// The SDK's version, sent with every install.
    public static let sdkVersion = "0.1.0"

    /// Starts the SDK. Call it once, early in launch (`application(_:didFinishLaunchingWithOptions:)`
    /// or your `App`'s `init`). It returns at once; the network work runs in the background.
    ///
    /// - Parameters:
    ///   - key: the app's public write key (`fload_pk_…`) from Fload. It names the app only.
    ///   - options: where to send and how much to log. The defaults are right for production.
    public static func configure(key: String, options: FloadOptions = FloadOptions()) {
        Runtime.shared.configure(key: key, options: options)
    }

    /// Links your app's user id (for example RevenueCat's `appUserID`) to this install.
    /// Optional. Safe to call before ``configure(key:options:)`` and on every launch:
    /// the same id is sent once.
    public static func setUserId(_ userId: String) {
        Runtime.shared.setUserId(userId)
    }

    /// This install's random reference, or nil before ``configure(key:options:)``.
    /// Useful when asking Fload support about one install.
    public static var installReference: String? {
        Runtime.shared.installReference
    }
}

/// How the SDK sends and logs.
public struct FloadOptions: Sendable {
    /// Fload's ingest endpoint. Change it only to test against your own Fload API.
    public var endpoint: URL
    /// What the SDK writes to the unified log (subsystem `com.fload.attribution`).
    public var logLevel: FloadLogLevel

    public init(
        endpoint: URL = URL(string: "https://ingest.fload.com")!,
        logLevel: FloadLogLevel = .warning
    ) {
        self.endpoint = endpoint
        self.logLevel = logLevel
    }
}

/// The SDK's log level. It never logs the write key or Apple's token.
public enum FloadLogLevel: Int, Sendable, Comparable {
    case none = 0
    case error
    case warning
    case info
    case debug

    public static func < (lhs: FloadLogLevel, rhs: FloadLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
