import Foundation

public struct CapturedAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channels: Int
    public let presentationSeconds: Double
    public var duration: Double { Double(samples.count) / Double(max(1, channels)) / sampleRate }
    public init(samples: [Float], sampleRate: Double, channels: Int, presentationSeconds: Double) {
        self.samples = samples; self.sampleRate = sampleRate
        self.channels = channels; self.presentationSeconds = presentationSeconds
    }
}
public enum CaptureFailure: Error, LocalizedError, Sendable, Equatable {
    case sourceMissing, permissionDenied, streamStopped, overflow, invalidAudio
    public var errorDescription: String? {
        switch self {
        case .sourceMissing: "Open Google Chrome before starting a recording."
        case .permissionDenied: "Allow Lecture Recorder in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
        case .streamStopped: "Chrome audio capture was interrupted."
        case .overflow: "Audio could not be saved quickly enough. Recording was interrupted."
        case .invalidAudio: "Chrome supplied an unsupported audio format."
        }
    }
}
public enum CaptureEvent: Sendable { case audio(CapturedAudio), interrupted(CaptureFailure) }
public struct CaptureOrigin: Sendable { public let hostSeconds: Double; public init(hostSeconds: Double) { self.hostSeconds = hostSeconds } }
public protocol CaptureService: Sendable {
    func start(onEvent: @escaping @Sendable (CaptureEvent) -> Void) async throws -> CaptureOrigin
    func stop() async
}
public struct CaptureApplication: Sendable, Equatable {
    public let processID: Int32
    public let bundleID: String
    public init(processID: Int32, bundleID: String) { self.processID = processID; self.bundleID = bundleID }
}
public enum ChromeSourceResolver {
    public static func select(from applications: [CaptureApplication]) throws -> [CaptureApplication] {
        guard applications.contains(where: { $0.bundleID == "com.google.Chrome" }) else { throw CaptureFailure.sourceMissing }
        return applications.filter { $0.bundleID == "com.google.Chrome" || $0.bundleID == "com.google.Chrome.helper" || $0.bundleID.hasPrefix("com.google.Chrome.helper.") }
    }
}
