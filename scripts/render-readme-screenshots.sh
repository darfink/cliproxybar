#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
destination="${1:-$root/docs/screenshots}"
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"
./scripts/build-app.sh
bin_dir="$(swift build --configuration release --show-bin-path)"
preview="$root/dist/ReadmePreview.app"
mkdir -p "$preview/Contents/MacOS"
ditto "$root/dist/CLIProxyBar.app/Contents/Resources" "$preview/Contents/Resources"
cp "$root/Info.plist" "$preview/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable ReadmePreview' "$preview/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.github.darfink.CLIProxyBar.ReadmePreview' "$preview/Contents/Info.plist"
core_objects=()
while IFS= read -r file; do core_objects+=("$file"); done < <(rg --files "$bin_dir/CLIProxyBarCore.build" -g '*.o')
sources=()
while IFS= read -r file; do
  [[ "$file" == "$root/Sources/MenuBar/App.swift" ]] || sources+=("$file")
done < <(rg --files "$root/Sources/MenuBar" -g '*.swift')
frameworks="$root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
xcrun swiftc -parse-as-library -swift-version 6 -I "$bin_dir/Modules" -F "$frameworks" \
  -framework Sparkle -Xlinker -rpath -Xlinker "$frameworks" \
  "${sources[@]}" "$root/scripts/ReadmePreview.swift" "${core_objects[@]}" \
  -o "$preview/Contents/MacOS/ReadmePreview"
CLIPROXYBAR_README_SCREENSHOTS="$destination" "$preview/Contents/MacOS/ReadmePreview"
