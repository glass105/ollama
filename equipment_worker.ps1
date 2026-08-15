[CmdletBinding()]
param(
    [string]$EnvironmentFile = "$PSScriptRoot\secrets\equipment_worker.env",
    [string]$EquipmentFile = "$PSScriptRoot\secrets\equipment.csv",
    [string]$OperationsFile = "$PSScriptRoot\equipment_operations.json",
    [switch]$Once
)

$ErrorActionPreference = "Stop"

function Read-EnvironmentFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Worker environment file not found: $Path"
    }
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $value = $Matches[2]
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$Matches[1]] = $value
        }
    }
    return $values
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-EquipmentSsh {
    param(
        [Parameter(Mandatory)]$Device,
        [Parameter(Mandatory)]$Operation
    )

    $timeoutSeconds = if ($Operation.timeoutSeconds) {
        [Math]::Min([Math]::Max([int]$Operation.timeoutSeconds, 5), 300)
    } else { 60 }
    $target = "$($Device.user)@$($Device.address)"
    $arguments = @(
        "-T",
        "-p", [string][int]$Device.ssh_port,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=2",
        "--", $target,
        [string]$Operation.command
    )

    $start = Get-Date
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = "ssh.exe"
    $processInfo.Arguments = (($arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " ")
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    if (-not $process.Start()) {
        throw "Failed to start ssh.exe."
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($timeoutSeconds * 1000)
    if (-not $completed) {
        $process.Kill()
        $process.WaitForExit()
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $limit = 524288
    if ($stdout.Length -gt $limit) { $stdout = $stdout.Substring(0, $limit) + "`n[output truncated]" }
    if ($stderr.Length -gt $limit) { $stderr = $stderr.Substring(0, $limit) + "`n[output truncated]" }

    return [ordered]@{
        status = if (-not $completed) { "failed" } elseif ($process.ExitCode -eq 0) { "completed" } else { "failed" }
        exitCode = if ($completed) { $process.ExitCode } else { 124 }
        stdout = $stdout
        stderr = if (-not $completed) { $stderr + "`nSSH command timed out." } else { $stderr }
        durationMs = [int]((Get-Date) - $start).TotalMilliseconds
        message = if (-not $completed) { "timeout" } else { "" }
    }
}

if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
    throw "Windows OpenSSH client ssh.exe is not available."
}
if (-not (Test-Path -LiteralPath $EquipmentFile -PathType Leaf)) {
    throw "Equipment inventory not found: $EquipmentFile"
}
if (-not (Test-Path -LiteralPath $OperationsFile -PathType Leaf)) {
    throw "Operations allowlist not found: $OperationsFile"
}

$settings = Read-EnvironmentFile -Path $EnvironmentFile
$bridgeUrl = ([string]$settings['BRIDGE_URL']).TrimEnd('/')
$bridgeToken = [string]$settings['BRIDGE_TOKEN']
$workerId = [string]$settings['WORKER_ID']
$pollSeconds = if ($settings['POLL_SECONDS']) { [Math]::Max([int]$settings['POLL_SECONDS'], 2) } else { 5 }
if (-not $bridgeUrl.StartsWith('https://')) { throw "BRIDGE_URL must use HTTPS." }
if ($bridgeToken.Length -lt 32) { throw "BRIDGE_TOKEN is missing or too short." }
if ($workerId -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw "WORKER_ID is invalid." }

$headers = @{ Authorization = "Bearer $bridgeToken" }
$devices = @{}
foreach ($device in Import-Csv -LiteralPath $EquipmentFile) {
    if ($device.enabled -notmatch '^(?i:true|1|yes|y|on)$') { continue }
    if ($device.name -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw "Invalid device name: $($device.name)" }
    if ($devices.ContainsKey($device.name)) { throw "Duplicate device name: $($device.name)" }
    $devices[$device.name] = $device
}
$operationsDocument = Get-Content -LiteralPath $OperationsFile -Raw | ConvertFrom-Json
$operations = @{}
foreach ($property in $operationsDocument.PSObject.Properties) {
    if ($property.Name -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw "Invalid operation name: $($property.Name)" }
    if (-not $property.Value.command) { throw "Operation '$($property.Name)' has no command." }
    $operations[$property.Name] = $property.Value
}
if ($devices.Count -eq 0 -or $operations.Count -eq 0) {
    throw "At least one enabled device and one operation are required."
}

Write-Host "Equipment worker '$workerId' started."
Write-Host "Bridge: $bridgeUrl"
Write-Host "Devices: $($devices.Keys -join ', ')"
Write-Host "Operations: $($operations.Keys -join ', ')"
Write-Host "Press Ctrl+C to stop."

do {
    try {
        $encodedWorkerId = [uri]::EscapeDataString($workerId)
        $response = Invoke-RestMethod -Method Get `
            -Uri "$bridgeUrl/api/jobs/next?workerId=$encodedWorkerId" `
            -Headers $headers -TimeoutSec 20
        $job = $response.job
        if ($null -eq $job) {
            if ($Once) { break }
            Start-Sleep -Seconds $pollSeconds
            continue
        }

        Write-Host "Claimed $($job.id): $($job.device) / $($job.operation)"
        if (-not $devices.ContainsKey([string]$job.device)) {
            $result = [ordered]@{ status="rejected"; exitCode=$null; stdout=""; stderr=""; durationMs=0; message="device not allowed" }
        }
        elseif (-not $operations.ContainsKey([string]$job.operation)) {
            $result = [ordered]@{ status="rejected"; exitCode=$null; stdout=""; stderr=""; durationMs=0; message="operation not allowed" }
        }
        else {
            $result = Invoke-EquipmentSsh -Device $devices[[string]$job.device] -Operation $operations[[string]$job.operation]
        }
        $result['workerId'] = $workerId
        $body = $result | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Method Post `
            -Uri "$bridgeUrl/api/jobs/$($job.id)/result" `
            -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 30 | Out-Null
        Write-Host "Returned $($result.status) for $($job.id)."
    }
    catch {
        Write-Warning "Worker cycle failed: $($_.Exception.Message)"
        if ($Once) { throw }
        Start-Sleep -Seconds $pollSeconds
    }
} while (-not $Once)
