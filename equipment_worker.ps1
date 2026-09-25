[CmdletBinding()]
param(
    [string]$EnvironmentFile,
    [string]$EquipmentFile,
    [string]$OperationsFile,
    [switch]$Once
)

$client = Join-Path $PSScriptRoot "equipment_bridge_client.ps1"
if (-not (Test-Path -LiteralPath $client -PathType Leaf)) {
    throw "Portable equipment bridge client not found: $client"
}

$arguments = @("-ExecutionPolicy", "Bypass", "-File", $client)
if ($EnvironmentFile) { $arguments += @("-EnvironmentFile", $EnvironmentFile) }
if ($EquipmentFile) { $arguments += @("-EquipmentFile", $EquipmentFile) }
if ($OperationsFile) { $arguments += @("-OperationsFile", $OperationsFile) }
if ($Once) { $arguments += "-Once" }

& powershell.exe @arguments
exit $LASTEXITCODE
