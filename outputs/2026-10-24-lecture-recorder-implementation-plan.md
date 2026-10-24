# Lecture Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one free Mac application that records English lecture audio from Chrome and automatically creates a local transcript after Finish.

**Architecture:** A native SwiftUI menu-bar application coordinates ScreenCaptureKit, a recoverable segmented audio store, and WhisperKit. Capture and inference stay off the UI thread. All sessions and models live locally; the UI consumes explicit state and service interfaces.

**Tech Stack:** Swift, Swift Package Manager, SwiftUI/AppKit, ScreenCaptureKit, AVFoundation, Core ML through WhisperKit, Foundation, CryptoKit, XCTest, IOKit power assertions.

**Spec:** [Approved design](2026-10-12-lecture-recorder-design.md). Read it with this plan. This document supplies implementation decisions, not evidence that the application already works.

## Global Constraints

- “Target Apple Silicon and macOS 14 or later”; acceptance testing is on the user's M4 Pro, with 24 GiB RAM previously observed.
- “Version one allows one active recording or transcription job at a time.”
- “Persist mono 16 kHz, 16-bit PCM audio in segments of at most ten seconds.”
- “After 30 seconds without detected audio, show a nonblocking message to check playback; silence does not end the session.”
- “Transcript timestamps refer to the saved recording.”
- “Delete moves a session to the macOS Trash after confirmation and cannot run while that session is active.”
- “After model preparation, capture and transcription must work without network access.”
- Model: `openai_whisper-large-v3-v20240930_626MB`; English, transcription rather than translation.
- No paid SDK, inference API, account, microphone capture, saved screen video, external recorder, browser extension, or normal-use command line.
- Implement the agreed library, playback, search, rename, copy/export, recovery, and retry scope; exclude summaries, live captions, editing, and cloud sync.
- Local `.app` delivery, stable bundle identity and install location; public distribution is excluded.
- Run focused tests after each task; full checks at integration and packaging. Every task ends in a scoped commit.

## Review Focus

These five conditions require explicit tests beyond the normal happy path:

1. Chrome restarts and its process IDs change: re-resolve the source at Start and never capture an unrelated app. Task 1.
2. Capture produces no callbacks during a pause or starts late: preserve elapsed silence without inserting duplicate samples when callbacks resume. Task 3.
3. A crash occurs after an audio rename but before manifest replacement: recover the valid orphan segment exactly once. Task 2.
4. Model weights exist but tokenizer assets or preparation caches do not: never advertise offline readiness prematurely. Tasks 4–5.
5. Finish, cancellation, sleep, and late inference completion race: finalize once, keep saved audio, and prevent stale results from completing a different job. Task 6.

## Starting point and build decisions

The repository contains only the approved design and planning notes. There is no product code or existing test suite. No ancestor `AGENTS.md` was found in the inspected workspace path.

On 24 October, `xcrun swift --version` reported Swift 6.3.2. `xcode-select -p` points to `/Library/Developer/CommandLineTools`; `xcodebuild -version` fails because full Xcode is not selected. Neither `/Applications/Xcode.app` nor `/Applications/Xcode-beta.app` exists. Begin with SwiftPM and a scripted app bundle. Task 1 tests that route. If an actual compiler/framework requirement needs full Xcode, report that concrete prerequisite rather than claiming a successful build or silently installing it.

Use `swift-tools-version: 6.2`, Swift language mode 6, an arm64 deployment target of macOS 14, and three package targets: `LectureCore` library, `LectureRecorder` executable, and `LectureCoreTests`. The app imports the library; tests import the library. A bundling script packages the executable and resource bundles without depending on an Xcode project generator.

Fixed identity: bundle ID `local.ayush.LectureRecorder`, display name `Lecture Recorder`. Runtime root: `~/Library/Application Support/LectureRecorder`. Stage runnable builds at `outputs/Lecture Recorder.app`; do not test capture from randomly changing build folders. Do not overwrite an unrelated existing app at that path.

Verified upstream candidates:

