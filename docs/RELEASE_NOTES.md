CLIProxyBar 0.4.9 shows the Antigravity usage that your proxy traffic consumes:

- Antigravity quota now comes from Google's daily service. CLIProxyAPI sends its Antigravity requests to that service.
- Before this release, the app read a separate meter on Google's production service. That meter stayed at 0% used for proxy traffic.
- The Gemini quota includes Gemini 4 models, such as Gemini 4 Neon.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.
Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

This ZIP has an ad hoc signature and no Apple notarization.
To open the app without a block, run `xattr -dr com.apple.quarantine /Applications/CLIProxyBar.app`.
Alternatively, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
