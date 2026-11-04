import Foundation

/// The two requests of Fload's ingest contract
/// (`packages/shared-types/src/contracts/attribution-ingest.ts` in the Fload
/// repo). Absent optionals are left out of the JSON.
enum Wire {
    static let installsPath = "attribution/v1/installs"
    static let identifyPath = "attribution/v1/identify"
    static let sdkName = "fload-attribution-ios"

    struct SDK: Encodable, Equatable {
        var name = Wire.sdkName
        var version = Fload.sdkVersion
    }

    struct AppleAds: Encodable, Equatable {
        /// `token`, `token_expired`, `unsupported_os` or `token_error`.
        var status: String
        /// Only with `status: "token"`.
        var token: String?
        var tokenCreatedAt: String?
    }

    struct Install: Encodable, Equatable {
        var requestId: String
        var installReference: String
        var platform = "ios"
        var appId: String
        var appVersion: String?
        var appBuild: String?
        var osVersion: String?
        var deviceModel: String?
        var locale: String?
        var sdk = SDK()
        var firstLaunchAt: String
        var appleAds: AppleAds
        var appUserId: String?
    }

    struct Identify: Encodable, Equatable {
        var requestId: String
        var installReference: String
        var platform = "ios"
        var appUserId: String
    }

    static func appleAds(_ token: TokenResult, at fetchedAt: Date) -> AppleAds {
        switch token {
        case let .token(value):
            return AppleAds(status: "token", token: value, tokenCreatedAt: timestamp(fetchedAt))
        case .unsupported:
            return AppleAds(status: "unsupported_os")
        case .failure, .retryableFailure:
            return AppleAds(status: "token_error")
        }
    }

    /// ISO 8601 in UTC with milliseconds, which the contract's `datetime` accepts.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func request(endpoint: URL, path: String, key: String, body: some Encodable) throws -> URLRequest {
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: WriteKey.header)
        request.setValue("\(sdkName)/\(Fload.sdkVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

/// The user id the contract accepts: trimmed, 1 to 256 characters.
enum AppUserId {
    static func validated(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf16.count <= 256 else { return nil }
        return trimmed
    }
}
