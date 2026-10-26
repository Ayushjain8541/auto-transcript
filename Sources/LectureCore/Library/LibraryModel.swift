import Foundation
import Observation
@MainActor @Observable public final class LibraryModel {
    public private(set) var sessions: [Session] = []
    public var selectedSessionID: SessionID?
    public var titleQuery = ""
    public var transcriptQuery = ""
    public var errors: [String] = []
    private let store: SessionStore
    private let activeID: @MainActor () -> SessionID?
    public var visibleSessions: [Session] { sessions.filter { titleQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(titleQuery) } }
    public init(store: SessionStore, activeID: @escaping @MainActor () -> SessionID?) { self.store = store; self.activeID = activeID }
    public func reload() async {
        do { sessions = try await store.list(); errors = await store.issues }
        catch { errors = [error.localizedDescription] }
        if selectedSessionID == nil || !sessions.contains(where: { $0.id == selectedSessionID }) { selectedSessionID = sessions.first?.id }
    }
    public func rename(_ id: SessionID, title: String) async throws {
        guard activeID() != id else { throw StorageFailure.activeSession }
        try await store.rename(id, title: title); await reload()
    }
    public func trash(_ id: SessionID) async throws {
        guard activeID() != id else { throw StorageFailure.activeSession }
        try await store.trash(id); await reload()
    }
}
extension SessionStore {
    public func rename(_ id: SessionID, title: String) throws {
        var session = try load(id)
        guard !session.state.isActive else { throw StorageFailure.activeSession }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 300 else { throw StorageFailure.invalidData("Use a title between 1 and 300 characters.") }
        session.title = title; try save(session)
    }
    public func trash(_ id: SessionID) throws {
        guard try !load(id).state.isActive else { throw StorageFailure.activeSession }
        try trashItem(folder(for: id))
    }
}
