CLIProxyBar 0.2.4 makes installation and updates easier:

- Install with the Homebrew command in the README. The tap lives in the app repository.
- Sparkle checks GitHub Releases for updates and verifies signatures before installation.
- **Settings → App updates** includes a manual check and options for automatic checks and installation.
- Automatic checks are enabled by default. Automatic installation is disabled by default.
- Each release updates the Homebrew cask's version and checksum automatically.

Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

CLIProxyAPI records request usage. CLIProxyBar collects these events and saves daily summaries locally while the app runs.
The usage queue retains events for about a minute. Closing the app or sleep can create gaps in recorded history.
Use one collector per proxy because retrieval removes events from the queue.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
