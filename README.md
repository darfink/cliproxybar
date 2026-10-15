<p align="center">
  <img src="docs/icon.png" width="96" alt="CLIProxyBar icon">
</p>

<h1 align="center">CLIProxyBar</h1>
<p align="center">CLIProxyAPI quotas in your macOS menu bar.</p>

Track account quotas, reset times, and usage history from a local or remote [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) instance.

## Install

CLIProxyBar requires **macOS 14 Sonoma or later**, on Apple Silicon or Intel, and a CLIProxyAPI instance with management access.

With [Homebrew](https://brew.sh) installed, run:

```sh
brew tap darfink/cliproxybar https://github.com/darfink/cliproxybar.git && brew install --cask darfink/cliproxybar/cliproxybar && open -a CLIProxyBar
```

In **Settings**:

1. Enter your proxy URL. The default is `http://127.0.0.1:8317`.
2. Select **Apply**.
3. Enter your CLIProxyAPI **management key**.
4. Select **Save**.

The management key is different from a client API key. CLIProxyAPI manages your provider accounts and the proxy service.

Current releases have no Apple notarization.
If macOS blocks the app, select **System Settings → Privacy & Security → Open Anyway**.

[Manual installation and remote connections →](docs/SETUP.md)

## Screenshots

<table>
  <tr>
    <th>Compact view</th>
    <th>Expanded view</th>
  </tr>
  <tr>
    <td valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/compact-dark.png">
        <img src="docs/screenshots/compact.png" width="280" alt="Compact menu with provider quota gauges, pace markers, and an optional countdown for exhausted quota">
      </picture>
    </td>
    <td valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/expanded-dark.png">
        <img src="docs/screenshots/expanded.png" width="360" alt="Expanded menu with Claude Pro and Max plan badges, account quotas, pace estimates, and reset times">
      </picture>
    </td>
  </tr>
</table>

<details>
<summary>Token and quota history</summary>

<table>
  <tr>
    <th>Token history</th>
    <th>Quota history</th>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/usage-dark.png">
        <img src="docs/screenshots/usage.png" width="420" alt="Token history with daily totals, token counters, activity levels, and model totals">
      </picture>
    </td>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/quota-history-dark.png">
        <img src="docs/screenshots/quota-history.png" width="420" alt="Quota history with gradual session and weekly usage, pauses, and sharp session resets">
      </picture>
    </td>
  </tr>
</table>

</details>

Screenshots use fictional accounts and sample data. Images adapt to light and dark mode.

## Features

CLIProxyBar includes:

- Quota gauges, reset times, and pace estimates for supported windows.
- Compact and expanded menus, with separate provider visibility for the menu bar and drop-down.
- Usage or remaining percentages, with optional countdowns for exhausted quotas.
- Account hover cards with quota graphs, token totals, and daily activity.
- Optional reset notifications and confetti for weekly or monthly resets.

## Supported quotas

| Provider | Quota windows |
| --- | --- |
| Claude Code | Five-hour session and weekly, with Pro and Max plan labels |
| Codex | Session and weekly, with plan labels and available resets |
| OpenCode Go | Rolling, weekly, and monthly through a compatible quota plugin |
| Antigravity | Provider quota groups or per-model limits |
| Generic quota plugins | Windows supplied by the plugin |

Gemini API-key accounts support token history. CLIProxyAPI currently exposes no allowance quotas for these accounts.
Quota availability depends on the provider, plugin, and CLIProxyAPI version.

[Provider support and limitations →](docs/PROVIDERS.md)

## Use

| Action | Result |
| --- | --- |
| Click the menu bar item | Open the default view |
| Option-click | Open the other view |
| ⌘R | Refresh quotas |
| ⌘, | Open Settings |
| Hover over an account | Show token and quota history |

Automatic quota refresh runs every five minutes. **Settings** controls the default view, visible providers, history, and reset alerts.
Token history requires **Collect token usage**. Quota history recording is on by default.

[Full user guide →](docs/USER_GUIDE.md)

## Keep up to date

CLIProxyBar checks GitHub Releases through [Sparkle](https://sparkle-project.org).
Automatic update checks are on by default. Automatic downloads and installation are off by default.
**Settings → App updates** includes a manual update check.

Before a Homebrew update, quit CLIProxyBar.

```sh
brew update && brew upgrade --cask --greedy darfink/cliproxybar/cliproxybar
```

After the update, open CLIProxyBar.

Updates preserve your settings, management key, and recorded history.

## Documentation

Read the guides for details:

- [Setup](docs/SETUP.md): Manual installation, remote connections, and macOS approval.
- [User guide](docs/USER_GUIDE.md): Display settings, history, countdowns, and reset alerts.
- [Providers](docs/PROVIDERS.md): Quota support, pace estimates, and plugin integration.
- [Privacy](docs/PRIVACY.md): Keychain access, local storage, and update requests.
- [Development](CONTRIBUTING.md): Source builds, tests, and screenshot exports.
- [Releases](docs/RELEASING.md): Packaging, update signatures, and optional Apple signing.

## Attribution

CLIProxyBar derives from [Quotio](https://github.com/nguyenphutrong/quotio), by Trong Nguyen, under the MIT license.
See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).
CLIProxyBar is an independent project with no affiliation with CLIProxyAPI or the providers shown in the app.
