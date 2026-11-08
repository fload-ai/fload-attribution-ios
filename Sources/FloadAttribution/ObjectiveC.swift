import Foundation

/// The SDK's log level for Objective-C callers (`FLDLogLevelNone` … `FLDLogLevelDebug`).
/// The raw values are ``FloadLogLevel``'s.
@objc(FLDLogLevel)
public enum FLDLogLevel: Int {
    case none = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4
}

/// ``Fload`` for Objective-C, and for every bridge that only sees the
/// Objective-C runtime (.NET bindings, Unity `.mm` plugins, React Native,
/// Kotlin/Native cinterop). Each call forwards to ``Fload`` unchanged.
///
/// ```objc
/// @import FloadAttribution;
/// [FLDAttribution configureWithKey:@"fload_pk_…"];
/// [FLDAttribution setUserId:appUserId];
/// ```
@objc(FLDAttribution)
public final class FLDAttribution: NSObject {
    /// ``Fload/sdkVersion``.
    @objc public static var sdkVersion: String { Fload.sdkVersion }

    /// ``Fload/configure(key:options:)`` with the default endpoint and log level.
    @objc(configureWithKey:)
    public static func configure(key: String) {
        Fload.configure(key: key)
    }

    /// ``Fload/configure(key:options:)``. A nil endpoint, or one that is not an
    /// absolute URL, keeps Fload's production endpoint.
    @objc(configureWithKey:endpoint:logLevel:)
    public static func configure(key: String, endpoint: String?, logLevel: FLDLogLevel) {
        Fload.configure(key: key, options: options(endpoint: endpoint, logLevel: logLevel))
    }

    /// ``Fload/configure(key:options:)`` for a cross-platform wrapper, which
    /// names itself (``FloadWrapper``). A nil or blank name or version sends
    /// no wrapper.
    @objc(configureWithKey:endpoint:logLevel:wrapperName:wrapperVersion:)
    public static func configure(
        key: String,
        endpoint: String?,
        logLevel: FLDLogLevel,
        wrapperName: String?,
        wrapperVersion: String?
    ) {
        Fload.configure(key: key, options: options(
            endpoint: endpoint,
            logLevel: logLevel,
            wrapperName: wrapperName,
            wrapperVersion: wrapperVersion
        ))
    }

    /// ``Fload/setUserId(_:)``.
    @objc(setUserId:)
    public static func setUserId(_ userId: String) {
        Fload.setUserId(userId)
    }

    /// ``Fload/installReference``: nil before configure.
    @objc public static var installReference: String? { Fload.installReference }

    static func options(
        endpoint: String?,
        logLevel: FLDLogLevel,
        wrapperName: String? = nil,
        wrapperVersion: String? = nil
    ) -> FloadOptions {
        var options = FloadOptions()
        if let wrapperName, let wrapperVersion {
            options.wrapper = FloadWrapper(name: wrapperName, version: wrapperVersion)
        }
        if let endpoint, let url = URL(string: endpoint), url.scheme != nil, url.host != nil {
            options.endpoint = url
        }
        options.logLevel = FloadLogLevel(rawValue: logLevel.rawValue) ?? .warning
        return options
    }

    private override init() {}
}
