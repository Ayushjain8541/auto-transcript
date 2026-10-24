# Building Lecture Recorder

Tested toolchain: Swift 6.3.2 with Apple Command Line Tools on Apple Silicon/macOS 26.6.2. Minimum target: macOS 14. Other macOS versions have not been manually validated. Full Xcode is not required for this build route.

## Build and checks

Run from the repository root:

```sh
swift package resolve
swift run LectureCoreChecks
python3 -m unittest discover -s Tests/Evaluation -v
bash scripts/bundle-app.sh release
bash scripts/verify-bundle.sh
open "outputs/Lecture Recorder.app"
```

`debug` is also accepted by the bundle script. SwiftPM pins are committed in `Package.resolved`. The script bundles the arm64 executable, model manifest and licenses, then ad-hoc signs and validates the result. It refuses to replace an unrelated app. The app has no dependency on Homebrew, Python, Node or a separately installed transcription executable.

The check executable can filter by regular expression, e.g. `swift run LectureCoreChecks 'Coordinator|Audio'`. XCTest and Swift Testing are unavailable in the installed CLT SDK; these behavioral checks execute the same production library without an IDE test runner.

## Model assets and offline verification

`python3 scripts/freeze-model.py` reproduces the immutable download manifest and places assets under ignored `work/model-freeze`. It downloads only the chosen model and tokenizer, never records credentials, and never adds weights to Git. Runtime setup puts independently verified assets in `~/Library/Application Support/LectureRecorder/Models`. Setup resumes from verified files. A successful Core ML load is required before a prepared marker is saved.

For a developer integration check, prepare the isolated model once, then run a new process with network access denied:

```sh
LECTURE_REAL_MODEL=1 swift run LectureCoreChecks ModelManager
LECTURE_REAL_TRANSCRIPTION=1 sandbox-exec -p '(version 1)(allow default)(deny network*)' .build/debug/LectureCoreChecks Transcription
```

The transcription check uses the newest saved user recording and writes results only under ignored `work`. It requires an existing recording. The macOS sandbox tool here restricts the test process; it does not change system networking. It is not needed for normal app use.

## Permissions and troubleshooting

Open the app at a stable path. In setup, use **Allow capture** and follow macOS Screen & System Audio Recording prompts. The app does not request microphone access or save screen video. If permission is denied, use **Open System Settings**. After permission changes, macOS may require quitting and reopening the app.

An ad-hoc signature identifies a particular build by its code hash. Replacing the executable can leave an old approval visible in Settings while the new process still reports denied. If needed, remove the stale Lecture Recorder entry, add the app at its current path, and reopen. This is a development-build limitation, not a requirement during ordinary repeated use of the same app.

If setup fails, retain existing sessions and retry setup after correcting disk/network access. If recording is interrupted, the library retains finalized audio. If inference fails or is cancelled, retry the saved recording. Explicit sleep/lid close can interrupt capture despite the idle-sleep assertion. Search, playback, copying and export operate locally.

Audio requires about 32 KB/second. Playback and inference each assemble a temporary continuous WAV; keep extra disk space available. Temporary job files are cleaned on normal completion/cancellation; interrupted-process cleanup is handled during session recovery.
