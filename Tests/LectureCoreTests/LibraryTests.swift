import Foundation
import LectureCore
@MainActor func registerLibraryTests() {
    Checks.add("Library rename search and active deletion") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        var session = try await store.create(); session.state = .recorded; try await store.save(session)
        var active: UUID?
        let library = LibraryModel(store: store, activeID: { active })
        await library.reload(); try expect(library.visibleSessions.count == 1)
        try await library.rename(session.id, title: "Logic / α")
        let renamed = try await store.load(session.id); try expect(renamed.title == "Logic / α")
        library.titleQuery = "LOGIC"; try expect(library.visibleSessions.count == 1)
        library.titleQuery = "missing"; try expect(library.visibleSessions.isEmpty)
        library.titleQuery = ""; try expect(library.visibleSessions.count == 1)
        active = session.id
        do { try await library.trash(session.id); throw CheckFailure(description: "Active deletion accepted") } catch StorageFailure.activeSession { }
    }
    Checks.add("Library inactive deletion delegates to macOS Trash") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let receipt = temp.url.appendingPathComponent("trash-receipt")
        let store = SessionStore(root: temp.url, trashItem: { try Data($0.lastPathComponent.utf8).write(to: receipt) })
        var session = try await store.create(); session.state = .recorded; try await store.save(session)
        try await store.trash(session.id)
        try expect(try String(contentsOf: receipt, encoding: .utf8) == session.id.uuidString)
    }
    Checks.add("Playback mapping boundaries gaps and nonfinite seek") {
        let segments = [AudioSegment(index: 0, relativePath: "audio/0-0.wav", startFrame: 0, frameCount: 160_000), .init(index: 1, relativePath: "audio/1-160000.wav", startFrame: 160_000, frameCount: 160_000)]
        try expect(PlaybackPosition.resolve(seconds: 12, segments: segments, duration: 20)?.segmentIndex == 1)
        try expect(PlaybackPosition.resolve(seconds: 12, segments: segments, duration: 20)?.offsetSeconds == 2)
        try expect(PlaybackPosition.resolve(seconds: 10, segments: segments, duration: 20)?.offsetSeconds == 0)
        try expect(PlaybackPosition.resolve(seconds: 20, segments: segments, duration: 20) == nil)
        try expect(PlaybackPosition.resolve(seconds: .nan, segments: segments, duration: 20) == nil)
    }
    Checks.add("TranscriptExport complete text hours and safe filename") {
        let session = Session(title: "Logic / α", createdAt: Date(timeIntervalSince1970: 0), timeZoneID: "UTC")
        let transcript = Transcript(modelIdentity: "test", segments: [.init(startSeconds: 3723, endSeconds: 3725, text: "α → β")], noSpeech: false)
        let text = TranscriptExport.text(session: session, transcript: transcript)
        try expect(text.contains("01:02:03") && text.contains("Logic / α") && text.contains("α → β") && text.contains("1970"))
        try expect(!TranscriptExport.filename(session.title).contains("/"))
    }
}
