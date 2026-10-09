#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/CLIProxyBar.app/Contents/Info.plist)"
archive="CLIProxyBar-${version}-macOS-universal.zip"
[[ -f "dist/$archive" ]] || { echo 'Package a universal release before generating its update feed.' >&2; exit 1; }
tools_dir="$root/.build/artifacts/sparkle/Sparkle/bin"
feed_dir="$(mktemp -d "$root/dist/.appcast.XXXXXX")"
trap 'rm -rf "$feed_dir"' EXIT
cp "dist/$archive" "$feed_dir/"
cp docs/RELEASE_NOTES.md "$feed_dir/${archive%.zip}.md"
signing_args=(--account io.github.darfink.CLIProxyBar)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then signing_args=(--ed-key-file -); fi
generate() {
  "$tools_dir/generate_appcast" "${signing_args[@]}" --maximum-deltas 0 --embed-release-notes \
    --download-url-prefix "https://github.com/darfink/cliproxybar/releases/download/v${version}/" \
    --link 'https://github.com/darfink/cliproxybar' -o "$feed_dir/appcast.xml" "$feed_dir"
}
verify() { "$tools_dir/sign_update" --verify "${signing_args[@]}" "$feed_dir/appcast.xml"; }
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s\n' "$SPARKLE_PRIVATE_KEY" | generate
  printf '%s\n' "$SPARKLE_PRIVATE_KEY" | verify
else
  generate
  verify
fi
cp "$feed_dir/appcast.xml" dist/appcast.xml
printf 'Generated and verified signed update feed for %s\n' "$version"
