#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
app=dist/CLIProxyBar.app
[[ -d "$app" ]] || { echo 'Build the app before packaging it.' >&2; exit 1; }
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
architectures="$(lipo -archs "$app/Contents/MacOS/CLIProxyBar")"
case "$architectures" in
  'x86_64 arm64'|'arm64 x86_64') platform=universal ;;
  arm64) platform=arm64 ;;
  x86_64) platform=x86_64 ;;
  *) echo "Unexpected architectures: $architectures" >&2; exit 1 ;;
esac
archive="CLIProxyBar-${version}-macOS-${platform}.zip"
rm -f "dist/$archive"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
printf 'Packaged %s\n' "$root/dist/$archive"
