import Foundation

public struct ModelManifest: Codable, Sendable {
    public struct Artifact: Codable, Sendable {
        public let relativePath: String
        public let immutableURL: URL
        public let byteCount: Int64
        public let sha256: String
        public init(relativePath: String, immutableURL: URL, byteCount: Int64, sha256: String) {
            self.relativePath = relativePath; self.immutableURL = immutableURL; self.byteCount = byteCount; self.sha256 = sha256
        }
    }
    public let modelIdentity: String
    public let sdkVersion: String
    public let modelRevision: String
    public let tokenizerRevision: String
    public let artifacts: [Artifact]
    public init(modelIdentity: String, sdkVersion: String, modelRevision: String, tokenizerRevision: String, artifacts: [Artifact]) {
        self.modelIdentity = modelIdentity; self.sdkVersion = sdkVersion; self.modelRevision = modelRevision; self.tokenizerRevision = tokenizerRevision; self.artifacts = artifacts
    }
    public static func bundled() throws -> Self {
        guard let url = LectureResources.bundle.url(forResource: "model-manifest", withExtension: "json") else { throw ModelFailure.invalidManifest }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
public struct ModelLocation: Sendable {
    public let modelFolder: URL
    public let tokenizerFolder: URL
    public let identity: String
    public init(modelFolder: URL, tokenizerFolder: URL, identity: String) {
        self.modelFolder = modelFolder; self.tokenizerFolder = tokenizerFolder; self.identity = identity
    }
}
public enum ModelSetupProgress: Sendable { case downloading(completedBytes: Int64, totalBytes: Int64), preparing, ready }
public enum ModelFailure: Error, LocalizedError {
    case invalidManifest, corruptArtifact(String), insufficientSpace, setupBusy
    public var errorDescription: String? {
        switch self {
        case .invalidManifest: "The bundled model manifest is invalid. Rebuild or reinstall the app."
        case .corruptArtifact(let path): "Model verification failed: \(path). Retry setup."
        case .insufficientSpace: "Not enough free disk space to prepare the model. Free at least 3 GB and retry."
        case .setupBusy: "Model setup is already running."
        }
    }
}
public protocol ModelManaging: Actor {
    func prepare(progress: @escaping @Sendable (ModelSetupProgress) -> Void) async throws -> ModelLocation
    func installed() async throws -> ModelLocation?
}
