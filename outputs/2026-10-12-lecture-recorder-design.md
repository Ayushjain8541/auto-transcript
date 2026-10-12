# Local lecture recorder for Mac — design specification

Date: 12 October 2026  
Status: Agreed conversational design; written specification awaiting user review.  
Working name: Lecture Recorder

## 1. Purpose and success

Build one application for watching a lecture in Chrome, recording its audio in the background, and automatically producing an English transcript after the user finishes. Normal use is **Start recording → watch → Finish → read transcript**. No terminal commands, audio exports between applications, subscriptions, API keys, or transcription fees are required.

The user confirmed an M4 Pro Mac, English lectures, Chrome, and no need to play other Chrome-tab audio during recording. A read-only machine check found 24 GiB RAM and macOS 26.6.2. The initial distribution target is personal use on this Mac. Public distribution is outside this version.

Success means a complete lecture can be captured while listening through headphones, safely saved, transcribed locally, reopened after an app restart, and copied or exported as timestamped text. Transcript accuracy and processing speed must be measured on lecture audio; neither is assumed from hardware alone.

## 2. Scope

Included:

- First-run capture permission guidance and automatic model download.
- Menu-bar recording controls, elapsed time, audio-level indicator, and processing status.
- Chrome application audio capture, with no microphone or saved screen video.
- Automatic transcription after a normal Finish action.
- Local lecture library with rename, title search, transcript text search, playback, copy, text export, and deletion.
- Recording recovery, transcription cancellation, and retry from saved audio.
- Prevention of idle sleep during active work and explicit handling of interruptions.

Excluded: live captions, lecture summaries, chat, speaker identification, cloud sync, accounts, automatic lecture-title extraction, tab isolation, browser extensions, video downloads, scheduled recording, and subtitle export. Playback speed and seeking remain Chrome/Panopto controls; the app transcribes what was actually played.

## 3. Chosen approach

Use a native SwiftUI application with a small AppKit integration layer where necessary, ScreenCaptureKit for capture, AVFoundation for audio conversion and playback, and the free open-source WhisperKit library for transcription. Target Apple Silicon and macOS 14 or later; acceptance testing is on the user's current Mac, without claiming testing on every supported OS.

