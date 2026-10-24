import Foundation
import CryptoKit

public actor ModelManager: ModelManaging {
    public typealias Download = @Sendable (URL) async throws -> URL
    public typealias Prepare = @Sendable (ModelLocation) async throws -> Void
    private let root: URL
    private let manifest: ModelManifest
    private let download: Download
    private let prepareModel: Prepare
    private let freeBytes: @Sendable (URL) throws -> Int64
    private var busy = false
    public init(root: URL, manifest: ModelManifest, download: @escaping Download = ModelManager.downloadFile, prepareModel: @escaping Prepare = LocalWhisper.prepare, freeBytes: @escaping @Sendable (URL) throws -> Int64 = ModelManager.availableBytes) {
        self.root = root; self.manifest = manifest; self.download = download; self.prepareModel = prepareModel; self.freeBytes = freeBytes
    }
    private var location: ModelLocation { .init(modelFolder: root.appendingPathComponent("model"), tokenizerFolder: root.appendingPathComponent("tokenizer"), identity: manifest.modelIdentity) }
    private var marker: URL { root.appendingPathComponent("prepared.json") }
    public func installed() async throws -> ModelLocation? {
        try validateManifest()
        guard let saved = try? Data(contentsOf: marker), saved == (try manifestData()),
              try manifest.artifacts.allSatisfy({ try verified($0) }) else { return nil }
        return location
    }
    public func prepare(progress: @escaping @Sendable (ModelSetupProgress) -> Void) async throws -> ModelLocation {
        guard !busy else { throw ModelFailure.setupBusy }; busy = true; defer { busy = false }
        try validateManifest()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let ready = try await installed() { progress(.ready); return ready }
        try? FileManager.default.removeItem(at: marker)
        let total = manifest.artifacts.reduce(Int64(0)) { $0 + $1.byteCount }
        let missing = try manifest.artifacts.filter { try !verified($0) }
        let needed = missing.reduce(Int64(0)) { $0 + $1.byteCount }
        guard try freeBytes(root) > needed + 2_000_000_000 else { throw ModelFailure.insufficientSpace }
        var completed = total - needed
        progress(.downloading(completedBytes: completed, totalBytes: total))
        for artifact in missing {
            try Task.checkCancellation()
            let temporary = try await download(artifact.immutableURL)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard try Self.matches(temporary, artifact) else { throw ModelFailure.corruptArtifact(artifact.relativePath) }
            let target = root.appendingPathComponent(artifact.relativePath)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let staging = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".partial")
            try FileManager.default.copyItem(at: temporary, to: staging)
            // rename() atomically replaces an old corrupt file on the same volume.
            guard rename(staging.path, target.path) == 0 else { try? FileManager.default.removeItem(at: staging); throw CocoaError(.fileWriteUnknown) }
            completed += artifact.byteCount
            progress(.downloading(completedBytes: completed, totalBytes: total))
        }
        progress(.preparing)
        try await prepareModel(location)
        try Task.checkCancellation()
        try manifestData().write(to: marker, options: .atomic)
        progress(.ready)
        return location
    }
    private func manifestData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(manifest)
    }
    private func validateManifest() throws {
        guard !manifest.artifacts.isEmpty, manifest.artifacts.contains(where: { $0.relativePath.hasPrefix("tokenizer/") }) else { throw ModelFailure.invalidManifest }
        for artifact in manifest.artifacts {
            let parts = artifact.relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count >= 2, parts.first == "model" || parts.first == "tokenizer", !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }), artifact.byteCount >= 0, artifact.immutableURL.scheme == "https", artifact.sha256.count == 64 else { throw ModelFailure.invalidManifest }
        }
    }
    private func verified(_ artifact: ModelManifest.Artifact) throws -> Bool {
        let url = root.appendingPathComponent(artifact.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return try Self.matches(url, artifact)
    }
    private static func matches(_ url: URL, _ artifact: ModelManifest.Artifact) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == artifact.byteCount else { return false }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == artifact.sha256
    }
    public static func availableBytes(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }
    public static func downloadFile(_ url: URL) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { try? FileManager.default.removeItem(at: file); throw URLError(.badServerResponse) }
        return file
    }
}
