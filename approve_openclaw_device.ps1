[CmdletBinding()]
param(
    [string]$ConnectionFile = "$PSScriptRoot\secrets\pod_connections.json",
    [ValidatePattern('^(latest|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$')]
    [string]$RequestId = "latest"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ConnectionFile -PathType Leaf)) {
    throw "RunPod connection manifest not found: $ConnectionFile"
}

$connection = Get-Content -LiteralPath $ConnectionFile -Raw | ConvertFrom-Json
$sshHost = [string]$connection.ssh.host
$sshPort = [int]$connection.ssh.port
$sshUser = [string]$connection.ssh.user
$keyPath = [string]$connection.ssh.identityFile

if (-not $sshHost -or $sshPort -lt 1 -or -not $sshUser) {
    throw "The connection manifest does not contain a complete SSH endpoint."
}
if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) {
    throw "SSH key not found: $keyPath"
}

$remoteScript = @'
set -euo pipefail

request_id="${1:-latest}"
token="$(cat /tmp/openclaw/gateway-token)"

openclaw devices list --url ws://127.0.0.1:18789 --token "$token" | tee /tmp/openclaw-devices-list.txt

if [ "$request_id" = "latest" ]; then
  request_id="$(grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' /tmp/openclaw-devices-list.txt | tail -1)"
fi

if [ -z "$request_id" ]; then
  echo "No pending OpenClaw device request found."
  exit 1
fi

echo
echo "Approving OpenClaw device request: $request_id"
openclaw devices approve "$request_id" --url ws://127.0.0.1:18789 --token "$token"
'@

Write-Host "Checking pending OpenClaw devices through $sshUser@$sshHost`:$sshPort..."
$remoteScript | ssh `
    -i $keyPath `
    -p $sshPort `
    -o BatchMode=yes `
    -o StrictHostKeyChecking=accept-new `
    "$sshUser@$sshHost" `
    "bash -s -- '$RequestId'"

if ($LASTEXITCODE -ne 0) {
    throw "OpenClaw device approval failed with exit code $LASTEXITCODE."
}
