# Release CLIProxyBar

## Publish a version

1. Update the version in `Info.plist`.
2. Update `docs/RELEASE_NOTES.md`.
3. Run `./scripts/verify.sh`.
4. Commit the version changes.
5. Create a version tag with `git tag v0.1.0`.
6. Push the commit and tag with `git push origin main --tags`.
7. Inspect the Release workflow in GitHub Actions.

The workflow runs tests and builds an app for Apple Silicon and Intel.
The release contains a universal ZIP, its SHA-256 checksum, and a signed Sparkle feed named `appcast.xml`.
Only the publication job has permission to write release assets.
After publication, that job updates `Casks/cliproxybar.rb` on `main` through the GitHub API.
The cask always refers to a published universal archive. Re-running an older release cannot downgrade the cask.
For a failed publication, run the Release workflow manually with the existing tag.

The default release has an ad hoc signature. It has no Apple notarization and requires macOS approval after download.

## Update signing

Sparkle 2.10 or later verifies both the update feed and the ZIP with Ed25519 signatures.
The public key is in `Info.plist`. GitHub Actions uses the `SPARKLE_PRIVATE_KEY` repository secret to sign updates.
The signing key also lives in the maintainer's macOS Keychain under the account `io.github.darfink.CLIProxyBar`.
Keep a secure backup of this key. Losing it prevents updates to existing installations without the current Developer ID signing setup.
Never commit the private key or include it in release assets.

To generate and verify the feed locally, package a universal app first:

```sh
./build.sh --universal
./scripts/package-release.sh
./scripts/generate-appcast.sh
```

The script uses the Keychain key locally. CI supplies the secret through standard input to Sparkle's signing tools.
The app reads the feed from the latest GitHub Release. A separate server is not required.
The existing notarization instructions still apply. Sparkle signatures do not replace Apple notarization.

## Test menu interaction

On a macOS desktop, run the native menu fixtures:

```sh
CLIPROXYBAR_MENU_INTERACTION_TEST=1 swift test --filter UsageMenuInteractionTests
```

These tests click the activity selector and measure native menu placement. They use fictional data and their own windows.
The selector fixture opens under the cursor without moving it. Keep the cursor away from screen edges during this test.
CI skips these desktop fixtures and runs the remaining regression tests.

## Optional Developer ID signing

A Developer ID Application certificate can sign a local release build:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
APP_VERSION=0.1.0 BUILD_NUMBER=1 \
./build.sh --universal
./scripts/package-release.sh
```

After signing, submit the ZIP to Apple with your own stored notary credentials:

```sh
xcrun notarytool submit dist/CLIProxyBar-0.1.0-macOS-universal.zip \
  --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/CLIProxyBar.app
./scripts/package-release.sh
```

Verify notarization before uploading the final ZIP. Stapling changes the app, so package it again to update the checksum.
The default GitHub workflow uses no Apple credentials. Developer ID signing and notarization require a separate credential setup.
