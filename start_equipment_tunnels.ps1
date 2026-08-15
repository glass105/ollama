[CmdletBinding()]
param(
    [string]$EquipmentFile = "$PSScriptRoot\secrets\equipment.csv",
    [string]$ConnectionsFile = "$PSScriptRoot\secrets\pod_connections.json",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $EquipmentFile -PathType Leaf)) {
    throw "Equipment inventory not found: $EquipmentFile"
}
if (-not (Test-Path -LiteralPath $ConnectionsFile -PathType Leaf)) {
    throw "Pod connections file not found: $ConnectionsFile"
}

$devices = @(Import-Csv -LiteralPath $EquipmentFile |
    Where-Object { $_.enabled -match '^(?i:true|1|yes|y|on)$' })
if ($devices.Count -eq 0) {
    throw "Equipment inventory contains no enabled devices."
}

$connections = Get-Content -LiteralPath $ConnectionsFile -Raw | ConvertFrom-Json
if ($connections.pod.status -ne "RUNNING") {
    throw "Saved RunPod status is '$($connections.pod.status)', not RUNNING."
}

$sshHost = [string]$connections.ssh.host
$sshPort = [int]$connections.ssh.port
$sshUser = [string]$connections.ssh.user
$identityFile = [string]$connections.ssh.identityFile
if (-not $sshHost -or $sshPort -lt 1 -or -not $sshUser) {
    throw "RunPod SSH connection information is incomplete."
}
if (-not (Test-Path -LiteralPath $identityFile -PathType Leaf)) {
    throw "RunPod identity file not found: $identityFile"
}

$arguments = @(
    "-N", "-T",
    "-i", $identityFile,
    "-p", [string]$sshPort,
    "-o", "BatchMode=yes",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=3"
)

$names = @{}
$ports = @{}
foreach ($device in $devices) {
    if ($device.name -notmatch '^[A-Za-z0-9_-]+$') {
        throw "Invalid equipment name: $($device.name)"
    }
    if ($device.address -notmatch '^[A-Za-z0-9_.:-]+$') {
        throw "Invalid equipment address for $($device.name): $($device.address)"
    }
    $tunnelPort = [int]$device.tunnel_port
    $equipmentPort = [int]$device.ssh_port
    if ($tunnelPort -lt 1024 -or $tunnelPort -gt 65535) {
        throw "Invalid tunnel port for $($device.name): $tunnelPort"
    }
    if ($equipmentPort -lt 1 -or $equipmentPort -gt 65535) {
        throw "Invalid equipment SSH port for $($device.name): $equipmentPort"
    }
    if ($names.ContainsKey($device.name)) {
        throw "Duplicate equipment name: $($device.name)"
    }
    if ($ports.ContainsKey($tunnelPort)) {
        throw "Duplicate tunnel port: $tunnelPort"
    }
    $names[$device.name] = $true
    $ports[$tunnelPort] = $true

    $forward = "127.0.0.1:${tunnelPort}:$($device.address):${equipmentPort}"
    Write-Host "$($device.name): RunPod 127.0.0.1:$tunnelPort -> $($device.address):$equipmentPort"
    $arguments += @("-R", $forward)
}

$arguments += "${sshUser}@${sshHost}"
Write-Host "RunPod SSH endpoint: ${sshHost}:$sshPort"

if ($DryRun) {
    Write-Host "Dry run complete; SSH was not started."
    exit 0
}

Write-Host "Opening equipment tunnels. Press Ctrl+C to stop."
& ssh.exe @arguments
if ($LASTEXITCODE -ne 0) {
    throw "SSH tunnel exited with code $LASTEXITCODE."
}