- [Argmax OSS release v1.1.1](https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.1): pin the Swift package to exact `1.1.1`, use only its `WhisperKit` product, and commit `Package.resolved`. Compatibility is still to be tested; the release is not a successful-build claim.
- [Model repository](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482/openai_whisper-large-v3-v20240930_626MB): pin revision `0f63a7800b00dd0226abd051b906c246e1907482`. The chosen folder contains 17 files. Task 4 generates the exact artifact list, byte sizes, and SHA-256 hashes and pins the tokenizer assets required by this SDK. Do not treat the model-folder name as its complete download size.
- The [SDK configuration](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.1/Sources/WhisperKit/Core/Configurations.swift) exposes local model/tokenizer paths and a download flag. Local initialization must be verified on a fresh app-specific cache; disabling model download alone is not proof that tokenizer loading is offline.

No dependencies or model weights were installed during planning.

## File structure

All paths below are relative to the repository root. They describe future files; only the specification and this plan exist today.

| Files | Responsibility |
|---|---|
| `Package.swift`, `Package.resolved`, `.gitignore` | Targets, dependency pins, generated-file exclusions |
| `Sources/LectureCore/Capture/{CaptureTypes,ChromeCaptureService,BoundedAudioQueue}.swift` | Owned sample buffers, application filtering, bounded event delivery |
| `Sources/LectureCore/Storage/{Session,SessionStore,SessionRecovery}.swift` | Schema, atomic persistence, crash reconciliation |
| `Sources/LectureCore/Audio/{AudioTimeline,PCMConverter,SegmentWriter,AudioAssembler}.swift` | Clock mapping, conversion, durable WAV segments, continuous inference input |
| `Sources/LectureCore/Models/{ModelManifest,ModelManager}.swift` | Pinned artifacts and verified setup |
| `Sources/LectureCore/Transcription/{Transcript,TranscriptionService}.swift` | Timed text, local model adapter, cancellation |
| `Sources/LectureCore/Session/{SessionCoordinator,PowerAssertion,SessionLifecycle,RecordingPresentation}.swift` | Single-job orchestration, sleep/quit/recovery |
| `Sources/LectureCore/Library/{PlaybackService,TranscriptExport,LibraryModel}.swift` | Playback, search, rename, export, deletion |
| `Sources/LectureRecorder/{LectureRecorderApp,AppDelegate,AppDependencies}.swift` | App entry, lifetime, composition |
| `Sources/LectureRecorder/Views/{SetupView,RecordingMenuView,LibraryView,TranscriptView}.swift` | Small native views |
| `Sources/LectureCore/Resources/{model-manifest.json,ThirdPartyNotices.txt}` | Runtime resources packaged with the library |
| `Resources/Info.plist`, `scripts/{bundle-app,verify-bundle}.sh` | App metadata, packaging and inspection |
| `scripts/freeze-model.py`, `scripts/score-transcript.py` | Development-only reproducibility and evaluation utilities |
| `Tests/LectureCoreTests/*Tests.swift`, `Tests/LectureCoreTests/Support/{Fixtures,Fakes}.swift` | Focused tests with injectable clocks, IO and services |
| `docs/{BUILD,ACCEPTANCE}.md`, `outputs/lecture-recorder-validation.md` | Build instructions, repeatable acceptance procedure, measured results |

## Shared contract conventions

Define each type in its owning task, not in one growing global file. Value types crossing concurrency boundaries are `Sendable`; persisted values are `Codable`. Use actor-isolated service protocols, `@MainActor` UI state, and owned sample arrays instead of moving `CMSampleBuffer` across actors. A compile-time API skeleton may precede a failing behavioral test; missing infrastructure is not evidence of a behavioral failure.

`SessionID` is a typealias for `UUID`. Audio positions use integer 16 kHz frame counts internally; convert to `Double` seconds only at UI/SDK boundaries. A ten-second segment contains at most `160_000` frames. The session folder name is its UUID; user titles never become file paths.

Tests may define small local fixture constructors, but every production type/function used in a task must be implemented by that task or a listed prerequisite. Test commands below refer to XCTest class names.

## Task 1: Prove packaged Chrome audio capture

**Files:** Create `Package.swift`, `.gitignore`, the three Capture files, the three app entry files, `Resources/Info.plist`, `scripts/bundle-app.sh`, `Tests/LectureCoreTests/ChromeCaptureTests.swift`, and `docs/ACCEPTANCE.md`. Create `Support/Fakes.swift` for source enumeration and capture callbacks.

