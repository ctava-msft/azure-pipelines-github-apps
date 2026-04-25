# Setup Guide

End-to-end steps for a platform engineer to reproduce the POC.

## 1. Prerequisites

- An Azure DevOps **project** you can administer (create variable groups, secure files, pipelines).
- A **GitHub organization** you can administer (create GitHub Apps, install them on repos).
- A test/sandbox repository in that org for read calls (and a *separate* sandbox repo if you intend to test the optional push step).
- Azure Pipelines agent: Microsoft-hosted `windows-latest` (PowerShell 7 preinstalled) — or any agent with PowerShell 7 + `dotnet` runtime available.

## 2. Create the GitHub App

1. In your GitHub org → **Settings → Developer settings → GitHub Apps → New GitHub App**.
2. Fill in:
   - **Name**: `customer-azpipelines-poc` (or similar)
   - **Homepage URL**: any internal URL.
   - **Webhook**: **uncheck "Active"** (we don't need webhooks for this POC).
3. **Repository permissions** — request the minimum needed. For the read POC:
   - `Contents`: **Read-only**
   - `Metadata`: **Read-only** (auto-required)
   For the optional push stretch goal, also:
   - `Contents`: **Read & write**
4. **Where can this GitHub App be installed?** → **Only on this account** (your org).
5. Create the App. Note the **App ID** and **Client ID** shown on the App settings page.
6. Scroll to **Private keys** → **Generate a private key**. A `.pem` file downloads. **Treat as a secret.**
7. **Install App** (left sidebar) → install on **only the repositories** the POC needs (do **not** select "All repositories" for production usage).

## 3. Store secrets in Azure DevOps

### 3a. Upload the PEM as a Secure File
1. Azure DevOps → **Pipelines → Library → Secure files → + Secure file**.
2. Upload the `.pem` file. Name it exactly `github-app.pem`.
3. Open the file → **Pipeline permissions** → grant access to the pipeline you'll create in step 5 (or check "Authorize for use by all pipelines" only if your governance allows).

### 3b. Create a variable group
1. Azure DevOps → **Pipelines → Library → Variable groups → + Variable group**.
2. Name: `github-app-poc`.
3. Add variables:
   | Name | Value | Secret? |
   |---|---|---|
   | `GITHUB_APP_CLIENT_ID` | the **Client ID** from step 2.5 (e.g. `Iv23li...`) | ✅ |
   | `GITHUB_OWNER` | the GitHub org login (e.g. `customer-sandbox`) | ❌ |
   | `GITHUB_REPOS` | comma-separated repo names the App is installed on (e.g. `automation-sandbox`) | ❌ |
   | `GITHUB_TEST_REPO` | one repo from the list above to use for the read demo | ❌ |
4. Save. Authorize the pipeline to use the variable group when prompted on first run.

> **Note:** GitHub now recommends using the **Client ID** (string starting with `Iv23...` for new apps, or numeric App ID for older apps) as the JWT `iss`. Either works; we use whatever you put in `GITHUB_APP_CLIENT_ID`.

## 4. Bring this repo into Azure DevOps

You have two options:

- **Option A (recommended for the POC):** Mirror this folder into an Azure Repos Git repository in your Azure DevOps project.
- **Option B:** Use the GitHub repo as the pipeline source via the standard GitHub service connection (the POC's *runtime* auth — minting the installation token — is independent of how the pipeline source is fetched).

## 5. Create the pipeline

1. Azure DevOps → **Pipelines → New pipeline**.
2. Select your repo source from step 4.
3. **Existing Azure Pipelines YAML file** → choose `azure-pipelines/azure-pipelines.poc.yml`.
4. **Save** (do not run yet).
5. Open the pipeline → **Edit → Triggers / Variables / Permissions**:
   - Confirm the variable group `github-app-poc` is linked.
   - Confirm the secure file `github-app.pem` is authorized.
6. **Run pipeline.** Optionally set the parameter `runOptionalPush=false` (default) for the first run.

## 6. Expected output

In the pipeline run logs you should see:

```
=== Generate GitHub App installation token ===
Generated JWT (length: ###)
Found installation id: 12345678
Token minted. Expires: 2026-04-23T18:42:11Z
##vso[task.setvariable variable=installationToken;issecret=true;isOutput=true]***
##vso[task.setvariable variable=installationId;isOutput=true]12345678
##vso[task.setvariable variable=tokenExpiration;isOutput=true]2026-04-23T18:42:11Z

=== Validate token ===
GET /app -> 200 OK ; app slug: customer-azpipelines-poc

=== Call GitHub API ===
GET /repos/<owner>/<repo> -> 200 OK
Default branch: main ; visibility: private

=== Revoke token (always) ===
DELETE /installation/token -> 204 No Content
```

The token itself **must appear as `***`** in logs. If you see the raw token, stop and treat as an incident — it means `issecret=true` was not honored.

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `401 Unauthorized` on `GET /app` | JWT signed with wrong key, wrong `iss`, or clock skew | Re-confirm `GITHUB_APP_CLIENT_ID`; ensure agent clock is synced; regenerate PEM if rotated. |
| `404 Not Found` on `/app/installations` lookup | App not installed on the org | Re-install the App on the org and the target repos. |
| `422 Unprocessable Entity` on `access_tokens` | Requested permission exceeds App's configured permission | Either reduce the requested permission, or grant it on the App settings page. |
| `404` on `GET /repos/{owner}/{repo}` | Repo not in the App's installation, or token wasn't scoped to it | Add repo to install; ensure repo name is in `GITHUB_REPOS`. |
| Token visible in logs | `issecret=true` flag missing on `setvariable` | Verify `scripts/create-github-app-token.ps1` line that emits the token. |
| Secure file not found | Secure file not authorized for this pipeline | Library → Secure files → Pipeline permissions → grant pipeline access. |
| `403 Resource not accessible by integration` on a write call | App lacks `contents:write` (or other) permission | Update the App permissions in GitHub and **accept the new permissions** on the installation. |
