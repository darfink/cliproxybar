CLIProxyBar 0.4.7 opens the drop-down faster:

- The drop-down no longer builds the token and quota history view of every account when it opens.
- Each account's history view loads when you first hover over that account.

On a test Mac with four accounts, building these views took about 290 ms of each open.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.
Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

This ZIP has an ad hoc signature and no Apple notarization.
To open the app without a block, run `xattr -dr com.apple.quarantine /Applications/CLIProxyBar.app`.
Alternatively, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
