# Azure Pipelines ↔ GitHub App POC (Humana)

Proof of concept: mint a short-lived **GitHub App installation token** inside an **Azure DevOps Pipeline** and use it to call GitHub — **no PATs**.

## Quick links

- 📘 Master design: [specification.md](specification.md)
- 📝 POC overview: [docs/poc-overview.md](docs/poc-overview.md)
- 🛠 Setup guide: [docs/setup-guide.md](docs/setup-guide.md)
- 🔒 Security notes: [docs/security-notes.md](docs/security-notes.md)
- 🚀 Pipeline: [azure-pipelines/azure-pipelines.poc.yml](azure-pipelines/azure-pipelines.poc.yml)
- ✅ Review checklist: [checklists/security-platform-review.md](checklists/security-platform-review.md)

## What this POC proves

1. Azure Pipelines can authenticate to GitHub using a **GitHub App**, not a PAT.
2. The installation token is **short-lived (≤ 1h)**, **repo-scoped**, **permission-scoped**, and **revoked** at end of job.
3. The token is usable by any step in the job via a masked output variable.
4. The pattern is reviewable, reproducible, and a clean stepping-stone to a packaged Azure DevOps extension.

## Reused from upstream

Patterns and input/output shapes are inspired by
[`tspascoal/azure-pipelines-create-github-app-token-task`](https://github.com/tspascoal/azure-pipelines-create-github-app-token-task).
See [task-or-extension-source/README.md](task-or-extension-source/README.md) for the full reuse map.
