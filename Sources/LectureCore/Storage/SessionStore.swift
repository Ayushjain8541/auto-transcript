import Foundation

public actor SessionStore {
    public let root: URL
    public internal(set) var issues: [String] = []
    let writeData: @Sendable (Data, URL) throws -> Void
    public init(root: URL, writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.root = root; self.writeData = writeData
    }
    public func folder(for id: SessionID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func create(now: Date = Date(), timeZone: TimeZone = .current) throws -> Session {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short; formatter.timeZone = timeZone
        let session = Session(title: formatter.string(from: now), createdAt: now, timeZoneID: timeZone.identifier)
        try save(session); return session
    }
    public func load(_ id: SessionID) throws -> Session {
        let session = try JSONDecoder().decode(Session.self, from: Data(contentsOf: folder(for: id).appendingPathComponent("session.json")))
        guard session.id == id else { throw StorageFailure.invalidData("Recording identifier does not match its folder.") }
        try validate(session); return session
    }
    public func save(_ session: Session) throws {
        try validate(session)
        let directory = folder(for: session.id)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("audio"), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try writeData(encoder.encode(session), directory.appendingPathComponent("session.json"))
    }
    public func list() throws -> [Session] {
        issues = []
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles)
        var sessions: [Session] = []
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent) else { continue }
            do {
                guard try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw StorageFailure.invalidData("Linked session folders are not supported.") }
                sessions.append(try load(id))
            } catch { issues.append("\(entry.lastPathComponent): \(error.localizedDescription)") }
        }
        return sessions.sorted { $0.createdAt > $1.createdAt }
    }
    private func validate(_ session: Session) throws {
        guard session.schemaVersion == 1 else { throw StorageFailure.unsupportedSchema(session.schemaVersion) }
        guard session.capturedFrames >= 0 else { throw StorageFailure.invalidData("Negative duration.") }
        var lastEnd: Int64 = 0; var indices = Set<Int>()
        for segment in session.segments {
            guard segment.index >= 0, indices.insert(segment.index).inserted,
                  segment.startFrame >= lastEnd, segment.frameCount > 0, segment.frameCount <= 160_000,
                  segment.startFrame <= Int64.max - segment.frameCount,
                  segment.relativePath == "audio/\(segment.index)-\(segment.startFrame).wav" else {
                throw StorageFailure.invalidData("Invalid audio segment manifest.")
            }
            lastEnd = segment.startFrame + segment.frameCount
        }
    }
}
