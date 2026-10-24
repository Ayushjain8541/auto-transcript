import Foundation
import LectureCore

@MainActor func registerCaptureTests() {
    Checks.add("ChromeCaptureTests.resolvesNewChromeProcessOnEveryStart") {
        let first = try ChromeSourceResolver.select(from: [.init(processID: 101, bundleID: "com.google.Chrome"), .init(processID: 9, bundleID: "com.apple.Safari")])
        let second = try ChromeSourceResolver.select(from: [.init(processID: 202, bundleID: "com.google.Chrome")])
        try expect(first.map(\.processID) + second.map(\.processID) == [101, 202], "Must select current Chrome PID")
    }
    Checks.add("ChromeCaptureTests.noChromeIsAnError") {
        try expectThrows({ _ = try ChromeSourceResolver.select(from: [.init(processID: 3, bundleID: "com.google.Chrome.canary")]) }, { $0 as? CaptureFailure == .sourceMissing })
    }
    Checks.add("ChromeCaptureTests.onlyChromeAndHelpers") {
        let result = try ChromeSourceResolver.select(from: [.init(processID: 1, bundleID: "com.google.Chrome"), .init(processID: 2, bundleID: "com.google.Chrome.helper.renderer"), .init(processID: 3, bundleID: "com.google.ChromeOther")])
        try expect(result.map(\.processID) == [1, 2])
    }
    Checks.add("ChromeCaptureTests.overflowIsExplicit") {
        let queue = BoundedAudioQueue(capacitySeconds: 2)
        let audio = CapturedAudio(samples: Array(repeating: 0.5, count: 16_000), sampleRate: 16_000, channels: 1, presentationSeconds: 0)
        try expect(queue.enqueue(.audio(audio)))
        try expect(queue.enqueue(.audio(audio)))
        try expect(!queue.enqueue(.audio(audio)))
        try expect(!queue.enqueue(.audio(audio)))
        var audioCount = 0; var errors: [CaptureFailure] = []
        while let event = queue.dequeue() {
            switch event { case .audio: audioCount += 1; case .interrupted(let error): errors.append(error) }
        }
        try expect(audioCount == 2); try expect(errors == [.overflow])
    }
}
