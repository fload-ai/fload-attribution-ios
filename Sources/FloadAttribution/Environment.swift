import Foundation

/// Everything the engine reaches outside itself, so tests can stand in for it.
struct Environment: Sendable {
    var endpoint: URL
    var transport: Transport
    var tokens: AttributionTokenProvider
    var store: StateStore
    var device: @Sendable () -> DeviceFacts
    var now: @Sendable () -> Date
    /// A factor in [0.5, 1] applied to each backoff delay.
    var jitter: @Sendable () -> Double
    var makeId: @Sendable () -> String
    var logger: SDKLogger
    /// Whether the engine sleeps until its next due request and flushes itself.
    /// Off in tests, which call `flush()` directly.
    var schedulesWakeups: Bool
    /// This SDK, and the wrapper around it, as every request names them.
    var sdk = Wire.SDK()

    static func live(endpoint: URL, store: StateStore, logger: SDKLogger, wrapper: FloadWrapper? = nil) -> Environment {
        Environment(
            endpoint: endpoint,
            transport: URLSessionTransport(),
            tokens: AdServicesTokenProvider(),
            store: store,
            device: { DeviceInfo.current() },
            now: { Date() },
            jitter: { Double.random(in: 0.5...1) },
            makeId: { UUID().uuidString.lowercased() },
            logger: logger,
            schedulesWakeups: true,
            sdk: Wire.SDK(wrapper: wrapper)
        )
    }
}
