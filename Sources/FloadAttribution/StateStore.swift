import Foundation

enum LoadResult: Equatable, Sendable {
    case loaded(StoredState)
    /// No state yet: the first launch with the SDK.
    case missing
    /// The file is there but cannot be read now (data protection before the
    /// device's first unlock, say).
    case unreadable
    /// The file is there but does not decode.
    case corrupt
}

protocol StateStore: Sendable {
    func load() -> LoadResult
    func save(_ state: StoredState) throws
}

/// The state as one JSON file in Application Support, written atomically,
/// readable after the device's first unlock (so background launches can
/// send), and excluded from backups so a restored backup is a new install.
struct FileStateStore: StateStore {
    let fileURL: URL

    static func inApplicationSupport() throws -> FileStateStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try FileStateStore(directory: base.appendingPathComponent("com.fload.attribution", isDirectory: true))
    }

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(excluded)
        fileURL = directory.appendingPathComponent("state.json")
    }

    func load() -> LoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable
        }
        guard let state = try? Self.decoder.decode(StoredState.self, from: data) else {
            return .corrupt
        }
        return .loaded(state)
    }

    func save(_ state: StoredState) throws {
        let data = try Self.encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
