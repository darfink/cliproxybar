CLIProxyBar 0.4.8 shows Antigravity's Gemini quota and lets you hide optional quota windows:

- Antigravity now shows its Gemini quota. Google reports this group only to newer Antigravity clients.
- Antigravity lists Gemini first, as 5 hours and Weekly. Claude & GPT windows follow with a prefix.
- The Antigravity menu bar figure uses Gemini. Claude & GPT stands in only when Gemini is absent.
- Settings → Display → Quota windows can hide Claude Fable, Sonnet, and Opus weekly, and Antigravity Claude & GPT.
- A hidden window leaves the menu bar, drop-down, and quota history. A hidden Fable window no longer sets the Claude weekly menu bar figure.

The app still records hidden windows and still sends their reset alerts.
Google currently reports Gemini 4 usage in neither Antigravity group, so those requests appear only in token history.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.
Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

This ZIP has an ad hoc signature and no Apple notarization.
To open the app without a block, run `xattr -dr com.apple.quarantine /Applications/CLIProxyBar.app`.
Alternatively, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
