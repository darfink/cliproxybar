CLIProxyBar 0.2.2 makes daily activity easier to compare:

- Four distinct color levels separate quiet and busy days, even with large token counts or unusually busy days.
- The **Tokens / Requests** selector controls which daily totals determine the colors.
- Hover details continue to show exact token totals, request counts, and failures.
- The README includes current compact, expanded, and usage views in light and dark mode, with fictional accounts and sample usage.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
