# Contribute to CLIProxyBar

CLIProxyBar uses Swift 6, AppKit, and SwiftUI. The minimum macOS version is 14.

## Build from source

Install Xcode or the Xcode Command Line Tools with Swift 6 or later.

```sh
git clone https://github.com/darfink/cliproxybar.git
cd cliproxybar
swift test
./build.sh
open dist/CLIProxyBar.app
```

For a universal app, run:

```sh
./build.sh --universal
./scripts/package-release.sh
```

The build accepts SwiftPM flags. Restricted environments can pass `--disable-sandbox` and specify writable Swift module caches.
Swift Package Manager downloads Sparkle. The build script embeds this update framework in the app bundle.

## Source layout

The menu renderer lives in `Sources/MenuBar/StatusBarMenuRenderer.swift`.
The local client and provider parsers live in `Sources/MenuBar`.
The shared quota and display models live in `Sources/CLIProxyBarCore`.

## Validation

Run `./scripts/verify.sh` before a pull request. This command runs tests, builds the app, and packages the ZIP.
For display changes, inspect compact and expanded menus. Use fictional accounts in shared screenshots.
For quota changes, cover missing values, invalid values, and account selection in tests.

Do not commit management keys, provider tokens, account caches, signing certificates, or local build output.
Keep the original copyright and attribution in source distributions.

## Screenshot exports

The screenshot exporter uses the app's actual views with fictional accounts and sample data.

On macOS, run:

```sh
./scripts/render-readme-screenshots.sh
```

The exporter saves light and dark images in `docs/screenshots`.

## Releases

[The release guide](docs/RELEASING.md) describes version tags, packaging, update signatures, and optional Apple signing.
GitHub Actions runs tests and builds on Apple Silicon and Intel.
Version tags trigger a universal build, ZIP packaging, checksums, a signed update feed, and a GitHub Release.
The release workflow also updates the Homebrew cask in this repository.
Dependabot checks GitHub Actions and Swift dependencies weekly.