WhisperKit provides on-device transcription as a Swift library and documents incremental loading for long audio. Its upstream package currently also contains unrelated speech products; depend only on WhisperKit. The selected first-version model is its compressed Large-v3 Turbo variant, `openai_whisper-large-v3-v20240930_626MB`, with language explicitly set to English and translation disabled. [WhisperKit documentation](https://github.com/argmaxinc/argmax-oss-swift)

This model choice is an engineering default, subject to the lecture-quality acceptance test below. A smaller English-only model is not assumed to be more accurate merely because lectures are in English. Freeze the tested SDK version, model revision, and artifact integrity metadata during implementation; do not resolve a moving model revision on each launch.

The alternative considered was SwiftUI with whisper.cpp, which supports Apple Silicon acceleration but requires additional Swift/C++ integration. It remains a replacement option if the selected engine fails validation, rather than a second engine to ship in version one. [whisper.cpp](https://github.com/ggml-org/whisper.cpp)

ScreenCaptureKit supplies application filtering and audio capture. Actual Chrome capture, including renderer/helper process behavior, must pass an early on-device test before building the full interface. [Apple capture documentation](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)

## 4. User experience

### First launch

Explain that the app captures Chrome audio. Guide the user through the macOS capture permission flow and show whether permission is available. Download the chosen model into local application storage, show progress, and provide Retry if interrupted. Validate and load the model once before declaring setup complete. Recording becomes available once setup passes.

Chrome is the saved source choice. Resolve the current Chrome process when starting each recording; do not persist a process ID. If Chrome is closed, show a clear instruction to open it. Other Chrome windows, profiles, and tabs may contribute audio; the setup explains that these should stay quiet.

### Recording

The primary control changes from **Start recording** to **Finish** only after capture starts successfully. Show elapsed recording time and audio levels. After 30 seconds without detected audio, show a nonblocking message to check playback; silence does not end the session.

The application remains active when its library window closes. Recording continues while Chrome is fullscreen or the app is in the background. It never starts merely because Chrome opens.

### Finish and transcription

Finish stops capture, finalizes recoverable audio and metadata, and starts transcription automatically. Show the processing stage and Cancel. Show percentage only when it reflects measured progress; do not invent an estimated completion time.

Version one allows one active recording or transcription job at a time. Start is unavailable during transcription; cancelling the current job preserves its audio and makes recording available again. A failed job has Retry. Closing the library window does not cancel work; explicit Quit during active work offers a clear choice to keep working or stop safely.

### Library and transcript

List sessions newest first with title, date, duration, and status. Default titles use local recording date and time and can be renamed. Show timestamped transcript segments and allow clicking a segment to seek to that position in the saved audio. Provide play/pause and a seek bar.

Copy and Export produce UTF-8 text with title, recording date, and `HH:MM:SS` segment timestamps. Search is limited to session titles and text within the open transcript. Transcripts remain machine-generated text, with playback available for checking uncertain terms. Version one does not add a transcript editor.

Delete moves a session to the macOS Trash after confirmation and cannot run while that session is active. No automatic retention expiry is applied.

## 5. Components and data flow

| Component | Responsibility and interface | Dependencies |
|---|---|---|
| Session coordinator | Owns state transitions and start, finish, cancel, retry, and recovery actions | Interfaces to the services below |
| Capture service | Resolves Chrome, starts/stops capture, emits timestamped audio and capture errors | ScreenCaptureKit |
| Audio writer | Converts sample format, persists segments, reports committed duration | AVFoundation, session store |
| Session store | Atomically saves metadata and transcripts; enumerates, renames, and trashes sessions | Local filesystem |
| Model manager | Downloads, validates, prepares, and locates the pinned model | Download client, local filesystem |
| Transcription service | Processes saved audio, reports progress, supports cancellation, returns timed text | WhisperKit, model manager |
| Playback/export services | Play session audio and format transcript text | AVFoundation, session store |
| SwiftUI interface | Displays coordinator state and forwards user actions | Service interfaces through coordinator |

Normal flow: Chrome audio → capture service → persistent audio segments → finalized session → local transcription → atomic transcript save → library.

Heavy audio work and inference run off the main actor. Capture callbacks never wait for model inference or UI updates. Use bounded buffers; if disk writing cannot keep up, report an interrupted recording instead of silently dropping speech. Keep capture, storage, and inference independently replaceable and testable.

## 6. Storage and timestamps

Use the current user's Application Support directory, in a dedicated application folder. Models and sessions are separate. There is no app-managed cloud upload, synchronization, or telemetry. User-configured system backups may still include this directory.

Each session has a UUID folder containing:

- `session.json`: schema version, title, creation date/time zone, source bundle ID, state, actual captured duration, segment manifest, model identity, and any interruption/error reason.
- `audio/`: ordered, independently playable audio segments.
- `transcript.json`: ordered text segments with start/end offsets and model identity, present only after successful transcription.
- Temporary working files, removed after successful completion or safe cancellation.

Persist mono 16 kHz, 16-bit PCM audio in segments of at most ten seconds. Conversion must carry resampler state across buffers and preserve continuity across segment boundaries. Finalize a segment to a temporary path, rename it atomically, then atomically update the manifest. Recovery also scans for finalized segments missed by the last manifest update.

The audio timeline is anchored to successful recording start and uses capture presentation timestamps. Preserve ordinary playback pauses as silence; segment rotation must not reset timestamps or omit elapsed time. Detect actual stream failures and system sleep separately from quiet audio. On interruption, end the session rather than automatically joining audio from an unknown later time.

Transcript timestamps refer to the saved recording. Seeking backward or changing playback speed in Panopto changes the recorded content; source-video timestamps cannot be reconstructed by this app.

For transcription, assemble finalized segments into a temporary continuous PCM file with bounded memory. Use incremental audio loading and speech-aware processing so ten-second recovery boundaries do not become forced sentence boundaries. Maintain a mapping back to the original recording timeline, including silence. Timestamped playback must use the same segment manifest.

## 7. States and interruption handling

Normal session states are `starting → recording → finalizing → transcribing → complete`. Additional persisted states are `recorded`, `interrupted`, and `transcriptionFailed`. Cancelling inference returns the session to `recorded`. Capture setup failure produces an actionable UI error without claiming that audio was recorded.

| Situation | Required behavior |
|---|---|
| Capture permission denied or revoked | Explain how to grant it; preserve any committed audio; never report recording success without capture |
| Model unavailable or download fails | Keep partial download separate from a ready model; offer Retry; do not fall back to a paid service |
| Chrome closes or capture stops unexpectedly | Finalize available audio and mark Interrupted; offer transcription of the partial recording |
| Browser is quiet or lecture is paused | Continue recording silence; show the quiet-audio hint without stopping |
| Low space or write failure | Stop capture with a clear error and preserve committed segments; no success indication for unwritten audio |
| App crashes or is force-quit | On restart, recover valid finalized segments, ignore corrupt temporary files, and label the session Interrupted |
| Transcription fails or is cancelled | Keep audio unchanged; offer Retry; never publish an incomplete transcript as complete |
| System sleeps or lid closes | Mark active recording Interrupted when detected; preserve saved audio and allow retry of interrupted transcription |

For process crashes, at most the current ten-second segment plus in-flight buffers should be at risk. This is a testable recovery target, not a guarantee against hardware failure or power loss. Recovered recordings require an explicit Transcribe action. Interrupted transcription restarts from saved audio in version one; exact inference checkpoint resumption is outside scope.

Acquire an idle-sleep prevention assertion during recording and inference and release it on every exit path. This does not override lid closure, forced sleep, or shutdown.

Persist transcripts only after a successful run, using atomic replacement. Silence-only sessions should produce a clear “No speech detected” outcome rather than a fabricated transcript. Use speech detection and model no-speech handling, then test them with silence and music fixtures.

## 8. Packaging and free operation

Deliver one locally runnable `.app` containing its required runtime libraries. Model download is handled inside the app; no Homebrew, Python environment, external recorder, background server, or browser extension is required for normal use. The development toolchain may be needed to build the app, but is not part of the end-user workflow.

The initial build uses local signing suitable for this Mac, a stable bundle identifier, and a stable install location so capture permissions can be tested consistently. App Store publication and public notarized distribution are outside this personal-use delivery. Include applicable open-source notices.

After model preparation, capture and transcription must work without network access. Internet remains necessary for streaming online lectures. Any model repair download is explicit and must never upload recordings or transcript content.

## 9. Verification and release criteria

The following are acceptance checks to perform during implementation, not results already obtained:

1. **Capture feasibility first:** record two minutes of an actual Chrome lecture with headphones. Verify audible playback of the saved file and exclusion of microphone input and audio played by another application. Repeat with Chrome fullscreen and the app window closed. Verify Chrome helper-process behavior before relying on application filtering.
2. **Long session:** capture a two-hour playback containing marked speech and pauses. Confirm start, middle, and end content, monotonic timestamps, continuous segment joins, and no sustained memory growth with duration. Measure memory, CPU, disk use, and processing time on the user's Mac.
3. **Transcript usefulness:** manually check a representative ten-minute lecture sample, including technical terms. Target at most 15% word error rate on the selected sample after ignoring case and punctuation. Report terminology errors separately and verify several transcript-to-playback seeks. This threshold is a product acceptance target, not an accuracy claim.
4. **Offline operation:** after setup, disconnect network access and capture a locally available video playing in Chrome; finish, transcribe, reopen, play, and export it successfully. Confirm the application makes no transcription network requests.
5. **Recovery:** force-quit during recording around segment boundaries; reopen and verify all valid committed audio is recovered. Test termination during metadata and transcript replacement.
6. **Failures and cancellation:** exercise denied permissions, Chrome exit, simulated disk errors, model download interruption, inference failure, cancellation, and retry. Verify saved recordings remain usable.
7. **Sleep and state:** test ordinary idle prevention, explicit sleep/lid interruption, repeated Finish clicks, and attempts to delete or start another session while work is active.
8. **Focused automated tests:** cover state transitions, atomic persistence/recovery, timestamp mapping with silence and resampling, ordered segment playback mapping, cancellation, and text export. Use a fake transcription engine for error paths and the real model for the representative integration test.
9. **Packaged application:** verify first launch, permissions, model setup, and subsequent offline launch using the actual `.app` at its intended stable location rather than only an IDE run.

The design is not considered validated if capture loses Chrome speech, saved audio is discarded after an error, silence generates persistent fabricated text, or packaged operation requires manual tools. If the selected model misses the quality target, report the measured result and revise the model choice before calling the app ready. Processing speed is reported from measurement; no fixed completion time is promised.

## 10. Review and handoff

The user approved the workflow and reliability design in chat. This written specification records those decisions and supplies implementation defaults: one active job, the chosen model, ten-second recovery segments, local file storage, and focused acceptance checks.

Next: user review of this document, then the writing-plans skill produces an implementation plan with concrete build tasks, dependency pinning, tests, and an execution-method choice. No product code or dependencies have been created or installed during this design stage.
