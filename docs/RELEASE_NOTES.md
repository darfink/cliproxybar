CLIProxyBar 0.2.3 fixes interaction with the Usage card:

- Click **Tokens** or **Requests** without closing the Usage card or the main menu.
- Native submenus keep the card beside its account and handle mouse clicks, hover navigation, and dismissal.
- **⌘R** also refreshes quotas from inside the Usage card.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
