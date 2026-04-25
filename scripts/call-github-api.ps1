<#
.SYNOPSIS
    Demonstrate a real read-only API call using the minted installation token:
    fetch repo metadata + list branches.

.PARAMETER Owner
    GitHub org/user login.

.PARAMETER Repo
    Repository name (without owner).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Owner,
    [Parameter(Mandatory)] [string] $Repo
)

$ErrorActionPreference = 'Stop'
$env:PSModulePath = 'C:\Program Files\PowerShell\7\Modules;C:\Program Files\PowerShell\Modules'
Set-StrictMode -Version Latest

Write-Host "=== Call GitHub API ==="

if (-not $env:GH_TOKEN) {
    throw "GH_TOKEN env var is not set."
}

$headers = @{
    Authorization = "Bearer $env:GH_TOKEN"
    Accept        = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'  = 'customer-azpipelines-poc'
}

# 1. Repo metadata
$meta = Invoke-RestMethod -Method Get `
    -Uri "https://api.github.com/repos/$Owner/$Repo" `
    -Headers $headers
Write-Host "Repo:           $($meta.full_name)"
Write-Host "Default branch: $($meta.default_branch)"
Write-Host "Visibility:     $($meta.visibility)"
Write-Host "Archived:       $($meta.archived)"

# 2. Branches (cap at 30 for log brevity)
$branches = Invoke-RestMethod -Method Get `
    -Uri "https://api.github.com/repos/$Owner/$Repo/branches?per_page=30" `
    -Headers $headers
Write-Host "Branches ($($branches.Count) shown):"
$branches | Select-Object -First 30 -Property name, @{n='protected';e={$_.protected}} |
    Format-Table -AutoSize | Out-String | Write-Host
