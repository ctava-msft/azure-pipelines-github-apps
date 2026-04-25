# Reuse map vs. upstream

Upstream: <https://github.com/tspascoal/azure-pipelines-create-github-app-token-task>

This POC deliberately **does not vendor the upstream TypeScript task** into
this repo. Pulling the TS source would (a) require Customer to package, sign,
and publish a private Azure DevOps extension before the POC can run, and
(b) make the security review surface ~10x larger (Node deps, Jest config,
extension manifest, etc.). The same security properties — short-lived,
scoped, masked, revocable installation token — are achievable with a single
PowerShell script that a reviewer can read in one sitting.

## What we reused conceptually

| Upstream concept | Where in this POC |
|---|---|
| JWT (RS256) → `GET /app/installations` → `POST .../access_tokens` flow | [`scripts/create-github-app-token.ps1`](../scripts/create-github-app-token.ps1) |
| Output variable names: `installationToken`, `installationId`, `tokenExpiration` | same script |
| `repositories` (comma-separated) input | same script `-Repositories` parameter |
| `permissions` (JSON) input | same script `-Permissions` parameter |
| Auto-revoke at job end (upstream `skipTokenRevoke` default `false`) | [`scripts/revoke-github-app-token.ps1`](../scripts/revoke-github-app-token.ps1) + `always()` step |
| Service-connection idea (`githubAppConnection` input) | Documented as future state in [`../samples/example-service-connection-usage.md`](../samples/example-service-connection-usage.md) |
| Per-pipeline example patterns (read repo, push commit) | [`../scripts/call-github-api.ps1`](../scripts/call-github-api.ps1), [`../scripts/optional-git-push.ps1`](../scripts/optional-git-push.ps1) |

## What we omitted, and why

| Upstream feature | Omitted because |
|---|---|
| TypeScript task implementation (`create-github-app-token/`) | POC doesn't need a packaged extension. Adopt during productionization. |
| `vss-extension.json` + `task.json` | Same — only needed to publish to the marketplace / a private publisher. |
| Enterprise-installation token support (`accountType: enterprise`) | Not in POC scope. |
| Proxy auto-detection (`HTTP_PROXY`/`HTTPS_PROXY`) | Add when targeting Customer self-hosted agents behind a forward proxy. |
| Jest unit tests, coverage thresholds | Out of POC scope. |
| GitHub Actions CI for the task itself | We're not building the task; only consuming the pattern. |

## License

The upstream project is MIT licensed. If/when Customer adopts the upstream task
verbatim, retain the original `LICENSE` and copyright notice and add the
Customer publisher metadata to a fork.
