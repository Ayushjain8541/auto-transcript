#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: bash scripts/verify-bundle.sh [app-path]" >&2
  exit 2
fi
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="${1:-$repo_root/outputs/Lecture Recorder.app}"
plist="$app_path/Contents/Info.plist"

fail() {
  echo "Bundle verification failed: $*" >&2
  exit 1
}

[[ -f "$plist" ]] || fail "missing Info.plist"
/usr/bin/plutil -lint "$plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == local.ayush.LectureRecorder ]] || fail "unexpected bundle identifier"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")" == LectureRecorder ]] || fail "unexpected executable name"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" == 14.0 ]] || fail "unexpected minimum macOS version"
binary="$app_path/Contents/MacOS/LectureRecorder"
[[ -x "$binary" ]] || fail "missing executable"
[[ "$(/usr/bin/lipo -archs "$binary")" == arm64 ]] || fail "expected arm64 executable"
/usr/bin/codesign --verify --strict "$app_path"

dependencies="$(/usr/bin/otool -L "$binary")"
while IFS= read -r dependency; do
  case "$dependency" in
    /System/Library/*|/usr/lib/*|@rpath/libswift*.dylib) ;;
    *) fail "unexpected external dependency: $dependency" ;;
  esac
done < <(printf '%s\n' "$dependencies" | /usr/bin/awk 'NR > 1 { print $1 }')

echo "Verified scaffold bundle: $app_path"
