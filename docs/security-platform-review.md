# Review-with-Security-and-Platform Checklist

Use before merging the POC into a shared/template repo or before pointing a
real workload at it.

## GitHub App configuration

- [ ] App is owned by a Customer **organization** (not an individual GitHub user).
- [ ] App permissions are documented and **minimum-necessary** for the use case.
- [ ] App is installed on **specific repositories**, not "All repositories", unless explicitly justified.
- [ ] App webhook is **disabled** (or, if enabled, the webhook URL is reviewed).
- [ ] Private key is stored only in Azure DevOps Secure Files and on the App owner's secrets manager — **not in any repo, wiki, or chat**.
- [ ] Key rotation owner and cadence are recorded (recommended: 90 days).

## Azure DevOps configuration

- [ ] Secure File `github-app.pem` is restricted to the POC pipeline (no "all pipelines" authorization).
- [ ] Variable group `github-app-poc` has `GITHUB_APP_CLIENT_ID` flagged as **secret**.
- [ ] Variable group is restricted to the POC pipeline.
- [ ] Pipeline is defined in a branch protected by required reviewers.
- [ ] Agent pool is approved for handling secrets (Microsoft-hosted **or** a hardened Customer self-hosted pool).

## Pipeline behavior

- [ ] `mintToken` step emits `installationToken` with `issecret=true`.
- [ ] All consumer steps receive the token via `env: GH_TOKEN: $(mintToken.installationToken)` — never via command-line args.
- [ ] Revoke step exists with `condition: always()`.
- [ ] Optional push step is **disabled by default** (`runOptionalPush: false`).
- [ ] Token permissions requested at mint time match the actual need (no idle `write` requests on read-only pipelines).
- [ ] `repositories:` is set; token is not silently org-wide.

## Log review (after a real run)

- [ ] Token does not appear in plaintext anywhere in the log (search the log for the first/last 4 chars of a known token from a one-off test).
- [ ] PEM contents do not appear in the log.
- [ ] JWT does not appear in the log (search for `eyJ`).
- [ ] Cleanup step shows `204 No Content`.

## Stretch (push) scenario

- [ ] Target repo for `optional-git-push.ps1` is a **sandbox**, not a production repo.
- [ ] CODEOWNERS for the target repo are aware of automated commits from the App identity.
- [ ] The branch the script writes to is **not** `main` / a protected branch.
- [ ] Commit messages are tagged (`chore(automation):`, `[skip ci]`) so they're filterable in audits.

## No PATs

- [ ] grep the repo for `PAT`, `pat=`, `personal access token`, `ghp_`, `ghs_` — **zero hits**.
- [ ] grep the pipeline for `System.AccessToken` used to call GitHub — **zero hits**.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Platform engineering | | |
| AppSec / security review | | |
| GitHub org admin | | |
| Azure DevOps admin | | |
