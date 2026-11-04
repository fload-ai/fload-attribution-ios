import Foundation

struct TransportResponse: Equatable, Sendable {
    var status: Int
    /// The `Retry-After` header, as sent.
    var retryAfter: String?
}

protocol Transport: Sendable {
    /// Throws when no HTTP answer came back (offline, timeout, TLS).
    func send(_ request: URLRequest) async throws -> TransportResponse
}

struct URLSessionTransport: Transport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> TransportResponse {
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return TransportResponse(
            status: http.statusCode,
            retryAfter: http.value(forHTTPHeaderField: "Retry-After")
        )
    }
}
