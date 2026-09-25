[CmdletBinding()]
param(
    [string]$EnvironmentFile,
    [string]$EquipmentFile,
    [string]$OperationsFile,
    [switch]$Once
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-PortablePath {
    param(
        [string]$Requested,
        [string[]]$Candidates,
        [switch]$Require
    )

    if ($Requested) {
        $path = if ([System.IO.Path]::IsPathRooted($Requested)) { $Requested } else { Join-Path $ScriptDir $Requested }
        if ($Require -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "File not found: $path"
        }
        return $path
    }

    foreach ($candidate in $Candidates) {
        $path = if ([System.IO.Path]::IsPathRooted($candidate)) { $candidate } else { Join-Path $ScriptDir $candidate }
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }

    if ($Require) {
        throw "None of these files exist beside the script: $($Candidates -join ', ')"
    }
    return $null
}

function Read-EnvironmentFile {
    param([Parameter(Mandatory)][string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $value = $Matches[2].Trim()
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

function Get-Setting {
    param(
        [hashtable]$Settings,
        [string]$Name,
        [string]$Default = ""
    )

    if ($Settings.ContainsKey($Name) -and [string]$Settings[$Name]) {
        return [string]$Settings[$Name]
    }
    $environmentValue = [Environment]::GetEnvironmentVariable($Name)
    if ([string]$environmentValue) {
        return [string]$environmentValue
    }
    return $Default
}

function Resolve-ToolPath {
    param(
        [string]$Tool,
        [hashtable]$Settings
    )

    if ($Tool -eq "plink") {
        $configured = Get-Setting -Settings $Settings -Name "PLINK_PATH"
        if ($configured) {
            $path = if ([System.IO.Path]::IsPathRooted($configured)) { $configured } else { Join-Path $ScriptDir $configured }
            if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
            throw "PLINK_PATH was set but not found: $path"
        }
        $local = Join-Path $ScriptDir "plink.exe"
        if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }
        $cmd = Get-Command plink.exe -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        throw "plink.exe was requested but was not found beside the script or on PATH."
    }

    $cmd = Get-Command ssh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "ssh.exe was requested but was not found on PATH."
}

function Invoke-CommandProcess {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [string[]]$InputLines
    )

    $start = Get-Date
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $FileName
    $processInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " ")
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.RedirectStandardInput = $null -ne $InputLines
    $processInfo.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    if (-not $process.Start()) {
        throw "Failed to start $FileName."
    }

    if ($null -ne $InputLines) {
        foreach ($line in $InputLines) {
            $process.StandardInput.WriteLine($line)
        }
        $process.StandardInput.Close()
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
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
        stderr = if (-not $completed) { $stderr + "`nCommand timed out." } else { $stderr }
        durationMs = [int]((Get-Date) - $start).TotalMilliseconds
        message = if (-not $completed) { "timeout" } else { "" }
    }
}

function Invoke-EquipmentSsh {
    param(
        [Parameter(Mandatory)]$Device,
        [Parameter(Mandatory)]$Operation,
        [Parameter(Mandatory)][hashtable]$Settings
    )

    $timeoutSeconds = if ($Operation.timeoutSeconds) {
        [Math]::Min([Math]::Max([int]$Operation.timeoutSeconds, 5), 300)
    } else { 60 }

    $tool = ([string](Get-Setting -Settings $Settings -Name "SSH_TOOL" -Default "auto")).ToLowerInvariant()
    if ($tool -eq "auto") {
        if ((Join-Path $ScriptDir "plink.exe" | Test-Path -PathType Leaf) -or (Get-Command plink.exe -ErrorAction SilentlyContinue)) {
            $tool = "plink"
        } else {
            $tool = "ssh"
        }
    }
    if ($tool -notin @("ssh", "plink")) {
        throw "SSH_TOOL must be auto, ssh, or plink."
    }

    $port = if ($Device.ssh_port) { [int]$Device.ssh_port } else { 22 }
    $command = [string]$Operation.command
    $fileName = Resolve-ToolPath -Tool $tool -Settings $Settings

    if ($tool -eq "plink") {
        $arguments = @("-batch", "-t", "-ssh", "-P", [string]$port, "-l", [string]$Device.user)
        $passwordEnv = [string]$Device.password_env
        if ($passwordEnv) {
            $password = Get-Setting -Settings $Settings -Name $passwordEnv
            if (-not $password) { throw "Device $($Device.name) expects password setting $passwordEnv." }
            $arguments += @("-pw", $password)
        }
        $keyFile = [string]$Device.key_file
        if ($keyFile) {
            $keyPath = if ([System.IO.Path]::IsPathRooted($keyFile)) { $keyFile } else { Join-Path $ScriptDir $keyFile }
            $arguments += @("-i", $keyPath)
        }
        $arguments += @([string]$Device.address)
        $inputLines = @(
            ""
            $command
            "exit"
        )
        return Invoke-CommandProcess `
            -FileName $fileName `
            -Arguments $arguments `
            -TimeoutSeconds $timeoutSeconds `
            -InputLines $inputLines
    }

    if ([string]$Device.password_env) {
        throw "ssh.exe cannot use password_env non-interactively. Use key auth with ssh.exe, or set SSH_TOOL=plink and provide plink.exe."
    }
    $target = "$($Device.user)@$($Device.address)"
    $arguments = @(
        "-T",
        "-p", [string]$port,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=2"
    )
    $keyFile = [string]$Device.key_file
    if ($keyFile) {
        $keyPath = if ([System.IO.Path]::IsPathRooted($keyFile)) { $keyFile } else { Join-Path $ScriptDir $keyFile }
        $arguments += @("-i", $keyPath)
    }
    $arguments += @("--", $target, $command)
    return Invoke-CommandProcess -FileName $fileName -Arguments $arguments -TimeoutSeconds $timeoutSeconds
}

function Resolve-OperationParameters {
    param(
        [Parameter(Mandatory)]$Operation,
        $JobParameters
    )

    $command = [string]$Operation.command
    $provided = @{}
    if ($null -ne $JobParameters) {
        foreach ($property in $JobParameters.PSObject.Properties) {
            $provided[$property.Name] = [string]$property.Value
        }
    }

    $definitions = $Operation.parameters
    $allowed = @{}
    if ($null -ne $definitions) {
        foreach ($definition in $definitions.PSObject.Properties) {
            $name = $definition.Name
            if ($name -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw "Invalid parameter definition: $name" }
            $allowed[$name] = $true
            $value = if ($provided.ContainsKey($name)) { [string]$provided[$name] } else { "" }
            if ($definition.Value.required -eq $true -and -not $value) { throw "Required parameter missing: $name" }
            if ($value -and $definition.Value.pattern -and $value -notmatch ([string]$definition.Value.pattern)) {
                throw "Parameter '$name' failed validation."
            }
            $command = $command.Replace("{$name}", $value)
        }
    }

    foreach ($name in $provided.Keys) {
        if (-not $allowed.ContainsKey($name)) { throw "Unexpected parameter: $name" }
    }
    if ($command -match '\{[A-Za-z0-9_-]+\}') { throw "Command contains an unresolved parameter placeholder." }
    return $command
}

$EnvironmentFile = Resolve-PortablePath -Requested $EnvironmentFile -Candidates @("equipment_bridge.env", "equipment_worker.env", "secrets\equipment_worker.env") -Require
$EquipmentFile = Resolve-PortablePath -Requested $EquipmentFile -Candidates @("equipment.csv", "secrets\equipment.csv") -Require
$OperationsFile = Resolve-PortablePath -Requested $OperationsFile -Candidates @("equipment_operations.json") -Require

$settings = Read-EnvironmentFile -Path $EnvironmentFile
$bridgeUrl = (Get-Setting -Settings $settings -Name "BRIDGE_URL").TrimEnd('/')
$bridgeToken = Get-Setting -Settings $settings -Name "BRIDGE_TOKEN"
$workerId = Get-Setting -Settings $settings -Name "WORKER_ID" -Default "equipment-pc-01"
$pollSeconds = [Math]::Max([int](Get-Setting -Settings $settings -Name "POLL_SECONDS" -Default "5"), 2)

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

Write-Host "Equipment bridge client '$workerId' started."
Write-Host "Bridge: $bridgeUrl"
Write-Host "Environment: $EnvironmentFile"
Write-Host "Equipment: $EquipmentFile"
Write-Host "Operations: $OperationsFile"
Write-Host "Devices: $($devices.Keys -join ', ')"
Write-Host "Operations: $($operations.Keys -join ', ')"
Write-Host "SSH tool: $(Get-Setting -Settings $settings -Name "SSH_TOOL" -Default "auto")"
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
            try {
                $operation = $operations[[string]$job.operation].PSObject.Copy()
                $operation.command = Resolve-OperationParameters -Operation $operation -JobParameters $job.parameters
                $result = Invoke-EquipmentSsh -Device $devices[[string]$job.device] -Operation $operation -Settings $settings
            }
            catch {
                $result = [ordered]@{ status="rejected"; exitCode=$null; stdout=""; stderr=""; durationMs=0; message=$_.Exception.Message }
            }
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
