# Privacy and local data

CLIProxyBar sends quota requests through your configured CLIProxyAPI instance.
The [setup guide](SETUP.md) describes connections, and [Provider support](PROVIDERS.md) describes provider behavior.

## Network requests and credentials

The app accepts local or remote HTTP and HTTPS URLs. A URL cannot contain credentials, a query, or a fragment. The app refuses redirects for management requests.

The app stores the CLIProxyAPI management key in macOS Keychain. Provider quota requests pass through CLIProxyAPI with the selected account. CLIProxyBar does not read provider token files directly. Provider credentials remain in CLIProxyAPI through its account token substitution API.

The browser management page handles its own authentication. CLIProxyBar does not put the management key in browser URLs.

Use HTTPS for remote connections to protect the management key in transit. HTTPS uses normal certificate validation.

## Local files

The quota cache lives at `~/Library/Application Support/CLIProxyBar/quota-cache.json` with owner-only permissions. It contains account display names, quota values, and timestamps. It contains no management key or authentication index.

Optional usage history lives in the same directory, in a separate file for each proxy URL. It stores daily counters, model names, and hashed account identifiers. It excludes raw events, keys, headers, and response bodies. CLIProxyBar saves daily token summaries locally for up to one year.

Token history covers traffic through the configured proxy. It records the collection start and leaves earlier history empty. CLIProxyAPI's default usage queue retains events for 60 seconds. Closing the app or putting the Mac to sleep can leave gaps in recorded totals.

With CLIProxyAPI v8, retrieving an event removes it from the usage queue. Another dashboard or collector can consume events before CLIProxyBar reads them.
The [user guide](USER_GUIDE.md#token-history) recommends one collector per proxy.
Turning off **Collect token usage** pauses this app's collection and preserves saved history. CLIProxyAPI's statistics setting remains enabled for other tools.

Quota history recording is on by default. The app saves fresh quota readings from its existing refreshes, with no extra API requests. It does not save cached readings or failed requests as new observations. CLIProxyAPI's current quota endpoints do not supply earlier quota percentage history.

The app saves up to 30 days of quota history, with bounded samples per quota window. Turning recording off preserves saved history. Each proxy URL has separate history. The history file contains timestamps, percentages, and hashed identifiers. It contains no provider credentials or raw API responses.

Reset history also lives in the same directory, in a separate file for each proxy URL. It stores hashed identifiers, quota percentages, plan labels, and timestamps. It excludes account names, email addresses, and credentials.

## Updates and telemetry

CLIProxyBar includes no telemetry. Sparkle contacts GitHub to look for app updates and download them. Automatic update checks are on by default. Automatic downloads and installation are optional and off by default. Sparkle verifies signatures on the update feed and downloaded archive before installation.

Update checks do not send your proxy URL, management key, account names, or usage history.
