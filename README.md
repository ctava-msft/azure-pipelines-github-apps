# Azure Pipelines ↔ GitHub App POC

Proof of concept: mint a short-lived **GitHub App installation token** inside an **Azure DevOps Pipeline** and use it to call GitHub — **no PATs**.

## Quick links

- 📘 Design Specification: [docs/specification.md](docs/specification.md)
- 📝 POC overview: [docs/poc-overview.md](docs/poc-overview.md)
- 🛠 Setup guide: [docs/setup-guide.md](docs/setup-guide.md)
- 🔒 Security notes: [docs/security-notes.md](docs/security-notes.md)
- 🚀 Pipeline: [azure-pipelines/azure-pipelines.poc.yml](azure-pipelines/azure-pipelines.poc.yml)
- ✅ Review checklist: [docs/security-platform-review.md](docs/security-platform-review.md)

## Reused from upstream

Patterns and input/output shapes are informed by
[`tspascoal/azure-pipelines-create-github-app-token-task`](https://github.com/tspascoal/azure-pipelines-create-github-app-token-task).
See [docs/task-or-extenson-source.md](docs/task-or-extenson-source.md) for the full reuse map.

## What this POC proves

1. Azure Pipelines can authenticate to GitHub using a **GitHub App**, not a PAT.
2. The installation token is **short-lived (≤ 1h)**, **repo-scoped**, **permission-scoped**, and **revoked** at end of job.
3. The token is usable by any step in the job via a masked output variable.
4. The pattern is reviewable, reproducible, and a clean stepping-stone to a packaged Azure DevOps extension.

## Scaling to tens of thousands of pipelines (programmatic rollout)

Question: *can we automate creating and wiring a GitHub App across 10k+ Azure Pipelines so we don't manage 10k+ PATs?* — **Yes, mostly. Two parts: (1) the GitHub App itself, (2) the per-pipeline ADO wiring.**

### Part 1 — Provisioning the GitHub App

You do **not** create one App per pipeline. You create **one App per trust boundary** (typically one per GitHub org, or one per environment per org) and install it on the repos that need it. The pipelines all share that App — token issuance is per-installation and per-job, so blast radius stays bounded.

GitHub itself does not expose a "create a GitHub App" REST endpoint for arbitrary creation; an org owner registers the App once via:

- The UI (`https://github.com/organizations/<org>/settings/apps/new`), **or**
- The [App Manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) — POST a JSON manifest to `/settings/apps/new`, the user clicks once, and GitHub returns the App ID, client ID, **PEM private key**, and webhook secret to your callback URL. This is the one-click bootstrap suitable for codifying.

Everything **after** registration is fully programmatic (REST + Octokit + Terraform `github_app_installation_*` data sources):

| Operation | API |
|---|---|
| List installations | `GET /app/installations` |
| Install on a repo / set repo selection | `PUT /user/installations/{id}/repositories/{repo_id}` (user) / org-managed via UI policy + `PATCH /orgs/{org}/installations/{id}` |
| Add/remove repos from an installation | `PUT/DELETE /user/installations/{installation_id}/repositories/{repository_id}` |
| Mint installation token | `POST /app/installations/{id}/access_tokens` |
| Rotate the App private key | `POST /app/manifests/{code}/conversions` (manifest flow) or UI (generate new PEM, distribute, delete old) |

Practical pattern: register once via manifest, store the resulting PEM in **Azure Key Vault**, automate everything else.

### Part 2 — Wiring 10k+ Azure Pipelines

This is the part that is **fully scriptable** today via the Azure DevOps REST API + `az pipelines` CLI. Nothing here requires per-pipeline manual work.

1. **One Variable Group, one Secure File, project-scoped.** Place the App Client ID and any common config in a single ADO Variable Group (linked to Key Vault, so secret rotation is automatic). Upload the PEM once as a Secure File. Authorize both for *all pipelines* in the project. Every pipeline references the same names — no per-pipeline secret material.
   - Variable Group: `POST /{org}/{project}/_apis/distributedtask/variablegroups`
   - Key Vault link: set `type=AzureKeyVault` on the variable group
   - Secure File upload: `POST /{org}/{project}/_apis/distributedtask/securefiles?name=...` (octet-stream)
   - Authorize all pipelines: `PATCH /{org}/{project}/_apis/pipelines/pipelinepermissions/{resourceType}/{id}` with `allPipelines.authorized=true`

2. **Ship the token-mint logic as a shared template, not copy-paste.** Put the YAML in a single repo (e.g. `pipeline-templates`) and have product pipelines reference it via `extends:` or a `template:` step. Updating the mint logic across 10k pipelines becomes a one-line PR in the template repo. (See `azure-pipelines/azure-pipelines.poc.yml` for the current step set.)

3. **Bulk-create or migrate pipelines.** For greenfield rollout, drive `POST /{org}/{project}/_apis/pipelines` from a CSV/inventory of repos. For brownfield migration off PATs, iterate existing pipelines via `GET /{org}/{project}/_apis/pipelines`, open a PR against each backing repo that swaps the PAT-based steps for the shared template `extends`. Tools like `gh repo-list` + `dotnet-format`/`yq` make this a batch job.

4. **Service connections (post-POC, when the upstream task is published as a private extension).** A "GitHub App" service connection holds the App ID + PEM once, per project. Create them programmatically:
   - `POST /{org}/{project}/_apis/serviceendpoint/endpoints?api-version=7.1`
   - Authorize all pipelines: `PATCH /{org}/{project}/_apis/pipelines/pipelinepermissions/endpoint/{id}`
   This collapses the Variable Group + Secure File pair into one resource and removes the need for ad-hoc PowerShell to mint tokens.

### Recommended end state for scale

- **1 GitHub App per org** (registered via manifest), PEM in **Azure Key Vault**.
- **1 ADO Variable Group per project**, Key-Vault-backed, authorized for all pipelines.
- **1 GitHub App service connection per project** once the [`tspascoal/azure-pipelines-create-github-app-token-task`](https://github.com/tspascoal/azure-pipelines-create-github-app-token-task) extension (or an internal fork) is published privately.
- **1 shared YAML template** consumed via `extends:` by every product pipeline.
- **PEM rotation** is a single Key Vault secret update — pipelines pick it up on next run.

Net result: onboarding pipeline #10,001 is a templated PR, not a ticket.

### Org-cap planning: 4 GitHub orgs × 100 GitHub Apps each

GitHub enforces a soft cap of **100 GitHub Apps owned per org**. With 4 customer orgs, the absolute ceiling is **400 Apps total** — far more than this design needs.

**Design budget per org (recommended):**

| App | Purpose | Count |
|---|---|---|
| `customer-azpipelines-prod` | Production CI/CD pipelines (read+write to allowed repos) | 1 |
| `customer-azpipelines-nonprod` | Dev/staging/sandbox pipelines (read+write, broader repo set) | 1 |
| `customer-azpipelines-readonly` | Audit, inventory, reporting jobs | 1 |
| Reserved (e.g. release-bot, security-scan, dependabot-mirror) | Domain-specific automations | 3–5 |
| **Total per org** | | **~6–8 Apps** |

That's **~24–32 Apps across all 4 orgs**, leaving 70+ headroom per org for future automations. The cap is **not a constraint** for this rollout; it only matters if a team starts treating Apps as throwaway, per-team or per-repo identities (which they should not).

**Rules to stay well under the cap:**

1. **One App per (org × trust tier)**, not per pipeline / team / repo. Trust tiers = prod / non-prod / read-only.
2. **Scope via installation, not via App.** A single App can be installed on a subset of repos with different permissions per installation; create new installations, not new Apps.
3. **Permissions on the App = the *maximum* it can ever request.** Token mint can request a *subset* (this POC does — see `GITHUB_TOKEN_PERMISSIONS`). Don't fragment Apps just to narrow permissions.
4. **Centralize ownership.** All Apps owned by org admins; PEMs live in **Azure Key Vault**; rotation is a single KV secret update per App.
5. **Inventory + alert.** Run a daily job (`GET /orgs/{org}/installations`, `GET /app` per App) that records App count per org and alerts at >70% of cap (≥70 Apps).

**Cross-org pattern.** When a single pipeline must touch repos in multiple orgs, prefer **one App per org with the same Client ID convention**, mint two tokens in the same job, and target each org with its own token. Do **not** try to register a single App that spans orgs — GitHub doesn't support that, and it would also dilute the audit trail.


