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
The release contains a universal ZIP and its SHA-256 checksum.
Only the publication job has permission to write release assets.
For a failed publication, run the Release workflow manually with the existing tag.

The default release has an ad hoc signature. It has no Apple notarization and requires macOS approval after download.

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
