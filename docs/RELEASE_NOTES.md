CLIProxyBar 0.4.0 adds provider discovery and broader quota support:

- Every configured provider can appear in the menu and optional usage history. Settings includes detected providers for menu bar indicators.
- Plugins with the generic quota capability share one adapter. It preserves quota groups, unfamiliar windows, reset times, plan labels, and numeric summaries.
- Antigravity has a direct adapter for quota summaries, with older per-model responses as a fallback.
- Unknown allowances stay unknown. Numeric summaries do not affect percentage gauges.

The new integrations use response fixtures and request tests. Antigravity and additional plugins still need live account validation.
Claude, Codex and OpenCode Go have live account checks. The notification crash fix from 0.3.3 remains included.

Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
