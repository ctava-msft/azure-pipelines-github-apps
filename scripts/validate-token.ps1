<#
.SYNOPSIS
    Sanity-check that the minted installation token is usable.

.DESCRIPTION
    Calls GET /installation/repositories with the token and prints how many
    repositories the token can see. This is a non-mutating call, scoped to
    exactly what the token is allowed to access.

    Reads the token from the GH_TOKEN environment variable (set by the
    pipeline as a secret), so it never appears on the command line.
#>

$ErrorActionPreference = 'Stop'
$env:PSModulePath = 'C:\Program Files\PowerShell\7\Modules;C:\Program Files\PowerShell\Modules'
Set-StrictMode -Version Latest

Write-Host "=== Validate token ==="

if (-not $env:GH_TOKEN) {
    throw "GH_TOKEN env var is not set. Did the previous step succeed?"
}

$headers = @{
    Authorization = "Bearer $env:GH_TOKEN"
    Accept        = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'  = 'customer-azpipelines-poc'
}

# /installation/repositories returns repos this installation token can access.
$resp = Invoke-RestMethod `
    -Method Get `
    -Uri 'https://api.github.com/installation/repositories?per_page=100' `
    -Headers $headers

Write-Host "Token is valid. Visible repositories: $($resp.total_count)"
$resp.repositories | Select-Object -First 10 -Property full_name, private |
    Format-Table -AutoSize | Out-String | Write-Host
