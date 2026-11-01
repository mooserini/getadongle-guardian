import Foundation
import XCTest
@testable import GuardianCore
@testable import HermesConfigGuardian

@MainActor
final class GuardianObservedEventTests: XCTestCase {
    private var root: URL!
    private var source: URL { root.appendingPathComponent("config.yaml") }
    private var state: URL { root.appendingPathComponent("state") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("guardian-observation-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("value: approved\n".utf8).write(to: source)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func model(sound: @escaping @MainActor () -> Void = {}) -> GuardianModel {
        GuardianModel(environment: [
            "HCG_TARGET_CONFIG": source.path, "HCG_STATE_DIR": state.path,
            "HCG_PENDING_SKILLS_DIR": root.appendingPathComponent("pending").path,
            "HCG_SKILLS_DIR": root.appendingPathComponent("skills").path,
            "HCG_HERMES_HOME": root.appendingPathComponent("hermes-home").path,
            "HCG_HERMES_DOCS_DIR": root.appendingPathComponent("docs").path,
            "HCG_RECONCILE_INTERVAL": "3600",
        ], userDefaults: UserDefaults(suiteName: "GuardianObservedEventTests.\(UUID().uuidString)")!, playAttentionSound: sound)
    }

    private func records() throws -> [[String: Any]] {
        let directory = state.appendingPathComponent("observed-events")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: Any]) }
    }

    func testConfigEventsAreDeduplicatedRetainedAndIndependentOfDecisions() async throws {
        let oldDecision = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try ApprovalStore(stateDirectory: state).approve(sourceURL: source, data: Data(contentsOf: source), at: oldDecision)
        let guardian = model()
        await guardian.waitForSkillReconciliationForTesting()
        let before = Date()
        try Data("value: changed\nsecret: do-not-record-this-value\n".utf8).write(to: source)
        guardian.checkForChange()
        guardian.checkForChange()
        let entries = try records()
        XCTAssertEqual(entries.count, 1)
        guard let event = entries.first else { return }
        XCTAssertEqual(event["channel"] as? String, "config")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(event["id"] as? String)))
        XCTAssertEqual(Set(event.keys), ["formatVersion", "id", "observedAt", "channel", "fingerprint"])
        let stamp = try XCTUnwrap(event["observedAt"] as? String)
        XCTAssertTrue(stamp.hasSuffix("Z"))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let observed = try XCTUnwrap(formatter.date(from: stamp))
        XCTAssertGreaterThanOrEqual(observed.timeIntervalSince1970, before.timeIntervalSince1970 - 0.001)
        XCTAssertLessThanOrEqual(observed, Date())
        XCTAssertNotEqual(observed, oldDecision)
        XCTAssertFalse(String(describing: event).contains("do-not-record-this-value"))
        XCTAssertEqual(event["fingerprint"] as? String, ApprovalStore.sha256(try Data(contentsOf: source)))
        guardian.accept()
        XCTAssertEqual(try records().count, 1)
        guardian.checkForChange()
        let reloaded = model()
        await reloaded.waitForSkillReconciliationForTesting()
        XCTAssertEqual(try records().count, 1)
        XCTAssertEqual(reloaded.latestObservedEvent?.id.uuidString, event["id"] as? String)
        XCTAssertNil(reloaded.observationHistoryWarning)
        try Data("value: another\n".utf8).write(to: source)
        reloaded.checkForChange()
        XCTAssertEqual(try records().count, 2)
        XCTAssertEqual(Set(try records().compactMap { $0["id"] as? String }).count, 2)
    }

    func testSkillAttentionRetainsRecordAcrossRelaunchWithoutRepeatingSound() async throws {
        let pending = root.appendingPathComponent("pending")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        try Data("{\"id\":\"one\",\"secret\":\"not-in-history\"}".utf8).write(to: pending.appendingPathComponent("one.json"))
        var sounds = 0
        let guardian = model { sounds += 1 }
        guardian.enroll()
        await guardian.waitForSkillReconciliationForTesting()
        guardian.checkForChange()
        await guardian.waitForSkillReconciliationForTesting()
        XCTAssertEqual(try records().count, 1)
        XCTAssertEqual(try records().first?["channel"] as? String, "skills")
        XCTAssertFalse(String(describing: try records()).contains("not-in-history"))
        XCTAssertEqual(sounds, 1)
        let reloaded = model { sounds += 1 }
        await reloaded.waitForSkillReconciliationForTesting()
        XCTAssertEqual(try records().count, 1)
        XCTAssertEqual(sounds, 1)
        try FileManager.default.removeItem(at: pending.appendingPathComponent("one.json"))
        reloaded.checkForChange()
        await reloaded.waitForSkillReconciliationForTesting()
        XCTAssertEqual(try records().count, 1)
    }

    func testSkillDriftStoresOpaqueFingerprintWithoutSkillNames() async throws {
        let skills = root.appendingPathComponent("skills")
        let label = "private-skill-label"
        let file = skills.appendingPathComponent("\(label)/SKILL.md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("original".utf8)
        try original.write(to: file)
        _ = try SkillsIntegrityStore(stateDirectory: state).record(rootURL: skills,
            manifest: SkillsManifest(files: ["\(label)/SKILL.md": ApprovalStore.sha256(original)]))
        let guardian = model()
        guardian.enroll()
        await guardian.waitForSkillReconciliationForTesting()
        try Data("new private content".utf8).write(to: file)
        guardian.checkForChange()
        await guardian.waitForSkillReconciliationForTesting()
        let event = try XCTUnwrap(try records().first)
        let fingerprint = try XCTUnwrap(event["fingerprint"] as? String)
        XCTAssertEqual(fingerprint.count, 64)
        XCTAssertFalse(String(describing: event).contains(label))
        XCTAssertFalse(String(describing: event).contains("new private content"))
    }

    func testSkillsUnavailableDiagnosticIsNotRetainedWithPendingAttention() async throws {
        let pending = root.appendingPathComponent("pending")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pending.appendingPathComponent("one.json"))
        try Data("not a directory".utf8).write(to: root.appendingPathComponent("skills"))
        let guardian = model()
        guardian.enroll()
        await guardian.waitForSkillReconciliationForTesting()
        let event = try XCTUnwrap(try records().first)
        XCTAssertEqual((event["fingerprint"] as? String)?.count, 64)
        XCTAssertFalse(String(describing: event).contains("not a directory"))
        XCTAssertEqual(try records().count, 1)
    }

    func testMutedAttentionStillRecordsAndReadFailureIsNonblocking() async throws {
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try Data("blocked".utf8).write(to: state.appendingPathComponent("observed-events"))
        let guardian = model()
        XCTAssertNotNil(guardian.observationHistoryWarning)
        guardian.enroll()
        await guardian.waitForSkillReconciliationForTesting()
        XCTAssertEqual(guardian.status, .clean)
        try FileManager.default.removeItem(at: state.appendingPathComponent("observed-events"))
        guardian.attentionSoundEnabled = false
        try Data("value: changed\n".utf8).write(to: source)
        guardian.checkForChange()
        XCTAssertEqual(try records().count, 1)
        XCTAssertNotNil(guardian.latestObservedEvent)
    }

    func testRecordingFailureDoesNotBlockAttentionOrApproval() async throws {
        var sounds = 0
        let guardian = model { sounds += 1 }
        guardian.enroll()
        await guardian.waitForSkillReconciliationForTesting()
        try Data("blocked".utf8).write(to: state.appendingPathComponent("observed-events"))
        try Data("value: changed\n".utf8).write(to: source)
        guardian.checkForChange()
        XCTAssertEqual(sounds, 1)
        XCTAssertNotNil(guardian.pending)
        XCTAssertEqual(guardian.status, .changed(1))
        XCTAssertNotNil(guardian.observationHistoryWarning)
        guardian.checkForChange()
        XCTAssertEqual(sounds, 1)
        guardian.accept()
        XCTAssertEqual(guardian.status, .clean)
        XCTAssertEqual(guardian.approved?.data, try Data(contentsOf: source))
    }
}
