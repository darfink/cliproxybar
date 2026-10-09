CLIProxyBar 0.3.2 makes quota reset notifications more concise:

- Notifications hide account names that repeat the provider name. Distinct account names remain visible.
- Shorter reset messages identify the restored quota window.

Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
