# POC Overview

## Purpose
Prove that an Azure DevOps Pipeline can authenticate to GitHub using a **GitHub App** — minting a short-lived installation access token at runtime — and use that token to perform controlled GitHub operations without ever using a PAT.

## Problem
Humana runs a coexistence model: Azure DevOps Pipelines is the system of control, GitHub is the source of truth for code. Pipelines that need to call the GitHub API beyond the built-in checkout/status integration default to **PATs**, which are long-lived, user-owned, broadly scoped, and a recurring audit finding.

## Why a GitHub App
- Org-owned credential (survives user churn).
- Token lifetime ≤ 1 hour, revocable on demand.
- Per-repo and per-permission scoping.
- Audit trail attributes actions to the App, not a person.
- GitHub-recommended pattern for automation.

## What the built-in Azure Pipelines GitHub App integration covers
- Triggering pipelines from GitHub events.
- `checkout` of a GitHub repo.
- Reporting build/PR status back to GitHub.

## What the built-in integration does not give you
- An exportable installation access token usable by your own scripts.
- Per-pipeline, per-repo, per-permission scoping at runtime.
- A documented pattern for arbitrary REST/GraphQL calls or controlled commits.

## What this POC adds
- A pipeline step that mints a fresh installation token at runtime, exposes it as a masked variable, and revokes it at end-of-job.
- A small, reviewable PowerShell implementation (no extension required).
- Sample read-only and (optional) write-path consumers.
- Documentation and a security checklist suitable for handoff to platform/security teams.

For full architecture, security boundaries, limitations, success criteria, and next steps, see [../specification.md](../specification.md).
