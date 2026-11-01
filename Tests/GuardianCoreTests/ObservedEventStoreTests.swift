import Foundation
import XCTest
@testable import GuardianCore

final class ObservedEventStoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("guardian-event-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testReloadFindsLatestAndPreservesOlderRecordBytes() throws {
        let store = ObservedEventStore(stateDirectory: root)
        XCTAssertNil(try store.loadLatest().event)
        let earlier = try store.append(channel: .config, fingerprint: "first", at: Date(timeIntervalSince1970: 1_700_000_000.125))
        let file = root.appendingPathComponent("observed-events/\(earlier.id.uuidString).json")
        let original = try Data(contentsOf: file)
        let later = try store.append(channel: .skills, fingerprint: "second", at: Date(timeIntervalSince1970: 1_700_000_001.875))
        let loaded = try ObservedEventStore(stateDirectory: root).loadLatest()
        XCTAssertEqual(loaded.event, later)
        XCTAssertFalse(loaded.incomplete)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testMalformedRecordDoesNotHideValidHistoryOrGetRewritten() throws {
        let store = ObservedEventStore(stateDirectory: root)
        let event = try store.append(channel: .config, fingerprint: "valid", at: Date(timeIntervalSince1970: 1_700_000_000))
        let corrupt = root.appendingPathComponent("observed-events/corrupt.json")
        let bytes = Data("not JSON".utf8)
        try bytes.write(to: corrupt)
        let loaded = try store.loadLatest()
        XCTAssertEqual(loaded.event, event)
        XCTAssertTrue(loaded.incomplete)
        XCTAssertEqual(try Data(contentsOf: corrupt), bytes)
    }
}
