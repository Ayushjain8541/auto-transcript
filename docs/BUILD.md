# Building Lecture Recorder

## Development prerequisites

- Apple Silicon Mac.
- macOS 14 or later.
- Swift 6.2 or later with a macOS SDK.

Inspect the selected toolchain with `xcrun swift --version` and `xcode-select -p`. The scaffold uses Swift Package Manager directly, so the bundle script does not require `xcodebuild` or a generated Xcode project. Full transcription integration may introduce additional toolchain requirements that must be validated separately.

## Commands

```bash
# Compile the package.
swift build

# Build, locally sign, and verify the arm64 app bundle.
bash scripts/bundle-app.sh debug

# Build an optimized version at the same location.
bash scripts/bundle-app.sh release

# Check the existing bundle without rebuilding it.
bash scripts/verify-bundle.sh

# Launch the placeholder app screen.
open "outputs/Lecture Recorder.app"
```

The bundle has identifier `local.ayush.LectureRecorder` and executable name `LectureRecorder`. Use the stable output path when the capture-permission flow is implemented.

The bundler refuses to replace a symlink or an unrelated item at its destination. It signs and verifies a temporary bundle before replacing a previous build of this app. Verification checks the property list, identity, architecture, executable, local signature, and linked dependency paths. It does not claim notarization or test future capture/transcription behavior.

No model resources or third-party runtime libraries are bundled yet. Add their packaging and verification with the corresponding implementation tasks, including SwiftPM resource lookup and license notices.

## Tests

No feature tests exist in this scaffold. `Tests/LectureCoreTests` reserves their location. Add the `LectureCoreTests` SwiftPM test target when the first meaningful capture tests are written. Until then, use the build and bundle commands above; `swift test` is not a verification command for this scaffold.

## Local files

Build products go in `.build/`; packaged apps go in `outputs/`; temporary assets go in `work/`. These generated files are ignored by Git. Design and plan Markdown files under `outputs/` remain tracked.
