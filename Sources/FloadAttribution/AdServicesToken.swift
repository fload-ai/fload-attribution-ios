import Foundation
#if canImport(AdServices)
import AdServices
#endif

/// What asking Apple for the AdServices attribution token gave.
enum TokenResult: Equatable, Sendable {
    case token(String)
    /// The platform has no AdServices attribution (Apple's `platformNotSupported`).
    case unsupported
    /// Apple's network or internal error: worth asking again shortly.
    case retryableFailure
    /// Any other failure, or a token not in the shape Fload accepts.
    case failure
}

protocol AttributionTokenProvider: Sendable {
    func token() async -> TokenResult
}

/// `AAAttribution.attributionToken()`: no IDFA, no ATT prompt. Apple's call
/// blocks, so it runs on a utility queue, never the caller's thread.
struct AdServicesTokenProvider: AttributionTokenProvider {
    func token() async -> TokenResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.fetch())
            }
        }
    }

    private static func fetch() -> TokenResult {
        #if canImport(AdServices)
        do {
            return AppleToken.validated(try AAAttribution.attributionToken())
        } catch let error as AAAttributionError {
            switch error.code {
            case .platformNotSupported:
                return .unsupported
            case .networkError, .internalError:
                return .retryableFailure
            default:
                return .failure
            }
        } catch {
            return .failure
        }
        #else
        return .unsupported
        #endif
    }
}

enum AppleToken {
    /// The contract's limits: at most 4,096 characters of base64 (or base64url).
    static let maxLength = 4096

    static func validated(_ raw: String) -> TokenResult {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf16.count <= maxLength,
              token.unicodeScalars.allSatisfy(allowed.contains)
        else { return .failure }
        return .token(token)
    }

    private static let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-"
    )
}
