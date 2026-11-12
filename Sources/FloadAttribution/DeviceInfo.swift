import Foundation

enum DeviceInfo {
    /// The contract's `shortText`: trimmed, 1 to 64 characters.
    static let shortTextLimit = 64

    static func current(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) -> DeviceFacts {
        let info = bundle.infoDictionary ?? [:]
        let os = processInfo.operatingSystemVersion
        let osVersion = os.patchVersion > 0
            ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            : "\(os.majorVersion).\(os.minorVersion)"
        return DeviceFacts(
            appId: appId(bundle.bundleIdentifier),
            appVersion: shortText(info["CFBundleShortVersionString"] as? String),
            appBuild: shortText(info["CFBundleVersion"] as? String),
            osVersion: shortText(osVersion),
            deviceModel: shortText(processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine()),
            locale: shortText(Locale.current.identifier),
            originalInstallAt: appInstalledAt(fileManager)
        )
    }

    /// When the app was first installed on this device: the creation date of
    /// its Documents directory, made with the app's data container at install
    /// and kept across updates (FLO-4496). An update to the first build with
    /// the SDK keeps the old date, so Fload counts an existing user apart from
    /// a new download. A file timestamp inside the app's own container
    /// (privacy manifest reason C617.1). Nil when it cannot be read.
    static func appInstalledAt(_ fileManager: FileManager) -> Date? {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return try? documents.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    /// The bundle id; the contract needs 1 to 256 characters.
    static func appId(_ bundleIdentifier: String?) -> String {
        let trimmed = (bundleIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        return truncated(trimmed, to: 256)
    }

    static func shortText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return truncated(trimmed, to: shortTextLimit)
    }

    /// At most `limit` UTF-16 units (what the server's string length counts),
    /// cut on a character boundary.
    static func truncated(_ value: String, to limit: Int) -> String {
        guard value.utf16.count > limit else { return value }
        var result = ""
        for character in value {
            if result.utf16.count + String(character).utf16.count > limit { break }
            result.append(character)
        }
        return result
    }

    /// The hardware model, e.g. `iPhone16,2`.
    private static func machine() -> String? {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
