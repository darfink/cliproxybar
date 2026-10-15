# User guide

[README](../README.md) · [Setup](SETUP.md) · [Providers](PROVIDERS.md) · [Privacy](PRIVACY.md)

## Daily use

| Action | Result |
| --- | --- |
| Click the menu bar item | Open the default view. Compact is the initial default. |
| Option-click the menu bar item | Open the other view. |
| Press `⌘R` or select **Refresh** | Refresh quotas for all supported accounts. |
| Open **Settings** with `⌘,` | Change the display, provider visibility, reset alerts, usage collection, proxy URL, or management key. |
| Hover over an account | Show token history and quota history. |
| Select **Open Management** | Open the proxy management page in your browser. |

At launch, the app shows saved quota readings while it fetches fresh data.
Automatic refresh runs every five minutes. A failed request keeps the previous reading and shows its status.

The management page handles its own authentication. CLIProxyBar does not put the management key in browser URLs.

**Default menu view** selects Compact or Expanded. Compact is the initial default. **Show both quota windows in the menu bar** keeps paired percentages, such as Claude session and weekly quotas. When this setting is off, one percentage shows the quota window closest to its limit. The drop-down keeps the full quota breakdown.

**When quota is exhausted** has separate countdown settings for the menu bar and compact menu. Both settings are off by default. An exhausted quota shows a short duration, such as `42m`, `3h`, or `2d`. Other quotas keep their percentages. Countdown labels use provider reset times and update once each minute without another quota request.

Paired percentages have separate countdowns. One percentage uses the latest reset among tied exhausted quotas. Missing or expired reset times keep the percentage. A quota that only rounds to 100% usage keeps its percentage.

The **Providers** table has separate **Menu bar** and **Drop-down** checkboxes. Each provider can appear in either location, both locations, or neither location. Drop-down visibility controls account panels and provider filter buttons.

Saved choices remain after relaunch. Hidden providers still receive quota refreshes and retain usage history and alert settings.
When every provider is hidden, Settings remains available.

## Quota reset alerts

Settings has three independent controls. All are off by default:

- **Notify for session and rolling resets** covers session limits and OpenCode Go rolling quota. This includes five-hour windows.
- **Notify for weekly and monthly resets** covers longer quota windows.
- **Celebrate weekly and monthly resets** plays a short confetti animation. **Preview** shows the animation without enabling it.

When you enable an alert, macOS requests notification permission. Confetti works independently of notifications. It passes clicks through, keeps keyboard focus unchanged, and respects macOS Reduce Motion.

Fresh provider readings verify scheduled resets. Rolling alerts wait until the allowance becomes fully available again. First readings establish a baseline.

Failed requests and expired countdowns alone do not trigger alerts. Windows that already show 0% usage do not trigger a notification or confetti at reset.
Saved reset history prevents duplicate alerts after relaunch. Limits that reset together produce one notification per account and one confetti animation.

The app must be running and connected. It refreshes at known reset times and checks again during regular polling. After sleep, it can verify session resets from the last 15 minutes and weekly or monthly resets from the last 24 hours. Rolling recovery requires readings no more than 15 minutes apart. Timed alerts require a reset time from the provider.

## Quota history

1. Hover over an account.
2. Select **Quota history**.

The card fits both panels. Tab switches do not change its header or height. It remembers the last tab across accounts and app restarts. **Token history** is the leftmost tab and the default before you select a tab. Accounts without quota readings show token history without changing that preference.

The graph shows all quota windows together on a 0–100% scale. Each window has a separate color and a legend with its recorded percentage.
The **5h**, **24h**, **7d**, and **30d** buttons select the time range.

Lines interpolate values between recorded points.
When you hover over the graph, it shows the nearest recorded percentage and reading time for each window.
When readings are more than 15 minutes apart, the graph leaves a gap.
Drops show decreases in reported usage. They can mark quota recovery or resets.

**Settings → Usage history → Record quota history** controls quota recording independently of token collection. Recording is on by default. The app saves fresh quota readings during existing refreshes, with no extra API requests. Current CLIProxyAPI quota endpoints do not provide earlier percentage history. Cached readings and failed requests do not create observations.

The app saves up to 30 days of local quota history, with bounded samples per quota window. When recording is off, saved history remains. Each proxy URL has separate history. The history records timestamps, percentages, and hashed identifiers. It contains no provider credentials or raw API responses. See the [privacy guide](PRIVACY.md) for full storage details.

Providers without quota percentages, such as Gemini API key accounts, keep the token history panel. The **Token history** tab continues to show token totals, the activity grid, and model totals.

## Token history

To collect token usage:

1. Open **Settings** with `⌘,`.
2. Enable **Collect token usage**.
3. Hover over an account in the compact or expanded menu.

This setting enables `usage-statistics-enabled` through the management API. CLIProxyAPI saves this setting.

To enable usage statistics directly in the CLIProxyAPI settings, set:

```yaml
usage-statistics-enabled: true
```

The panel shows recorded token or request totals for today, yesterday, and the last 30 days. It includes input, output, cache, and reasoning counters, an activity grid, and totals by model. It aligns with the hovered account and stays within the screen.

Processed token totals include reused cached context in the input count where the provider reports it.
Cache and reasoning counters are subsets of the input and output totals.

Each activity square represents one day. Month and weekday labels orient the 26-week grid. Today has a thicker outline.
Upcoming days have dashed outlines, and days before collection have a faint fill. The Today legend is hollow.

Square colors show the recorded activity level. Four color levels separate quiet and busy days within the visible history.

Hover over a square to see its date, recorded tokens, requests, and failures.

Choose **Tokens** or **Requests** to change period totals, daily activity, and model totals. The model list sorts by the selected measure. The token breakdown stays visible in both modes. Available token fields depend on the provider. CLIProxyAPI supplies request counters.

CLIProxyAPI records request usage. CLIProxyBar reads its usage queue every 15 seconds while the app runs. CLIProxyBar saves daily summaries locally for up to one year.

The panel covers traffic through this proxy. It marks the start of collection and leaves earlier history empty.
The default queue retains events for 60 seconds. Closing the app or sleep can create gaps in recorded totals.

Use one collector per proxy.

CLIProxyAPI v8 supplies events through a queue that removes records after retrieval. Another dashboard or collector can consume events before CLIProxyBar receives them.
Turning off **Collect token usage** pauses collection in this app and preserves saved history. The proxy statistics setting remains enabled for other tools.
