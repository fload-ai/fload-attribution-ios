import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

/// Flushes the queue when the app comes to the foreground and when the
/// network comes back. Lives as long as the SDK.
final class FlushTriggers: @unchecked Sendable {
    private let flush: @Sendable () async -> Void
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.fload.attribution.path", qos: .utility)
    private var observer: NSObjectProtocol?
    /// Touched only on `queue`.
    private var wasSatisfied = true

    init(flush: @escaping @Sendable () async -> Void) {
        self.flush = flush
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            if satisfied, !self.wasSatisfied {
                Task { await self.flush() }
            }
            self.wasSatisfied = satisfied
        }
        monitor.start(queue: queue)
        #if canImport(UIKit)
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [flush] _ in
            Task { await flush() }
        }
        #endif
    }

    deinit {
        monitor.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
