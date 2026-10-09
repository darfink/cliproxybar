CLIProxyBar 0.3.1 adds configurable quota reset alerts:

- Settings has separate notifications for session/rolling resets and weekly/monthly resets.
- Weekly and monthly resets can play a short confetti animation, independently of notifications. A Preview button shows the effect.
- All options are off by default. macOS requests notification permission when you enable an alert.
- Fresh provider readings confirm scheduled resets. Rolling alerts wait for the allowance to become fully available again.
- Confirmed resets are remembered across launches. Limits that reset together produce one notification per account and one confetti animation.
- Confetti respects Reduce Motion, stays transparent, and does not intercept clicks or keyboard focus.
- CLIProxyBar refreshes at known reset times as well as during regular polling. The app must be running and connected.

Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
