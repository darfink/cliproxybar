CLIProxyBar 0.4.4 adds quota history, reset countdowns, and Claude plan badges:

- Quota usage graphs with session, weekly, monthly, and other windows on one 0–100% scale.
- Connected lines, a compact color legend, and hover values from recorded observations.
- Time ranges of 5 hours, 24 hours, 7 days, and 30 days, with gaps for missing observations.
- Separate Token history and Quota history tabs, with a stable header and shared card height.
- Token history as the initial default. The app remembers explicit tab choices across accounts and restarts.
- Optional reset countdowns for exhausted quotas in the menu bar and compact menu. Both settings start off.
- Claude Pro, Max 5×, and Max 20× badges from the OAuth profile through CLIProxyAPI.
- Updated README screenshots in light and dark mode, with fictional accounts and sample data.

Quota recording starts on by default and uses existing quota refreshes, without extra quota requests.
The app saves up to 30 days locally. Earlier quota history is unavailable from the current CLIProxyAPI endpoints.
Only timestamps, percentages, and hashed identifiers reach the quota history file.

Countdowns use reported future reset times. Missing reset times retain the percentage.
Quota usage that merely rounds to 100% does not trigger a countdown.
Claude profile lookups use a one-hour cache. Profile errors retain known plan labels and do not stop quota updates.

Tests cover graph gaps and hover readings, stable panel geometry, saved preferences, countdown selection, and Claude profile integration.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.
Versions before 0.2.4 need one manual or Homebrew upgrade to get the built-in updater.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
