CLIProxyBar 0.4.3 adds menu choices and OpenCode Go pace estimates:

- Independent provider visibility in the menu bar and drop-down, including plugin providers.
- Compact or expanded default view. Option-click opens the other view. Compact remains the initial default.
- Optional single percentage for the quota window closest to its limit. Paired percentages remain the initial default.
- OpenCode Go pace estimates for the five-hour rolling window and weekly quota.
- Monthly pace for OpenCode Go when the UTC billing cycle is unambiguous, with the actual month length.
- Gemini API-key accounts from Google AI Studio, with optional usage history. CLIProxyAPI currently supplies no allowance quotas for these keys.

Display choices survive relaunch. Hidden providers retain their quota refreshes, usage history, and alert settings.
The drop-down keeps the full quota breakdown after you select a single percentage for the menu bar.
If you hide every provider, Settings remains accessible.
CLIProxyBar keeps Gemini key values out of its account records and quota cache.

Tests cover display persistence, Option-click behavior, provider visibility, Gemini account discovery, and billing cycles across short months and leap years.

Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
