CLIProxyBar 0.4.10 makes reset alerts easier to read and can open at login:

- Reset notifications now read as one sentence, such as "Weekly limit restored, including Fable."
- Antigravity reset notifications name the group, such as "Gemini weekly limit restored."
- Settings → Connection → Startup has an Open at login checkbox. It uses the macOS login item, so it matches System Settings → General → Login Items.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.
Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

This ZIP has an ad hoc signature and no Apple notarization.
To open the app without a block, run `xattr -dr com.apple.quarantine /Applications/CLIProxyBar.app`.
Alternatively, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
