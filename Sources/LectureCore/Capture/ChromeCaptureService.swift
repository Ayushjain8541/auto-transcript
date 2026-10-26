import Foundation
import AVFoundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor public final class ChromeCaptureService: CaptureService {
    private var stream: SCStream?
    private var output: ChromeAudioOutput?
    public init() {}
    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    public static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }
    public static var hostSeconds: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    public func start(onEvent: @escaping @Sendable (CaptureEvent) -> Void) async throws -> CaptureOrigin {
        guard stream == nil else { throw CaptureFailure.streamStopped }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
        catch { throw Self.hasPermission ? CaptureFailure.streamStopped : .permissionDenied }
        let selected = try ChromeSourceResolver.select(from: content.applications.map { .init(processID: $0.processID, bundleID: $0.bundleIdentifier) })
        let ids = Set(selected.map(\.processID))
        guard let display = content.displays.first else { throw CaptureFailure.streamStopped }
        let filter = SCContentFilter(display: display, including: content.applications.filter { ids.contains($0.processID) }, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.capturesAudio = true; config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000; config.channelCount = 2
        if #available(macOS 15, *) { config.captureMicrophone = false }
        let output = ChromeAudioOutput(onEvent: onEvent)
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.delivery.queue)
        self.output = output; self.stream = stream
        let origin = CaptureOrigin(hostSeconds: Self.hostSeconds)
        do { try await stream.startCapture() }
        catch { self.output = nil; self.stream = nil; throw error }
        return origin
    }
    public func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        await output?.delivery.finish()
        self.stream = nil; output = nil
    }
}

private final class ChromeAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let delivery: CaptureDelivery
    init(onEvent: @escaping @Sendable (CaptureEvent) -> Void) { delivery = CaptureDelivery(onEvent) }
    private func deliver(_ event: CaptureEvent) { delivery.deliver(event) }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { deliver(.interrupted(.streamStopped)) }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, buffer.isValid, CMSampleBufferDataIsReady(buffer),
              let description = CMSampleBufferGetFormatDescription(buffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let count = CMSampleBufferGetNumSamples(buffer)
        guard count > 0, format.commonFormat == .pcmFormatFloat32,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            deliver(.interrupted(.invalidAudio)); return
        }
        pcm.frameLength = AVAudioFrameCount(count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(buffer, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList)
        guard status == noErr, let pointers = pcm.floatChannelData else { deliver(.interrupted(.invalidAudio)); return }
        let channels = Int(format.channelCount)
        var samples = [Float](repeating: 0, count: count * channels)
        if format.isInterleaved {
            samples.withUnsafeMutableBufferPointer { $0.baseAddress!.update(from: pointers[0], count: count * channels) }
        } else {
            for frame in 0..<count { for channel in 0..<channels { samples[frame * channels + channel] = pointers[channel][frame] } }
        }
        deliver(.audio(.init(samples: samples, sampleRate: format.sampleRate, channels: channels, presentationSeconds: CMSampleBufferGetPresentationTimeStamp(buffer).seconds)))
    }
}
