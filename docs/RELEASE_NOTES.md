CLIProxyBar 0.2.5 simplifies the usage card:

- The card starts with Today, Yesterday, and Last 30 days. The title, account email, and request-counter header are removed.
- **Tokens** and **Requests** change period totals, daily activity colors, and model totals.
- The model list sorts by the selected measure. The token breakdown stays visible in both modes.
- A small marker beneath the square identifies today. Its full color shows the activity level.
- The card keeps the same height when you switch measures. Clicks keep the menu open.

Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
