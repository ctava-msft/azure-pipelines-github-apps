<#
.SYNOPSIS
    STRETCH GOAL — controlled mutation: commit a small generated metadata
    file to a sandbox repo using the GitHub App installation token as the
    git credential.

.DESCRIPTION
    - Clones the repo over HTTPS using the token (sent as the password of an
      'x-access-token' user — the GitHub-documented pattern).
    - Writes .github/automation/last-run.json with a timestamp and the Azure
      DevOps build id.
    - Commits as the App's bot identity and pushes to a feature branch.

    This is INTENTIONALLY a feature branch, not main. Promotion to main is
    out of scope for the POC and should go through normal PR/CODEOWNERS.

    Requires the App permission `contents:write` and the token request to
    have included `contents:write` (update GITHUB_TOKEN_PERMISSIONS in the
    pipeline yml when enabling this).

.PARAMETER Owner
    Org login.
.PARAMETER Repo
    Sandbox repo name.
.PARAMETER Branch
    Branch to create/update. Defaults to 'automation/poc-metadata'.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Owner,
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter()]          [string] $Branch = 'automation/poc-metadata'
)

$ErrorActionPreference = 'Stop'
$env:PSModulePath = 'C:\Program Files\PowerShell\7\Modules;C:\Program Files\PowerShell\Modules'
Set-StrictMode -Version Latest

Write-Host "=== Stretch: controlled push to $Owner/$Repo on branch $Branch ==="

if (-not $env:GH_TOKEN) {
    throw "GH_TOKEN env var is not set."
}

# Use a fresh dir under the agent workspace; cleaned up with the job.
$work = Join-Path $env:AGENT_TEMPDIRECTORY "poc-push-$(Get-Random)"
New-Item -ItemType Directory -Path $work | Out-Null
Push-Location $work
try {
    # Embed token only in the remote URL on the local clone — never logged.
    # The token is masked by Azure DevOps in any output that includes it.
    $remote = "https://x-access-token:$($env:GH_TOKEN)@github.com/$Owner/$Repo.git"

    git clone --quiet --depth 1 $remote repo
    Set-Location repo

    git config user.email "customer-azpipelines-poc[bot]@users.noreply.github.com"
    git config user.name  "customer-azpipelines-poc[bot]"

    # Create / switch to the feature branch
    git checkout -B $Branch | Out-Null

    $metaDir = ".github/automation"
    New-Item -ItemType Directory -Force -Path $metaDir | Out-Null
    $payload = [ordered]@{
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        buildId        = $env:BUILD_BUILDID
        buildNumber    = $env:BUILD_BUILDNUMBER
        pipeline       = $env:BUILD_DEFINITIONNAME
        source         = 'customer-azpipelines-poc'
    } | ConvertTo-Json -Depth 3
    Set-Content -Path "$metaDir/last-run.json" -Value $payload -Encoding UTF8

    git add "$metaDir/last-run.json"

    if (-not (git status --porcelain)) {
        Write-Host "No changes to commit. Skipping push."
        return
    }

    git commit -m "chore(automation): refresh last-run metadata [skip ci]" | Out-Null
    git push --quiet --set-upstream origin $Branch
    Write-Host "Pushed $Branch."
}
finally {
    Pop-Location
    # Defense in depth: ensure no remote URL with the token lingers in git config.
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $work
}