**Interfaces:** Produces `CapturedAudio(samples: [Float], sampleRate: Double, channels: Int, presentationSeconds: Double)` with interleaved samples; `CaptureFailure` with sourceMissing, permissionDenied, streamStopped, and overflow cases; `CaptureEvent.audio(CapturedAudio)` / `.interrupted(CaptureFailure)`; and `CaptureOrigin(hostSeconds: Double)`. Define `CaptureService.start(onEvent: @escaping @Sendable (CaptureEvent) -> Void) async throws -> CaptureOrigin` and `stop() async`. `ChromeCaptureService` implements it. `BoundedAudioQueue.enqueue(_ event: CaptureEvent) -> Bool` refuses excess data instead of dropping it silently.

- [ ] **1. Add capture selection and overflow tests.** With an injected application list, `testResolvesNewChromeProcessOnEveryStart` asserts `XCTAssertEqual(selectedIDs, [101, 202])` across a simulated restart; no Chrome yields `sourceMissing`. `testOverflowIsExplicit` asserts the first over-capacity enqueue is false and exactly one overflow interruption is delivered. Set capacity to two seconds of input audio, counted by sample duration rather than callback count.
- [ ] **2. Run red:** `swift test --filter ChromeCaptureTests`. Confirm failures identify the missing selection/overflow behavior after package scaffolding builds.
- [ ] **3. Implement the capture service and minimal bundled app.** Enumerate shareable content at each Start, use ScreenCaptureKit application filtering for Chrome, capture audio, and attach only an audio output. Keep any framework-required display configuration internal; save no video. Copy samples on a dedicated capture queue, map timestamps to the host clock, and propagate errors. The temporary diagnostic UI supplies Start/Stop and audio levels and writes a short diagnostic WAV under `work/capture-check/`; it is replaced by Task 7. Bundle an arm64 binary with stable identity and local ad-hoc signing. Exclude generated builds, runtime recordings, `work/`, and model weights from Git.
- [ ] **4. Run green and real capture:** `swift test --filter ChromeCaptureTests`, then `bash scripts/bundle-app.sh debug`. Launch `outputs/Lecture Recorder.app`. With the user operating any OS permission prompt and lecture playback, record two minutes with headphones, Chrome fullscreen, and the app window closed. Play the saved WAV. Play a distinguishable sound in a different app and verify exclusion; verify the microphone is absent. If Chrome helper processes require explicit inclusion, constrain them to Chrome and repeat the exclusion check. No whole-system-audio fallback. Record results in `docs/ACCEPTANCE.md`; do not proceed past this gate on a silent or mixed-source capture.
- [ ] **5. Commit the listed source/tests/scripts/docs only:** `git commit -m "feat: verify packaged Chrome audio capture"`. Record any real toolchain prerequisite before continuing.

## Task 2: Persist sessions and recover committed segments

**Files:** Create the three Storage files, `Support/Fixtures.swift`, `SessionStoreTests.swift`, and `SessionRecoveryTests.swift` under `Tests/LectureCoreTests`.

**Interfaces:** Define `SessionState` cases starting, recording, finalizing, recorded, transcribing, complete, interrupted, transcriptionFailed. `AudioSegment` contains index, relativePath, startFrame, and frameCount. `Session` contains id, schemaVersion=1, title, createdAt, timeZoneID, sourceBundleID, state, segments, capturedFrames, modelIdentity (optional String), and interruptionReason (optional String). `SessionStore` is an actor with `init(root: URL)`, `create(now: Date, timeZone: TimeZone) throws -> Session`, `load(_ id: SessionID) throws -> Session`, `save(_ session: Session) throws`, `list() throws -> [Session]`, `folder(for id: SessionID) -> URL`, and `recover() throws -> [Session]`.

- [ ] **1. Add persistence tests.** `testRoundTripAndOrdering` asserts a saved session reloads exactly and newer sessions sort first. `testOrphanRecoveryIsIdempotent` creates valid segment 0 plus an unlisted finalized segment 1 and asserts recovered indices equal `[0, 1]` after both first and second recovery. `testCorruptTempIsNotAudio` asserts an unfinished WAV is not added. `testFailedManifestReplacementPreservesPrevious` injects a rename error and checks the original file remains decodable. `testUnknownSchemaDoesNotOverwrite` preserves unsupported data and reports a recoverable library error.
- [ ] **2. Run red:** `swift test --filter 'SessionStoreTests|SessionRecoveryTests'`.
- [ ] **3. Implement atomic JSON replacement and recovery.** Use temporary files in the destination directory, finalized filenames encoding segment index/start frame, WAV header validation, and session-level error isolation. Do not infer missing audio as successfully recorded. Interrupted capture/finalization becomes interrupted; interrupted inference becomes recorded for retry. Titles use local date/time, independently of immutable UUID paths. Skip a corrupt session with a visible library error while continuing to load other sessions.
- [ ] **4. Run green:** repeat the focused command. Verify two sequential recovery passes produce identical manifests and that a missing middle segment records an interruption rather than silently shifting later timestamps.
- [ ] **5. Commit:** `git commit -m "feat: persist and recover lecture sessions"` after staging this task's files.

