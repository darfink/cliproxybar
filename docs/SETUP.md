# Install and connect

[README](../README.md) · [User guide](USER_GUIDE.md)

## Requirements

CLIProxyBar requires:

- macOS 14 Sonoma or later, on Apple Silicon or Intel.
- A local or remote CLIProxyAPI instance with management access enabled.
- Provider accounts configured in CLIProxyAPI.
- The CLIProxyAPI management key.

The management key is different from a client API key.
CLIProxyAPI manages the provider accounts and proxy service. CLIProxyBar shows quotas and opens the management dashboard.

## Install with Homebrew

With [Homebrew](https://brew.sh) installed, run:

```sh
brew tap darfink/cliproxybar https://github.com/darfink/cliproxybar.git && brew install --cask darfink/cliproxybar/cliproxybar && open -a CLIProxyBar
```

The tap lives in the app repository. Each release updates its version and SHA-256 checksum automatically.

## Install manually

1. Download the universal macOS ZIP from [Releases](https://github.com/darfink/cliproxybar/releases/latest).
2. Extract the ZIP.
3. Move `CLIProxyBar.app` into Applications.
4. Open the app.

## Connect to CLIProxyAPI

When no management key exists, the app opens Settings on first launch.

1. Open **Settings** with ⌘,.
2. Enter the proxy URL. The default is `http://127.0.0.1:8317`.
3. Select **Apply**.
4. Enter your CLIProxyAPI management key.
5. Select **Save**.

The app stores the management key in macOS Keychain.
The [privacy guide](PRIVACY.md) describes key access and local storage.

## Remote connections

The app supports HTTP and HTTPS servers, including reverse-proxy prefixes such as `https://proxy.example.com/cli`.
URLs cannot contain credentials, queries, or fragments.

For a remote connection, enable `remote-management.allow-remote` in the CLIProxyAPI settings.
Use HTTPS to protect the management key in transit.

HTTPS uses normal certificate validation. The app refuses redirects for management requests.
The browser management page handles its own authentication. The app does not put the management key in browser URLs.

## macOS approval

The default release uses an ad hoc signature and has no Apple notarization.

If macOS blocks the app after the first launch attempt, select **System Settings → Privacy & Security → Open Anyway**.

## Updates and migration

The [README](../README.md#keep-up-to-date) describes Sparkle and Homebrew updates.
Homebrew updates use `--greedy` because the app also has a built-in updater.
Updates preserve settings, the management key, and recorded history.
Versions before 0.2.4 require one manual or Homebrew upgrade to get the built-in updater.

Users of the extracted Quotio Menu Bar keep their display settings, cached readings, and management key during migration.
CLIProxyBar preserves the legacy Keychain item.
