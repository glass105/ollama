param(
  [string]$DashboardUrlFile = "$PSScriptRoot\tmp\openclaw_dashboard_url.local.txt"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DashboardUrlFile)) {
  throw "Dashboard URL file not found: $DashboardUrlFile"
}

$content = Get-Content -LiteralPath $DashboardUrlFile -Raw
$url = ($content -split "`r?`n" | Where-Object { $_ -match '^https://.*\?url=wss://' } | Select-Object -First 1)

if (-not $url) {
  throw "Tokenized Dashboard URL not found in $DashboardUrlFile"
}

Write-Host "Opening OpenClaw dashboard..."
Start-Process $url
