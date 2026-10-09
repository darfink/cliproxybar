CLIProxyBar 0.2.1 improves usage panels and supports remote CLIProxyAPI servers:

- Settings accepts HTTP and HTTPS proxy URLs, including reverse-proxy path prefixes.
- The **Usage** panel aligns with the hovered account. A colored pointer identifies the source when screen bounds shift the panel.
- The activity grid includes month and weekday labels, a today marker, and dashed outlines for upcoming days.
- Hover over a day to see its date, tokens, requests, and failures. Earlier unrecorded days remain distinct from zero usage.

For remote servers, enable `remote-management.allow-remote` on CLIProxyAPI. Use HTTPS to protect the management key in transit.
Usage collection remains optional and covers traffic through the configured proxy while CLIProxyBar runs.
CLIProxyAPI removes usage events after retrieval. Use one collector per proxy.

Requires macOS 14 or later and a CLIProxyAPI instance with management access.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
