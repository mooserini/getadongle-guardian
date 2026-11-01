import Foundation

/// An existing attention-gate selection, not the writer's time or a decision receipt.
public struct ObservedEvent: Codable, Equatable, Sendable, Identifiable {
    public enum Channel: String, Codable, Sendable { case config, skills }
    public let formatVersion: Int
    public let id: UUID
    public let observedAt: Date
    public let channel: Channel
    public let fingerprint: String
}

/// Metadata-only, append-only retention: old records are never replaced or deleted.
/// Loading the latest record scans the retained directory; storage and startup work
/// grow with the history. There is intentionally no automatic cleanup policy.
public final class ObservedEventStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(stateDirectory: URL) {
        directory = stateDirectory.appendingPathComponent("observed-events", isDirectory: true)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let stamp = try container.decode(String.self)
            guard let date = formatter.date(from: stamp) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid observation timestamp")
            }
            return date
        }
    }

    @discardableResult
    public func append(channel: ObservedEvent.Channel, fingerprint: String, at date: Date = Date()) throws -> ObservedEvent {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let event = ObservedEvent(formatVersion: 1, id: UUID(), observedAt: date, channel: channel, fingerprint: fingerprint)
        let file = directory.appendingPathComponent("\(event.id.uuidString).json")
        try encoder.encode(event).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return event
    }

    public func loadLatest() throws -> (event: ObservedEvent?, incomplete: Bool) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return (nil, false) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var latest: ObservedEvent?
        var incomplete = false
        for file in files where file.pathExtension == "json" {
            do {
                let event = try decoder.decode(ObservedEvent.self, from: Data(contentsOf: file))
                guard event.formatVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
                if latest == nil || event.observedAt > latest!.observedAt { latest = event }
            } catch {
                incomplete = true
            }
        }
        return (latest, incomplete)
    }
}
