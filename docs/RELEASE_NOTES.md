CLIProxyBar 0.2.0 adds account hover panels for proxy usage:

- Both menus show token totals, a token breakdown, daily activity, and totals by model.
- The **Collect token usage** option enables usage statistics on CLIProxyAPI and saves daily summaries locally.
- Each panel labels the start of collection. Earlier days show no recorded history.
- The app saves counters and hashed account identifiers, without raw events, keys, headers, or response bodies.

Collection covers requests through the local proxy while CLIProxyBar runs. Closing the app or sleep can create gaps.
CLIProxyAPI removes usage events after retrieval. Use one collector per proxy.

Requires macOS 14 or later and a local CLIProxyAPI instance.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
