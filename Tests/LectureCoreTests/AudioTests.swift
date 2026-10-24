import Foundation
import AVFoundation
import LectureCore

@MainActor func registerAudioTests() {
    Checks.add("AudioTimelineTests.leadingSilenceAndPauseKeepTime") {
        var timeline = AudioTimeline()
        let a = try timeline.append(Array(repeating: 0.5, count: 32_000), atFrame: 32_000)
        let b = try timeline.append(Array(repeating: 0.5, count: 48_000), atFrame: 112_000)
        try expect(timeline.frameCount == 160_000)
        try expect(a.count + b.count == 160_000)
        try expect(a.prefix(32_000).allSatisfy { $0 == 0 })
        try expect(b.prefix(48_000).allSatisfy { $0 == 0 })
    }
    Checks.add("AudioTimelineTests.resumeDoesNotDuplicateSilence") {
        var timeline = AudioTimeline()
        _ = timeline.silence(untilFrame: 32_000)
        let added = try timeline.append(Array(repeating: 0, count: 48_000), atFrame: 0)
        try expect(added.count == 16_000); try expect(timeline.frameCount == 48_000)
    }
    Checks.add("AudioTimelineTests.lateSpeechIsExplicitInterruption") {
        var timeline = AudioTimeline(); _ = timeline.silence(untilFrame: 32_000)
        try expectThrows { _ = try timeline.append([0.5, 0.5], atFrame: 0) }
    }
    Checks.add("PCMConverterTests.resamplesAcrossCallbackBoundaries") {
        for rate in [44_100, 48_000] {
            let converter = PCMConverter(); var output: [Float] = []
            var offset = 0
            while offset < rate {
                let count = min(713, rate-offset)
                output += try converter.convert(.init(samples: Array(repeating: 0.25, count: count*2), sampleRate: Double(rate), channels: 2, presentationSeconds: Double(offset)/Double(rate))).flatMap(\.samples)
                offset += count
            }
            let tail = try converter.finish().flatMap(\.samples)
            output += tail
            try expect(abs(output.count-16_000) <= 1, "Expected one second after resampling, got \(output.count)")
            try expect(output.dropFirst(100).dropLast(100).allSatisfy { abs($0-0.25)<0.01 })
        }
    }
    Checks.add("SegmentWriterTests.splitsAt160000FramesAndCommitsTail") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        let session = try await store.create()
        let writer = SegmentWriter(store: store, clock: { 0 })
        try await writer.begin(session: session, origin: .init(hostSeconds: 0), onEvent: { _ in })
        // Feed at most one second at a time and let the bounded worker drain.
        for second in 0..<22 {
            try expect(writer.accept(.audio(.init(samples: Array(repeating: 0.25, count: 16_000), sampleRate: 16_000, channels: 1, presentationSeconds: Double(second)))))
            try await Task.sleep(for: .milliseconds(15))
        }
        let saved = try await writer.finish(atHostSeconds: 22)
        try expect(saved.segments.map(\.frameCount) == [160_000, 160_000, 32_000])
        let folder = await store.folder(for: saved.id)
        let url = try await AudioAssembler.assemble(saved, at: folder)
        let file = try AVAudioFile(forReading: url)
        try expect(file.length == 352_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 352_000)!
        try file.read(into: buffer)
        try expect(abs(buffer.floatChannelData![0][160_000]-0.25)<0.001)
    }
    Checks.add("SegmentWriterTests.diskFailurePreservesEarlierSegments") {
        let temp = try TemporaryDirectory(); defer { temp.remove() }
        let store = SessionStore(root: temp.url)
        let session = try await store.create()
        let folder = await store.folder(for: session.id)
        try makeWAV(at: folder.appendingPathComponent("audio/0-0.wav"), frames: 160_000)
        let failing = SessionStore(root: temp.url, writeData: { _,_ in throw CocoaError(.fileWriteOutOfSpace) })
        let writer = SegmentWriter(store: failing, clock: { 0 })
        do { try await writer.begin(session: session, origin: .init(hostSeconds: 0), onEvent: { _ in }); throw CheckFailure(description: "Expected failure") }
        catch let error as CocoaError { try expect(error.code == .fileWriteOutOfSpace) }
        let recovered = try await store.recover(); try expect(recovered[0].segments.count == 1)
    }
}