## Task 3: Write continuous, recoverable audio

**Files:** Create the four Audio files and `AudioTimelineTests.swift`, `SegmentWriterTests.swift`, `AudioAssemblerTests.swift`; extend Fixtures and Capture wiring.

**Interfaces:** `AudioTimeline` maps CaptureOrigin and sample presentation times to integer output frames. Define `WriterEvent.progress(committedFrames: Int64, audioLevel: Float, lastAudibleHostSeconds: Double?)` and `.failed(message: String)`. `SegmentWriter.begin(session: Session, origin: CaptureOrigin, onEvent: @escaping @Sendable (WriterEvent) -> Void) async throws`; `accept(_ event: CaptureEvent) -> Bool` is a nonblocking, thread-safe enqueue; `finish(atHostSeconds: Double) async throws -> Session` drains once and commits the tail. Its async worker consumes the bounded queue and uses SessionStore. `AudioAssembler.assemble(_ session: Session, at folder: URL) async throws -> URL` creates a temporary continuous WAV. `PCMConverter` owns one streaming AVAudioConverter per input format, preserving state.

- [ ] **1. Add sample-based tests.** `testSplitsAt160000Frames` supplies 352,000 output frames and asserts segment counts `[160_000, 160_000, 32_000]`. `testLateStartAndPauseKeepTime` simulates two seconds of leading silence, five seconds of speech, and a three-second callback gap and asserts `XCTAssertEqual(totalFrames, 160_000)`. `testResumeDoesNotDuplicateClockFilledSilence` asserts the same timeline after delayed callbacks. Test 44.1/48 kHz stereo conversion across arbitrary callback boundaries, format changes, overlaps, final tail, and injected write failure. `testAssemblyPreservesSegmentSamples` compares the assembled samples with expected concatenation, including silence.
- [ ] **2. Run red:** `swift test --filter 'AudioTimelineTests|SegmentWriterTests|AudioAssemblerTests'`.
- [ ] **3. Implement WAV persistence and clock reconciliation.** Write little-endian mono signed-16 PCM. Rotate at 160,000 frames and finalize before adding to the manifest. Use a monotonic clock watermark with a 500 ms reorder allowance to materialize pauses even when no audio callbacks arrive; trim duplicate overlap on resumption. If late non-silent audio would replace silence already committed beyond that allowance, report an interrupted recording rather than silently losing speech; add `testLateSpeechIsAnExplicitInterruption`. Emit writer failures immediately so the coordinator stops capture, even before Finish. Drain callbacks on Finish before committing the final watermark. A detected sleep/stream failure ends capture instead of filling the suspended interval. Bound queued audio to two seconds; overflow or disk failure interrupts. Inspect free capacity before capture/assembly and handle actual IO failures throughout. Assemble with streaming reads; retain original segments after temporary-file failure.
- [ ] **4. Run green:** repeat focused tests, then replay the Task 1 recording through this writer. Verify sample continuity across a ten-second boundary and preservation of a playback pause. Disk-error tests must leave prior finalized WAVs playable.
- [ ] **5. Commit:** `git commit -m "feat: save recoverable continuous lecture audio"` after staging the task files.

## Task 4: Install and verify the complete local model

**Files:** Modify `Package.swift`; create `Package.resolved`, both Models files, both library Resources files, `scripts/freeze-model.py`, and `ModelManagerTests.swift`.

**Interfaces:** `ModelManifest` contains modelIdentity, sdkVersion, modelRevision, tokenizerRevision, and artifacts (relativePath, immutableURL, byteCount, sha256). `ModelLocation` contains modelFolder and tokenizerFolder URLs plus identity. `ModelSetupProgress` is downloading(completedBytes,totalBytes), preparing, or ready. Actor protocol `ModelManaging` exposes `prepare(progress: @escaping @Sendable (ModelSetupProgress) -> Void) async throws -> ModelLocation` and `installed() async throws -> ModelLocation?`; `ModelManager` implements it using injected download/file clients.

