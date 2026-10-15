# Provider support

CLIProxyBar reads quota data from CLIProxyAPI for configured accounts. Support depends on a provider allowance API or a plugin with generic quota support. The [README](../README.md) describes installation and app use.

## Supported quotas

| Provider | Quota windows | Extra information |
| --- | --- | --- |
| Claude Code | Five-hour session, weekly | Pro and Max plan labels come from the OAuth profile through CLIProxyAPI. |
| Codex | Session, weekly | If the provider supplies them, plan labels and available resets appear with quota data. |
| OpenCode Go | Rolling, weekly, monthly | Plan labels come from the generic plugin quota API. |
| Antigravity | Provider groups or per-model limits | The app looks up project and plan details. Response fixtures cover these lookups. |
| Generic quota plugins | Windows supplied by the plugin | Plugins can provide groups, reset times, plan labels, and numeric summaries. |

OpenCode Go requires CLIProxyAPI v8 and a companion plugin with native generic quota support. The [OpenCode Go plugin](https://github.com/massiveits/opencode-go-cliproxyapi) and [upstream pull request #10](https://github.com/massiveits/opencode-go-cliproxyapi/pull/10) provide more information. A plugin version with only its separate quota page does not support this integration.

## Generic quota plugins

CLIProxyBar discovers plugin capabilities through `GET /v0/management/quota/providers` and account `supports_quota` flags. It reads normalized quotas through `POST /v0/management/quota/fetch`. Plugins that implement these endpoints do not need a separate app adapter.

The app uses backend metadata for provider names and plan labels. Numeric summaries preserve units and use your locale for number and currency formats. A successful response with no quota limits stays neutral. The menu distinguishes unavailable quotas, cached readings, and failed requests.

When the app knows a generic plugin's window behavior, it gives that plugin pace indicators and reset alerts. Providers without an allowance API show no quota data. Unknown quota does not mean zero usage.

Every configured provider can appear in the menu and optional usage history. **Settings** lists detected providers and has separate visibility controls for the menu bar and drop-down.

## Provider details

Claude plan lookups use CLIProxyAPI's account token substitution. Provider credentials remain in the proxy. The app caches plan labels for one hour and retries failed profile lookups after five minutes. Profile lookup failures do not prevent quota updates. Existing cached labels remain available.

Gemini API keys from Google AI Studio appear as accounts beside Gemini OAuth accounts. CLIProxyAPI supplies request usage for API key accounts, but it exposes no allowance quotas for them. CLIProxyBar does not retain provider key values.

CLIProxyAPI also routes Gemini, Vertex AI, AI Studio, Kimi, Grok, Devin, Meta, and compatible API endpoints. Additional providers depend on installed plugins and the CLIProxyAPI version. Routing support alone does not establish an API for subscription quotas.

## Pace estimates

Pace compares used quota with elapsed time in a fixed window. It is an estimate, not a provider guarantee. OpenCode Go uses a five-hour rolling window and a seven-day weekly window for pace estimates.

Monthly pace uses the UTC billing anniversary and the actual month length. If the reset date permits different cycle starts, the app hides monthly pace.

## Integration validation

New integrations use response fixtures and request tests without provider credentials. Live account checks cover Claude, Codex, and OpenCode Go. Antigravity and other plugins still need live validation by someone with an account.
