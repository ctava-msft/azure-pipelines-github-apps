<#
.SYNOPSIS
    Revoke the current installation access token (best-effort cleanup).

.DESCRIPTION
    Calls DELETE /installation/token. Expected response: 204 No Content.
    Never throws — this runs in an always() step and must not fail the build.
#>

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest
$env:PSModulePath = 'C:\Program Files\PowerShell\7\Modules;C:\Program Files\PowerShell\Modules'

Write-Host "=== Revoke token (always) ==="

if (-not $env:GH_TOKEN) {
    Write-Host "No GH_TOKEN to revoke. Nothing to do."
    return
}

try {
    $resp = Invoke-WebRequest `
        -Method Delete `
        -Uri 'https://api.github.com/installation/token' `
        -Headers @{
            Authorization = "Bearer $env:GH_TOKEN"
            Accept        = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent'  = 'customer-azpipelines-poc'
        } `
        -SkipHttpErrorCheck
    Write-Host "DELETE /installation/token -> $($resp.StatusCode) $($resp.StatusDescription)"
}
catch {
    Write-Host "Revoke call failed (non-fatal): $($_.Exception.Message)"
}