- [ ] **1. Add setup tests.** `testIncompleteTokenizerIsNotReady` asserts `let installed = try await manager.installed(); XCTAssertNil(installed)` when model files exist without required tokenizer files. `testHashMismatchNeverPromotesDownload` checks no ready directory appears. `testRetryKeepsVerifiedArtifacts` checks already verified files are not downloaded twice. `testInstalledLookupMakesNoNetworkCalls` asserts the fake downloader's request count remains zero. Test unavailable network and insufficient space with existing sessions untouched.
- [ ] **2. Resolve the exact SDK and run red:** `swift package resolve`, then `swift test --filter ModelManagerTests`. If the pinned release cannot compile, record the compiler evidence and select a verified compatible pin; never silently use a floating branch.
- [ ] **3. Implement setup and freeze its assets.** Fetch only the chosen model folder at the recorded revision. Inspect this SDK's tokenizer resolution, identify its required repository/files, resolve that repository to an immutable revision, and record its files and hashes alongside the model. `python3 scripts/freeze-model.py` writes `Sources/LectureCore/Resources/model-manifest.json` from verified downloads in `work/model-freeze/`; it does not put weights in Git. Download into staging, verify sizes/hashes, promote atomically, and initialize once using explicit local model/tokenizer folders and model downloading disabled. The app must not depend on the developer's global Hugging Face cache. Include SDK/model/tokenizer license notices.
- [ ] **4. Run green and compatibility check:** `swift test --filter ModelManagerTests`; load and prepare the real model from an isolated application storage root. Record the generated tokenizer revision and the resolved package commit in `docs/ACCEPTANCE.md`. Readiness requires successful preparation with all required artifacts present. Keep percentage based on known bytes; use an indeterminate Preparing stage.
- [ ] **5. Commit:** `git commit -m "feat: prepare a pinned offline transcription model"`, including manifest and dependency lock, excluding weights and caches.

## Task 5: Transcribe saved audio with correct timestamps

**Files:** Create both Transcription files and `TranscriptionServiceTests.swift`; extend integration fixtures and model setup checks.

**Interfaces:** `TranscriptSegment(startSeconds: Double, endSeconds: Double, text: String)`; `Transcript(modelIdentity: String, segments: [TranscriptSegment], noSpeech: Bool)`. `TranscriptionProgress` is preparing or processing(fraction: Double?). Protocol `Transcribing.run(audioURL: URL, model: ModelLocation, progress: @escaping @Sendable (TranscriptionProgress) -> Void) async throws -> Transcript`; cancellation uses Swift Task cancellation. `TranscriptionService` implements the protocol with an injected decoder adapter for tests. Inference returns values; it does not save session state.

- [ ] **1. Add decoder-boundary tests.** `testEnglishTranscriptionOptions` asserts language `en` and task transcribe. `testSilenceOffsetsRemainInOriginalTimeline` checks speech after a 12-second pause starts at or after 12 seconds. `testCancellationDoesNotReturnCompletedTranscript` expects CancellationError. `testSilenceReturnsNoSpeech` asserts empty segments and `noSpeech == true`. Reject NaN, negative, backward, and beyond-duration timestamps; cap only sub-frame rounding error, not arbitrary bad output.
- [ ] **2. Run red:** `swift test --filter TranscriptionServiceTests`.
- [ ] **3. Implement the local WhisperKit adapter.** Configure the supplied local folders, English decoding, speech/no-speech handling, and incremental input loading. Use continuous assembled audio, with speech detection preserving original offsets. Run one inference worker off the main actor. Honor cancellation before starting and inside supported decoding callbacks; wait for the worker to stop before releasing its slot. Do not report completion from a late callback. Use no text-generating postprocessor. Expose measured progress where available and an indeterminate state otherwise.
- [ ] **4. Run green and real-engine checks:** repeat the focused command, then test speech, pauses, silence, and a short music fixture using the pinned model. Warm setup in an isolated cache, deny network for the test process, then cold-launch transcription from that cache. Verify neither model nor tokenizer attempts remote resolution. A missing artifact must produce a setup/repair error, not a download during inference. Save measured results without claiming fixture accuracy represents every lecture.
- [ ] **5. Commit:** `git commit -m "feat: transcribe recordings locally with timed text"` after staging the task files.

## Task 6: Coordinate recording, retry, cancellation, and interruption

