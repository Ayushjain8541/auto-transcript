import LectureCore
@MainActor func registerPresentationTests() {
    Checks.add("Presentation disables unavailable and busy actions") {
        for phase in [SessionState.starting, .finalizing, .transcribing] {
            let state = RecordingPresentation(modelReady: true, permissionGranted: true, phase: phase, lastAudio: nil, startedAt: nil, now: 0)
            try expect(!state.canStart && !state.canFinish)
        }
        for (model, permission) in [(false, true), (true, false)] {
            try expect(!RecordingPresentation(modelReady: model, permissionGranted: permission, phase: nil, lastAudio: nil, startedAt: nil, now: 0).canStart)
        }
    }
    Checks.add("Presentation quiet hint at thirty seconds only") {
        for elapsed in [29.9, 30.0] {
            let state = RecordingPresentation(modelReady: true, permissionGranted: true, phase: .recording, lastAudio: nil, startedAt: 100, now: 100 + elapsed)
            try expect(state.quietHintVisible == (elapsed >= 30))
            try expect(state.canFinish && !state.canStart)
        }
    }
}
