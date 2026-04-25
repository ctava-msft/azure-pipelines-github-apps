# Customer POC — Azure Pipelines ↔ GitHub App Authentication

> Master design document. All other docs in this repo derive from this file.

---

## 1. Solution Summary

This POC proves that an **Azure DevOps Pipeline** can authenticate to **GitHub** using a **GitHub App** (no Personal Access Tokens), mint a **short-lived installation access token** at runtime, and use that token for one or more controlled GitHub operations (read repo metadata, list branches, optionally write a commit/comment/status).

The implementation is intentionally minimal:

- A GitHub App private key (PEM) is stored as an Azure DevOps **Secure File** (and the App Client ID as a secret variable).
- A PowerShell script generates a JWT (RS256), exchanges it for an installation token via the GitHub REST API, and emits the token as a **masked pipeline output variable**.
- Subsequent pipeline steps consume the token only via secret variables and environment variables — never echoed.
- The token is **revoked** at the end of the job to minimize blast radius.

The reference project [`tspascoal/azure-pipelines-create-github-app-token-task`](https://github.com/tspascoal/azure-pipelines-create-github-app-token-task) is used as conceptual inspiration (input shape, service-connection idea, output variable names). We deliberately **do not require** a published Azure DevOps extension for the POC, because:

- Customer would need to package, sign, and publish a private extension before use.
- The same security properties can be achieved with ~80 lines of inline PowerShell.
- A future "productionization" step can swap our inline script for the packaged task with **no pipeline changes** other than the task reference (we keep the same output variable names: `installationToken`, `installationId`, `tokenExpiration`).

---

## 2. Problem Statement

Customer operates in a **coexistence model**:

- Azure DevOps Pipelines = system of control for CI/CD and release governance.
- GitHub = source of truth for code, collaboration, and innovation.

Today, automation that needs to call GitHub from Azure Pipelines (beyond the built-in checkout/status integration) tends to fall back to **Personal Access Tokens (PATs)**. PATs are:

- Long-lived (often 90+ days, sometimes never-expiring).
- Tied to an individual user → leaves orphaned access when people change roles.
- Broadly scoped (hard to scope to a single repo + minimal permission set).
- A frequent finding in security audits.

We need a path that lets pipelines authenticate to GitHub using **org-owned, short-lived, narrowly-scoped** credentials.

---

## 3. Why GitHub App Auth Is Preferred Over PATs

| Property | PAT | GitHub App Installation Token |
|---|---|---|
| Owner | Individual user | Organization-owned app |
| Lifetime | Up to 1 year (often longer if classic) | **1 hour max**, revocable on demand |
| Scope | User-wide; coarse scopes | Per-installation, per-repo, per-permission |
| Auditability | Logged as the user | Logged as the App (clear provenance) |
| Rate limits | 5,000 req/hour shared | 5,000 req/hour per installation (scales with repos) |
| Rotation | Manual | Automatic (re-mint each run) |
| Offboarding risk | Token survives user departure | App is org-owned; immune to user churn |

GitHub App tokens are the **GitHub-recommended** automation credential.

---

## 4. Built-in Azure Pipelines GitHub Integration vs. What This POC Adds

Azure Pipelines already supports a "GitHub App" service connection used for:

- Triggering pipelines on GitHub events.
- `checkout` of a GitHub repo.
- Reporting commit/PR statuses back to GitHub.

**What it does not give you:**

- A usable, exportable **installation access token** that your scripts can call arbitrary GitHub REST/GraphQL APIs with.
- Fine-grained per-repo, per-permission scoping at pipeline runtime.
- A documented pattern for repo mutation (commits, comments, labels, releases, deployments, dispatching workflows, etc.) from inside a pipeline step.

**This POC fills exactly that gap**: minting an on-demand, short-lived installation token usable by any step in the job.

---

## 5. Architecture

```
┌────────────────────────────────────────────────────────────────┐
│ Azure DevOps Project                                           │
│                                                                │
│   ┌──────────────────────┐        ┌─────────────────────────┐  │
│   │ Secure File          │        │ Variable Group          │  │
│   │  github-app.pem      │        │  GITHUB_APP_CLIENT_ID   │  │
│   │  (private key)       │        │  GITHUB_OWNER           │  │
│   └──────────┬───────────┘        │  GITHUB_REPOS           │  │
│              │                    └────────────┬────────────┘  │
│              ▼                                 ▼               │
│   ┌────────────────────────────────────────────────────────┐   │
│   │ Pipeline job (azure-pipelines.poc.yml)                 │   │
│   │                                                        │   │
│   │  Step 1: DownloadSecureFile@1   (PEM → agent temp)     │   │
│   │  Step 2: scripts/create-github-app-token.ps1           │   │
│   │           - build JWT (RS256, 10-min exp)              │   │
│   │           - GET /app/installations                     │   │
│   │           - POST /app/installations/:id/access_tokens  │   │
│   │           - emit ##vso[task.setvariable;issecret=true] │   │
│   │  Step 3: scripts/validate-token.ps1   (read-only)      │   │
│   │  Step 4: scripts/call-github-api.ps1  (read-only)      │   │
│   │  Step 5 (optional): scripts/optional-git-push.ps1      │   │
│   │  Step 6 (always):  revoke-token.ps1                    │   │
│   └────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────┬─────────────────────────┘
                                       │ HTTPS (api.github.com)
                                       ▼
                         ┌─────────────────────────────┐
                         │ GitHub App                  │
                         │  - private key (PEM)        │
                         │  - installed in org         │
                         │  - scoped to N repos        │
                         │  - minimal permissions      │
                         └─────────────────────────────┘
```

### Token lifecycle

1. **JWT** (signed with App private key, RS256, ≤ 10 min lifetime) → authenticates *as the App*.
2. JWT → `GET /app/installations` → discover installation ID for the target org.
3. JWT → `POST /app/installations/{id}/access_tokens` with `{ repositories: [...], permissions: {...} }` → returns an **installation access token** (1 hour max, narrower than the App's max permissions).
4. Pipeline uses installation token for normal `Authorization: Bearer ...` REST calls.
5. End of job: `DELETE /installation/token` → revokes the token immediately.

---

## 6. Security Boundaries & Assumptions

### Assumptions
- The GitHub App is **owned by a Customer GitHub org**, not an individual.
- The App's private key is stored as an **Azure DevOps Secure File** with restricted pipeline permissions.
- The Azure DevOps project, agent pool, and service connections follow Customer's existing access-control standards.
- The pipeline runs on a **trusted agent** (Microsoft-hosted or Customer-managed self-hosted). The agent is treated as a trust boundary — anyone with shell on the agent during the run can read the token.

### Boundaries enforced by this design
- Private key **never appears** in a pipeline log, repo, or variable expansion.
- Installation token is registered as a **secret** with `##vso[task.setvariable;issecret=true]` → Azure DevOps masks it from logs.
- Installation token is **scoped to specific repos** via the `repositories` parameter on the access-token request.
- Installation token has **minimal permissions** (e.g., `contents:read`) requested explicitly; cannot exceed the App's configured permissions.
- Installation token is **revoked** in an `always()` cleanup step.
- No PAT is created, stored, or referenced anywhere.

### Out-of-scope for the POC
- Multi-tenant / multi-org pipelines.
- Enterprise-installation tokens (the reference repo supports them; we leave that as a follow-up).
- Self-hosted GitHub Enterprise Server endpoints (only github.com is targeted).
- Caching tokens across jobs (each job mints fresh).

---

## 7. Limitations / Known Gaps

| Area | Limitation |
|---|---|
| Extension packaging | We use inline scripts, not a published Azure DevOps task. Trade-off: simpler to review, but less reusable across many pipelines. |
| Proxy support | Not implemented (reference repo handles `HTTP_PROXY`/`HTTPS_PROXY`). Add if Customer's agents are behind a forward proxy. |
| Enterprise installs | Only `org` account type is implemented. |
| GHES | Hardcoded to `https://api.github.com`. Parameterize for GHES. |
| Pagination | `GET /app/installations` is not paginated in our script (fine for ≤ 30 installations). |
| Key rotation | Manual: re-upload the new PEM as a new Secure File version and update reference. No automation. |

---

## 8. Next-Step Path If The POC Succeeds

1. **Harden as a shared template**
   Move `azure-pipelines.poc.yml` and the scripts into a Customer-internal template repo; consume via `extends` / `template:` in product pipelines.
2. **Package as a private Azure DevOps extension**
   Adopt the reference repo's TypeScript task and publish as a private extension under a Customer publisher ID. This gives a single `task: create-github-app-token@1` line per pipeline. Output variable names are already aligned.
3. **Add a "GitHub App" service connection type**
   The reference repo includes the manifest for a custom service connection. This removes the need for a Secure File per pipeline.
4. **Centralize key management**
   Move the PEM out of Secure Files into Azure Key Vault; replace the Secure File download with an Azure CLI / Key Vault step using a workload-identity service connection. No PAT, no PEM-on-disk.
5. **Onboard real workloads**
   Pilot with: PR labelers, release-note generators, repo metadata sync, deployment status reporters, etc.
6. **Audit & telemetry**
   Pipe GitHub audit-log events for the App into Customer's SIEM. Alert on tokens minted outside expected pipelines.

---

## 9. Folder Structure

```
azure-pipelines-github-apps/
├── README.md                              ← entry point / quick links
│
├── docs/
│   ├── specification.md                   ← this file (master design)
│   ├── poc-overview.md                    ← exec summary of sections 1–4
│   ├── setup-guide.md                     ← step-by-step reproduction
│   ├── security-notes.md                  ← reviewer-facing security notes
│   ├── security-platform-review.md        ← pre-merge review checklist
│   ├── task-or-extenson-source.md         ← what we reused/skipped from upstream
│   └── example-service-connection-usage.md ← future-state with extension
│
├── azure-pipelines/
│   ├── azure-pipelines.poc.yml            ← the working sample pipeline
│   └── example-variable-template.yml      ← variable group / parameter pattern
│
└── scripts/
    ├── create-github-app-token.ps1        ← JWT + installation token mint
    ├── revoke-github-app-token.ps1        ← token cleanup (always() step)
    ├── validate-token.ps1                 ← sanity-check the minted token
    ├── call-github-api.ps1                ← read-only API demo
    └── optional-git-push.ps1              ← stretch: controlled mutation
```

---

## 10. Reuse Map vs. `tspascoal/azure-pipelines-create-github-app-token-task`

| Upstream concept | Reused? | Where in this POC |
|---|---|---|
| JWT (RS256) → installation token flow | ✅ Yes | `scripts/create-github-app-token.ps1` |
| Output variable names (`installationToken`, `installationId`, `tokenExpiration`) | ✅ Yes | same script, `##vso[task.setvariable]` lines |
| `repositories` and `permissions` inputs | ✅ Yes | script parameters |
| Auto-revoke at end of job (`skipTokenRevoke` default = false) | ✅ Yes | `revoke-github-app-token.ps1` + `always()` step |
| Service-connection type for GitHub App | ⏭ Deferred | `docs/example-service-connection-usage.md` (next-step) |
| Enterprise installation support | ⏭ Deferred | not needed for POC |
| Proxy env-var detection | ⏭ Deferred | document as gap |
| TypeScript task / vss-extension packaging | ❌ Skipped | unnecessary for POC; see `docs/task-or-extenson-source.md` |
| Jest unit tests, coverage gates | ❌ Skipped | out of POC scope |

---

## 11. Success Criteria

The POC passes if **all** of the following are true after a single pipeline run:

1. ✅ Pipeline successfully generates a GitHub App installation token (`installationToken` output is set).
2. ✅ Token expiration (`tokenExpiration`) is **≤ 1 hour** in the future.
3. ✅ Token is used to complete at least one authenticated GitHub operation (e.g., `GET /repos/{owner}/{repo}` returns 200).
4. ✅ No PAT exists or is referenced anywhere in the pipeline, scripts, or service connections.
5. ✅ Token value never appears in pipeline logs (verify by searching the log; it should appear as `***`).
6. ✅ Repo access is limited to the explicitly listed `repositories` (verify by attempting an API call to a repo *not* in scope and observing 404).
7. ✅ Token is successfully revoked in the `always()` cleanup step (`DELETE /installation/token` → 204).
8. ✅ A platform engineer unfamiliar with the POC can reproduce it end-to-end using only [setup-guide.md](setup-guide.md).

---

## 12. Optional Stretch Goal — Controlled Repo Mutation

`scripts/optional-git-push.ps1` demonstrates committing a generated metadata file (`.github/automation/last-run.json`) to a designated **sandbox repository** using the minted installation token as the Git credential.

**Appropriate for:** generated docs, release notes, build-metadata sidecars, automation-owned config files in a repo that humans don't co-edit.

**Not appropriate for:**
- Repos with branch protection requiring code-owner review (the App identity bypasses humans → audit/governance concern).
- Anything touching production config, IaC, or compliance-sensitive paths without explicit Customer approval and a CODEOWNERS-enforced review path.
- Any operation that should be attributable to a human author.

---

## 13. Review-with-Security/Platform Checklist (summary)

Full version: [security-platform-review.md](security-platform-review.md)

- [ ] GitHub App is org-owned, not user-owned.
- [ ] App permissions documented and minimum-necessary.
- [ ] PEM stored as Secure File; pipeline-level access restricted.
- [ ] Pipeline uses `issecret=true` when emitting the token.
- [ ] Token is repo-scoped via `repositories` parameter.
- [ ] Token is revoked in an `always()` step.
- [ ] Logs reviewed: no PEM, no JWT, no installation token in plaintext.
- [ ] No PATs introduced.
- [ ] Stretch (push) scenario: target repo is sandbox; CODEOWNERS reviewed.
