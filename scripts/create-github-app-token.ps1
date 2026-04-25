<#
.SYNOPSIS
    Mint a short-lived GitHub App installation access token and emit it as a
    masked Azure Pipelines output variable.

.DESCRIPTION
    1. Builds an RS256-signed JWT using the GitHub App's private key (PEM).
    2. Calls GET /app/installations as the App to find the installation id
       for $Owner.
    3. Calls POST /app/installations/{id}/access_tokens to mint an installation
       token, optionally scoped to specific repositories and permissions.
    4. Emits three pipeline output variables (names match the upstream
       reference task for forward compatibility):
         - installationToken   (secret/masked)
         - installationId
         - tokenExpiration

.NOTES
    - PEM is read from disk; never echoed.
    - JWT is built using only the .NET BCL (RSA + JsonWebTokenHandler not
      required) so this script works on any Windows/Linux agent with PS 7.
    - This script intentionally does NOT support: enterprise installs, GHES,
      proxies. Add as needed; see docs/specification.md §7.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $AppClientId,        # Iv23... or numeric App ID
    [Parameter(Mandatory)] [string] $PrivateKeyPath,     # Path to PEM file on agent
    [Parameter(Mandatory)] [string] $Owner,              # GitHub org login
    [Parameter()]          [string] $Repositories = '', # comma-separated; empty = all installed
    [Parameter()]          [string] $Permissions  = ''  # JSON string, e.g. '{"contents":"read"}'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Avoid loading Windows PowerShell 5.1 modules into pwsh 7 (causes
# duplicate System.Security.AccessControl.ObjectSecurity type errors).
$env:PSModulePath = 'C:\Program Files\PowerShell\7\Modules;C:\Program Files\PowerShell\Modules'

Write-Host "=== Generate GitHub App installation token ==="

# ----- 1. Build a JWT signed with the App private key (RS256, ~9 min) --------

function ConvertTo-Base64Url([byte[]]$bytes) {
    [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$header  = @{ alg = 'RS256'; typ = 'JWT' } | ConvertTo-Json -Compress
$payload = @{
    iat = [int]($now - 30)   # tolerate small clock skew
    exp = [int]($now + 540)  # 9 min — well under GitHub's 10 min cap
    iss = $AppClientId
} | ConvertTo-Json -Compress

$enc       = [System.Text.Encoding]::UTF8
$headerB64 = ConvertTo-Base64Url $enc.GetBytes($header)
$payloadB64= ConvertTo-Base64Url $enc.GetBytes($payload)
$signingInput = "$headerB64.$payloadB64"

# Load the PEM. PS 7 has ImportFromPem on RSA.
$rsa = [System.Security.Cryptography.RSA]::Create()
try {
    $rsa.ImportFromPem((Get-Content -Raw -LiteralPath $PrivateKeyPath))
} catch {
    throw "Failed to load private key from '$PrivateKeyPath': $($_.Exception.Message)"
}

$sigBytes = $rsa.SignData(
    $enc.GetBytes($signingInput),
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)
$jwt = "$signingInput.$(ConvertTo-Base64Url $sigBytes)"
Write-Host "Generated JWT (length: $($jwt.Length))"

# ----- 2. Look up the installation id for $Owner -----------------------------

$jwtHeaders = @{
    Authorization = "Bearer $jwt"
    Accept        = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'  = 'customer-azpipelines-poc'
}

$installations = Invoke-RestMethod `
    -Method Get `
    -Uri 'https://api.github.com/app/installations' `
    -Headers $jwtHeaders

$inst = $installations | Where-Object { $_.account.login -ieq $Owner } | Select-Object -First 1
if (-not $inst) {
    throw "GitHub App is not installed on org '$Owner'. Found: $($installations.account.login -join ', ')"
}
Write-Host "Found installation id: $($inst.id)"

# ----- 3. Mint the installation access token ---------------------------------

$body = @{}
if ($Repositories -and $Repositories.Trim()) {
    $body.repositories = $Repositories.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
if ($Permissions -and $Permissions.Trim()) {
    # Pass through as a hashtable so it serializes as a JSON object, not a string.
    $body.permissions = $Permissions | ConvertFrom-Json -AsHashtable
}
$jsonBody = ($body | ConvertTo-Json -Depth 5 -Compress)
if ($body.Count -eq 0) { $jsonBody = '{}' }

$tokenResp = Invoke-RestMethod `
    -Method Post `
    -Uri "https://api.github.com/app/installations/$($inst.id)/access_tokens" `
    -Headers $jwtHeaders `
    -ContentType 'application/json' `
    -Body $jsonBody

Write-Host "Token minted. Expires: $($tokenResp.expires_at)"

# ----- 4. Emit output variables ---------------------------------------------
# issecret=true causes Azure DevOps to mask the token in all logs.
# isOutput=true makes them consumable as $(stepName.varName) in later steps.

Write-Host "##vso[task.setvariable variable=installationToken;issecret=true;isOutput=true]$($tokenResp.token)"
Write-Host "##vso[task.setvariable variable=installationId;isOutput=true]$($inst.id)"
Write-Host "##vso[task.setvariable variable=tokenExpiration;isOutput=true]$($tokenResp.expires_at)"
