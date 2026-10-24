# Lecture Recorder

A free, local macOS app for recording English lecture audio from Chrome and transcribing it after watching. Built for Apple Silicon, macOS 14 or later.

1. Open **Lecture Recorder.app** and complete setup: grant capture permission and prepare the speech model.
2. Play the lecture in Chrome and click **Start recording** in the app or menu bar. Keep other Chrome tabs quiet.
3. Click **Finish**. The app saves the recording, transcribes it locally, and adds the result to your library.
4. Play the audio, search or rename lectures, copy the text, or export a `.txt` file. Transcript timestamps follow the recording, including pauses.

The first model setup needs internet and downloads about 630 MB. Recording and transcription then run locally. No paid service, API key, microphone capture, browser extension, or external recorder is required. Allow 3 GB of free space for model preparation; recorded audio uses about 115 MB per hour, plus temporary space for playback/transcription.

**Status:** functional development build. Real Chrome capture and denied-network transcription have been exercised on an M4 Pro. Long-duration, source-exclusion, lecture-quality and some manual lifecycle checks remain outstanding; see [validation](outputs/lecture-recorder-validation.md). Do not interpret passing unit checks as completed acceptance.

## Development

```sh
swift run LectureCoreChecks
python3 -m unittest discover -s Tests/Evaluation -v
bash scripts/bundle-app.sh release
bash scripts/verify-bundle.sh
```

The standalone app is written to `outputs/Lecture Recorder.app`. Swift 6.2+ and a macOS SDK are needed to build; neither a developer toolchain nor Python is needed to run the app. Tests use a portable Swift check executable because the installed Command Line Tools do not provide XCTest or Swift Testing.

- [Build and troubleshooting guide](docs/BUILD.md)
- [Approved design](outputs/2026-10-12-lecture-recorder-design.md)
- [Implementation plan](outputs/2026-10-24-lecture-recorder-implementation-plan.md)
- [Acceptance evidence](docs/ACCEPTANCE.md)

Data lives in `~/Library/Application Support/LectureRecorder`. Sessions use recoverable ten-second WAV segments and atomic JSON metadata. Models, recordings, caches, credentials, and app bundles are excluded from Git. **Trash** moves an inactive lecture and its audio to macOS Trash; cancellation retains audio for retry.

The app uses pinned WhisperKit 1.1.1 and a pinned quantized Whisper large-v3 model. License notices ship in the application resources. Local builds are ad-hoc signed; rebuilding may require renewing macOS capture permission. Public distribution/notarization is outside this project’s current scope.
