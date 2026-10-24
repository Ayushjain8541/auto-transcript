#!/bin/bash
set -euo pipefail

configuration="${1:-debug}"
if [[ $# -gt 1 || ( "$configuration" != debug && "$configuration" != release ) ]]; then
  echo "Usage: bash scripts/bundle-app.sh [debug|release]" >&2
  exit 2
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
destination="$repo_root/outputs/Lecture Recorder.app"
bundle_id="local.ayush.LectureRecorder"

if [[ -L "$destination" ]]; then
  echo "Refusing to replace a symlink at $destination" >&2
  exit 1
fi
if [[ -e "$destination" ]]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$existing_id" != "$bundle_id" ]]; then
    echo "Refusing to replace an unrelated item at $destination" >&2
    exit 1
  fi
fi

swift build --package-path "$repo_root" --configuration "$configuration" --arch arm64 --product LectureRecorder
bin_dir="$(swift build --package-path "$repo_root" --configuration "$configuration" --arch arm64 --show-bin-path)"
mkdir -p "$repo_root/outputs" "$repo_root/work"
staging_root="$(mktemp -d "$repo_root/work/bundle.XXXXXX")"
cleanup() {
  if [[ -d "$staging_root/previous.app" && ! -e "$destination" && ! -L "$destination" ]]; then
    if ! mv "$staging_root/previous.app" "$destination"; then
      echo "Previous build preserved at $staging_root/previous.app" >&2
      return
    fi
  fi
  rm -rf -- "$staging_root"
}
trap cleanup EXIT
staged_app="$staging_root/Lecture Recorder.app"

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$repo_root/Resources/Info.plist" "$staged_app/Contents/Info.plist"
cp "$bin_dir/LectureRecorder" "$staged_app/Contents/MacOS/LectureRecorder"
chmod 755 "$staged_app/Contents/MacOS/LectureRecorder"
/usr/bin/codesign --force --sign - --timestamp=none "$staged_app"
bash "$repo_root/scripts/verify-bundle.sh" "$staged_app"

if [[ -e "$destination" ]]; then
  mv "$destination" "$staging_root/previous.app"
fi
if ! mv "$staged_app" "$destination"; then
  if [[ -d "$staging_root/previous.app" ]]; then
    mv "$staging_root/previous.app" "$destination"
  fi
  exit 1
fi
echo "Built: $destination"
