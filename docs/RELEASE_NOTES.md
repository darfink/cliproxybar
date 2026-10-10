CLIProxyBar 0.4.1 improves generic provider quotas and daily activity:

- Provider names use backend metadata in menus and Settings. The provider selector scrolls when many providers are available.
- Plan labels support more subscription fields. Numeric summaries preserve units and use your locale for number and currency formats.
- Duplicate quota windows have distinct labels. Quota identities stay stable when the backend changes their order.
- Successful responses with no quota limits remain neutral. Cached readings, unavailable quotas, and failed requests have separate states.
- Failed requests preserve earlier readings. Cached accounts retain plan labels and empty responses after relaunch.
- Generic requests honor the account's quota provider override. Refresh results match the provider and credential identity.
- Pace indicators and reset alerts require known window behavior. Generic window labels alone do not establish reset behavior.
- Today has a thicker outline along the activity square's border. The outline preserves the activity color, and its legend stays hollow.

Response fixtures cover the generic quota contract. Claude, Codex and OpenCode Go passed live checks against a local CLIProxyAPI instance.
Antigravity and additional plugins still need live account validation.

Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
