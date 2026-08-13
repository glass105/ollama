param(
  [string]$DashboardUrlFile = "$PSScriptRoot\tmp\openclaw_dashboard_url.local.txt"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DashboardUrlFile)) {
  throw "Dashboard URL file not found: $DashboardUrlFile"
}

$content = Get-Content -LiteralPath $DashboardUrlFile -Raw
$url = ($content -split "`r?`n" | Where-Object { $_ -match '^https://.*/?$' } | Select-Object -First 1)

if (-not $url) {
  throw "OpenClaw Dashboard URL not found in $DashboardUrlFile"
}

Write-Host "Opening OpenClaw dashboard..."
Write-Host "Use the password from: $PSScriptRoot\tmp\openclaw_gateway_password.local.txt"
Start-Process $url
