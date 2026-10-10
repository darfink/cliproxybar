CLIProxyBar 0.4.2 suppresses redundant reset alerts:

- Timed windows that already show 0% usage reset silently, without a notification or confetti.
- Reset alerts use the last reading before the deadline. Usage in a new window cannot trigger an alert for an unused window.
- Silent resets remain recorded after relaunch. Later resets of used windows still trigger alerts.
- Reset history from earlier versions remains compatible.

The reset tests cover session, weekly, and monthly limits, delayed confirmation, percentage rounding, and relaunch behavior.
Rolling alerts still require a full refill after usage.

Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