**Files:** Create all three Session files, `SessionCoordinatorTests.swift`, and `SessionLifecycleTests.swift`; extend Fakes and app dependency wiring.

**Interfaces:** `@MainActor @Observable SessionCoordinator` exposes `activeSession: Session?`, `phase: SessionState?`, `errorMessage: String?`, `elapsedSeconds: Double`, `audioLevel: Float`, and `progress: TranscriptionProgress?`; actions `start() async`, `finish() async`, `cancelTranscription() async`, `transcribe(_ id: SessionID) async`, `interrupt(reason: String) async`, and `restore() async`. Dependencies use CaptureService, SegmentWriter, SessionStore, ModelManaging, and Transcribing. `PowerAssertion.acquire() throws` and `release()` are idempotent. `SessionLifecycle` converts sleep/wake and quit events into coordinator actions.

- [ ] **1. Add race/state tests.** `testFinishTwiceFinalizesOnce` asserts writer finalize count and inference count are both 1. `testSavedAudioPrecedesInference` asserts the recording is readable before the fake decoder is entered. `testCancelledLateCompletionCannotCommit` asserts state remains recorded and no transcript is written. `testSleepEndsRecordingWithoutAutoRestart` asserts interrupted and zero new capture starts on wake. Add `testEarlyCaptureBuffersReachWriter` asserting first samples survive callbacks arriving before writer initialization. Test revoked permission, Chrome exit, write/inference errors, a second Start while busy, recovery without auto-transcribe, and power assertion release on every terminal path.
- [ ] **2. Run red:** `swift test --filter 'SessionCoordinatorTests|SessionLifecycleTests'`.
- [ ] **3. Implement orchestration.** Serialize user actions and retain one operation ID plus one inference task; ignore stale completions. Stage early callbacks in the same bounded two-second queue until the returned CaptureOrigin initializes the writer, then drain it in order. Subscribe to WriterEvent for immediate disk/queue failures and audio-level updates. Persist the finalized recording before assembly/inference. Commit transcript atomically before setting complete; reconcile a crash between those writes on restart. Cancellation retains source audio, removes only job temporary files, and returns to recorded after inference stops. Preserve capture interruption metadata when transcribing a partial session. Interruption stops at the last valid capture boundary, not wake time. Acquire/release idle-sleep assertions with structured cleanup. Delete and new-job actions must consult the same active-session guard.
- [ ] **4. Run green:** repeat focused tests, then `swift test`. Drive a short packaged Start/Finish and an inference cancellation through the diagnostic interface. Confirm no false complete state and no duplicate jobs.
- [ ] **5. Commit:** `git commit -m "feat: coordinate safe lecture session lifecycle"` after staging task files.

## Task 7: Finish setup and menu-bar controls

**Files:** Create `Sources/LectureRecorder/Views/SetupView.swift`, `Sources/LectureRecorder/Views/RecordingMenuView.swift`, `Sources/LectureCore/Session/RecordingPresentation.swift`, and `Tests/LectureCoreTests/RecordingPresentationTests.swift`; modify app entry/dependencies and replace the Task 1 diagnostic interface.

**Interfaces:** Views receive SessionCoordinator and ModelManaging through app composition. Define `RecordingPresentation` in `Sources/LectureCore/Session/RecordingPresentation.swift`, with `primaryTitle: String`, `canStart: Bool`, `canFinish: Bool`, and `quietHintVisible: Bool`, derived from setup status, phase, and last audio time. AppDelegate handles explicit quit; closing a window does not terminate the process.

- [ ] **1. Add presentation tests in the core target.** `testNoFinishBeforeCaptureStarts` asserts false while starting. `testQuietHintAtThirtySeconds` asserts false at 29.9 and true at 30.0 without changing recording state. `testBusyDisablesStart` covers finalizing/transcribing. `testSetupRequiredBlocksStart` covers permission denied and unavailable model. Use an injected clock, not real sleeps.
- [ ] **2. Run red:** `swift test --filter RecordingPresentationTests`.
- [ ] **3. Implement setup and controls.** Use SwiftUI MenuBarExtra with Setup, Start recording/Finish, timer, meter, stage, Cancel/Retry, Open Library, and Quit. Show Chrome-only capture and timestamp semantics briefly during setup. Permission failures provide System Settings guidance without repeatedly prompting. For explicit Quit during work, offer Keep Working or Stop and Quit; the latter finalizes recording without launching inference or cancels inference and waits for safe cleanup. Do not request notification or microphone permissions. Surface processing completion in the app/library.
- [ ] **4. Run green and UI check:** `swift test --filter RecordingPresentationTests`, then `bash scripts/bundle-app.sh debug`. Verify first-run setup, normal repeat launch, denied permissions, quiet audio, background capture, and closing/reopening the library. Check keyboard access, accessible button labels, and readable status at increased text size. Progress must not freeze the UI.
- [ ] **5. Commit:** `git commit -m "feat: add one-button lecture recording controls"` after staging task files.

