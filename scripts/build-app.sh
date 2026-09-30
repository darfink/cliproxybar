#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
version="${APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)}"
build_number="${BUILD_NUMBER:-1}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'APP_VERSION must contain three numeric components.' >&2; exit 1; }
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo 'BUILD_NUMBER must be numeric.' >&2; exit 1; }
mkdir -p dist
staging="$(mktemp -d "$root/dist/.bundle.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/CLIProxyBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
universal=false
swift_flags=()
for argument in "$@"; do
  if [[ "$argument" == '--universal' ]]; then universal=true
  else swift_flags+=("$argument")
  fi
done
if $universal; then
  # Separate SwiftPM builds avoid the Xcode build backend used by multiple --arch flags.
  for architecture in arm64 x86_64; do
    swift build --configuration release --arch "$architecture" ${swift_flags[@]+"${swift_flags[@]}"}
    bin_dir="$(swift build --configuration release --arch "$architecture" --show-bin-path ${swift_flags[@]+"${swift_flags[@]}"})"
    cp "$bin_dir/CLIProxyBar" "$staging/CLIProxyBar-$architecture"
  done
  lipo -create "$staging/CLIProxyBar-arm64" "$staging/CLIProxyBar-x86_64" -output "$app/Contents/MacOS/CLIProxyBar"
else
  swift build --configuration release ${swift_flags[@]+"${swift_flags[@]}"}
  bin_dir="$(swift build --configuration release --show-bin-path ${swift_flags[@]+"${swift_flags[@]}"})"
  cp "$bin_dir/CLIProxyBar" "$app/Contents/MacOS/CLIProxyBar"
fi
cp Info.plist "$app/Contents/Info.plist"
cp LICENSE NOTICE.md "$app/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
xcrun actool Assets.xcassets --compile "$app/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$staging/assets-info.plist" >/dev/null
xcrun xcstringstool compile Localizable.xcstrings --output-directory "$app/Contents/Resources" >/dev/null
# Developer ID signing is optional. The default bundle has an ad hoc signature.
identity="${SIGNING_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
  codesign --force --sign - "$app"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
plutil -lint "$app/Contents/Info.plist"
rm -rf "$root/dist/CLIProxyBar.app"
mv "$app" "$root/dist/CLIProxyBar.app"
printf 'Built %s\n' "$root/dist/CLIProxyBar.app"
