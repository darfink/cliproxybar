# Contribute to CLIProxyBar

CLIProxyBar uses Swift 6, AppKit, and SwiftUI. The minimum macOS version is 14.

## Development

1. Install Xcode or the Xcode Command Line Tools.
2. Run `swift test`.
3. Run `./build.sh`.
4. Open `dist/CLIProxyBar.app`.

The menu renderer lives in `Sources/MenuBar/StatusBarMenuRenderer.swift`.
The local client and provider parsers live in `Sources/MenuBar`.
The shared quota and display models live in `Sources/CLIProxyBarCore`.

## Validation

Run `./scripts/verify.sh` before a pull request. This command runs tests, builds the app, and packages the ZIP.
For display changes, inspect compact and expanded menus. Use fictional accounts in shared screenshots.
For quota changes, cover missing values, invalid values, and account selection in tests.

Do not commit management keys, provider tokens, account caches, signing certificates, or local build output.
Keep the original copyright and attribution in source distributions.