## Task 8: Add the lecture library, playback, and export

**Files:** Create all three Library files, `Views/LibraryView.swift`, `Views/TranscriptView.swift`, and `LibraryTests.swift`, `PlaybackServiceTests.swift`, `TranscriptExportTests.swift`; extend SessionStore with rename/trash support.

**Interfaces:** `@MainActor LibraryModel` exposes sessions, selectedSessionID, titleQuery, transcriptQuery, and library errors; methods `reload() async`, `rename(_ id: SessionID, title: String) async throws`, `trash(_ id: SessionID) async throws`. `SessionStore.rename(_ id: SessionID, title: String) throws` / `trash(_ id: SessionID) throws`. `PlaybackService.load(session: Session, folder: URL) async throws`, `play()`, `pause()`, `seek(to seconds: Double)` and read-only position/duration. `TranscriptExport.text(session: Session, transcript: Transcript) -> String` is pure.

- [ ] **1. Add library/playback/export tests.** A title containing `/` or Unicode changes metadata only. Search matches case-insensitively and clearing filters restores results. Active deletion is rejected; inactive deletion invokes an injected Trash operation. For segments [0–10,10–20], seek 12 maps to segment 1 at offset 2 and seek 10 maps to segment 1 at 0. Test the final position and non-finite seek rejection. Export asserts `XCTAssertTrue(text.contains("01:02:03"))` for a 3,723-second segment and includes title/date and complete Unicode text.
- [ ] **2. Run red:** `swift test --filter 'LibraryTests|PlaybackServiceTests|TranscriptExportTests'`.
- [ ] **3. Implement the library.** Newest-first list, rename, title search, within-transcript search, timed segment list, play/pause/seek, click-to-seek, copy, and Save Panel text export. Use AVFoundation to play ordered segments as a continuous timeline using manifest offsets. Keep the source audio intact. Gate deletion using coordinator state immediately before moving to Trash. Surface corrupt-session and missing-audio errors without breaking other rows. Default export filenames are sanitized independently of display titles; confirm overwrite through the Save Panel.
- [ ] **4. Run green:** repeat focused tests. In the bundled app reopen two sessions, search, rename, seek across a segment boundary and into silence, copy/export, and delete an inactive session. Verify content persists after relaunch.
- [ ] **5. Commit:** `git commit -m "feat: browse play and export lecture transcripts"` after staging task files.

## Task 9: Verify the standalone app bundle

**Files:** Modify `scripts/bundle-app.sh`, `Resources/Info.plist`, app resource access, and notices; create `scripts/verify-bundle.sh` and `docs/BUILD.md`.

**Interfaces:** `bash scripts/bundle-app.sh debug|release` builds and stages `outputs/Lecture Recorder.app`. `bash scripts/verify-bundle.sh [app-path]` defaults to the staged output app and exits zero only when bundle structure, arm64 architecture, embedded dependency paths/resources, and local signature checks pass.

- [ ] **1. Add bundle checks:** verify executable/Info.plist identity and minimum OS, model manifest and notices, required SwiftPM resource bundles, `codesign --verify --strict`, and `otool -L` dependencies without build-directory or Homebrew paths. Missing resources must fail rather than produce a seemingly valid app.
- [ ] **2. Run red:** copy the app to `work/bundle-negative/Lecture Recorder.app`, remove a required resource only from that copy, and run `bash scripts/verify-bundle.sh "work/bundle-negative/Lecture Recorder.app"`; expect nonzero with that resource named. Never damage the working signed app to test this.
- [ ] **3. Complete release packaging.** Use `swift build -c release --product LectureRecorder`; copy package resource bundles, preserve their expected lookup layout, then ad-hoc sign after all copies. Include usage descriptions required by the selected capture APIs and no unrelated permissions. BUILD.md records exact build command, tested toolchain, stable app location, free operation, and model download behavior. Keep binary delivery in outputs and source under version control; no release upload or public publication.
- [ ] **4. Run green:** `bash scripts/bundle-app.sh release && bash scripts/verify-bundle.sh`. Launch the release bundle from its stable path with a clean app-specific setup root, not the IDE or source checkout. Complete setup, restart offline, and perform a short local-video recording/transcription/export. Confirm the app survives closing its window and no external runtime is needed. Record any unverified platform variants explicitly.
- [ ] **5. Commit:** `git commit -m "build: package standalone lecture recorder for macOS"`, excluding the binary and downloaded model files.

