import Foundation
import LectureCore

@MainActor func registerStorageTests() {
    Checks.add("Recovery removes abandoned processing files only") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        var session = try await store.create(); session.state = .recorded; try await store.save(session)
        let processing = await store.folder(for: session.id).appendingPathComponent("processing")
        try FileManager.default.createDirectory(at: processing, withIntermediateDirectories: true)
        let orphan = processing.appendingPathComponent(UUID().uuidString + ".wav")
        let unrelated = processing.appendingPathComponent("notes.txt")
        try Data("temporary".utf8).write(to: orphan); try Data("notes".utf8).write(to: unrelated)
        _ = try await store.recover()
        try expect(!FileManager.default.fileExists(atPath: orphan.path))
        try expect(FileManager.default.fileExists(atPath: unrelated.path))
    }
    Checks.add("SessionStoreTests.roundTripAndOrdering") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        let first = try await store.create(now: Date(timeIntervalSince1970: 10), timeZone: TimeZone(secondsFromGMT: 0)!)
        let second = try await store.create(now: Date(timeIntervalSince1970: 20))
        let loaded = try await store.load(first.id); let list = try await store.list()
        try expect(loaded == first); try expect(list.map(\.id) == [second.id, first.id])
    }
    Checks.add("SessionRecoveryTests.orphanRecoveryIsIdempotent") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        var session = try await store.create()
        let folder = await store.folder(for: session.id)
        try makeWAV(at: folder.appendingPathComponent("audio/0-0.wav"), frames: 160_000)
        session.segments = [.init(index: 0, relativePath: "audio/0-0.wav", startFrame: 0, frameCount: 160_000)]
        session.state = .recording; try await store.save(session)
        try makeWAV(at: folder.appendingPathComponent("audio/1-160000.wav"), frames: 8_000)
        try Data([1,2,3]).write(to: folder.appendingPathComponent("audio/2-168000.partial"))
        let first = try await store.recover(); let second = try await store.recover()
        try expect(first == second); try expect(first[0].segments.map(\.index) == [0, 1])
        try expect(first[0].capturedFrames == 168_000); try expect(first[0].state == .interrupted)
    }
    Checks.add("SessionStoreTests.failedManifestReplacementPreservesPrevious") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        var session = try await store.create(); let original = session
        let failing = SessionStore(root: temp.url, writeData: { _,_ in throw CocoaError(.fileWriteOutOfSpace) })
        session.title = "Changed"
        do { try await failing.save(session); throw CheckFailure(description: "Expected disk error") }
        catch let error as CocoaError { try expect(error.code == .fileWriteOutOfSpace) }
        let loaded = try await store.load(original.id); try expect(loaded == original)
    }
    Checks.add("SessionRecoveryTests.unknownSchemaDoesNotOverwrite") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        var session = try await store.create(); session.schemaVersion = 999
        let file = await store.folder(for: session.id).appendingPathComponent("session.json")
        let bytes = try JSONEncoder().encode(session); try bytes.write(to: file)
        let recovered = try await store.recover(); let issues = await store.issues
        try expect(recovered.isEmpty); try expect(!issues.isEmpty); try expect(try Data(contentsOf: file) == bytes)
    }
    Checks.add("SessionRecoveryTests.missingMiddleSegmentPreservesOffsets") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        var session = try await store.create(); session.state = .recording; try await store.save(session)
        let folder = await store.folder(for: session.id)
        try makeWAV(at: folder.appendingPathComponent("audio/0-0.wav"), frames: 160_000)
        try makeWAV(at: folder.appendingPathComponent("audio/2-320000.wav"), frames: 16_000)
        let recovered = try await store.recover()
        try expect(recovered[0].state == .interrupted)
        try expect(recovered[0].segments[1].startFrame == 320_000)
        try expect(recovered[0].interruptionReason?.contains("Missing audio") == true)
    }
}
