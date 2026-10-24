# Lecture Recorder

A native Mac application being built to record English lecture audio from Chrome and transcribe it locally after you finish watching.

**Status: repository scaffold.** The SwiftUI app shell builds and displays a status screen. Audio capture, model setup, transcription, and the lecture library are not implemented yet.

## Intended workflow

1. Click **Start recording** and watch your lecture in Chrome.
2. Click **Finish**.
3. Read, play back, copy, or export the transcript.

The planned application uses ScreenCaptureKit and the free open-source WhisperKit library. Processing and storage stay on your Mac. The first-run model download requires internet; subsequent transcription is designed to run offline. No paid service is planned.

## Build the scaffold

Requirements: Apple Silicon Mac, macOS 14 or later, and a Swift 6.2+ development toolchain with the macOS SDK.

```bash
swift build
bash scripts/bundle-app.sh debug
bash scripts/verify-bundle.sh
open "outputs/Lecture Recorder.app"
```

Use `bash scripts/bundle-app.sh release` for an optimized build. The application is locally ad-hoc signed, for development on your Mac. It does not request capture permission, record audio, or download a model at this stage.

There are no external Swift package dependencies yet. WhisperKit will be introduced at the model-integration step in the plan. See [build details](docs/BUILD.md).

## Repository layout

```text
Sources/LectureCore/       Shared identity and future capture/storage/transcription services
Sources/LectureRecorder/  SwiftUI app shell
Resources/                App bundle metadata
Tests/LectureCoreTests/   Reserved for the first behavior tests
scripts/                  Local build and bundle verification
docs/                     Development notes
outputs/                  Design, plan, and ignored local app builds
work/                     Ignored scratch files, test recordings, and model downloads
```

## Design and implementation

- [Approved design](outputs/2026-10-12-lecture-recorder-design.md)
- [Implementation plan](outputs/2026-10-24-lecture-recorder-implementation-plan.md)
- [Current scaffold scope](docs/SCAFFOLD.md)

The next implementation milestone is verified Chrome audio capture. The scaffold does not complete that milestone. Automated behavior tests will be added with the first feature; build and bundle checks are the current verification.

Keep recordings, downloaded models, credentials, caches, and packaged binaries out of Git. The `.gitignore` covers the designated local working and build directories.