## Task 10: Run end-to-end acceptance and document evidence

**Files:** Complete `docs/ACCEPTANCE.md`; create `scripts/score-transcript.py`, `Tests/Evaluation/test_score_transcript.py`, and `outputs/lecture-recorder-validation.md`. Fix defects in their owning files with focused regression tests.

**Interfaces:** `python3 scripts/score-transcript.py reference.txt hypothesis.txt` prints reference word count, substitutions/deletions/insertions, and WER. Normalize Unicode, case, and punctuation consistently; an empty reference reports undefined WER, not zero. This utility is development-only and is not shipped as an app dependency.

- [ ] **1. Test the evaluation utility:** use `unittest`; assert WER 0 for identical normalized text, 0.25 for one substitution in four reference words, and undefined for an empty reference. Run `python3 -m unittest discover -s Tests/Evaluation -v`, observe the intended failure, implement word-level edit distance, and rerun to pass.
- [ ] **2. Execute the real acceptance matrix:** two-minute actual Chrome/Panopto capture; two-hour marked playback with pauses; a ten-minute representative English lecture with manually checked reference; offline cold launch; force-quit around segment/manifest/transcript commits; Chrome exit; permission revocation; disk-error injection; cancellation/retry; explicit sleep/lid interruption; quiet and music audio; library/export/deletion after restart. Use an app-scoped denied-network test environment or a user-controlled offline period rather than changing the Mac's global networking silently. Real media and reference transcripts stay under `work/acceptance/`, outside Git.
- [ ] **3. Record measurements and outcomes:** every row is Pass, Fail, or Not Run with evidence. Include recording duration, RAM/CPU/disk measurements, inference time, timestamp spot checks, WER target ≤15%, technical-term errors, capture source isolation, recovery loss, and packaged/offline status. For the two-hour check, sample process RSS periodically; distinguish a fixed model allocation from memory growth proportional to recording length. Do not substitute a sped-up fixture for the real-duration capture. If a needed lecture, permission prompt, or lid action is unavailable, mark that row Not Run and state the user action needed; do not call acceptance complete.
- [ ] **4. Resolve failures and verify:** run the owning task's tests after each fix. When fixes settle, run `swift test`, the Python evaluation tests, and the release bundle verifier. Retest affected acceptance rows. If the model fails the agreed quality threshold, document the result and revise the model choice with a new measured comparison before claiming readiness. No silent cloud fallback.
- [ ] **5. Commit the report and any scoped fixes:** `git commit -m "test: document lecture recorder acceptance results"`. Deliver the `.app`, source, build guide, and validation report with remaining limitations explicit.

## Order, review, and execution handoff

Execute Tasks 1–10 in order. Task 1 is the capture feasibility checkpoint; Tasks 4–5 establish actual offline inference before UI completion. The remaining work integrates shared state and persistence, so avoid concurrent edits across those interfaces. Do not spawn implementation agents before the user chooses an execution method.

Spec coverage: purpose/scope → Tasks 1, 6–8; architecture → Tasks 1–6; storage/timestamps → Tasks 2–3, 5, 8; interruption handling → Tasks 2, 3, 6–7; packaging/free operation → Tasks 4–5, 9; all acceptance criteria → Task 10. Every Review Focus item has an owning test above.

Plan self-review: scoped task outputs and test cycles checked; cross-task names/signatures reconciled; fixed values carried over; source paths mapped; no product code or installation performed. Exact artifact hashes and tokenizer revision are generated and committed by Task 4 because their integrity depends on the downloaded bytes, not guesses in this document.

Recommended execution method: **Native**—one implementer works through these tightly connected capture/storage/state interfaces, followed by an independent whole-branch review. **Subagent-driven** adds a fresh implementer and reviewer for each task, at greater context cost. The user must review this plan and select a method before implementation begins.
