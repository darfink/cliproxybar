CLIProxyBar 0.4.6 hides files that are not provider credentials:

- CLIProxyAPI lists every JSON file in its auth directory, including model catalogs. Files without a provider type no longer appear as Unknown accounts.
- These files no longer appear in the menu bar, the drop-down, or the Accounts tab.

To remove them from CLIProxyAPI as well, keep model catalogs and other non-credential files outside the proxy `auth-dir`.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.
Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

This ZIP has an ad hoc signature and no Apple notarization.
To open the app without a block, run `xattr -dr com.apple.quarantine /Applications/CLIProxyBar.app`.
Alternatively, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
