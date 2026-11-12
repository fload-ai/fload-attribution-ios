import XCTest
@testable import FloadAttribution

final class StorageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fload-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripsTheState() throws {
        let store = try FileStateStore(directory: directory)
        XCTAssertEqual(store.load(), .missing)

        let state = StoredState(
            installReference: "ins-00000001",
            firstLaunchAt: Date(timeIntervalSince1970: 1_800_000_000.123),
            device: DeviceFixture.facts,
            queue: [QueuedRequest(
                requestId: "req-00000001",
                kind: .install,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000.123),
                failures: 2,
                nextAttemptAt: Date(timeIntervalSince1970: 1_800_000_010),
                appUserId: "user-1"
            )],
            lastUserId: "user-1",
            revokedKeys: ["abc"],
            refusedKeys: ["def": Date(timeIntervalSince1970: 1_800_086_400)]
        )
        try store.save(state)
        XCTAssertEqual(try FileStateStore(directory: directory).load(), .loaded(state))
    }

    func testStateWrittenBeforeLaterFieldsStillLoads() throws {
        let store = try FileStateStore(directory: directory)
        let firstVersion = """
        {"version":1,"installReference":"ins-00000001","firstLaunchAt":1800000000000,
         "device":{"appId":"com.example.app"},"queue":[]}
        """
        try Data(firstVersion.utf8).write(to: store.fileURL)
        guard case let .loaded(state) = store.load() else { return XCTFail("did not load") }
        XCTAssertEqual(state.installReference, "ins-00000001")
        XCTAssertTrue(state.refusedKeys.isEmpty)
        XCTAssertTrue(state.revokedKeys.isEmpty)
        XCTAssertNil(state.device.originalInstallAt, "an older SDK did not record it")
    }

    func testTheDirectoryIsExcludedFromBackup() throws {
        _ = try FileStateStore(directory: directory)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testGarbageIsCorrupt() throws {
        let store = try FileStateStore(directory: directory)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), .corrupt)
    }

    func testAFileThatCannotBeReadIsUnreadableNotMissing() throws {
        let store = try FileStateStore(directory: directory)
        // A directory where the file should be: present, but not readable as data.
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        XCTAssertEqual(store.load(), .unreadable)
    }

    func testThePrivacyManifestShipsAndDeclaresNoTracking() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((plist["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        // The install's first install time is the app container's creation
        // date: a file timestamp inside the app container (C617.1), nothing else.
        let accessed = (plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]]) ?? []
        XCTAssertEqual(accessed.count, 1)
        XCTAssertEqual(accessed.first?["NSPrivacyAccessedAPIType"] as? String, "NSPrivacyAccessedAPICategoryFileTimestamp")
        XCTAssertEqual(accessed.first?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])
        let collected = (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]]) ?? []
        XCTAssertFalse(collected.isEmpty)
        XCTAssertTrue(collected.allSatisfy { $0["NSPrivacyCollectedDataTypeTracking"] as? Bool == false })
    }
}
