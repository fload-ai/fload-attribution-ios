import Foundation
import os

/// The unified log, filtered by the configured level. Messages are fixed
/// text: never the write key, Apple's token or a user id.
struct SDKLogger: Sendable {
    let level: FloadLogLevel
    private let log = Logger(subsystem: "com.fload.attribution", category: "sdk")

    init(level: FloadLogLevel) {
        self.level = level
    }

    func error(_ message: String) { write(.error, message) }
    func warning(_ message: String) { write(.warning, message) }
    func info(_ message: String) { write(.info, message) }
    func debug(_ message: String) { write(.debug, message) }

    private func write(_ at: FloadLogLevel, _ message: String) {
        guard at != .none, at <= level else { return }
        switch at {
        case .error: log.error("\(message, privacy: .public)")
        case .warning: log.warning("\(message, privacy: .public)")
        case .info: log.info("\(message, privacy: .public)")
        case .debug, .none: log.debug("\(message, privacy: .public)")
        }
    }
}
