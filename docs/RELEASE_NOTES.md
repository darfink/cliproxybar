CLIProxyBar 0.1.1 fixes misleading quota warnings in the menu bar:

- Quota cooldowns keep their percentages in the menu bar, including 0% and 100% usage.
- Disabled accounts use a pause icon instead of an error triangle.
- Failed refreshes retain cached percentages. Details still show the refresh problem and observation time.
- README screenshots use sRGB colors and keep email addresses blurred.

Requires macOS 14 or later and a local CLIProxyAPI instance.
OpenCode Go requires a plugin with native generic quota support.

This ZIP has an ad hoc signature and no Apple notarization.
If macOS blocks the downloaded app, open **System Settings → Privacy & Security**. Then select **Open Anyway**.
