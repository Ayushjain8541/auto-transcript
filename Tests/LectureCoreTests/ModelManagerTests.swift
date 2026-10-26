import Foundation
import CryptoKit
import LectureCore

actor DownloadProbe {
    var requests = 0
    let source: URL
    init(_ source: URL) { self.source = source }
    func download(_ url: URL) throws -> URL {
        requests += 1
        let result = source.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: result)
        return result
    }
}
func smallManifest(data: Data) -> ModelManifest {
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return ModelManifest(modelIdentity: "fixture", sdkVersion: "test", modelRevision: "r1", tokenizerRevision: "r2", artifacts: ["model/weights", "tokenizer/tokenizer.json"].map {
        .init(relativePath: $0, immutableURL: URL(string: "https://example.invalid/\($0)")!, byteCount: Int64(data.count), sha256: hash)
    })
}
@MainActor func registerModelTests() {
    if ProcessInfo.processInfo.environment["LECTURE_REAL_MODEL"] == "1" {
        Checks.add("ModelManager real isolated model preparation") {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("work/model-freeze")
            let manager = ModelManager(root: root, manifest: try .bundled())
            _ = try await manager.prepare { stage in print("Model stage: \(stage)") }
            let installed = try await manager.installed(); try expect(installed != nil)
        }
    }
    Checks.add("ModelManager verifies complete setup and offline lookup") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let data = Data("fixture".utf8), source = temp.url.appendingPathComponent("source")
        try data.write(to: source)
        let probe = DownloadProbe(source)
        let manager = ModelManager(root: temp.url.appendingPathComponent("install"), manifest: smallManifest(data: data), download: { try await probe.download($0) }, prepareModel: { _ in })
        let initial = try await manager.installed(); try expect(initial == nil)
        _ = try await manager.prepare { _ in }
        let ready = try await manager.installed(); try expect(ready != nil)
        let count = await probe.requests; try expect(count == 2)
        _ = try await manager.prepare { _ in }
        let after = await probe.requests; try expect(after == 2, "Verified artifacts must be reused")
        try FileManager.default.removeItem(at: ready!.tokenizerFolder.appendingPathComponent("tokenizer.json"))
        let incomplete = try await manager.installed(); try expect(incomplete == nil, "Tokenizer is required for offline readiness")
        _ = try await manager.prepare { _ in }
        let repaired = await probe.requests; try expect(repaired == 3, "Only missing file should download")
    }
    Checks.add("ModelManager rejects corrupt download without promotion") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let source = temp.url.appendingPathComponent("bad"); try Data("bad".utf8).write(to: source)
        let probe = DownloadProbe(source)
        let manager = ModelManager(root: temp.url.appendingPathComponent("install"), manifest: smallManifest(data: Data("good".utf8)), download: { try await probe.download($0) }, prepareModel: { _ in })
        do { _ = try await manager.prepare { _ in }; throw CheckFailure(description: "Corrupt model accepted") }
        catch ModelFailure.corruptArtifact { }
        let installed = try await manager.installed(); try expect(installed == nil)
    }
    Checks.add("ModelManager preparation failure retains verified downloads for retry") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let data = Data("valid".utf8), source = temp.url.appendingPathComponent("source")
        try data.write(to: source)
        let probe = DownloadProbe(source), root = temp.url.appendingPathComponent("install")
        let first = ModelManager(root: root, manifest: smallManifest(data: data), download: { try await probe.download($0) }, prepareModel: { _ in throw URLError(.notConnectedToInternet) })
        do { _ = try await first.prepare { _ in }; throw CheckFailure(description: "Preparation failure swallowed") }
        catch is URLError { }
        let notReady = try await first.installed(); try expect(notReady == nil)
        let retry = ModelManager(root: root, manifest: smallManifest(data: data), download: { _ in throw URLError(.notConnectedToInternet) }, prepareModel: { _ in })
        _ = try await retry.prepare { _ in }
        let requests = await probe.requests; try expect(requests == 2)
        let ready = try await retry.installed(); try expect(ready != nil)
    }
    Checks.add("ModelManager insufficient disk makes no request") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let probe = DownloadProbe(temp.url)
        let manager = ModelManager(root: temp.url, manifest: smallManifest(data: Data()), download: { try await probe.download($0) }, prepareModel: { _ in }, freeBytes: { _ in 0 })
        do { _ = try await manager.prepare { _ in }; throw CheckFailure(description: "Disk check missing") }
        catch ModelFailure.insufficientSpace { }
        let requests = await probe.requests; try expect(requests == 0)
    }
}
