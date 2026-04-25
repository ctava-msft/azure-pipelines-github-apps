# Security Notes (Reviewer-Facing)

This document is written for a security reviewer doing a single-sitting review.

## Threat model (one-paragraph)

An attacker with one of: (a) write access to the pipeline YAML, (b) shell on the build agent during a run, (c) read access to pipeline logs, or (d) the App's PEM file, can mint installation tokens against the configured org. Each of these is mitigated by an Azure DevOps control listed below. The blast radius if a token leaks is bounded by: ≤ 1 hour lifetime, the repo list passed at mint time, and the permission set requested at mint time (which itself cannot exceed the App's configured permissions).

## Controls

| # | Control | Where enforced |
|---|---|---|
| 1 | Private key never in source | Stored as Azure DevOps **Secure File** `github-app.pem`. Downloaded to agent temp; deleted with the agent workspace at job end. |
| 2 | Private key never in env vars | Script reads PEM from disk path, not from a variable. |
| 3 | Client ID treated as secret | Stored as a **secret** variable in the `github-app-poc` variable group (defense in depth — Client ID is not strictly secret, but exposing it makes phishing easier). |
| 4 | JWT lifetime minimized | Script issues JWT with `iat = now-30s` and `exp = now+9m` (max allowed by GitHub is 10m). |
| 5 | Token lifetime minimized | GitHub installation tokens expire in ≤ 1 hour. We do not extend. |
| 6 | Token is masked in logs | Emitted via `##vso[task.setvariable variable=installationToken;issecret=true;isOutput=true]` → Azure DevOps replaces with `***`. |
| 7 | Token is repo-scoped | `POST /app/installations/{id}/access_tokens` body includes `repositories: [...]`. |
| 8 | Token is permission-scoped | Same body includes `permissions: { contents: "read", ... }`. Cannot exceed App's configured permissions. |
| 9 | Token revoked on completion | `always()` cleanup step calls `DELETE /installation/token`. |
| 10 | No PAT involved | Pipeline contains zero references to `System.AccessToken`-as-GitHub or any user PAT. |
| 11 | Logs reviewed | Setup guide instructs reviewer to grep the log for the token; expected result is "not present". |

## Secrets inventory

| Secret | Storage | Rotation owner | Rotation cadence (recommended) |
|---|---|---|---|
| GitHub App private key (PEM) | Azure DevOps Secure File | GitHub org admin | Every 90 days, or on suspicion |
| `GITHUB_APP_CLIENT_ID` | Azure DevOps secret variable | GitHub org admin | Re-read from App settings whenever PEM rotates |
| Installation access token | In-memory + masked pipeline variable | n/a — auto-expires in 1h, revoked at job end | Each run |

## Audit trail

All token-mint and API calls show up in the GitHub org **audit log** as the App identity (e.g. `customer-azpipelines-poc[bot]`). Recommend forwarding GitHub audit logs to Customer's SIEM and alerting on:
- Tokens minted from IPs outside expected Azure DevOps egress ranges.
- Tokens minted at unusual hours.
- Permission elevation attempts (App settings change).
- New installations of the App.

## Known residual risks

1. **Build agent compromise.** Anyone with shell on the agent during a run can read the PEM (briefly on disk) and the token (in-memory + env vars passed to scripts). Use ephemeral agents and restrict pool membership.
2. **Pipeline YAML tampering.** A malicious YAML edit could exfiltrate the token to an attacker-controlled endpoint. Mitigate via branch protection on the pipeline-defining branch and required code review.
3. **Over-broad App permissions.** If the App was created with `contents:write` org-wide, any pipeline that obtains a token can write anywhere. Keep App permissions minimum; prefer multiple narrowly-scoped Apps over one broad one.
4. **Secure File access creep.** Each new pipeline must be explicitly authorized. Audit periodically.
