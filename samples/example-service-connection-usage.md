# Future-state: GitHub App service connection usage

This is the **post-POC** shape, after Humana publishes the upstream task as a
private Azure DevOps extension and creates a "GitHub App" service connection
type. Included here so reviewers can see the migration path. **Not used by the
POC pipeline.**

## Service connection (one-time setup)

1. Project Settings → Service connections → **New service connection** → **GitHub App**.
2. Fields:
   - **Connection name**: `github-app-humana-sandbox`
   - **App Client ID**: `Iv23li...`
   - **Private key (PEM)**: paste the PEM contents
   - **Limit token permissions** (optional): `{"contents":"read","metadata":"read"}`
   - **Scope to repository** (optional): on
3. Restrict pipeline access to specific pipelines/projects.

The PEM lives only in the service connection — no Secure File needed.

## Pipeline usage

```yaml
steps:
  # Once the private extension is published under the Humana publisher,
  # this is the only line that changes vs. the POC.
  - task: create-github-app-token@1
    name: ghToken
    inputs:
      githubAppConnection: github-app-humana-sandbox
      owner: humana-sandbox
      repositories: automation-sandbox
      permissions: '{"contents":"read","metadata":"read"}'

  - bash: |
      gh api /repos/humana-sandbox/automation-sandbox | jq .default_branch
    env:
      GH_TOKEN: $(ghToken.installationToken)
```

The output variable names (`installationToken`, `installationId`,
`tokenExpiration`) are **identical** to those emitted by the POC's
`scripts/create-github-app-token.ps1`, so consumer steps don't change.

## When to migrate from the POC pattern to this

- After security review approves the inline POC, **and**
- The extension is packaged, signed, and published to a private Humana publisher, **and**
- The "GitHub App" service connection type is enabled in the target ADO collection.

Until then, the inline-script POC is the supported path.
