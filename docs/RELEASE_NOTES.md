CLIProxyBar 0.4.5 adds Claude Fable usage, Settings tabs, and account removal:

- Claude Fable weekly usage, with its own reset time and reset alerts.
- Settings tabs for Display, Accounts, Alerts & History, and Connection.
- An Accounts tab that lists the provider credentials on your CLIProxyAPI.
- Credential file removal from the Accounts tab, after confirmation.
- No reset alerts or confetti for a session or model window while its weekly or monthly quota stays exhausted.

Anthropic reports Fable only as a scoped weekly limit. Other scoped model limits also appear when Anthropic reports them.
The menu bar weekly percentage shows the Claude weekly window closest to its limit, including Fable.

Removal deletes the credential from CLIProxyAPI. This affects every client of that proxy. Add the credential again to restore access.
Accounts from proxy settings and runtime accounts stay read-only. Manage them in CLIProxyAPI.
Saved usage and quota history remain after removal.

Without a management key, the app now opens Settings on the Connection tab.

Tests cover scoped Claude limits, credential removal checks, Settings navigation, and parent quota suppression.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.
Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
